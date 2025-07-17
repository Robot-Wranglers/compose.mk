"""
See the main docs: https://robot-wranglers.github.io/compose.mk/demos/ai
"""
import os, sys, hashlib, logging

import click, ollama
from langchain.chains import RetrievalQA
from langchain_community.document_loaders import DirectoryLoader
from langchain_community.vectorstores import FAISS
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import RunnablePassthrough
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_ollama import OllamaLLM
from langchain_text_splitters import RecursiveCharacterTextSplitter

LLM_MODEL_NAME = os.environ.get("LLM_MODEL", "phi3:mini")
OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "localhost")
OLLAMA_PORT = os.environ.get("OLLAMA_PORT", "11434")
OLLAMA_URL = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}"
USE_CACHE = os.environ.get("USE_CACHE", "1") == "1"
EMBEDDINGS = HuggingFaceEmbeddings(model_name=os.environ.get("EBD_MODEL_NAME", "all-MiniLM-L6-v2"))
OLLAMA_CLIENT = ollama.Client(host=OLLAMA_URL)
LLM = OllamaLLM(model=LLM_MODEL_NAME, base_url=OLLAMA_URL)

TEMPLATE = """Use the following pieces of context to answer the question at the end.
If you don't know the answer, just say that you don't know, don't try to make up an answer.
Use 5 sentences or less and keep the answer as concise as possible.

{context}

Question: {question}"""
PROMPT = PromptTemplate.from_template(TEMPLATE)

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
logger.addHandler(logging.StreamHandler(sys.stderr))

def hashed(glob):
    return hashlib.md5(glob.encode()).hexdigest()

def get_vectors(glob, fname=None):
    if not USE_CACHE or fname is None:
        documents = DirectoryLoader(os.getcwd(), glob=glob).load()
        text_splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
        docs = text_splitter.split_documents(documents)
        logger.debug("Computing the FAISS index, this might take a while")
        return FAISS.from_documents(docs, EMBEDDINGS)
    return FAISS.load_local(
        os.path.join(os.getcwd(), fname),
        EMBEDDINGS,
        allow_dangerous_deserialization=True,
    )

def model_exists(model_name):
    models = [m.model for m in OLLAMA_CLIENT.list()['models']]
    return model_name in models

def pull_model(model_name=LLM_MODEL_NAME):
    logger.debug(f"Checking for model '{model_name}'...")
    if not model_exists(model_name):
        logger.debug(f"Pulling model '{model_name}', please wait...")
        OLLAMA_CLIENT.pull(model_name)
    logger.debug(f"Model '{model_name}' is ready")

def show_response(response):
    if isinstance(response, (dict,)):
        result = response.get("result", "RAG result failure?")
        citations = []
        for doc in response["source_documents"]:
            citations += [
                f"- {doc.metadata.get('source', 'unknown source')} (\"{doc.page_content[:20].strip()}...\")"
            ]
        citations = "\n".join(["CITATIONS:\n"] + citations)
    else:
        result = response
        citations = "\n".join(
            ["CITATIONS: (not implemented yet for `chat`, use `ask` instead)"]
        )
    logger.debug(f"\n{result}\n\n{citations}")

@click.group()
def cli():
    """RAG pipeline demo"""

@cli.command()
@click.argument("glob")
@click.option("--force", is_flag=True, default=False,)
def chat(glob, force=False):
    db_path = _ingest(glob, force=force)
    base_retriever = get_vectors(glob, db_path).as_retriever()
    retrieval_chain = (
        {"context": base_retriever, "question": RunnablePassthrough()}
        | PROMPT | LLM | StrOutputParser()
    )
    logger.debug("Starting interactive session.  Use exit, quit, q, or Ctrl+D to exit.")
    while True:
        query = input(">> ")
        if query.lower() in ["exit", "quit", "q"]:
            break
        response = retrieval_chain.invoke(query)
        show_response(response)

@cli.command()
@click.argument("glob")
@click.argument("query", nargs=-1)
@click.option("--force", is_flag=True, default=False,)
def query(glob, query, force=False):
    pull_model()
    db_path = _ingest(glob, force=force)
    query = " ".join(query)
    logger.debug(f"Got query: {query}")
    retriever = get_vectors(glob, db_path).as_retriever()
    logger.debug("Running query..")
    qa_chain = RetrievalQA.from_chain_type(
        LLM, retriever=retriever, return_source_documents=True
    )
    response = qa_chain.invoke(query)
    show_response(response)

@cli.command()
@click.argument("glob")
@click.option("--force", is_flag=True, default=False,)
def ingest(glob, force=False):
    return _ingest(glob, force=force)

def _ingest(glob, force=False):
    db_path = f".tmp.faiss_index.{hashed(glob)}"
    logger.debug(f"FAISS index: {db_path}")
    if os.path.exists(db_path) and not force:
        logger.debug("Index already exists, remove it to reingest.")
    else:
        force and logger.debug("Forcing reingest..")
        get_vectors(glob).save_local(db_path)
    return db_path

@cli.command()
def init():
    pull_model()

if __name__ == "__main__":
    cli()
