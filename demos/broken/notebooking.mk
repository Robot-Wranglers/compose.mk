# demos/notebook.mk: 
#   Demonstrates building a highly customized and self-contained console application,
#   where all the application components bootstrap themselves on demand.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   This defines/embeds two containers, one for the lean4 theorem prover[1] and one for alloylang[2].
#
#   Since there's no official docker images available, we have to provision containers from 
#   scratch, but using the ideas from `demos/makeception.mk`, we will build them in-situ and 
#   defer to `make` itself for the provisioning details.
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/demos/notebooking
#
#   USAGE: make -f demos/app.mk

include demos/lean.mk 

.DEFAULT_GOAL := demo.entry
lab_url=http://localhost:9999/lab/tree/notebooks

# WARNING: name is really important for use with `up --detach` and `exec`
# if it's going to work inside the TUI.
# https://docs.docker.com/compose/how-tos/project-name/
# jupyter==1.1.1
define proof.services
name: jupyter-lab 
services:
  lab: &base
    hostname: lab
    stdin_open: true
    tty: true
    privileged: true
    entrypoint: bash
    build:
      context: .
      dockerfile_inline: |
        # inherit from the lean prover image defined in `lean.mk`
        FROM compose.mk:Lean.base
        RUN apt-get update 
        RUN apt-get install -y git make curl sudo python3.11-venv python3-pip wget
        RUN pip3 install jupyter --break-system-packages
        #RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf > /usr/local/bin/elan-init.sh
        #RUN bash /usr/local/bin/elan-init.sh -y 
        #ENV PATH="$PATH:/root/.elan/bin"
        #RUN lean --help
        #RUN lake new project
        #RUN cd project && printf '[[require]]\nname = "mathlib"\nscope = "leanprover-community"' >> lakefile.toml
        #RUN cd project && lake update && lake build
        #RUN pip install lean-dojo --break-system-packages
        COPY ./demos/data/jupyter/kernels/ /usr/share/jupyter/kernels/
        COPY ./demos/data/jupyter/lab/ /usr/local/share/jupyter/lab/
    ports: ['9999:9999']
    working_dir: /lab
    volumes:
      - ${PWD}:/lab
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
      #- ${PWD}/demos/data/jupyter/:/usr/local/share/jupyter/
endef 

# Autogenerate target scaffolding for each service.
$(eval $(call compose.import.def,  ▰,  TRUE, proof.services))

demo.entry: demo.init  \
	lab/up.detach flux.apply.later/10/open.notebook \
	tux.open/lab/exec/jupyter.up,lab/shell


open.notebook:
	@# Attempts to open a browser pointed at jupyter lab.
	@# (This requires python on the host and can't run from docker)
	python3 -c"import webbrowser; webbrowser.open(\"${lab_url}\")" \
	|| $(call log.target, ${red}cannot open browser!)

demo.init: docker.from.def/Lean.base lab/build
	@# We inherit the base-image from `demos/lean.mk`, 
	@# so make sure it's built first, then build local compose file.

jupyter.up:
	$(call tux.log, Starting lab server)
	jupyter lab \
	--allow-root --no-browser \
	--ip=0.0.0.0 --port=9999 \
	--ServerApp.token= --ServerApp.password= \
	--ServerApp.root_dir=/lab/demos/data/jupyter/