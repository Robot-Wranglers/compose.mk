import os
import sys 
import faiss
from langchain_community.document_loaders import DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.vectorstores import FAISS
# from langchain_community.embeddings import OllamaEmbeddings
# from langchain_community.llms import Ollama
from langchain_ollama import OllamaLLM
from langchain.chains import RetrievalQA
from langchain_huggingface import HuggingFaceEmbeddings

OLLAMA_HOST=os.environ.get('OLLAMA_HOST','ragd')
OLLAMA_PORT=os.environ.get('OLLAMA_PORT','11434')
DB_PATH = "faiss_index"

# Load and split documents
loader = DirectoryLoader("docs/", glob="*.md", show_progress=True)
documents = loader.load()
text_splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
docs = text_splitter.split_documents(documents)

# Initialize embeddings
# embeddings = OllamaEmbeddings(model="phi3:mini")
# embeddings = HuggingFaceEmbeddings(model_name="BAAI/bge-small-en")
embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
# Check if FAISS index exists
if os.path.exists(DB_PATH):
# if False:
    print("Loading existing FAISS index...")
    vectorstore = FAISS.load_local(DB_PATH, embeddings, allow_dangerous_deserialization=True)
else:
    print("Generating new FAISS index...")
    vectorstore = FAISS.from_documents(docs, embeddings)
    vectorstore.save_local(DB_PATH)  # Save to disk for reuse

retriever = vectorstore.as_retriever()

llm = OllamaLLM(model="phi3:mini",base_url=f"http://{OLLAMA_HOST}:{OLLAMA_PORT}")

# Create RAG chain
qa_chain = RetrievalQA.from_chain_type(llm, retriever=retriever)

# Run query
query=' '.join(sys.argv[1:])
print(f'Running query: {query}')
# query = "Describe features related to markdown"
response = qa_chain.invoke(query)

print(response.get('result', 'RAG result failure?'))