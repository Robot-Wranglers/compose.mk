"""
See the main docs: https://robot-wranglers.github.io/compose.mk/demos/RAG
"""
import os
import functools
import hashlib
import requests

import click

from rich.console import Console
from rich.text import Text

from langchain.chains import (ConversationalRetrievalChain, LLMChain,
                              RetrievalQA, StuffDocumentsChain)
from langchain_community.document_loaders import DirectoryLoader
from langchain_community.vectorstores import FAISS
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import RunnablePassthrough
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_ollama import OllamaLLM
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain.chains import RetrievalQA
EBD_MODEL_NAME = os.environ.get("EBD_MODEL_NAME", "all-MiniLM-L6-v2")
LLM_MODEL_NAME = os.environ.get('LLM_MODEL', 'phi3:mini')
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "localhost")
OLLAMA_PORT = os.environ.get("OLLAMA_PORT", "11434")
OLLAMA_URL = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}"
USE_CACHE = os.environ.get('USE_CACHE',"1")=="1"
console = Console(stderr=True)

template = """Use the following pieces of context to answer the question at the end.
If you don't know the answer, just say that you don't know, don't try to make up an answer.
Use 5 sentences or less and keep the answer as concise as possible.

{context}

Question: {question}

Helpful Answer:"""

def log(header, txt):
    green_text = Text(header, style="green")
    dim_text = Text(txt, style="dim")
    console.print(green_text, dim_text)

log.init = functools.partial(log, 'init:  ')
log.chat = functools.partial(log, 'chat:  ')
log.ingest = functools.partial(log, 'ingest:')
log.query = functools.partial(log, 'query: ')
log.result = functools.partial(log, 'result:')

def hashed(glob):
    return hashlib.md5(glob.encode()).hexdigest()

def get_loader(glob):
    return DirectoryLoader(os.getcwd(), glob=glob)

def get_embeddings(): return HuggingFaceEmbeddings(model_name=EBD_MODEL_NAME)

def get_llm():
    return OllamaLLM(model=LLM_MODEL_NAME, base_url=OLLAMA_URL)

def get_vectors(glob, fname=None):
    if not USE_CACHE or fname is None:
        documents = get_loader(glob).load()
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=500, chunk_overlap=50)
        docs = text_splitter.split_documents(documents)
        embeddings = get_embeddings()
        log.ingest(
            f"Computing the FAISS index, this might take a while")
        return FAISS.from_documents(docs, embeddings)
    else:
        return FAISS.load_local(
            os.path.join(os.getcwd(),fname), 
            get_embeddings(), allow_dangerous_deserialization=True)

def show_response(response):
    if isinstance(response,(dict,)):
        result = response.get('result', 'RAG result failure?')
        citations = []
        # print(response.keys())
        for doc in response['source_documents']:
            citations += [
                f"- {doc.metadata.get('source', 'unknown source')} (\"{doc.page_content[:20].strip()}...\")"]
        citations = '\n'.join(["CITATIONS:\n"] + citations)
    else:
        result=response
        citations = '\n'.join(["CITATIONS: (not implemented yet for `chat`, use `ask` instead)"])
    log.result(f'\n{result}')
    log.result(f'\n\n{citations}')

@click.group()
def cli():
    """A simple CLI app with multiple commands."""

@cli.command()
@click.argument("glob")
@click.option("--force", is_flag=True, default=False,)
def chat(glob, force=False):
    _init()
    db_path = _ingest(glob, force=force)
    vectorstore = get_vectors(glob, db_path)
    base_retriever = vectorstore.as_retriever()
    llm = get_llm()
    custom_rag_prompt = PromptTemplate.from_template(template)
    retrieval_chain = (
        {"context": base_retriever, "question": RunnablePassthrough()}
        | custom_rag_prompt
        | llm
        | StrOutputParser()
    )
    log.chat("Starting interactive session.  Use exit, quit, q, or Ctrl+D to exit.")
    while True:
        query = input(">> ")
        if query.lower() in ["exit", "quit", "q"]:
            break
        response = retrieval_chain.invoke(query)
        show_response(response)

@cli.command()
@click.argument("glob")
@click.option("--force", is_flag=True, default=False,)
@click.argument('query', nargs=-1)
def query(glob, query, force=False):
    _init()
    db_path = _ingest(glob, force=force)
    query = ' '.join(query)
    log.query(f"Got query: {query}")
    loader = get_loader(glob)
    embeddings = get_embeddings()
    vectorstore = get_vectors(glob, db_path)
    retriever = vectorstore.as_retriever()
    log.query(f'Running query..')
    qa_chain = RetrievalQA.from_chain_type(
        get_llm(), retriever=retriever, return_source_documents=True)
    response = qa_chain.invoke(query)
    show_response(response)

@cli.command()
@click.argument("glob")
@click.option("--force", is_flag=True, default=False,)
def ingest(glob, force=False):
    return _ingest(glob, force=force)
def _ingest(glob, force=False):
    db_path = f".tmp.faiss_index.{hashed(glob)}"
    log.ingest(f"FAISS index at {db_path}")
    if os.path.exists(db_path) and not force:
        log.ingest(f"FAISS index already exists, remove it to reingest.")
    else:
        force and log.ingest(f"Reingest was forced.")
        loader = get_loader(glob)
        vectorstore = get_vectors(glob)
        vectorstore.save_local(db_path)
    return db_path

@cli.command()
@click.argument("model", default=LLM_MODEL_NAME)
def init(model, ): _init(model=model)
def _init(model=LLM_MODEL_NAME):
    def model_exists(model_name):
        try:
            response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=3)
            models = response.json().get("models", [])
            return any(model["name"] == model_name for model in models)
        except requests.exceptions.RequestException:
            return False

    def pull_model(model_name):
        log.init(f"Checking for model '{model_name}'...")
        if not model_exists(model_name):
            log.init(f"Pulling model '{model_name}', please wait...")
            os.system(f"ollama pull {model_name}")
            log.init(f"Finished pulling model '{model_name}'")
        else:
            log.init(f"Model '{model_name}' is ready")
    pull_model(model)

if __name__ == '__main__':
    cli()