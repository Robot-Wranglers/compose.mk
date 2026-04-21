#!/usr/bin/env -S make -f
# uv.mk: uv-run a PEP-723 python script in a container (no venv).

include compose.mk

# uv runtime image (the script carries its own deps + python version)
uv.img=ghcr.io/astral-sh/uv:debian

# the PEP-723 inline-script: its own uv shebang + dependency block
define hello_world
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "requests==2.31.0",
# ]
# ///
import requests
r = requests.get('https://httpbin.org/basic-auth/user/pass', auth=('user', 'pass'))
print(r.status_code)
endef

__main__:
	@# run the code-object's source in the uv container (low-level helper)
	img=${uv.img} entrypoint=uv cmd="run --script" def=hello_world ${make} docker.run.def
