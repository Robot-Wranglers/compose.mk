#!/usr/bin/env -S make -f
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
#   USAGE: make -f demos/notebooking.mk lab.ui
#   USAGE: make -f demos/notebooking.mk lab.pipeline

include compose.mk
.DEFAULT_GOAL := __main__
lab.url.base=http://localhost:9999
lab.url=${lab.url.base}/lab/tree/notebooks
jupyter.root=demos/data/jupyter
jupyter.notebook.root=${jupyter.root}/notebooks
jupyter.kernels.root=${jupyter.root}/kernels

__main__:; $(call log, ${red}Provide a target like 'lab.ui' or 'lab.pipeline' or use 'help' for help.)
# Configuration for TUI pane contents. 
lab.tui_panes=lab.notebook.open/networkx-atlas.ipynb,lab.up

# A filter to pull b64 data data out of jupyter notebook outputs
jq.img.filter='.cells[]|select(.outputs!=null).outputs[]|select(.output_type=="display_data").data["image/png"]'

# This constants configures tmux pane geometry.
lab.tui.geometry=c3f2,231x57,0,0[231x48,0,0,1,231x8,0,49{125x8,0,49,2,105x8,126,49,4}]

# Autogenerate target scaffolding for each kernel container
$(eval $(call compose.import, demos/data/jupyter/docker-compose.fmtk.yml, fmtk))

# Autogenerate scaffolding for the jupyter-lab container.
$(eval $(call compose.import, demos/data/jupyter/docker-compose.jupyter.yml, jupyter))

## Use the service scaffolding to create language kernels.
## Kernel-targets must accept 1 argument in the form a filename,
## and then run on it.  Mostly this is a simple mapping, but 
## depending on the container entrypoint/command setup, we may
## have to massage the invocation.  See z3_py / lean4_script.
kernel.alloy/%:; ${docker.curry.command}/fmtk/alloy
kernel.lean4/%:; ${docker.curry.command}/fmtk/lean4
kernel.z3/%:; ${docker.curry.command}/fmtk/z3
kernel.z3_py/%:; entrypoint=python cmd="${*}" ${make} fmtk/z3
kernel.lean4_script/%:; cmd="--run ${*}" ${make} fmtk/lean4

# Dynamically filters available targets, returning ones above that match "kernel.*" 
kernels.list: mk.targets.filter.parametric/kernel.

## Generates kernel.json files for each of the "kernel.*" targets above.  
## This involves a template for jupyter kernelspec JSON, which is a starting place 
## for generating dynamic kernels.  This works by deferring most of the kernel 
## behaviour to a base class (i.e. BaseK), and basically adjusts environment 
## variables to configure kernel-names, kernel-commands, etc.. just in time.
lab.gen.kernels: flux.starmap/.kernel.from.target,kernels.list
.kernel.from.target/%:; cmd="${make} ${*}" ${make} .kernel.gen/${*}
.kernel.gen/%:
	mkdir -p ${jupyter.kernels.root}/${*} \
	&& kfile="${jupyter.kernels.root}/${*}/kernel.json" \
	&& $(call log.target.part1, generating) \
	&& touch $${kfile} \
	&& disp_name="`echo ${*}|cut -d. -f2`" \
	&& disp_name=$${display_name:-$${disp_name}} \
	&& cat ${jupyter.root}/kernel.json.template \
	| ${jq} ".env.cmd = \"$${cmd}\"" \
	| ${jq} ".env.kernel_name = \"$${disp_name}\"" \
	| ${jq} ".display_name = \"$${disp_name}\"" \
	| ${jq} ".language = \"$${disp_name}\"" \
	| ${jq} ".env.kernel_banner = \"experimental kernel created for target @ ${*} \"" \
	| ${jq} ".env.workspace = \"/lab\"" \
	> $${kfile} \
	&& $(call log.target.part2, ${dim_ital}$${kfile})

## A small bridge to the jupyter lab HTTP API.
## This isn't necessarily that useful since we have CLI access to 
## jupyter, but this shows that it's accessible and calls to curl 
## could be replaced with `nbclient`, etc.
api.kernels:
	@# Show kernel status, according to the web ui 
	curl -s "${lab.url.base}/api/kernels" | ${jq} .

api.kernels.busy:
	@# Shows only busy kernels 
	curl -s "${lab.url.base}/api/kernels" \
		| ${jq} '.[] | select(.execution_state=="busy")'

api.sessions:
	@# Show sessions 
	curl -s "${lab.url.base}/api/sessions" | ${jq} .

## Top-level interfaces for the lab.
lab.pipeline: lab.init lab.notebooks.preview api.kernels lab.stop
	@# Pipeline-mode interface.  

export geometry=${lab.tui.geometry}
lab.ui: lab.init tux.open.horizontal/${lab.tui_panes}
	@# UI-mode.  Launches the jupyter server in a pane, and 
	@# summarizes project status / offer debugging shells elsewhere

## Top level command and control for the lab ensemble.
lab.init: \
	jupyter.stop jupyter.build.quiet fmtk.build.quiet \
	lab.notebooks.normalize lab.gen.kernels \
	lab.serve.background lab.summary
	@# Clean initialization.  This syncs updates but won't force rebuild
	@# Besides background the jupyter lab server, it also synchronizes 
	@# raw .ipynb with paired markdown equivalent using `jupytext`.

lab.notebook.preview/%:
	@# Shows input and execution for a single notebook.
	@# Console friendly, colored markdown rendering, and usable from the host.
	bname=`basename ${*}` \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ${no_ansi}( ${bold_under}input${no_ansi})) \
	&& quiet=1 ${make} lab.dispatch/self.notebook.preview.in/${*} | ${stream.markdown} \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ${no_ansi}( ${bold_under}output${no_ansi})) \
	&& $(call io.mktemp) \
	&& quiet=1 ${make} lab.dispatch/self.notebook.exec/${*} \
	&& quiet=1 ${make} lab.dispatch/self.notebook.preview.out/${*} > $${tmpf} \
	&& cat $${tmpf} | ${stream.markdown} \
	&& cat $${tmpf} | grep '!\[png\]' \
	  && ($(call log.target, detected image. attempting preview..) \
	      && ${make} lab.notebook.preview.images/${*} \
	      || $(call log.target, preview failed.  multiple images or incompatible file types)) \
	  || true

lab.notebook.preview.images/%:
	@# Try to yank the images from notebook output.
	@# This is naive, but we try to extract them anyway 
	@# for a low-resolution console preview that can 
	@# give a hint what changed.  Unfortunately glow 
	@# doesn't render markdown images, but we can 
	cat ${*} | ${jq} -r ${jq.img.filter} \
		| base64 -d | ${stream.img}

lab.notebook.open/%:
	@# Open the given notebook in the TUI browser.  
	@# (This is used as a widget by `lab.ui`)
	url="${lab.url.base}/notebooks/notebooks/${*}" ${make} tux.browser

lab.notebooks:
	@# List notebooks.  This assumes normalization 
	@# has already happened, so we only return .ipynb
	(ls ${jupyter.notebook.root}/*.ipynb || true) \
		| grep -v Untitled | grep -v Copy 

lab.notebooks.normalize: lab.dispatch/self.notebooks.normalize
	@# Normalize / synchronize all notebook representations.

lab.notebooks.preview: flux.starmap/lab.notebook.preview,lab.notebooks
	@# Previews input, then executes the notebook and displays just output.
	@# (This is a pipeline, but we ignore order and don't do IO between notebooks)

lab.running:; strict=1 ${make} lab.ps
	@# Succeeds only if the lab is currently running.

lab.serve: lab.stop lab.serve.background lab.logs
	@# Blocking jupyter lab server

lab.serve.background: lab.up.detach
	@# Non-blocking jupyter lab server

lab.summary: lab.wait lab.test 
	@# Waits for jupyterlab to ready, then describes available kernels / notebooks
	echo "Available notebooks:"
	${make} lab.notebooks|${stream.indent}
	echo "Markdown notebooks:"
	ls ${jupyter.notebook.root}/*.md | ${stream.indent}
	
lab.test: lab.dispatch/self.kernelspec.list
	@# Runs a simple test-case for the lab

lab.wait: flux.loop.until/lab.running
	@# Waits for the jupyter lab service to become ready

lab.webpage.open: lab.wait
	@# Attempts to open a browser pointed at jupyter lab.
	@# (This requires python on the host and can't run from docker)
	$(call log.target, ${red}opening ${lab.url})
	python3 -c"import webbrowser; webbrowser.open(\"${lab.url}\")" \
		|| $(call log.target, ${red}could not open browser!)

## Low level helpers, these need to run in the lab container.
self.kernelspec.list:
	@# Show the available kernels 
	jupyter kernelspec list

self.notebook.exec/%:
	@# Actually run a notebook, updating it in-place.
	jupyter execute ${*} --inplace

self.notebooks.normalize:
	$(call log.target, Pairing and syncing all markdown notebooks with ipynbs)
	${make} self.notebook.normalize/${jupyter.notebook.root}/*.md
self.notebook.normalize/%:
	@# Runs the bidirectional sync from ipynb / notebooks-as-code markdown. 
	jupytext --set-formats ipynb,md --update --sync ${*} | ${stream.as.log}

self.notebook.preview.in/%:
	@# Show markdown from ipnyb, pre-execution.  
	@# (We exclude the output because it might change)
	jupyter nbconvert --to $${format:-markdown} --log-level WARN \
		--stdout --MarkdownExporter.exclude_output=True ${*}
self.notebook.preview.out/%:
	@# Shows markdown from ipynb, post-execution.  
	@# (We exclude the input and labels to just show output.)
	jupyter nbconvert --to $${format:-markdown} --log-level WARN \
		--stdout --no-input --MarkdownExporter.exclude_markdown=True ${*}