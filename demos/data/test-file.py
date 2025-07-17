import os 
print(f"hello world foo={os.environ.get('foo','notset')} bar={os.environ.get('bar','notset')}")