# demos/notebooking.mk: 
#   Demonstrates building a highly customized and self-contained console application,
#   where all the application components bootstrap themselves on demand.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   This defines/embeds two containers, one for the lean4 theorem prover[1] and one for alloylang[2].
#
#   Since there's no official docker images available, we have to provision containers from 
#   scratch, but using the ideas from `demos/matrioshka.mk`, we will build them in-situ and 
#   defer to `make` itself for the provisioning details.
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/demos/notebooking
#
#   USAGE: make -f demos/notebooking.mk
#   USAGE: make -f demos/notebooking.mk

include demos/lean.mk 

.DEFAULT_GOAL := lab.pipeline

lab.url=http://localhost:9999/lab/tree/notebooks
jupyter.notebook.root=demos/data/jupyter/notebooks
jupyter.kernels.root=demos/data/jupyter/kernels
lab.tui_panes=lab.summary,lab.up,lab.base.shell

# Use the service scaffolding to create language kernels.
# Kernel-targets must accept 1 argument in the form a filename,
# and then run on it.  Mostly this is a simple mapping, but 
# depending on the container entrypoint/command setup, we may
# have to massage the invocation.  See z3_py / lean4_script.
#
# * One kernel for Alloy lang
# * Two kernels for lean4 (script vs theorem style execution)
# * Two kernels for z3 (direct interface vs python-bindings)
# 
kernel.alloy/%:; cmd=${*} ${make} project.services/alloy
kernel.lean4/%:; cmd=${*} ${make} project.services/lean4
kernel.z3/%:; cmd="${*}" ${make} project.services/z3
kernel.z3_py/%:; entrypoint=python cmd="${*}" ${make} project.services/z3
kernel.lean4_script/%:; cmd="--run ${*}" ${make} project.services/lean4

# Dynamically filters available targets, returning ones above that match "kernel.*" 
kernels.list: mk.targets.filter.parametric/kernel.

# Generates kernel.json files for each of the "kernel.*" targets above.  This 
# involves a template for jupyter kernelspec JSON, which is a starting place for 
# generating dynamic kernels.  This works by deferring most of the kernel behaviour
# to a base class (i.e. BaseK), and basically adjusts environment variables to 
# configure kernel-names, kernel-commands, etc.. just in time.
lab.gen.kernels: flux.starmap/.kernel.from.target,kernels.list
.kernel.from.target/%:; cmd="${make} ${*}" ${make} .kernel.gen/${*}
.kernel.gen/%:
	mkdir -p ${jupyter.kernels.root}/${*} \
	&& kfile="${jupyter.kernels.root}/${*}/kernel.json" \
	&& $(call log.part1, generating kernel) \
	&& touch $${kfile} \
	&& disp_name="`echo ${*}|cut -d. -f2`" \
	&& disp_name=$${display_name:-$${disp_name}} \
	&& ${make} mk.def.read/.kernel.json.template \
	| ${jq} ".env.cmd = \"$${cmd}\"" \
	| ${jq} ".env.kernel_name = \"$${disp_name}\"" \
	| ${jq} ".display_name = \"$${disp_name}\"" \
	| ${jq} ".language = \"$${disp_name}\"" \
	| ${jq} ".env.kernel_banner = \"experimental kernel created for target @ ${*} \"" \
	| ${jq} ".env.workspace = \"/lab\"" \
	> $${kfile} \
	&& $(call log.part2, ${dim_ital}$${kfile}) \
	
.kernel.json.template={"argv":["python","-c", "import os; from basek import BaseK; from ipykernel.kernelapp import IPKernelApp; banner=os.environ.get('kernel_banner','kernel_banner'); name=os.environ.get('kernel_name','kernel_name'); IPKernelApp.launch_instance(kernel_class=type(name,(BaseK,),dict(banner=banner,)))", "-f", "{connection_file}"], "display_name":"name", "env": {"PYTHONPATH":"/usr/share/jupyter/kernels/basek"}}


## Top level
lab.init: lab.stop lab.build lab.notebooks.normalize lab.gen.kernels lab.serve.background
	@# Clean initialization.  This syncs updates but won't force rebuild
	@# Besides background the jupyter lab server, it also synchronizes 
	@# raw .ipynb with paired markdown equivalent using `jupytext`.
	${make} docker.from.def/Lean.base project.services.build
lab.notebooks.preview: flux.starmap/lab.notebook.preview,lab.notebooks
lab.notebook.preview/%:
	bname=`basename ${*}` \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ( ${no_ansi}${bold}${underline}input${no_ansi_dim} )) \
	&& quiet=1 ${make} lab.dispatch/self.notebook.preview.in/${*} | ${stream.markdown} \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ( ${no_ansi}${bold}${underline}output${no_ansi_dim} )) \
	&& $(call io.mktemp) \
	&& quiet=1 pipe=yes ${make} lab.dispatch/self.notebook.exec/${*} \
	&& quiet=1 ${make} lab.dispatch/self.notebook.preview.out/${*} > $${tmpf} \
	&& cat $${tmpf} | ${stream.markdown} \
	&& (cat $${tmpf} \
    | awk '/!\[png\]/ {gsub(/.*!\[png\]\(|\).*/,""); print}' \
    | xargs -I% -n1 sh -c "cat ${jupyter.notebook.root}/% | ${stream.img} || exit 255" \
    || true)
lab.notebooks.normalize:; quiet=0 ${make} lab.dispatch/self.notebooks.normalize
lab.notebooks:; (ls ${jupyter.notebook.root}/*.ipynb || true) | grep -v Untitled | grep -v Copy 
lab.open.webpage: lab.wait
	@# Attempts to open a browser pointed at jupyter lab.
	@# (This requires python on the host and can't run from docker)
	$(call log.target, ${red}opening ${lab.url})
	python3 -c"import webbrowser; webbrowser.open(\"${lab.url}\")" \
    || $(call log.target, ${red}cannot open browser!)
lab.pipeline: lab.init lab.notebooks.preview lab.stop
lab.running:; strict=1 ${make} lab.ps
lab.serve: lab.stop lab.serve.background
	@# Blocking jupyter lab server
	id=`${make} lab.ps | jq -r .ID` \
	&& ${make} docker.logs.follow/$${id}
lab.serve.background: lab.up.detach
	@# Non-blocking jupyter lab server
	$(call log.target, started server and detached.)
lab.summary: lab.wait lab.test lab.notebooks
lab.test: lab.dispatch/self.kernelspec.list
lab.ui: lab.init flux.apply.later/10/lab.open.webpage tux.open.horizontal/${lab.tui_panes}
lab.wait: flux.loop.until/lab.running


## Low level helpers, these need to run in the lab container.
self.kernelspec.list:; jupyter kernelspec list
self.notebook.exec/%:; jupyter execute ${*} --inplace
self.notebooks.normalize:
	$(call log.target, ${sep} Pairing and syncing all markdown notebooks with ipynbs)
	ls ${jupyter.notebook.root}/*.md | ${stream.peek} | xargs -I% sh -c "${make} self.notebook.normalize/%"
self.notebook.normalize/%:; jupytext --set-formats ipynb,md --update --sync ${*} | ${stream.as.log}
self.notebook.preview.in/%:; jupyter nbconvert --to $${format:-markdown} --log-level WARN --stdout --MarkdownExporter.exclude_output=True ${*}
self.notebook.preview.out/%:; jupyter nbconvert --to $${format:-markdown} --log-level WARN --stdout --no-input --MarkdownExporter.exclude_markdown=True ${*}

# atlas.preview:; ${make} lab.notebook.preview/${jupyter.notebook.root}/networkx-atlas.ipynb
# alloy.test:; ${make} lab.notebook.preview/demos/data/jupyter/notebooks/alloy-knights.ipynb
# lean_script.test:; ${make} lab.notebook.preview/demos/data/jupyter/notebooks/lean-script.ipynb
# lean4.test:; ${make} lab.notebook.preview/demos/data/jupyter/notebooks/lean-theorems.ipynb
# z3.test: z3.dispatch/.z3.test
# .z3.test:
# 	which z3; z3 --version
# 	pwd
# 	python demos/data/jupyter/notebooks/socrates.py
define project.services
# default to line-nos: https://github.com/jupyterlab/jupyterlab/issues/2395
# docker images https://github.com/Z3Prover/z3/discussions/5740
# https://github.com/z3prover/z3/pkgs/container/z3
# docker pull ghcr.io/z3prover/z3:ubuntu-20.04-bare-z3-sha-d66609e
name: jupyter 
services:
  
  # Only used for inheritance, this collects common config.
  lab.base: &base
    image: hello-world
    stdin_open: false
    tty: false
    environment:
      DOCKER_HOST_WORKSPACE: ${DOCKER_HOST_WORKSPACE:-${PWD}}
      CMK_DIND: "1"
      workspace: /lab
    working_dir: /lab
    volumes:
      - ${DOCKER_HOST_WORKSPACE:-${PWD}}:/lab
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
  
  # https://github.com/Z3Prover/z3/discussions/5740
  # z3 official container does not include bindings
  z3:
    <<: *base
    hostname: z3
    image: compose.mk:z3
    build:
      context: .
      dockerfile_inline: |
        FROM ghcr.io/z3prover/z3:ubuntu-20.04-bare-z3-sha-d66609e
        RUN apt-get update && apt-get install -y python3 python3-pip
        RUN pip3 install z3-solver==4.14.0.0
  
  # no official container for alloy-lang, 
  # but this one can run headless and return JSON
  alloy:
    <<: *base
    hostname: alloy
    image: compose.mk:alloy 
    build:
      context: .
      dockerfile_inline: |
        #FROM compose.mk:dind_base as dind_base
        FROM eloengineering/alloy-cli:4.2
        RUN apt-get update && apt-get install -y make procps g++ openjdk-17-jdk-headless 
    entrypoint: alloy-run
    command: /dev/stdin
  
  # Reuse the lean container we built in `demos/lean.mk`
  lean4: &lean4
    <<: *base
    hostname: lean4 
    image: compose.mk:Lean.base
    entrypoint: lean
  
  # main jupyter container, includes the server and the main python kernel
  lab:
    <<: *base
    hostname: lab
    image: compose.mk:lab
    entrypoint: jupyter 
    ports: ['9999:9999']
    build:
      context: .
      dockerfile_inline: |
        FROM compose.mk:dind_base
        USER root 
        RUN apt-get install -y python3.11-venv python3-pip 
        RUN apt-get install -y nodejs npm
        RUN pip3 install jupyter==1.1.1 nbconvert==7.16.6 ipywidgets==8.1.5 jupytext==1.16.7 --break-system-packages
        RUN apt-get install -y graphviz graphviz-dev 
        RUN pip install networkx==3.4.2 matplotlib==3.10.1 pygraphviz==1.14 --break-system-packages
        COPY ./demos/data/jupyter/kernels/ /usr/share/jupyter/kernels/
        COPY ./demos/data/jupyter/lab/ /usr/local/share/jupyter/lab/
    command: >-
      lab --allow-root --no-browser 
      --ip=0.0.0.0 --port=9999 --ServerApp.token= 
      --ServerApp.password= 
      --ServerApp.root_dir=/lab/demos/data/jupyter/
endef 
# Autogenerate target scaffolding for each service.
$(eval $(call compose.import.def,  project.services,  TRUE))

