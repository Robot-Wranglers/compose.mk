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
#   USAGE: ./demos/notebooking.mk lab.tui
#   USAGE: ./demos/notebooking.mk lab.pipeline
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

include compose.mk

# Main entrypoint, just shows usage hints 
.DEFAULT_GOAL := __main__
__main__:; $(call log, ${red}Provide a target like 'lab.tui' or 'lab.pipeline' or use 'help' for help.)

# Jupyter lab URL
lab.url.base=http://localhost:9999
lab.url=${lab.url.base}/lab/tree/notebooks

# Configuration for TUI pane contents. 
lab.tui_panes=lab.notebook.open/networkx-atlas.ipynb,lab.up

# Constants to configure tmux pane geometry.
lab.tui.geometry=c3f2,231x57,0,0[231x48,0,0,1,231x8,0,49{125x8,0,49,2,105x8,126,49,4}]

# Jupyter constants relative to wd; lab constants 
jupyter.root=demos/data/jupyter
jupyter.notebook.root=${jupyter.root}/notebooks
jupyter.kernels.root=${jupyter.root}/kernels

# A filter to pull b64 data data out of jupyter notebook outputs
jq.img.filter='.cells[]|select(.outputs!=null).outputs[]|select(.output_type=="display_data").data["image/png"]'

# Autogenerate target scaffolding for each kernel container
$(eval $(call compose.import, ${jupyter.root}/docker-compose.fmtk.yml, fmtk))

# Autogenerate scaffolding for the jupyter-lab container.
$(eval $(call compose.import, ${jupyter.root}/docker-compose.jupyter.yml, jupyter))

## Next section uses the service scaffolding to create target-handles for language kernels
## dynamically.  Although `compose.import` already created handles for all the containers involved, 
## we want to plan for being able to import from other compose files, or use future targets as 
## kernels directly.  This means we want carefully designed namespaces.  Another wrinkle is that 
## kernel-invocation involves accepting a filename as argument.  Thus for each service, we map
## a new target `kernel.<svc>/<fname>` --> `fmtk/<svc>.command/<fname>`.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Maps compose-services to future kernels
# Loop over the kernel list, and creating a target handle for each.
kernel_services=$(call compose.services, ${jupyter.root}/docker-compose.fmtk.yml)
kernel_target_names=$(foreach svc, ${kernel_services}, kernel.$(svc))
$(foreach svc, ${kernel_services}, $(eval  kernel.$(svc)/%:; $${make} fmtk/$(svc).command/$${*}))

kernels.list:
	@# A target to list available kernels.  Importantly, this is kernels according 
	@# to compose.mk, *not* jupyter, and it is how we bootstrap the jupyter kernels.
	@#
	@# Returns both the kernels that are directly mapped from compose-services 
	@# as well as *any targets defined in this file* matching the "kernel.*" pattern.
	@#
	quiet=1 \
	&& ( echo "${kernel_target_names}" \
		&&  ${make} mk.targets.filter.parametric/kernel. \
		|| true ) \
	| ${stream.nl.to.space}

kernel.echo/%:
	@# Demonstrating a jupyter kernel that's *not* coming from the 
	@# fmtk compose file.  This kernel simply echoes whatever code
	@# is sent to it, but you can imagine it using yet another docker 
	@# container that we don't need to customize, or imagine it activating
	@# a specific python venv, or whatever.
	@#
	cat ${*}

## Next section generates kernel.json files for each of the "kernel.*" targets above,
## regardless of whether those targets are static or dynamic.  This step involves
## a template for jupyter kernelspec JSON, which is our starting place for generating
## dynamic kernels on the jupyter side.  This works by deferring most of the kernel 
## behaviour to a base class (i.e. `BaseK`), and basically adjusts environment variables 
## to configure kernel-names, kernel-commands, etc.. just in time.  See the appendix in 
## the main docs for `basek.py` and kernel.json.template for more details.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lab.gen.kernels: flux.starmap/.kernel.from.target,kernels.list
.kernel.from.target/%:; cmd="${make} ${*}" ${make} .kernel.gen/${*}
.kernel.gen/%:
	mkdir -p ${jupyter.kernels.root}/${*} \
	&& kfile="${jupyter.kernels.root}/${*}/kernel.json" \
	&& $(call log.target.part1, generating) \
	&& touch $${kfile} \
	&& disp_name="`echo ${*}|cut -d. -f2`" \
	&& disp_name=$${display_name:-$${disp_name}} \
	&& cat ${jupyter.root}/kernel.base/kernel.json.template \
	| ${jq} ".env.cmd = \"$${cmd}\"" \
	| ${jq} ".env.kernel_name = \"$${disp_name}\"" \
	| ${jq} ".display_name = \"$${disp_name}\"" \
	| ${jq} ".language = \"$${disp_name}\"" \
	| ${jq} ".env.kernel_banner = \"experimental kernel created for target @ ${*} \"" \
	| ${jq} ".env.workspace = \"/lab\"" \
	> $${kfile} \
	&& $(call log.target.part2, ${dim_ital}$${kfile})

## Next section is a small bridge to the jupyter lab HTTP API.  This isn't necessarily 
## that useful since we have CLI access to jupyter, but this shows that it's accessible 
## and calls to `curl` could be replaced with `nbclient`, etc.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
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
lab.tui: lab.init tux.open.horizontal/${lab.tui_panes}
	@# UI-mode.  By default this launches the jupyter server 
	@# in one tmux pane for log viewing, then opens a 
	@# TUI webbrowser (carbonyl) that's pointed at it 

## Top level command and control for the lab ensemble.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lab.init: \
	tux.require jupyter.stop jupyter.build fmtk.build \
	lab.notebooks.normalize lab.gen.kernels \
	lab.serve.background lab.summary
	@# Clean initialization.  This syncs updates but won't force rebuild
	@# Besides background the jupyter lab server, it also synchronizes 
	@# raw .ipynb with paired markdown equivalent using `jupytext`.

lab.notebook.exec/%:
	quiet=1 ${make} lab.dispatch/self.notebook.exec/${*}

lab.notebook.preview/%:
	@# Shows input and execution for a single notebook.
	@# Console friendly, colored markdown rendering, and usable from the host.
	bname=`basename ${*}` \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ${no_ansi}( ${bold_under}input${no_ansi})) \
	&& quiet=1 ${make} lab.dispatch/self.notebook.preview.in/${*} | ${stream.markdown} \
	&& $(call log.target, ${dim_ital}$${bname} ${sep} ${no_ansi}( ${bold_under}output${no_ansi})) \
	&& label="notebook finished in" ${make} flux.timer/lab.notebook.exec/${*} \
	&& $(call io.mktemp) \
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
	@# (This is used as a widget by `lab.tui`)
	url="${lab.url.base}/notebooks/notebooks/${*}" ${make} tux.browser

lab.notebooks:
	@# List notebooks.  This assumes normalization 
	@# has already happened, so we only return .ipynb
	(ls ${jupyter.notebook.root}/*.ipynb || true) \
		| grep -v Untitled | grep -v Copy 

lab.notebooks.normalize normalize: lab.dispatch/self.notebooks.normalize
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
	$(call log.target, ${dim_cyan}Available notebooks:)
	${make} lab.notebooks | ${stream.indent}
	$(call log.target, ${dim_cyan}Markdown notebooks:)
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
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
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
	rm -f ${jupyter.notebook.root}/*.ipynb
	jupytext --set-formats ipynb,md --show-changes --sync ${*} | ${stream.as.log}

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