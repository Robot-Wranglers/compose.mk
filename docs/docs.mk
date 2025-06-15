
## BEGIN: Docs-related targets
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

docs: docs.jinja #docs.mermaid
docs.build: docs.builder.build docs.builder.dispatch/.mkdocs.build
docs.init:; pynchon --version
docs.jinja_templates:; find docs | grep .j2 | sort  | grep -v macros.j2
docs.jinja:
	@# Render all docs with jinja
	${make} docs.jinja_templates \
	| xargs -I% sh -x -c "make docs.jinja/% || exit 255"
docs.jinja/% j/% jinja/%: docs.init
	@# Render the named docs twice (once to use includes, then to get the ToC)
	ls ${*}/*.j2 2>/dev/null >/dev/null \
	&& ( \
		$(call log,is dir); ls ${*}/*.j2 \
			| xargs -I% sh -x -c "${make} j/%") \
	|| case ${*} in \
		*.md.j2) ${make} .docs.jinja/${*};; \
		*.md) ${make} .docs.jinja/${*}.j2;; \
		*) ${make} .docs.jinja/${*}.md.j2;; \
	esac
.docs.jinja/%:
	ls ${*} ${stream.obliviate} || ($(call log,${red} no such file ${*}); exit 39)
	$(call io.mktemp) && first=$${tmpf} \
	&& set -x && pynchon jinja render ${*} -o $${tmpf} --print \
	&& dest="`dirname ${*}`/`basename -s .j2 ${*}`" \
	&& mv $${tmpf} $${dest}


mmd.args=--theme neutral -b transparent
docs.mermaid docs.mmd:
	@# Renders all diagrams for use with the documentation 
	find docs | grep '[.]mmd$$' | ${stream.peek} | ${flux.each}/.mmd.render
.mmd.render/%:
	output=`dirname ${*}`/`basename -s.mmd ${*}`.png \
	&& cmd="-i ${*} -o $${output} ${mmd.args}" ${make} mmd \
	&& cat $${output} | ${stream.img}


mkdocs: mkdocs.build mkdocs.serve
mkdocs.build build.mkdocs:; mkdocs build
.mkdocs.build:
	set -x && (make docs && mkdocs build --clean --verbose && tree site) \
	; find site docs|xargs chmod o+rw; ls site/index.html
mkdocs.serve serve:; mkdocs serve --dev-addr 0.0.0.0:8000

README.md:
	set -x && pynchon jinja render docs/README.md.j2 -o README.md