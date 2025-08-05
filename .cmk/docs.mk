## BEGIN: Docs-related targets
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

docs: docs.jinja
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


mkdocs: mkdocs.build mkdocs.serve
mkdocs.build build.mkdocs:; mkdocs build
.mkdocs.build:
	set -x && (make docs && mkdocs build --clean --verbose && tree site) \
	; find site docs|xargs chmod o+rw; ls site/index.html
mkdocs.serve serve:; mkdocs serve --dev-addr 0.0.0.0:8000

README.md:; set -x && pynchon jinja render docs/README.md.j2 -o README.md

define Dockerfile.css.min
FROM node:18-alpine
RUN npm install -g clean-css-cli
WORKDIR /workspace
ENTRYPOINT ["cleancss"]
endef
css.min/%: Dockerfile.build/css.min
	img=css.min cmd="--output ${*} ${*}" ${make} mk.docker

define Dockerfile.css.pretty
FROM node:18-alpine
RUN npm install -g prettier
WORKDIR /workspace
ENTRYPOINT ["prettier", "--write"]
endef
css.pretty/%: Dockerfile.build/css.pretty
	img=css.pretty cmd="--write ${*}" ${make} mk.docker

docs.build: Dockerfile.build/mkdocs 
	img=mkdocs ${make} mk.docker.dispatch/.mkdocs.build

define Dockerfile.mkdocs 
FROM python:3.9.21-bookworm
RUN pip3 install --break-system-packages pynchon==2025.3.20.17.28 mkdocs==1.5.3 mkdocs-autolinks-plugin==0.7.1 mkdocs-autorefs==1.0.1 mkdocs-material==9.5.3 mkdocs-material-extensions==1.3.1 mkdocstrings==0.25.2 mkdocs-redirects==1.2.2
RUN apt-get update && apt-get install -y tree jq make procps
endef

define Dockerfile.mermaid 
FROM ghcr.io/mermaid-js/mermaid-cli/mermaid-cli:10.6.1
USER root 
RUN apk add -q --update --no-cache coreutils build-base bash procps-ng
endef
docs.mermaid docs.mmd: Dockerfile.build/mermaid
	@# Renders all diagrams for use with the documentation 
	find docs | grep '[.]mmd$$' | ${stream.peek} | ${flux.each}/.mmd.render
.mmd.render/%:
	output=`dirname ${*}`/`basename -s.mmd ${*}`.png \
	&& img=mermaid \
		cmd="-i ${*} -o $${output} --theme neutral -b transparent" ${make} mk.docker \
	&& cat $${output} | ${stream.img}