#!/usr/bin/env -S bash
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# compose.mk: A minimal automation framework for working with containers.
#
# DOCS: https://github.com/robot-wranglers/compose.mk
#
# LATEST: https://github.com/robot-wranglers/compose.mk/tree/master/compose.mk
#
# FEATURES:
#   1) Library-mode extends `make`, adding native support for working with (external) container definitions
#   2) Stand-alone mode also available, i.e. a tool that requires no Makefile and no compose file.
#   3) A minimal, elegant, and dependency-free approach to describing workflow pipelines. (See flux.* API)
#   4) A small-but-powerful built-in TUI framework with no host dependencies. (See the tux.* API)
#
# USAGE: ( For Integration )
#   # Add this to your project Makefile
#   include compose.mk
#   $(eval $(call compose.import, ▰, ., docker-compose.yml))
#   # Example for target dispatch:
#   # A target that runs inside the `debian` container
#   demo: ▰/debian/.demo
#   .demo:
#       uname -n -v
#
# USAGE: ( Stand-alone tool mode )
#   ./compose.mk help
#   ./compose.mk help <namespace>
#   ./compose.mk help <prefix>
#   ./compose.mk help <target>
#
# USAGE: ( Via CLI Interface, after Integration )
#   # drop into debugging shell for the container
#   make <stem_of_compose_file>/<name_of_compose_service>/shell
#
#   # stream data into container
#   echo echo hello-world | make <stem_of_compose_file>/<name_of_compose_service>/shell/pipe
#
#   # show full interface (see also: https://github.com/robot-wranglers/compose.mk/bridge)
#   make help
#
# APOLOGIES:
#   In advance if you're checking out the implementation.  This is unavoidably gnarly in a lot of places.
#   No one likes a file this long, and especially make-macros are not the most fun stuff to read or write.
#   Breaking this apart would make development easier but complicate boilerplate required for integration
#   with external projects.  Pull requests are welcome! =P
#
# HINTS:
#   1) The goal is that the implementation is well tested, nearly frozen, and generally safe to ignore!
#   2) If you just want API or other docs, see https://github.com/robot-wranglers/compose.mk
#   3) If you need to work on this file, you want Makefile syntax-highlighting & tab/spaces visualization.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Let's get into the horror and the delight right away with shebang hacks. 
# The block below these comments looks like a comment, but it's not. That line,
# and a matching one at EOF, makes this file a polyglot, and so it is executable
# simultaneously as both a bash script and a Makefile.  This allows for some improvement 
# around the poor signal-handling that Make supports by default, and each CLI invocation 
# that uses this file directly is wrapped to bootstrap handlers. If relevant signals are 
# caught, they are passed back to make for handling.  (Only SIGINT is currently supported.)
#
# Signals are used sometimes to short-circuit `make` from attempting to parse the full CLI. 
# This supports special cases like `./compose.mk loadf` & container invocations that use ' -- '
# See docs & usage of `mk.interrupt` for details.
#
#/* \
_make_="make -sS --warn-undefined-variables -f ${0}"; trace="${TRACE:-${trace:-0}}"; \
no_ansi="\033[0m"; green="\033[92m"; dim="\033[2m"; sep="${no_ansi}//${dim}";\
case ${CMK_SUPERVISOR:-1} in \
	0) ([ "${trace}" == 0 ] || \
		printf "⓪  ᐂ ${sep}Skipping setup for signal handlers..\n${no_ansi}">/dev/stderr); \
		${_make_} ${@}; st=$?; ;; \
	1) ([ "${trace}" == 0 ] || \
		printf "⓪  ᐂ ${sep} Installing supervisor..\n\033[0m" > /dev/stderr); \
		export MAKE_SUPER=$(exec sh -c 'echo "$PPID"'); \
		[ "${trace}" == 1 ] && set -x || true;  \
		trap "${_make_} mk.supervisor.trap/SIGINT; " SIGINT; \
		${_make_} mk.supervisor.enter/${MAKE_SUPER} ${@} 2> >(sed '/^make.*:.*mk.interrupt\/SIGINT.*Killed/,/^make:.*Error.*/d' >/dev/stderr); \
		st=$? ; ${_make_} mk.supervisor.exit/${st}; st=$?; ;; \
esac \
; exit ${st}

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: Supervisor & Signals Boilerplate
## BEGIN: Colors, Logging, and Makefile-related Boilerplate
##
## This includes hints for determining Makefile invocations:
##   MAKE:          Alias for 'make'
##   MAKEFILE:      The path to the Makefile being used at the top-level
##   MAKE_CLI:      Full CLI invocation for this process (Reliable with Linux, somewhat broken for OSX?)
##   MAKEFILE_LIST: A list of includes, either used with 'include ..' or present at CLI with '-f ..'
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
SHELL:=bash
MAKEFLAGS:=-s -S --warn-undefined-variables
MAKEFLAGS+=--no-builtin-rules
.DEFAULT_GOAL?=help

.SUFFIXES:
.INTERMEDIATE: .tmp.* .flux.*

# Color constants and other stuff for formatting user-messages
ifeq ($(shell echo $${NO_COLOR:-}),1) # https://no-color.org/
no_ansi=
green=
yellow=
dim=
underline=
bold=
ital=
no_color=
red=
cyan=
else
no_ansi=\033[0m
green=\033[92m
yellow=\033[33m
blue=\033[38;5;27m
dim=\033[2m
underline=\033[4m
bold=\033[1m
ital=\033[3m
no_color=\e[39m
red=\033[91m
cyan=\033[96m
endif
dim_red=${dim}${red}
dim_cyan=${dim}${cyan}
bold_cyan=${bold}${cyan}
bold_green=${bold}${green}
dim_green=${dim}${green}
dim_ital=${dim}${ital}
no_ansi_dim=${no_ansi}${dim}
cyan_flow_left=${bold_cyan}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
cyan_flow_right=${no_ansi_dim}⋙${dim}${cyan}⋙${no_ansi}${bold_cyan}⋙${no_ansi}
green_flow_left=${bold_green}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
green_flow_right=${bold_green}⋙${dim}⋙${no_ansi_dim}⋙${no_ansi}
sep=${no_ansi}//

# Glyphs used in log messages 📢 🤐
_GLYPH_COMPOSE=${bold}≣${no_ansi}
GLYPH_COMPOSE=${green}${_GLYPH_COMPOSE}${dim_green}
_GLYPH_DOCKER=${bold}≣${no_ansi}
_GLYPH_MK=${bold}✱${no_ansi}
GLYPH_MK=${green}${_GLYPH_MK}${dim_green}
GLYPH_DOCKER=${green}${_GLYPH_DOCKER}${dim_green}
_GLYPH_IO=${bold}⇄${no_ansi}
GLYPH_IO=${green}${_GLYPH_IO}${dim_green}
_GLYPH_TUI=${bold}⏣${no_ansi}
GLYPH_TUI=${green}${_GLYPH_TUI}${dim_green}
_GLYPH_FLUX=${bold}Φ${no_ansi}
GLYPH_FLUX=${green}${_GLYPH_FLUX}${dim_green}
GLYPH_DEBUG=${dim}(debug=${no_ansi}${CMK_DEBUG}${dim})${no_ansi}
GLYPH_SPARKLE=✨
GLYPH_SUPER=${green}ᐂ${dim_green}
GLYPH_NUMS=① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩
glyph.num=${dim_green}$(word $(shell echo $$((${1} + 1))),${GLYPH_NUMS})${no_ansi}
glyph.tree_item:=├┈

export TERM?=xterm-256color

export DOCKER_HOST_WORKSPACE?=$(shell pwd)

OS_NAME:=$(shell uname -s)
ifeq (${OS_NAME},Darwin)
export DOCKER_UID:=0
export DOCKER_GID:=0
export DOCKER_UGNAME:=root
export MAKE_CLI:=$(shell echo `which make` `ps -o args -p $${PPID} | tail -1 | cut -d' ' -f2-`)
else
export DOCKER_UID:=$(shell id -u)
export DOCKER_GID:=$(shell getent group docker 2> /dev/null | cut -d: -f3 || id -g)
export DOCKER_UGNAME:=user
export MAKE_CLI:=$(shell \
	( cat /proc/$(strip $(shell ps -o ppid= -p $$$$ 2> /dev/null))/cmdline 2>/dev/null \
		| tr '\0' ' ' ) ||echo '?')
endif
export MAKE_CLI_EXTRA=$(shell printf "${MAKE_CLI}"|awk -F' -- ' '{print $$2}')
export MAKEFILE_LIST:=$(call strip,${MAKEFILE_LIST})
export MAKE_FLAGS=$(shell [ `echo ${MAKEFLAGS} | cut -c1` = - ] && echo "${MAKEFLAGS}" || echo "-${MAKEFLAGS}")
export MAKEFILE?=$(firstword $(MAKEFILE_LIST))
export TRACE?=$(shell echo "$${TRACE:-$${trace:-0}}")
ifeq (${TRACE},1)
$(shell printf "${yellow}${MAKE_CLI}${no_ansi}\n" > /dev/stderr)
else
endif 

# IMPORTANT: this is the way to safely call `make` recursively. 
# It determines MAKE and MAKEFILE_LIST are not reliable!
make=make ${MAKE_FLAGS} $(addprefix -f,$(shell echo "${MAKE_CLI}"|awk '{for(i=1;i<=NF;i++)if($$i=="-f"&&i+1<=NF){print$$(++i)}else if($$i~/^-f./){print substr($$i,3)}}' | xargs))

# Stream constants
stderr:=/dev/stderr
stdin:=/dev/stdin
devnull:=/dev/null
stderr_stdout_indent=2> >(sed 's/^/  /') 1> >(sed 's/^/  /')
stderr_devnull:=2>${devnull}
all_devnull:=2>&1 > /dev/null

# Literal newline and other constants 
define nl

endef
comma=,

# Aliases used with redirects
dash_x_maybe:=`[ $${TRACE} == 1 ] && echo -x || true`

trace_maybe=[ "${TRACE}" == 1 ] && set -x || true 
log.prefix.makelevel.glyph=${dim}$(call glyph.num, ${MAKELEVEL})${no_ansi}
log.prefix.makelevel.indent=$(foreach x,$(shell seq 1 $(MAKELEVEL)),)
log.prefix.makelevel=${log.prefix.makelevel.glyph} ${log.prefix.makelevel.indent}
log.prefix.loop.inner=${log.prefix.makelevel}${bold}${dim_green}${glyph.tree_item}${no_ansi}
log.stdout=printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n"
log=([ "$${quiet:-0}" == "1" ] || ( ${log.stdout} >${stderr} ))
log.noindent=(printf "${log.prefix.makelevel.glyph} `echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr})
log.fmt=( ${log} && (printf "${2}" | fmt -w 55 | ${stream.indent} | ${stream.indent} | ${stream.indent.to.stderr} ) )
log.escape=(printf \"${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n\" >${stderr})
log.trace=[ "${TRACE}" == "0" ] && true || (printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr} )
log.trace.fmt=( ${log.trace} && [ "${TRACE}" == "0" ] && true || (printf "${2}" | fmt -w 70 | ${stream.indent.to.stderr} ) )
log.trace.part1=[ "${TRACE}" == "0" ] && true || $(call log.part1, ${1})
log.trace.part2=[ "${TRACE}" == "0" ] && true || $(call log.part2, ${1})
log.target.rerouting=$(call log, ${GLYPH_IO} ${@} ${sep}${dim} Invoked from top; rerouting to tool-container)
log.trace.target.rerouting=( [ "${TRACE}" == "0" ] && true || $(call log.target.rerouting) )
log.json=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.run} ${1} | ${jq.run} . | ${stream.dim.indent.stderr}
log.json.min=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.run} ${1} | ${jq.run} -c . | ${stream.dim.indent.stderr}
log.target=$(call log, ${GLYPH_IO}${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep} ${dim_ital} $(shell printf "${@}" | cut -d/ -f2-))
tux.log=$(call log,${GLYPH_TUI} $(1))
io.log=$(call log,${GLYPH_IO} $(1))

# Logger suitable for loops.  
define log.loop.top # Call this at the top
printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr}
endef
define log.stdout.loop.item # Call this in the loop
(printf "${log.prefix.loop.inner}`echo "$(or $(1),)" | sed 's/^ //'`${no_ansi}\n")
endef
define log.loop.item 
 ( printf "${log.prefix.loop.inner}`echo "$(or $(1),)" | sed 's/^ //'`${no_ansi}\n" > ${stderr} )
endef
define log.trace.loop.top
[ "${TRACE}" == "0" ] && true || $(call log.loop.top, ${1})
endef
define log.trace.loop.item 
[ "${TRACE}" == "0" ] && true || $(call log.loop.item, ${1})
endef
# Logger suitable for action logging in 2 parts: <label> <action-result>
# Call this to show the label
log.stdout.part1=([ -z "$${quiet:-}" ] && (printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi} ${no_ansi_dim}..${no_ansi}") || true )
# Call this to show the result
log.stdout.part2=([ -z "$${quiet:-}" ] && (printf "`echo "${no_ansi}$(or $(1),)" | ${stream.lstrip}`${no_ansi}\n")|| true)

log.part1=(${log.stdout.part1}>${stderr})
log.part2=(${log.stdout.part2}>${stderr})

define _compose_quiet
2> >(\
	grep -vE '.*Container.*(Running|Recreate|Created|Starting|Started)' \
	>&2 \
	| grep -vE '.*Network.*(Creating|Created)' >&2 )
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: Colors, Logging, and Makefile-related Boilerplate
## BEGIN: Environment Variables
##
## Variables used internally:
##
## | Variable               | Meaning                                                          |
## | ---------------------- | ---------------------------------------------------------------- |
## | CMK_COMPOSE_FILE       | *Temporary file used for the embedded-TUI*                       |
## | CMK_DEBUG:             | 1 if normal debugging output should be shown, otherwise 0        |
## | CMK_DIND               | *Determines whether docker-in-docker is allowed*                 |
## | CMK_INTERNAL           | *1 if dispatched inside container, otherwise 0*                  |
## | CMK_SUPERVISOR         | *1 if supervisor/signals is enabled, otherwise 0*                |
## | COMPOSE_IGNORE_ORPHANS |  *Honored by 'docker compose', this helps to quiet output*       |
## | DOCKER_HOST_WORKSPACE  | *Needs override for correctly working with DIND volumes*         |
## | TRACE:                 | Increase verbosity (more detailed than CMK_DEBUG)                |
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

export COMPOSE_IGNORE_ORPHANS?=True
# export CMK_AT_EXIT_TARGETS=flux.stage.clean
export CMK_AT_EXIT_TARGETS=flux.noop
export CMK_COMPOSE_FILE?=.tmp.compose.mk.yml
export CMK_DIND?=0
export CMK_DEBUG?=1
export CMK_INTERNAL?=0
export CMK_SRC=$(shell echo ${MAKEFILE_LIST}|sed 's/ /\n/g'|grep compose.mk)
export CMK_SUPERVISOR?=1

ifneq ($(findstring compose.mk, ${MAKE_CLI}),)
export CMK_LIB=0
export CMK_STANDALONE=1
export CMK_SRC=$(findstring compose.mk, ${MAKE_CLI})
endif
ifeq ($(findstring compose.mk, ${MAKE_CLI}),)
export CMK_LIB=1
export CMK_STANDALONE=0
endif

${CMK_COMPOSE_FILE}:
	(ls ${CMK_COMPOSE_FILE} 2>/dev/null >/dev/null || CMK_DEBUG=0 ${make} mk.def.to.file/FILE.TUX_COMPOSE/${CMK_COMPOSE_FILE})

# Used internally.  If this is container-dispatch and DIND,
# then DOCKER_HOST_WORKSPACE should be treated carefully
ifeq ($(shell echo $${CMK_DIND:-0}), 1)
export workspace?=$(shell echo ${DOCKER_HOST_WORKSPACE})
export CMK_INTERNAL=0
endif
export CMK_EXTRA_REPO?=.

docker.images=($(call docker.tags.by.repo,compose.mk) ; $(call docker.tags.by.repo,${CMK_EXTRA_REPO})) | sort | uniq
docker.compose:=docker compose
docker.containers.all:=docker ps --format json
docker.run.base:=docker run --rm -i 

# NB: exit status doesn't work right without grep..
docker.images.filter=docker images --filter reference=${1} --format "{{.Repository}}:{{.Tag}}"|grep ${1}

# External tool used for parsing Makefile metadata
PYNCHON_CLI_VERSION=baf56b7
pynchon=$(trace_maybe) && ${pynchon.run}
pynchon.run=python -m pynchon.util.makefile

# Macros for use with jq/yq/jb, using local tools if available and falling back to dockerized versions
jq.docker=${docker.run.base} -e key=$${key:-} -v `pwd`:/workspace -w/workspace ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}
yq.docker=${docker.run.base} -e key=$${key:-} -v `pwd`:/workspace -w/workspace mikefarah/yq:$${YQ_VERSION:-4.43.1}
yq.run:=$(shell which yq 2>/dev/null || echo "${yq.docker}")
jq.run:=$(shell which jq 2>/dev/null || echo "${jq.docker}")
jq.run.pipe:=$(shell which jq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} -v `pwd`:/workspace -w/workspace ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}")
yq.run.pipe:=$(shell which yq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} -v `pwd`:/workspace -w/workspace mikefarah/yq:$${YQ_VERSION:-4.43.1}")
jb.run:=docker container run --rm ghcr.io/h4l/json.bash/jb:$${JB_CLI_VERSION:-0.2.2}
jb=${jb.run}
jq=${jq.run}
yq=${yq.run}

# Default base for debian, used for the embedded TUI amongst other things
export DEBIAN_CONTAINER_VERSION?=debian:bookworm

define docker.from.repo
ARG DOCKER_BASE
FROM ${DOCKER_BASE}
ARG HASH
ARG REPO_URL
RUN apt-get update && apt-get install -y curl git 
RUN git clone ${REPO_URL} /app && cd /app && git checkout ${HASH}
endef
docker.from.github/%:
	@# Creates the container from the given info.
	@# The given repository-name should end in '.git'
	@#
	@# USAGE:
	@#  ./compose.mk docker.from.github/<org>/<repo_name>/<hash>
	@#
	true \
	&& header="${GLYPH_DOCKER} docker.from.github ${sep} " \
	&& org="`printf ${*}|cut -s -d/ -f1`" \
	&& repo="`printf ${*}|cut -s -d/ -f2`" \
	&& export hash="`printf ${*}|cut -s -d/ -f3`" \
	&& export repo_url="https://github.com/$${org}/$${repo}" \
	&& $(call log, $${header} ${dim}repo_url=$${repo_url}) \
	&& ${make} docker.from.repo
	
docker.from.repo:
	@# Create a container from the given repository/hash.
	@# The repo-url needs to be fully qualified, starting with https:// and ending in .git.
	@# 
	@# USAGE:
	@#  hash=<..> repo_url=<..> ./compose.mk docker.from.repo
	@#
	true \
	&& export repo_name="`basename -s.git $${repo_url}`" \
	&& export tag="$${tag:-$${repo_name}:$${hash}}" \
	&& header="${GLYPH_DOCKER} docker.from.repo ${sep} " \
	&& $(call docker.images.filter,$${tag}) \
	; st=$$?; case $${st} in \
		0) $(call log, $${header} $${tag} cached); ;; \
		*) ( true \
			&& export docker_base="$${docker_base:-$${DEBIAN_CONTAINER_VERSION}}" \
			&& export docker_args="--build-arg HASH=$${hash} \
			--build-arg DOCKER_BASE=$${docker_base} \
			--build-arg REPO_URL=$${repo_url}" \
			&& $(call log, ${@} ${sep} $${repo_url}) \
			&& ${make} mk.def.read/docker.from.repo \
			| ${stream.peek} \
			| ${make} docker.build/- \
		); ;; \
	esac

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: data
## BEGIN: compose.* targets
## ----------------------------------------------------------------------------
##
## Targets for working with docker compose, without using the 'compose.import' macro.  
## These targets support basic operations on compose files like 'build' and 'clean', 
## so in some cases autogenerated targets will chain here.  
##
## ----------------------------------------------------------------------------
## DOCS:
##   * [1] https://github.com/robot-wranglers/compose.mk/docs/api#api-compose
##   * [2] https://github.com/robot-wranglers/compose.mk/#loading-compose-files
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

compose.build/%:
	@# Builds all services for the given compose file.
	@# This optionally runs for just the given service, otherwise on all services.
	@#
	@# USAGE:
	@#   ./compose.mk compose.build/<compose_file>
	@#   svc=<svc_name> ./compose.mk compose.build/<compose_file>
	@#
	$(call log, ${GLYPH_DOCKER} compose.build${no_ansi_dim} ${sep} ${green}${*} ${sep} $${svc:-all})
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${*} build $${svc:-}

compose.build.quiet/%:
	@#
	@# USAGE:
	@#   $ svc=svc1 ./compose.mk compose.build.quiet/<fname>
	@#
	$(call log.trace, ${GLYPH_DOCKER} compose.build.quiet ${sep}${dim} ${green}${*} ${sep} ${dim}extra=$${COMPOSE_EXTRA_ARGS})
	$(trace_maybe) \
	&& cmd="${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${*} build $${svc}" \
	make io.quiet.stderr.sh

compose.clean/%:
	@# Docker-compose down for the given compose file.
	@# This optionally runs on a given service, otherwise on all services.
	@# This is quiet, removes orphans, and removes the corresponding image(s).
	@#
	@# USAGE:
	@#   ./compose.mk compose.clean/<compose_file>
	@#   svc=<svc_name> ./compose.mk compose.clean/<compose_file> 
	@#
	header="${GLYPH_DOCKER} compose.clean ${sep} " && $(trace_maybe) \
	&& $(call log, $${header} ${dim}file=${*} ${sep} ${dim}svc=$${svc:-}) \
	&& ${docker.compose} -f ${*} \
		--progress quiet down -t 1 \
		--remove-orphans --rmi local $${svc:-}

compose.dispatch.sh/%:
	@# Static target that's used on given compose files.
	@# The interface is similar to the dynamic '<compose_stem>.dispatch',
	@# except that this is a backup plan for when 'compose.import' has not
	@# imported services more directly.
	@#
	@# USAGE: 
	@#   cmd=<shell_cmd> svc=<svc_name> compose.dispatch.sh/<fname>
	@#
	$(call log.trace, ${GLYPH_DOCKER} compose.dispatch ${sep} ${green}${*}) \
	&& ${trace_maybe} \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${*} run \
		--rm --remove-orphans \
		--entrypoint $${entrypoint:-bash} $${svc} ${dash_x_maybe} \
		-c "$${cmd:-true}" $(_compose_quiet)

compose.get.stem/%:
	@# Returns a normalized version of the stem for the given compose-file.
	@# A "stem" is just the basename without a suffix.
	@#
	@# USAGE:
	@#  ./compose.mk compose.get.stem/<fname>
	@#
	basename -s .yml `basename -s .yaml ${*}`

# compose.kernel:; ${make} $${make_extra:-} "`cat ${stdin} | ${stream.peek}`"
# 	@# Executes the input data on stdin as a kind of "script" that runs inside the current make-context.
# 	@# This basically allows you to treat targets as an instruction-set without any kind of 'make ... ' preamble.
# 	@#
# 	@# Since 'flux.*' targets allow for some conditions and flow-control, this might be useful now? 
# 	@# Eventually this will be expanded for use with IPython/Jupyter.
# 	@#
# 	@# USAGE: ( concrete )
# 	@#  echo flux.ok | ./compose.mk kernel
# 	@#  echo flux.apply/flux.ok,flux.ok | ./compose.mk kernel
	

compose.loadf: tux.require
	@# Loads the given file,
	@# then curries the rest of the CLI arguments to the resulting environment
	@# FIXME: this is linux-only due to usage of MAKE_CLI?
	@#
	@# USAGE:
	@#  ./compose.mk loadf <compose_file> ...
	@#
	true \
	&& words=`echo "$${MAKE_CLI#*loadf}"` \
	&& fname=`printf "$${words}" | sed 's/ /\n/g' | tail -n +2 | head -1` \
	&& words=`printf "$${words}" | sed 's/ /\n/g' | tail -n +3 | xargs` \
	&& cmd_disp="${dim_cyan}$${words:-(No commands given.  Defaulting to opening UI..)}${no_ansi}" \
	&& header="${GLYPH_IO} loadf ${sep} ${dim_green}${underline}$${fname}${no_ansi} ${sep}" \
	&& $(call log, $${header} $${cmd_disp}) \
	&& ls $${fname} > ${devnull} || (printf "No such file"; exit 1) \
	&& tmpf=./.tmp.mk \
	&& stem=`${make} compose.get.stem/$${fname}` \
	&& eval "$${LOADF}" > $${tmpf} \
	&& chmod ugo+x $${tmpf} \
	&& ( [ "$${TRACE}" == 1 ] \
		 && ( ( style=monokai ${make} io.file.preview/$${fname} \
		        && ${make} io.file.preview/$${tmpf} ) \
					2>&1 | ${stream.indent} ) \
		 || true ) \
	&& ( \
			$(call log.part1, $${header} ${dim}Validating services) \
			&& validation=`$${tmpf} $${stem}.services` \
			&& count=`printf "$${validation}"|wc -w` \
			&& validation=`printf "$${validation}" \
				| xargs | fmt -w 60 \
				| ${stream.indent} | ${stream.indent}` \
			&& $(call log.part2, ${dim_green}ok${no_ansi_dim} ($${count} services total)) \
		) \
	&& first=`make -f $${tmpf} $${stem}.services \
		| head -5 | xargs -I% printf "% " \
		| sed 's/ /,/g' | sed 's/,$$//'` \
	&& msg=`[ -z "$${words:-}" ] && echo 'Starting TUI' || echo "Starting downstream targets"` \
	&& $(call log, $${header} ${dim}$${msg}) \
	&& ${trace_maybe} \
	&& $(call log.trace, $${header} Handing off to generated makefile) \
	&& $(call mk.yield2, env -i HOME=${HOME} make ${MAKE_FLAGS} -f $${tmpf} $${words:-tux.open.service_shells/$${first}})

compose.services/%:
	@# Lists services available for the given compose file.
	@# Used when 'compose.import' hasn't been called for the given compose file.
	@# If 'compose.import' has been called, use '<compose_stem>.services' directly.
	@#
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${*} config --services | sort
compose.validate.quiet/%:; ${make} compose.validate/${*} >/dev/null 2>/dev/null

compose.validate/%:
	@# Validates the given compose file (i.e. asks docker compose to parse it)
	@#
	@# USAGE:
	@#   $ ./compose.mk compose.validate/<compose_file>
	@#
	header="${GLYPH_IO} compose.validate ${sep}" \
	&& $(call log.trace, $${header}  ${dim}extra="$${COMPOSE_EXTRA_ARGS}") \
	&& $(call log.part1, $${header} ${dim}$${label:-Validating compose file} ${sep} ${*}) \
	&& ${make} compose.services/${*} ${all_devnull} \
	; case $$? in \
		0) $(call log.part2, ok) && exit 0; ;; \
		*) $(call log.part2, failed) && exit 1; ;; \
	esac

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: compose.* targets
## BEGIN: docker.* targets
##
## The docker.* targets cover a few helpers for working with docker. 
##
## This interface is deliberately minimal, focusing on verbs like 'stop' and 'stat' more than verbs like 'build' and 'run'. That's because containers that are managed by docker compose are preferred, but some ability to work with inlined Dockerfiles for simple use-cases is supported. See stream.pygmentize for an example.
##
## DOCS:
##   * `[1]`: https://github.com/robot-wranglers/compose.mk/docs/api#api-docker
##
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

docker.clean:
	@# This refers to "local" images.  Cleans all images from 'compose.mk' repository,
	@# i.e. affiliated containers that are related to the embedded TUI, and certain things
	@# created by the 'docker.*' targets. No arguments.
	@#
	$(trace_maybe) \
	&& ${make} docker.images \
		| ${stream.peek} | xargs -I% sh -x -c "docker rmi -f compose.mk:% 2>/dev/null || true" \
	&& [ -z "$${CMK_EXTRA_REPO}" ] \
		&& true \
		|| (${make} docker.images \
			| ${stream.peek} | xargs -I% sh -c "docker rmi -f $${CMK_EXTRA_REPO}:% 2>/dev/null || true")

docker.images:; $(call docker.images)
	@# Returns only affiliated images from 'compose.mk' repository, 
	@# i.e. containers that are related to the embedded TUI, and/or 
	@# things created by compose.mk inside the 'docker.*' targets, etc.
	@# These are "local" images.
	@#
	@# Extensions (like 'k8s.mk') may optionally export a value for 
	@# 'CMK_EXTRA_REPO', which appends to the default list described above.

docker.images.all:=docker images --format json
docker.images.all:; ${docker.images.all}
	@# Like plain 'docker images' CLI, but always returns JSON
	@# This target is also available as a function.

docker.tags.by.repo=((${docker.images.all} | ${jq.run} -r ".|select(.Repository==\"${1}\").Tag" )|| echo '{}')
docker.tags.by.repo/%:; $(call docker.tags.by.repo,${*})
	@# Filters all docker images by the given repository.
	@# This helps to separate system images from compose.mk images.
	@# This target is also available as a function.
	@# See 'docker.images' for more details.
	
docker.build.maybe/%:
	@# Builds quietly, iff and only if the named image is not cached.
	@#
	@# USAGE:
	@#   ./compose.mk docker.build.maybe/<name>
	@#
	${docker.images} | grep -w "${*}" || ${make} docker.build.quiet/${*}

docker.build/%:
	@# Standard noisy docker build.
	@#
	@# USAGE:
	@#   tag=<tag_to_use> ./compose.mk docker.build/<name>
	@#
	$(trace_maybe) && docker build -t $${tag} $${docker_args:-} ${*}

docker.build.quiet/%:
	@# Builds the given dockerfile quietly, tagging it with 'tag.'
	@#
	@# USAGE:
	@#  tag=<tag_to_use> ./compose.mk docker.build.quiet/<name>
	@#
	docker build `[ $${TRACE} == 1 ] && true|| echo "-q"` -t $${tag} $${docker_args:-} ${*} > ${devnull}

docker.context:; docker context inspect
	@# Returns all of the available docker context. Pipe-friendly.

docker.context/%:
	@# Returns docker-context details for the given context-name.
	@# Pipe-friendly; outputs JSON from 'docker context inspect'
	@#
	@# USAGE: (shortcut for the current context name)
	@#  ./compose.mk docker.context/current
	@#
	@# USAGE: (using named context)
	@#  ./compose.mk docker.context/<context_name>
	@#
	case "$(*)" in \
		current) \
			${make} docker.context \
			|  ${jq.run} ".[]|select(.Name=\"`docker context show`\")" -r; ;; \
		*) \
			${make} docker.context \
			| ${jq.run} ".[]|select(.Name=\"${*}\")" -r; ;; \
	esac

# flux.if.then/flux.negate/docker.def.cached,docker.builDR
docker.def.is.cached/%:
	@# Answers whether the named define has a cached docker image
	@# This never fails and exits with "yes" if the image has been built at least once,
	@# and "no" otherwise, but it also respects whether 'force=1' has been set.
	@#
	header="${GLYPH_DOCKER} ${no_ansi_dim} Checking if ${dim_cyan}${ital}${*}${no_ansi_dim} is cached" \
	&& $(call log.trace.part1, $${header} ) \
	&& ( ${docker.images} || true) | grep --word-regexp "${*}" 2>/dev/null >/dev/null \
	; case $$? in \
		0) ( case $${force:-0} in \
				1) ($(call log.trace.part2, ${yellow}no${no_ansi_dim} (force is set)) && echo no;);; \
				*) ($(call log.trace.part2, ${dim_green}yes) && echo yes;);;  \
			esac); ;;  \
		*) $(call log.trace.part2, missing) && echo no; ;; \
	esac


docker.from.def/% docker.build.def/%:
	@# Builds a container, treating the given 'define' block as a Dockerfile.
	@# This implicitly prefixes the named define with 'Dockerfile.' to enforce 
	@# naming conventions, and make for easier cleanup.  Container tags are 
	@# determined by 'tags' var if provided, falling back to the name used 
	@# for the define-block.  Tags are implicitly prefixed with 'compose.mk:',
	@# for the same reason as the other prefixes.
	@#
	@# This is part of the mad-science[1] test-suite and not really a good idea =P
	@#
	@# USAGE: ( explicit tag )
	@#   tag=<my_tag> make docker.from.def/<my_def_name>
	@#
	@# USAGE: ( implicit tag, same name as the define-block )
	@#   make docker.from.def/<my_def_name>
	@#
	@# REFS:
	@#  [1]: https://github.com/robot-wranglers/compose.mk/blob/master/tests/Makefile.mad-science.mk
	@#
	def_name="Dockerfile.${*}" \
	&& tag="compose.mk:$${tag:-${*}}" \
	&& header="${GLYPH_DOCKER} docker.from.def ${sep} ${dim_cyan}${ital}$${def_name}${no_ansi_dim}" \
	&& $(call log.trace, $${header} ) \
	&& $(trace_maybe) \
	&& export builder=none \
	&& case `${make} docker.def.is.cached/${*}` in \
		yes) $(call log.trace,${GLYPH_DOCKER}${no_ansi_dim}  Tag ${bold}${ital}$${tag}${no_ansi_dim} is ready); ;; \
		no) ( $(call log.trace,${GLYPH_DOCKER}${no_ansi_dim}  Tag ${bold}${ital}$${tag}${no_ansi_dim} needs building) \
				&& case $${quiet:-1} in \
					1) ${make} mk.def.read/$${def_name}| tag=$${tag} ${make} docker.build.quiet/- ; ;; \
					*) ${make} mk.def.read/$${def_name}| tag=$${tag} ${make} docker.build/- ; ;; \
				esac \
				&& $(call log.trace,$${header} ${sep} ${no_ansi_dim} Built ok. (quiet=${bold}${ital}$${quiet:-1}${no_ansi_dim})) \
			); ;; \
	esac
		
docker.from.file/%:
	@# Builds a container from the given Dockerfile.  The 'tag' variable is required.
	@#
	@# USAGE:
	@#  tag=<tag_name> ./compose.mk docker.from.file/<fname>
	@#
	$(call log,${GLYPH_DOCKER} ${@} ${sep}${dim} ${dim_cyan}${*}${no_ansi_dim} as ${dim_green}$${tag}) \
	&& $(trace_maybe) \
	&& cat ${*} | ${stream.peek} | docker build -t $${tag} -

docker.from.url/%:
	@# Builds a container, treating the given 'url' as a Dockerfile.  The 'tag' variable is required.
	@# This is part of the mad-science[1] test-suite and not really a good idea =P
	@#
	@# USAGE:
	@#   make docker.Dockerfile/<my_def_name>
	@#   tag=<my_tag> make docker.from.url/<my_def_name>
	@#
	@# REFS:
	@#  [1]: https://github.com/robot-wranglers/compose.mk/blob/master/tests/Makefile.mad-science.mk
	@#
	$(call io.mktemp) && curl -sL "$${url}" > $${tmpf} \
	&& make docker.from.file/$${tmpf}

docker.help:; ${make} mk.namespace.filter/docker.
	@# Lists only the targets available under the 'docker' namespace.
	@#

docker.init.compose:
	@# Ensures compose is available.  Note that
	@# build/run/etc cannot happen without a file,
	@# for that, see instead targets like '<compose_file_stem>.build'
	@#
	cver="`${docker.compose} version`" \
	; $(call log, ${GLYPH_DOCKER} ${@} ${sep} ${no_ansi_dim} version ${sep} ${ital}$${cver}${no_ansi})

docker.init:
	@# Checks if docker is available, then displays version/context (no real setup)
	@#
	( dctx="`docker context show 2>/dev/null`" \
		; $(call log, ${GLYPH_DOCKER} ${@} ${sep} ${no_ansi_dim}context ${sep} ${ital}$${dctx}${no_ansi}) \
		&& dver="`docker --version`" \
		&& $(call log, ${GLYPH_DOCKER} ${@} ${sep} ${no_ansi_dim}version ${sep} ${ital}$${dver}${no_ansi})) \
	| ${stream.dim} | $(stream.to.stderr)
	${make} docker.init.compose

docker.commander:
	@# TUI layout providing an overview for docker.
	@# This has 3 panes by default, where the main pane is lazydocker, plus two utility panes.
	@# Automation also ensures that lazydocker always starts with the "statistics" tab open.
	@#
	$(call log, ${GLYPH_DOCKER} ${@} ${sep} ${no_ansi_dim}Opening commander TUI for docker)
	TUX_CMDR_PANE_COUNT=3 \
		TUX_LAYOUT_CALLBACK=.${@}.layout \
			${make} tux.commander/.tux.widget.lazydocker
.docker.commander.layout:
	geometry="${GEO_DOCKER}" \
	${make} \
		.tux.commander.layout \
		.tux.pane/2/flux.apply/docker.stat,io.envp/DOCKER \
		.tux.pane/1/.tux.widget.img

docker.network.panic:; docker network prune -f
	@# Runs 'docker network prune' for the entire system.

docker.panic: docker.stop.all docker.network.panic docker.volume.panic docker.system.prune
	@# Debugging only!  This is good for ensuring a clean environment,
	@# but running this from automation will nix your cache of downloaded
	@# images, and so you will probably quickly hit rate-limiting at dockerhub.
	@# It tears down volumes and networks also, so you don't want to run this in prod.
	@#
	docker rm -f $$(docker ps -qa | tr '\n' ' ') 2>/dev/null || true

docker.prune docker.system.prune:; docker system prune -a -f
	@# Runs 'docker system prune' for the entire system.

docker.ps:; docker ps --format json
	@# Like 'docker ps', but always returns JSON.

docker.run/%:
	@# Runs the named target inside the named docker container.
	@# This works for any image as given; See instead 'mk.docker.run' for
	@# a version that implicitly uses internally generated containers.
	@#
	@# USAGE:
	@#  img=<img> make docker.run/<target>
	@#
	@# EXAMPLE:
	@#  img=debian/buildd:bookworm ./compose.mk docker.run/flux.ok
	@#
	$(trace_maybe) \
	&& entrypoint=make \
		cmd="${MAKE_FLAGS} -f ${MAKEFILE} ${*}" \
			img=$${img} ${make} docker.run.sh
docker.run.image/%:
	@# Runs the given commands in the given image.
	@#
	@# USAGE:
	@#  entrypoint=<entry> cmd=<args_to_entrypoint> ./compose.mk docker.run.image/<img>
	@#
	@# EXAMPLE:
	@#  entrypoint=make cmd=flux.ok ./compose.mk docker.run.image/debian/buildd:bookworm
	@#
	$(trace_maybe) && img=${*} ${make} docker.run.sh

docker.run.def/%:
	@# Like 'docker.run.def', but unpacks arguments from target invocation.
	@#
	@# USAGE:
	@#  ./compose.mk docker.run.def/<def_name>/<image>
	@#
	def="`echo ${*} | cut -d/ -f1 `" \
	&& img=`echo ${*} | cut -d/ -f2- ` \
	${make} docker.run.def

docker.run.def:
	@# Treats the named 'define' as a script, then runs it inside the given container.
	@# This automatically detects whether input should be treated as a pipe.
	@#
	@# USAGE:
	@#  entrypoint=<entry> def=<def_name> img=<image> ./compose.mk docker.run.def
	@#
	true \
	&& $(call log, ${GLYPH_DOCKER} docker.run.def ${no_ansi}${sep} ${dim_cyan}${ital}$${def}${no_ansi} ${sep} ${bold}${underline}$${img}) \
	&& $(call io.mktemp) \
	&& (${make} mk.def.to.file/$${def}/$${tmpf} \
	&& script_pre="$${cmd:-}" && unset cmd \
	&& script="$${script_pre} $${tmpf}" img=$${img} ${make} docker.run.sh) ${stderr_stdout_indent}

docker.run.sh:
	@# Runs the given command inside the named container.
	@#
	@# This automatically detects whether it's used as a pipe & proxies stdin as appropriate.
	@# This always shares the working directory as a volume & uses that as a workspace.
	@# If 'env' is provided, it should be a comma-delimited list of variable names; 
	@# those variables will be dereferenced and passed into docker's "-e" arguments.
	@#
	@# USAGE:
	@#   img=... entrypoint=... cmd=... env=var1,var2 ./compose.mk docker.run.sh
	@#
	${trace_maybe} \
	&& image_tag="$${img}" \
	&& entry=`[ "$${entrypoint:-}" == "none" ] && echo ||  echo "--entrypoint $${entrypoint:-bash}"` \
	&& cmd="$${cmd:-$${script:-}}" \
	&& header="${GLYPH_DOCKER} docker.run ${sep} ${dim}img=${bold}$${image_tag} ${sep}" \
	&& disp_cmd="`echo $${cmd} | sed 's/${MAKE_FLAGS}//g'|${stream.lstrip}`" \
	&& ( \
		[ -z "$${quiet:-}" ] \
		&& ( \
			$(call log, $${header} ${dim_cyan}[${no_ansi}${bold}$${entrypoint:-}${no_ansi}${cyan}] ${no_ansi_dim}$${disp_cmd})  \
			) \
		|| true ) \
	&& extra_env=`[ -z $${env:-} ] && true || ${make} .docker.proxy.env/$${env}` \
	&& tty=`[ -z $${tty:-} ] && true || echo "-t"` \
	&& cmd_args="\
		--rm -i $${tty} $${extra_env} \
		-e TERM="$${TERM}" \
		-e CMK_INTERNAL=1 \
		-v `pwd`:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		-w /workspace \
		$${entry} \
		$${docker_args:-}" \
	&& dcmd="docker run $${cmd_args}" \
	&& ([ -p ${stdin} ] && dcmd="cat ${stdin} | eval $${dcmd}" || true) \
	&& eval $${dcmd} $${image_tag} $${cmd}

.docker.proxy.env/%:
	@# Internal usage only.  This generates code that has to be used with eval.
	@# See 'docker.run.sh' for an example of how this is used.
	$(call log, ${GLYPH_DOCKER} docker.proxy.env${no_ansi} ${sep} ${dim}${ital}$${env:-}) \
	&& printf ${*} | sed 's/,/\n/g' \
	| xargs -I% printf " -e %=\"\`echo \$${%}\`\""; printf '\n'

docker.start/%:; img="${*}" entrypoint=none ${make} docker.run.sh
	@# Starts the named docker image with the default entrypoint
	@# USAGE: 
	@#   ./compose.mk docker.start/<img>

docker.start:; ${make} docker.start/$${img}
	@# Like 'docker.run', but uses the default entrypoint.
	@# USAGE: 
	@#   img=.. ./compose.mk docker.start

.docker.start/%:; ${make} docker.start/compose.mk:${*}
	@# Like 'docker.start' but implicitly uses 'compose.mk' prefix. This is used with "local" images.

docker.socket:; ${make} docker.context/current | ${jq.run} -r .Endpoints.docker.Host
	@# Returns the docker socket in use for the current docker context.
	@# No arguments & pipe-friendly.
	

docker.stat:
	@# Show information about docker-status.  No arguments.
	@#
	@# This is pipe-friendly, although it also displays additional
	@# information on stderr for humans, specifically an abbreviated
	@# table for 'docker ps'.  Machine-friendly JSON is also output
	@# with the following schema:
	@#
	@#   { "version": .., "container_count": ..,
	@#     "socket": .., "context_name": .. }
	@#
	$(call io.mktemp) && \
	${make} docker.context/current > $${tmpf} \
	&& printf "${GLYPH_DOCKER} docker.stat${no_ansi_dim}:\n" > ${stderr} \
	&& ${make} docker.init  \
	&& echo {} \
		| ${make} stream.json.object.append key=version \
			val="`docker --version | sed 's/Docker " //' | cut -d, -f1|cut -d' ' -f3`" \
		| ${make} stream.json.object.append key=container_count \
			val="`docker ps --format json| ${jq.run} '.Names'|wc -l`" \
		| ${make} stream.json.object.append key=socket \
			val="`cat $${tmpf} | ${jq.run} -r .Endpoints.docker.Host`" \
		| ${make} stream.json.object.append key=context_name \
			val="`cat $${tmpf} | ${jq.run} -r .Name`"

docker.stop:
	@# Stops one container, using the given timeout and the given id or name.
	@#
	@# USAGE:
	@#   ./compose.mk docker.stop id=8f350cdf2867
	@#   ./compose.mk docker.stop name=my-container
	@#   ./compose.mk docker.stop name=my-container timeout=99
	@#
	$(call log, ${GLYPH_DOCKER} docker.stop${no_ansi_dim} ${sep} ${green}$${id:-$${name}})
	export cid=`[ -z "$${id:-}" ] && docker ps --filter name=$${name} --format json | ${jq.run} -r .ID || echo $${id}` \
	&& case "$${cid:-}" in \
		"") \
			$(call log, ${dim}${GLYPH_DOCKER} docker.stop${no_ansi} ${sep} ${yellow}No containers found); ;; \
		*) \
			set -x && docker stop -t $${timeout:-1} $${cid} > ${devnull}; ;; \
	esac

docker.stop.all:
	@# Non-graceful stop for all running containers.
	@#
	@# USAGE:
	@#   ./compose.mk docker.stop name=my-container timeout=99
	@#
	ids=`docker ps -q | tr '\n' ' '` \
	&& count=`printf "$${ids}" | wc -w` \
	&& printf "${GLYPH_DOCKER} docker.stop.all${no_ansi_dim} ${sep} ${dim}(${dim_green}$${count}${no_ansi_dim} containers total)${no_ansi}\n" \
	&& [ -z "$${ids}" ] && true || (set -x && docker stop -t $${timeout:-1} $${ids})


docker.volume.panic:; docker volume prune -f
	@# Runs 'docker volume prune' for the entire system.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: docker.* targets
## BEGIN: io.* targets
##
## The `io.*` namespace has misc helpers for working with input/output, including utilities
## for working with temp files and showing output to users.  User-facing output leverages 
## charmbracelet utilities like gum[1] and glow[2].  Generally we use tools directly if they 
## are available, falling back to utilities in containers.
##
## See also `io.print.*` and `stream.pygmentize` for simpler versions of some of these features.
##
## DOCS:
##  * [0] https://github.com/robot-wranglers/compose.mk/docs/api#api-io
##  * [1] https://github.com/charmbracelet/gum
##  * [1] https://github.com/charmbracelet/glow
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

io.gum.div_style:=--border double --align center --width $${width:-$$(echo "x=$$(tput cols) - 5;if (x < 0) x=-x; default=30; if (default>x) default else x" | bc)}
io.gum.default_style:=--border double --foreground 2 --border-foreground 2

charm.glow:=docker run -i charmcli/glow -s dracula

io.gum.style=label="${1}" make io.gum.style

define Dockerfile.gum
# Default container does not include any shell, 
# which prevents using 'gum spin -- sleep ..', etc
FROM ${GUM_IMAGE:-ghcr.io/charmbracelet/gum} as gum
FROM ${DEBIAN_CONTAINER_VERSION:-debian:bookworm}
COPY --from=gum /usr/local/bin/gum /usr/bin
endef

io.gum=(which gum >/dev/null && ( ${1} ) \
	|| (entrypoint=bash cmd="${dash_x_maybe} -c '${1}'" quiet=1 \
		img=gum ${make} docker.from.def/gum mk.docker.run.sh)) > /dev/stderr
io.gum.tty=export tty=1; $(call io.gum, ${1})
io.gum.format.code=$(call io.gum, ${stream.stdin} | gum format -t code) | ${stream.trim}
io.gum.format.code:; $(call io.gum.format.code)
io.gum.spin:
	@# Runs `gum spin` with the given command/label.
	@#
	@# EXAMPLE:
	@#   cmd="sleep 2" label=title ./compose.mk io.gum.spin
	@#
	@# REFS:
	@# [1] https://github.com/charmbracelet/gum for more details.
	@#
	$(call io.gum.tty, gum spin \
		--spinner $${spinner:-meter} \
		--spinner.foreground $${color:-39} \
		--title \"$${label:-?}\" -- $${cmd:-sleep 2};)

io.gum.style:
	@# Helper for formatting text and banners using `gum style` and `gum format`.
	@# Expects label text under the `label variable, plus supporting optional `width`.
	@# Labels automatically go through 'gum format' before 'gum style', so templates are supported.
	@#
	@# REFS:
	@# [1] https://github.com/charmbracelet/gum for more details.
	@#
	@# EXAMPLE:
	@#   label="..." ./compose.mk io.gum.style 
	@#   width=30 label='...' ./compose.mk io.gum.style 
	@#
	$(call io.gum, gum style ${io.gum.default_style} ${io.gum.div_style} \"$${label}\")

io.gum.style/%:; ( width=`echo \`tput cols\` / ${*} | bc` ${make} io.gum.style )
	@# Prints a divider on stdout for the given fraction of the full terminal width,
	@# with given label.  This automatically detects console width, but
	@# it requires 'tput' (usually part of a 'ncurses' package).
	@#
	@# EXAMPLE: (A half-width labeled divider)
	@#   label=... ./compose.mk io.gum.style/2

##
## ----------------------------------------------------------------------------
## DOCS:
##   [1] https://github.com/robot-wranglers/compose.mk/docs/api#api-io
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Helper for working with temp files.  Returns filename,
# and uses 'trap' to handle at-exit file-deletion automatically.
# Note that this has to be macro for reasons related to ONESHELL.
# You should chain commands with ' && ' to avoid early deletes
define io.mktemp
	export tmpf=$$(TMPDIR=`pwd` mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
endef

# Similar to io.mktemp, but returns a directory.
define io.mktempd
	export tmpd=$$(TMPDIR=`pwd` mktemp -d ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -r $${tmpd}" EXIT
endef

io.stack/%:; $(call io.stack, ${*})
	@# Returns all the data in the named stack-file 
	@#
	@# USAGE:
	@#  ./compose.mk io.stack/<fname>
	@#  [ {.. data ..}, .. ]
io.stack=(${io.stack.require} && cat ${1} | ${jq.run} .)
	
io.stack.pop/%:; $(call io.stack.pop, ${*})
	@# Pops first item off the given stack file
	@#
	@# USAGE:
	@#  ./compose.mk io.stack/<fname>
	@#  {.. data ..}
io.stack.pop=(${io.stack} | ${jq.run} '.[0]'; ${io.stack} | ${jq.run} '.[1:]' > ${1}.tmp && mv ${1}.tmp ${1})

io.stack.require=( ls ${1} >/dev/null 2>/dev/null || echo '[]' > ${1})
log.file.contents=([ "$${quiet:-0}" == "1" ] || printf "`printf "${1}"|${stream.lstrip}` ${dim}`cat ${2}`${no_ansi}\n" > /dev/stderr) 
log.maybe=([ "$${quiet:-0}" == "1" ] || $(call log, ${1}))
io.stack.push/%:
	@# Returns all the data in the named stack-file 
	@#
	@# USAGE:
	@#   echo '<json>' | ./compose.mk io.stack.push/<fname>
	@#
	set -x \
	&& $(call io.stack.require, ${*}) && $(call io.mktemp) \
	&& header="${GLYPH_IO} io.stack.push ${sep}" \
	&& ([ "$${quiet:-0}" == "1" ] || $(call log, $${header} ${dim}stack=${no_ansi}${*})) \
	&& ${stream.stdin} | ${jq.run} -c . > $${tmpf} \
	&& $(call log.file.contents, ${log.prefix.makelevel}${green_flow_left}, $${tmpf}) \
	&& ${jq.docker} -n --slurpfile obj $${tmpf} --slurpfile stack ${*} '$$stack[0]+$$obj' > ${*}.tmp
	mv ${*}.tmp ${*}

io.bash:
	@# Starts an interactive shell with all the environment variables set
	@# by the parent environment, plus those set by this Makefile context.
	@#
	env bash -l

io.env:
	@# Dumps a relevant subset of environment variables for the current context.
	@# No arguments.  Pipe-safe since this is just filtered output from 'env'.
	@#
	@# USAGE:
	@#   ./compose.mk io.env
	@#
	${make} io.env.filter.prefix/PWD,CMK,KUBE,K8S,MAKE,TUI,DOCKER| grep -iv password|grep -iv passwd

io.env/% io.env.filter.prefix/%:
	@# Filters environment variables by the given prefix or (comma-delimited) prefixes.
	@#
	@# USAGE:
	@#   ./compose.mk io.env/<prefix1>,<prefix2>
	@#
	echo "${make}"
	echo ${*} | sed 's/,/\n/g' \
	| xargs -I% sh -c "env | grep -iv password|grep -iv passwd| grep \"^%.*=\"||true"

io.envp io.env.pretty .tux.widget.env:
	@# Pretty version of io.env, this includes some syntax highlighting.
	@# No arguments.  See 'io.envp/<arg>' for a version that supports filtering.
	@#
	@# USAGE:
	@#  ./compose.mk io.envp
	@#
	${make} io.env | ${make} stream.ini.pygmentize

io.envp/% io.env.pretty/% .tux.widget.env/%:
	@# Pretty version of 'io.env/<arg>', this includes syntax highlighting and also filters the output.
	@#
	@# USAGE:
	@#  ./compose.mk io.envp/<prefix_to_filter_for>
	@#
	@# USAGE: (only vars matching 'TUI*')
	@#  ./compose.mk io.envp/TUI
	@#
	${make} io.env/${*} | ${make} stream.ini.pygmentize

io.file.pygmentize/%:; fname="${*}" ${make} stream.pygmentize
	@# Syntax highlighting for the given file.
	@# Lexer will autodetected unless override is provided.
	@# Style defaults to 'trac', which works best with dark backgrounds.
	@#
	@# USAGE:
	@#   ./compose.mk io.file.pygmentize/<fname>
	@#   lexer=.. ./compose.mk io.file.pygmentize/<fname>
	@#   lexer=.. style=.. ./compose.mk io.file.pygmentize/<fname>
	@#
	@# REFS:
	@# [1]: https://pygments.org/
	@# [2]: https://pygments.org/styles/
	@#

io.file.preview/% stream.pygmentize/%:
	@# Outputs syntax-highlighting + line-numbers for the given filename to stderr.
	@#
	@# USAGE:
	@#  ./compose.mk io.file.preview/<fname>
	@#
	header="${GLYPH_IO} io.file.preview${no_ansi}" \
	&& $(call log, $${header} ${sep} ${dim}${bold}${*}) \
	&& style=trac ${make} io.file.pygmentize/${*} \
	| ${stream.nl.enum} | ${stream.indent.to.stderr}

io.help:; ${make} mk.namespace.filter/io.
	@# Lists only the targets available under the 'io' namespace.

io.gum.div=label=${@} ${make} io.gum.div
io.gum.div:
	@# Like `io.print.div`, but defaults to using `gum` to render it.
	@# If `label` is not provided, this defaults to using a timestamp.
	@#
	@# USAGE:
	@#  ./compose.mk io.gum.div label=".."
	@#
	label=$${label:-`date`} ${make} io.gum.style

io.print.div=label=${@} ${make} io.print.div
io.print.div:
	@# Prints a divider on stdout, defaulting to the full terminal width, with optional label.  
	@# This automatically detects console width, but it requires 'tput' (usually part of a 'ncurses' package).
	@#
	@# USAGE:
	@#  ./compose.mk io.print.div label=".." filler=".." width="..."
	@#
	@export width=$${width:-`tput cols||echo 45`} \
	&& label=$${label:-`date`} \
	&& label=$${label/./-} \
	&& if [ -z "$${label}" ]; then \
	    filler=$${filler:-¯} && printf "%*s${no_ansi}\n" "$${width}" '' | sed "s/ /$${filler}/g"; \
	else \
		label=" $${label//-/ } " \
	    && default="#" \
		&& filler=$${filler:-$${default}} && label_length=$${#label} \
	    && side_length=$$(( ($${width} - $${label_length} - 2) / 2 )) \
	    && printf "\n${dim}%*s" "$${side_length}" | sed "s/ /$${filler}/g" \
		&& printf "${no_ansi_dim}${bold}${green}$${label}${no_ansi_dim}" \
	    && printf "%*s${no_ansi}\n\n" "$${side_length}" | sed "s/ /$${filler}/g" \
	; fi

io.print.div/%:
	@# Prints a divider with a width of `term_width / <arg>`
	@#
	@# USAGE: (half-width labelled divider)
	@#  label.. ./compose.mk io.print.div/<int>
	@#
	width=`echo \`tput cols\` / ${*} \
	| bc 2>/dev/null || echo 45` ${make} io.print.div

io.quiet.stderr/%:; cmd="${make} ${*}" make io.quiet.stderr.sh
	@# Runs the given target, surpressing stderr output, except in case of error.
	@#
	@# USAGE:
	@#  ./compose.mk io.quiet/<target_name>
	@#
	true && header="${GLYPH_IO} io.quiet.stderr ${sep}" \
	&& $(call log,  $${header} ${green}$${*}) 

io.quiet.stderr.sh:
	@# Runs the given target, surpressing stderr output, except in case of error.
	@#
	@# USAGE:
	@#  ./compose.mk io.quiet/<target_name>
	@#
	$(call io.mktemp) \
	&& header="io.quiet.stderr ${sep}" \
	&& cmd_disp=`printf "$${cmd}" | sed 's/make -s --warn-undefined-variables/make/'` \
	&& $(call log, ${GLYPH_IO} $${header} ${green}$${cmd_disp}) \
	&& header="${_GLYPH_IO} io.quiet.stderr ${sep}" \
	&& $(call log, $${header} ${dim}( Quiet output, except in case of error. ))\
	&& start=$$(date +%s) \
	&& ([ -p ${stdin} ] && cmd="cat ${stdin} | ${cmd}" || true) \
	&& $${cmd} 2>&1 > $${tmpf} ; exit_status=$$? ; end=$$(date +%s) ; elapsed=$$(($${end}-$${start})) \
	; case $${exit_status} in \
		0) \
			$(call log, $${header} ${green}ok ${no_ansi_dim}(in ${bold}$${elapsed}s${no_ansi_dim})); ;; \
		*) \
			$(call log, $${header} ${red}failed ${no_ansi_dim} (error will be propagated)) \
			; cat $${tmpf} | awk '{print} END {fflush()}' > ${stderr} \
			; exit $${exit_status} ; \
		;; \
	esac

io.tail/%:
	@# Tails the named file, creating it first if necessary.
	@# This is always blocking and won't throw an error even if the file doesn't exist.
	@#
	@# USAGE:
	@#  ./compose.mk io.tail/<fname>
	@#
	$(trace_maybe) && touch ${*} && tail -f ${*} 2>/dev/null

io.wait io.time.wait: io.time.wait/1
	@# Pauses for 1 second.

io.time.wait/% io.wait/%:
	@# Pauses for the given amount of seconds.
	@#
	@# USAGE:
	@#   ./compose.mk io.time.wait/<int>
	@#
	$(call log,  ${GLYPH_IO} ${@}${no_ansi} ${sep} ${dim}Waiting for ${*} seconds..) \
	&& sleep ${*}


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: io.* targets
## BEGIN: mk.* targets
##
## The 'mk.*' targets are meta-tooling that include various extensions to `make` itself.  
## 
## A rough guide to stuff you can find here:
## 
## * `mk.supervisor.*` for signals and supervisors
## * `mk.def.*` for tools related to reading 'define' blocks
## * `mk.parse.*` for makefile parsing (used as part of generating help)
## * `mk.help.*` for help-generation
##
## For more details: 
## * Full API Docs: https://github.com/robot-wranglers/compose.mk/docs/api#api-mk
## * Signals & Supervisors: https://github.com/robot-wranglers/compose.mk/#signals-and-supervisors
## * Mad Science Test-Suite: https://github.com/robot-wranglers/compose.mk/tests/Makefile.mad-science.mk
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mk.unpack=$(shell printf "${*}" | cut -s -d${1} -f${2})
mk.def.dispatch/%:
	@# Reads the given <def_name>, writes to a tmp-file,
	@# then runs the given interpretter on the tmp file.
	@# 
	@# This requires that the interpretter is actually available..
	@# for dockerized access to similar functionality, see `docker.run.def`
	@#
	@# USAGE:
	@#   ./compose.mk mk.def.dispatch/<interpretter>/<def_name>
	@#
	@# HINT: for testing, use 'make mk.def.dispatch/cat/<def_name>'
	@#
	$(call io.mktemp) \
	&& export intr=`printf "${*}"|cut -d/ -f1` \
	&& export def_name=`printf "${*}" | cut -d/ -f2-` \
	&& ${make} mk.def.to.file/$${def_name}/$${tmpf} \
	&& [ -z $${preview:-} ] && true || ${make} io.file.preview/$${tmpf} \
	&& header="${GLYPH_MK} mk.def.dispatch${no_ansi}" \
	&& ([ $${TRACE} == 1 ] &&  printf "$${header} ${sep} ${dim}`pwd`${no_ansi} ${sep} ${dim}$${tmpf}${no_ansi}\n" > ${stderr} || true ) \
	&& $(call log, $${header} ${sep} ${cyan}[${no_ansi}${bold}$${intr}${no_ansi}${cyan}] ${sep} ${dim}$${tmpf}) \
	&& which $${intr} > ${devnull} || exit 1 \
	&& $(trace_maybe) \
	&& src="$${intr} $${tmpf}" \
	&& [ -p ${stdin} ] && cat ${stdin} | eval $${src} || eval $${src}

mk.def.read/%:
	@# Reads the named define/endef block from this makefile, emitting it to stdout.
	@#
	@# This works around make's normal behaviour of completely wrecking indention/newlines
	@# present inside the block.
	@#
	@# USAGE:
	@#   ./compose.mk mk.read_def/<name_of_define>
	@#
	$(eval def_name=${*})
	$(info $(value ${def_name}))

mk.def.to.file/%:
	@# Reads the given define/endef block from this makefile context, writing it to the given output file.
	@#
	@# USAGE: 
	@#   ./compose.mk mk.def.to.file/<def_name>/<fname>
	@#
	def_name=`printf "${*}" | cut -d/ -f1` \
	&& out_file=`printf "${*}" | cut -d/ -f2-` \
	&& header="${GLYPH_MK} mk.def ${sep}" \
	&& ([ ${CMK_DEBUG} == 1 ] && \
		$(call log, $${header} ${dim_cyan}${ital}$${def_name}${no_ansi} ${green_flow_right} ${dim}${bold}$${out_file}) \
		|| true) \
	&& ${make} mk.def.read/$${def_name} > $${out_file}

mk.ifdef=echo "${.VARIABLES}" | grep -w ${1} ${all_devnull}
mk.ifdef/%:; $(call mk.ifdef, ${*})
	@# Answers whether the given variable is defined.
	@# This is silent, and only communicates via the exit code.
	
mk.ifndef=echo "${.VARIABLES}" | grep -v -w ${1} ${all_devnull}
mk.ifndef/%:; $(call mk.ifndef,${*})
	@# Flips the assertion for 'mk.ifdef'.

mk.docker.run/%:; img="compose.mk:$${img}" ${make} docker.run/${*}
	@# Like `mk.docker.run`, but accepts image as an argument.
 
mk.docker.run:; img="compose.mk:$${img}" ${make} docker.run
	@# Like `docker.run`, but assumes the 'compose.mk:' prefix implicitly. 
	@# Requires `img` variable to already to be set.
	@# This is used with "local" images, i.e. what `compose.mk` uses 
	@# internally, or to handle embedded Dockerfiles.

mk.docker.run.sh:; img="compose.mk:$${img}" ${make} docker.run.sh
	@# Like docker.run.sh, but implicitly assumes the 'compose.mk:' prefix.

mk.get/%:; $(info ${${*}})
	@# Returns the value of the given make-variable


mk.help:
	@# Lists only the targets available under the 'mk' namespace.
	${make} mk.namespace.filter/mk.
mk.help.module/%:
	@# Shows help for the named module.
	@#
	@# USAGE:
	@#   ./compose.mk mk.help.module/<mod_name>
	@#
	$(call io.mktemp) && export key="${*}" \
	&& (${make} mk.parse.module.docs/${MAKEFILE} \
		| ${jq.run} ".$${key}"  2>/dev/null | ${jq.run} -r '.[1:-1][]' 2>/dev/null  \
	> $${tmpf}) \
	; [ -z "`cat $${tmpf}`" ] && exit 0 \
	|| ( \
		$(call log.stdout, ${GLYPH_MK} mk.help.module ${sep} ${bold}$${key}) \
		&& cat $${tmpf} | ${stream.glow} ) 

mk.help.block/%:
	@# Shows the help-block matching the given pattern.
	@#
	@# Similar to module-docs, but this need not match a target namespace.
	@#
	@# USAGE:
	@#   ./compose.mk mk.help.block/<pattern>
	@#
	pattern="${*}" ${make} mk.parse.block/${MAKEFILE} | ${stream.glow} 

mk.help.target/%:
	@# Shows help for the named target.
	@#
	@# USAGE:
	@#   ./compose.mk mk.help.target/<target_name>
	@#
	$(call io.mktemp) \
	&& export key="${*}" \
	&& ${make} mk.parse/${MAKEFILE} > $${tmpf} \
	&& (cat $${tmpf} | jq -r '.[env.key].docs[]' 2>/dev/null > .tmp.t) \
	|| ( cat $${tmpf} \
		| key="$${key}/%" jq -r '.[env.key].docs[]' 2>/dev/null \
			> .tmp.t) \
	; case $$? in \
		0) ( \
			$(call log, ${GLYPH_MK} mk.help.target ${sep} ${bold}$${key}) \
			&& printf "\n`cat .tmp.t`\n\n" | ${stream.indent} ); ;; \
		*) exit 0; ;; \
	esac

mk.help.search/%:
	@# Shows targets matching the given prefix.
	@#
	@# USAGE:
	@#   ./compose.mk mk.help.search/<pattern>
	@#
	$(call io.mktemp) \
	&& ${make} mk.parse.targets/${MAKEFILE} | grep "^${*}" \
	| sed 's/\/%/\/<arg>/g' > $${tmpf} \
	&& count="`cat $${tmpf}|wc -l`" \
	&& header="${dim} ${no_ansi}${GLYPH_MK} mk.help.search ${sep}" \
	&& max=5 \
	&& case $${count} in \
		1) exit 0; ;; \
		*) ( \
			$(call log, $${header} ${dim}pattern=${no_ansi}${bold}${*}) \
			; cat $${tmpf} | head -$${max} \
			| xargs -I% printf " ${dim_green}${glyph.tree_item} ${dim}${ital}%${no_ansi}\n" \
			| ${stream.indent}  \
			&& $(call log, $${header} ${dim}top ${no_ansi}$${max}${no_ansi_dim} of ${no_ansi}$${count}${no_ansi_dim} total )\
			); ;; \
	esac

mk.include/%:
	@# Dynamic includes.
	@# This is experimental stuff for reflection support.
	@#
	@# This works by using code-generation and turning over the execution, 
	@# so it requires the supervisor/signals hack to short-circuit the 
	@# original execution!
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk mk.include/<makefile>
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk mk.include/demos/no-include.mk foo:flux.ok mk.let/bar:foo bar
	@#
	header="${GLYPH_MK} mk.include ${sep} ${dim_cyan}${*} ${sep}" \
	&& $(call mk.yield2, ${make} -f${*} $${MAKE_CLI#*mk.include/${*}})

mk.let/%:
	@# Dynamic target assignment.
	@# This is experimental stuff for reflection support.
	@#
	@# This is basically a hack to work around the dreaded error 
	@# that "recipes may not define targets".  It should probably 
	@# be regarded as black magic that's best avoided!  
	@#
	@# This works by using code-generation and turning over the execution, 
	@# so it requires the supervisor/signals hack to short-circuit the 
	@# original execution!
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk mk.let/<newtarget>:<oldtarget>
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk mk.let/foo:flux.ok mk.let/bar:foo bar
	@#
	header="${GLYPH_MK} mk.let ${sep} ${dim_cyan}${*} ${sep}" \
	&& $(call log.part1, $${header} ${dim}Generating code) \
	&& $(call io.mktemp) \
	&& src="`printf ${*} | cut -d: -f1`: `printf ${*}|cut -d: -f2-`" \
	&& printf "$${src}" >  $${tmpf} \
	&& $(call log.part2, ${no_ansi_dim}$${tmpf}) \
	&& cmd="make ${MAKE_FLAGS} $${MAKEFILE_LIST// / -f} -f $${tmpf} $${MAKE_CLI#*mk.let/${*}}" \
	&& $(call mk.yield2, $${cmd} )

mk.pkg:
	@# Like `mk.self`, but includes `compose.mk` source also.
	@#
	archive="$${archive} ${CMK_SRC}" ${make} mk.self

mk.pkg/%:
	@# Packages the given make target as a single-file executable.
	@#
	@# This works by using to `makeself` to bundle/freezes/release 
	@# a self-extracting archive where we include the current Makefile, 
	@# and try to automatically include any related dependencies.
	@#
	@# To add other explicit deps to the archive, set `archive` 
	@# as a space-separated list of files or directories.
	@#
	@# USAGE:
	@#  archive="file1 file2 dir1" make -f ... mk.pkg/<target_name>
	@#
	label=${*} script=make \
	script_args="${MAKE_FLAGS} -f ${MAKEFILE} ${*}" \
	${make} mk.pkg

mk.namespace.list help.namespaces:
	@# Returns only the top-level target namespaces
	@# Pipe-friendly; stdout is newline-delimited target prefixes.
	@#
	tmp="`$(call _help_gen) | cut -d. -f1 |cut -d/ -f1 | uniq | grep -v ^all$$`" \
	&& count=`printf "$${tmp}"| wc -l` \
	&& $(call log, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} ) \
	&& printf "$${tmp}\n" \
	&& $(call log, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} )

mk.namespace.filter/%:
	@# Lists all targets in the given namespace. Simple, pipe-friendly output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE:
	@#   ./compose.mk mk.namespace.filter/<namespace>
	@#
	${make} mk.parse.targets/${MAKEFILE} | uniq | grep -v ^all$$ | grep ^${*}
	
mk.parse/%:
	@# Parses the given Makefile, returning JSON output that describes the targets, docs, etc.
	@# This uses a dockerized version of the pynchon[1] tool.
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/elo-enterprises/pynchon/
	@#
	${pynchon} parse --markdown ${*} 2>/dev/null

mk.parse.block/%:
	@# Pulls out documentation blocks that match the given pattern.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.block/<makefile>
	@#
	@# EXAMPLE:
	@#   pattern='*Keybindings*' make mk.parse.block/compose.mk
	@#
	${make} mk.parse.module.docs/${*} \
	| ${jq.run} "to_entries | map(select(.key | test(\".*$${pattern}.*\"))) | first | .value" \
	| ${jq.run} -r '.[1:-1][]'

mk.parse.targets/%:
	@# Parses the given Makefile, returning target-names only. Simple, pipe-friendly output. 
	@# WARNING: Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: 
	@#   ./compose.mk mk.parse.targets/<file>
	@#
	${make} mk.parse/${*} | ${jq.run} -r '.|keys[]'

mk.parse.module.docs/%:
	@# Parses the given Makefile, returning module-level documentation.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.module.docs/<makefile>
	@#
	${pynchon} parse --module-docs ${*} 2>/dev/null | jq .


define Dockerfile.makeself
FROM debian:bookworm
RUN apt-get update
RUN apt-get install -y bash make makeself
ENTRYPOINT bash
endef
mk.self: docker.from.def/makeself
	@# An interface to a dockerized version of the `makeself` tool.[1]
	@#
	@# You can use this to create self-extracting executables.  
	@# Required arguments are only accepted as environment variables.
	@#
	@# Set `archive` as a space-separated list of files or directories. 
	@# Set `script` as the script that will run inside the archive.
	@# Set `bin` as the name of the executable you want to create. 
	@#
	@# Optionally set `label`.  This is displayed at runtime, 
	@# after rehydrating the archive but before the script runs.
	@#
	@# USAGE:
	@#  archive=<dirname> label=<label> bin=<bin_name> script="pwd; ls" ./compose.mk mk.self
	@#
	@# [1]: https://makeself.io/
	@#
	header="${GLYPH_IO} ${@}${no_ansi} ${sep}${dim}" \
	&& $(call log, $${header} Archive for ${no_ansi}${ital}$${archive}${no_ansi_dim} will be released as ${no_ansi}${bold}./$${bin}) \
	&& (ls $${archive} >/dev/null || exit 1) \
	&& $(call io.mktempd) \
	&& cp -rf $${archive} $${tmpd} \
	; archive_dir=$${tmpd} \
	&& file_count=`find $${archive_dir}|wc -l` \
	&& $(call log, $${header} Total files: ${no_ansi}$${file_count}) \
	&& $(call log, $${header} Entrypoint: ${no_ansi}$${script}) \
	&& cmd="--noprogress --quiet --nomd5 --nox11 --notemp $${archive_dir} $${bin} \"$${label:-archive}\" $${script} $${script_args:-}" \
	img=compose.mk:makeself entrypoint=makeself ${make} docker.run.sh
	sed -i -e 's/quiet="n"/quiet="y"/' $${bin}

mk.set/%:
	@# Setter for make variables, available as a target. 
	@# This is experimental stuff for reflection support.
	@# USAGE:
	@#   ./compose.mk mk.set/<key>/<val>
	@#
	$(eval $(shell echo ${*}|cut -s -d/ -f1):=$(shell echo ${*}|cut -s -d/ -f2-))

mk.stat:
	@# Shows version-information for make itself.
	@#
	@# USAGE:
	@#    ./compose.mk mk.stat
	@#
	@#
	$(call log, ${GLYPH_MK} mk.stat${no_ansi_dim}:) \
	&& make --version | ${stream.dim.indent.stderr}

mk.supervisor.interrupt mk.interrupt: mk.interrupt/SIGINT
	@# The default interrupt.  This is shorthand for mk.interrupt/SIGINT
mk.interrupt=${make} mk.interrupt
ifeq (${CMK_SUPERVISOR},0)
mk.supervisor.interrupt/% mk.interrupt/%:
	@# CMK_SUPERVISOR is 0; signals are disabled.
	@#
	$(call log, ${GLYPH_MK} ${@} ${sep} ${dim}Supervisor is disabled.) \
	; exit 1
mk.supervisor.pid/%: #; $(call log ${GLYPH_COMPOSE} ${@} ${sep} ${dim}Supervisor is disabled.)
	@# CMK_SUPERVISOR is 0; signals are disabled.
	@#
else 
mk.supervisor.pid:
	@# Returns the pid for the supervisor process which is responsible for trapping signals.
	@# See 'mk.interrupt' docs for more details.
	@#
	$(trace_maybe) \
	&& case $${MAKE_SUPER:-} in \
		"") ( \
				header="${GLYPH_MK} mk.supervisor.pid ${sep} " \
				&& $(call log, $${header} ${red}Supervisor not found) \
				&& $(call log, $${header} ${no_ansi_dim}MAKE_SUPER is not set by any wrapper) \
				&& $(call log, $${header} ${dim}No pid to handle signals could be found.) \
				&& $(call log, $${header} ${dim}Signal-handling is only supported for stand-alone mode.) \
				&& $(call log, $${header} ${dim}Use 'compose.mk' instead of using 'make' directly?) \
			); exit 0; ;; \
		*) \
			case "${OS_NAME}" in \
				Darwin) \
					ps auxo ppid|grep $${MAKE_SUPER}$$|awk '{print $$2}'; ;; \
				*) \
					ps --ppid $${MAKE_SUPER} -o pid= ; ;; \
			esac \
	esac

mk.supervisor.interrupt/% mk.interrupt/%:
	@# Sends the given signal to this process-tree's supervisor, then kills this process with SIGKILL.
	@#
	@# This is mostly used to short-circuit make's default command-line processing, 
	@# so that targets can be greedy about consuming the *whole* CLI, rather than 
	@# having make try to interpret everything as additional targets.
	@#
	@# This can be used without a supervisor process wrapping 'make', 
	@# but in that case the exit status is *always* failure, and there 
	@# is *always* an error that the user has to know they should ignore.
	@#
	@# To correct for exit status/error output, you'll have to have a supervisor. 
	@# See the polyglot-wrapper at the top of this file for an example, and see 
	@# the 'mk.supervisor.*' namespace for handlers invoked by that supervisor.
	@#
	case $${CMK_SUPERVISOR} in \
		0) $(call log.trace, ${red}Supervisor disabled!); exit 0; ;; \
		*) \
			header="${GLYPH_MK} mk.interrupt ${sep}" \
			&& super=`${make} mk.supervisor.pid||true` \
			&& case "$${super:-}" in \
				"") $(call log.trace, ${red}Can't find supervisor!); ;; \
				*) (\
					$(call log.trace, $${header} ${red}${*} ${sep} ${dim}Sending signal to $${super}) \
					&& kill -${*} $${super} \
					&& kill -KILL $$$$ \
				); ;; \
			esac; ;; \
	esac
endif
	
mk.supervisor.enter/%:
	@# Unconditionally executed by the supervisor program, prior to main pipeline. 
	@# Argument is always supervisor's PPID.  Not to be confused with 
	@# the supervisor's pid; See instead 'mk.supervisor.pid'
	@# 
	$(eval export MAKE_SUPER:=${*}) \
	$(call log.trace, ${GLYPH_MK} ${@} ${sep} ${red}started pid $${MAKE_SUPER}${no_ansi})
	# $(call log.trace, ${GLYPH_MK} ${@} ${sep} ${red}handler @ `${make} mk.supervisor.pid`)

define mk.yield2
	header="${GLYPH_MK} mk.yield ${sep}${dim}" \
	&& $(call log.trace, $${header} Yielding to:${dim_cyan} $(call strip, ${1})) \
	&& ${1} \
	; echo $$? > .tmp.mk.super.$${MAKE_SUPER} \
	; ${mk.interrupt}
endef

mk.supervisor.exit/%:
	@# Unconditionally executed by the supervisor program after main pipeline, 
	@# regardless of whether that  pipeline was successful. Argument is always 
	@# the exit-status of the main pipeline.
	@#
	header="${GLYPH_MK} mk.supervisor.exit ${sep}" \
	&& $(call log.trace, $${header} ${red} status=${*} ${sep} ${bold}pid=$${MAKE_SUPER}) \
	&& ${make} ${CMK_AT_EXIT_TARGETS} \
	&& if [ -f .tmp.mk.super.${MAKE_SUPER} ]; then \
		( $(call log.trace, WARNING: execution was yielded from ${MAKE_SUPER}) \
			; trap "rm -f .tmp.mk.super.${MAKE_SUPER}" EXIT \
			; exit `cat .tmp.mk.super.${MAKE_SUPER}`) \
	else exit ${*}; \
	fi
	
mk.supervisor.trap/%:
	@# Executed by the supervisor program when the given signal is trapped.
	@#
	header="${GLYPH_MK} mk.supervisor.trap ${sep}" \
	&& $(call log.trace, $${header} ${red}${*} ${sep} ${dim}Supervisor trapped signal)

mk.vars:; echo "${.VARIABLES}\n" | sed 's/ /\n/g' | sort
	@# Lists all the variables known to Make.
	@# This is effectively local or inherited env-vars, plus make-vars and make-defines
	

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: mk.* targets
## BEGIN: flux.* targets
##
## The flux.* targets describe a miniature workflow library. Combining flux with 
## container dispatch is similar in spirit to things like declarative pipelines 
## in Jenkins, but simpler, more portable, and significantly easier to use.  
## What's a workflow in this context? Shell by itself is fine for what you might
## call "process algebra", and using operators like `&&`, `||`, `|` in the grand 
## unix tradition goes a long way. And adding `make` to the mix already provides 
## DAGs.
##
## What `flux.*` targets add is flow-control constructs and higher-level 
## join/loop/map instructions over other make targets, taking inspiration from 
## functional programming and threading libraries. Alternatively, one may think of
## flux as a programming language where all primitives are the objects that make 
## understands, like targets, defines, and variables. Since every target in `make`
## is a DAG, you might say that task-DAGs are also primitives. Since `compose.import`
## maps containers onto targets, containers are primitives too.  Since `tux` targets 
## map targets onto TUI panes, UI elements are also effectively primitives.
##
## In most cases flux targets are used programmatically for scripting, but in 
## stand-alone mode it can sometimes be useful for cleaning up (external) bash 
## scripts, or porting from bash to makefiles, or ad-hoc interactive scripting.  
##
## For parts that are more specific to shell code, see `flux.*.sh`, and for 
## working with scripts see `flux.*.script`.
##
## ----------------------------------------------------------------------------
##
## DOCS:
##   * `[1]:` https://github.com/robot-wranglers/compose.mk/docs/api#api-flux
##   * `[1]:` https://github.com/robot-wranglers/compose.mk/docs/api#api-flux
##   * `[1]:` https://github.com/robot-wranglers/compose.mk/docs/api#api-flux
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


define _flux.always
	@# NB: Used in 'flux.always' and 'flux.finally'.  For reasons related to ONESHELL,
	@# this code can't be target-chained and to make it reusable, it needs to be embedded.
	@#
	printf "${GLYPH_FLUX} flux.always${no_ansi_dim} ${sep} registering target: ${green}${*}${no_ansi}\n" >${stderr}
	target="${*}" pid="$${PPID}" $(MAKE) .flux.always.bg &
endef

flux.wrap/%:
	@# Performs an 'and' operation with the named colon-delimited targets.
	@# This is equivalent to the default behaviour of `make t1 t2 .. tN`.
	@# This is mostly used as a wrapper in case targets are unary, 
	@# and is the same as `flux.and` except for the delimiter
	@#
	${make}	flux.and/`echo ${*}|sed 's/:/,/g'`

flux.apply/% flux.and/%:
	@# Performs an 'and' operation with the named comma-delimited targets.
	@# This is equivalent to the default behaviour of `make t1 t2 .. tN`.
	@# This is mostly used as a wrapper in case targets are unary.
	@#
	@# See also 'flux.or'.
	@#
	$(trace_maybe) && ${make} `echo "${*}" | ${stream.comma.to.space}`

flux.apply.later/% flux.delay/%:
	@# Applies the given targets at some point in the future.  This is non-blocking.
	@# Not pipe-safe, because since targets run in the background, this can garble your display!
	@#
	@# USAGE:
	@#   ./compose.mk flux.apply.later/<seconds>/<target>
	@#
	time=`printf ${*} | cut -d/ -f1` \
	&& target=`printf ${*} | cut -d/ -f2-` \
	cmd="${make} $${target}" \
		${make} flux.apply.later.sh/$${time}

flux.apply.later.sh/%:
	@# Applies the given command at some point in the future.  This is non-blocking.
	@# Not pipe-safe, because since targets run in the background, this can garble your display!
	@#
	@# USAGE:
	@#   cmd="..." ./compose.mk flux.apply.later.sh/<seconds>
	@#
	header="${GLYPH_FLUX} flux.apply.later${no_ansi_dim} ${sep} ${dim_green}$${target} ${sep}" \
	&& time=`printf ${*}| cut -d/ -f1` \
	&& ([ -z "$${quiet:-}" ] && true || printf "\n$${header} ${sep} after ${dim_green}$${time}s\n" > ${stderr}) \
	&& ( $(call log, $${header} ${dim_cyan}callback scheduled for ${yellow}$${time}s) && ${make} io.wait/$${time} \
	&& $(call log, $${header} ${dim}callback triggered after ${yellow}$${time}s) && $${cmd:-true} )&

flux.do.when/%:
	@# Runs the 1st given target iff the 2nd target is successful.
	@#
	@# This is a version of 'flux.if.then', see those docs for more details.
	@# This version is nicer when your "then" target has multiple commas.
	@#
	@#  USAGE: ( generic )
	@#    ./compose.mk flux.do.when/<umbrella>,<raining>
	@#
	$(trace_maybe) \
	&& _then="$(call mk.unpack,$(comma),1)" \
	&& _if="$(call mk.unpack,$(comma),2-)" \
	&& ${make} flux.if.then/$${_if},$${_then}

flux.do.unless/%:
	@# Runs the 1st target iff the 2nd target fails.
	@# This is a version of 'flux.if.then', see those docs for more details.
	@#
	@#  USAGE: ( generic )
	@#    ./compose.mk flux.do.unless/<umbrella>,<dry>
	@#
	@#  USAGE: ( concrete ) 
	@#    ./compose.mk flux.do.unless/flux.ok,flux.fail
	@#
	${make} flux.do.when/`printf ${*}|cut -d, -f1`,flux.negate/`printf ${*}|cut -d, -f2-`

flux.dmux flux.split:
	@# Demultiplex / fan-out operator that sends stdin to each of the named targets in parallel.
	@# (This is like `flux.sh.tee` but works with make-target names instead of shell commands)
	@#
	@# USAGE: (pipes the same input to target1 and target2)
	@#   echo {} | ./compose.mk flux.dmux targets="target1,target2"
	@#
	header="${GLYPH_FLUX} ${@}${no_ansi_dim}" \
	&& header+=" ${sep} ${dim}$${targets//,/ ; }${no_ansi}\n" \
	&& $(call log, $${header})
	${stream.stdin} \
	| make flux.sh.tee \
		cmds="`\
			printf $${targets} \
			| tr ',' '\n' \
			| xargs -I% echo make % \
			| tr '\n' ','`"

flux.dmux/%:; cat ${stdin} | targets="${*}" make flux.dmux
	@# Same as flux.dmux, but accepts arguments directly (no variable)
	@# Stream-usage is required (this blocks waiting on stdin).
	@#
	@# USAGE: ( pipes the same input to yq and jq )
	@#   echo {} | ./compose.mk flux.dmux/jq,jq

flux.fail:
	@# Alias for 'exit 1', which is POSIX failure.
	@# This is mostly for used for testing other pipelines.
	@#
	@# See also the `flux.ok` target.
	@#
	$(call log, ${GLYPH_FLUX} flux.fail ${sep} ${red}failing${no_ansi} as requested!)  \
	&& exit 1

flux.finally/% flux.always/%:
	@# Always run the given target, even if the rest of the pipeline fails.
	@# See also 'flux.try.except.finally'.
	@#
	@# NB: For this to work, the `always` target needs to be declared at the
	@# beginning.  See the example below where "<target>" always runs, even
	@# though the pipeline fails in the middle.
	@#
	@# USAGE:
	@#   ./compose.mk flux.always/<target_name> flux.ok flux.fail flux.ok
	@#
	$(call _flux.always)
.flux.always.bg:
	@# Internal helper for `flux.always`
	@#
	header="${GLYPH_FLUX} flux.always${no_ansi_dim} ${sep} main process finished, " \
	&& ( \
		while kill -0 $${pid} 2> ${devnull}; do sleep 1; done \
		&& 	$(call log, $${header} dispatching ${green}$${target}) \
		&& $(MAKE) $$target \
	) &

flux.help:; ${make} mk.namespace.filter/flux.
	@# Lists only the targets available under the 'flux' namespace.

flux.if.then/%:
	@# Runs the 2nd given target iff the 1st one is successful.
	@#
	@# Failure (non-zero exit) for the "if" check is not distinguished
	@# from a crash, & it won't propagate.  Only the 2nd argument may contain 
	@# commas.  For a reversed version of this construct, see 'flux.do.when'
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk flux.if.then/<name_of_test_target>,<name_of_then_target>
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk flux.if.then/flux.fail,flux.ok
	@#
	$(trace_maybe) \
	&& _if=`printf "${*}"|cut -s -d, -f1` \
	&& _then=`printf "${*}"|cut -s -d, -f2-` \
	header="${GLYPH_FLUX} flux.if.then ${sep}${dim}" \
	&& $(call log, $${header} ${ital}$${_if}${no_ansi} ${sep} ${dim}${bold}$${_then}) \
	&& case $${verbose:-0} in \
		0) ${make} $${_if} 2>/dev/null; st=$$?; ;; \
		*) ${make} $${_if}; st=$$?; ;; \
	esac \
	&& case $${st} in \
		0) $(call log.trace, $${header} ${yellow}(Condition ok)); ${make} $${_then}; ;; \
		*) $(call log.trace, $${header} ${yellow}(Condition failed)); ;; \
	esac

flux.indent/%:
	@# Given a target, this runs it and indents both the resulting output for both stdout/stderr.
	@# See also the 'stream.indent' target.
	@#
	@# USAGE:
	@#   ./compose.mk flux.indent/<target>
	@#
	${make} flux.indent.sh cmd="${make} ${*}"

flux.indent.sh:
	@# Similar to flux.indent, but this works with any shell command.
	@#
	@# USAGE:
	@#  cmd="echo foo; echo bar >/dev/stderr" ./compose.mk flux.indent.sh
	@#
	$${cmd}  1> >(sed 's/^/  /') 2> >(sed 's/^/  /')

flux.loop/%:
	@# Helper for repeatedly running the named target a given number of times.
	@# This requires the 'pv' tool for progress visualization, which is available
	@# by default in k8s-tools containers.   By default, stdout for targets is
	@# supressed because it messes up the progress bar, but stderr is left alone.
	@#
	@# USAGE:
	@#   ./compose.mk flux.loop/<times>/<target_name>
	@#
	@# NB: This requires "flat" targets with no '/' !
	$(eval export target:=$(strip $(shell echo ${*} | cut -d/ -f2-)))
	$(eval export times:=$(strip $(shell echo ${*} | cut -d/ -f1)))
	$(call log, ${GLYPH_FLUX} flux.loop${no_ansi_dim} ${sep} ${green}$${target}${no_ansi} ($${times}x))
	(for i in `seq $${times}`; \
	do \
		${make} $${target} > ${devnull}; echo $${i}; \
	done) | eval `which pv||echo cat` > ${devnull}

flux.loopf/%:; verbose=1 ${make} flux.loopf.quiet/${*}
	@# Loops the given target forever.

flux.loopf.quiet/%:
	@# Loops the given target forever.
	@#
	@# By default to reduce logging noise, this sends stderr to null, but preserves stdout.
	@# This makes debugging hard, so only use this with well tested/understood sub-targets,
	@# or set "verbose=1" to allow stderr.  When "quiet=1" is set, even more logging is trimmed.
	@#
	@# USAGE:
	@#   ./compose.mk flux.loopf/
	@#
	header="${GLYPH_FLUX} flux.loopf${no_ansi_dim}" \
	&& header+=" ${sep} ${green}${*}${no_ansi}" \
	&& interval=$${interval:-1} \
	&& ([ -z "$${quiet:-}" ] \
		&& tmp="`\
			[ -z "$${clear:-}" ] \
			&& true \
			|| echo ", clearing screen between runs" \
		   `" \
		&& $(call log, $${header} ${dim}( looping forever at ${yellow}$${interval}s${no_ansi_dim} interval$${tmp})) || true ) \
	&& while true; do ( \
		([ -z "$${verbose:-}" ] && ${make} ${*} 2>/dev/null || ${make} ${*} ) \
		|| ([ -z "$${quiet:-}" ] && true || printf "$${header} ($${failure_msg:-failed})\n" > ${stderr}) \
		; sleep $${interval} \
		; ([ -z "$${clear:-}" ] && true || clear) \
	) ;  done

flux.loopf.quiet.quiet/%:; quiet=yes ${make} flux.loopf/${*}
	@# Like flux.loopf, but even more quiet.

flux.loop.until/%:
	@# Loop the given target until it succeeds.
	@#
	@# By default to reduce logging noise, this sends stderr to null, but preserves stdout.
	@# This makes debugging hard, so only use this with well tested/understood sub-targets,
	@# or set "verbose=1" to allow stderr.  When "quiet=1" is set, even more logging is trimmed.
	@#
	@# USAGE:
	@#
	header="${GLYPH_FLUX} flux.loop.until${no_ansi_dim} ${sep} ${green}${*}${no_ansi}" \
	&& printf "$${header} (until success)\n" > ${stderr}
	${make} ${*} 2>/dev/null || (sleep $${interval:-1}; ${make} flux.loop.until/${*})

flux.loop.watch/%:
	@# Loops the given target forever, using 'watch' instead of the while-loop default
	@#
	watch \
		--interval $${interval:-2} \
		--color make ${*}

flux.map/%:
	@# Similar to 'flux.apply', but maps input stream sequentially onto the comma-delimited target list.
	@#
	@# USAGE:
	@#   echo hello-world | ./compose.mk flux.map/stream.echo,stream.echo
	@#
	$(call io.mktemp) && \
	${stream.stdin} > $${tmpf} \
	&& printf ${*} | sed 's/,/\n/g' | xargs -I% printf 'cat $${tmpf} | make %\n' \
	| bash -x

flux.or/%:
	@# Performs an 'or' operation with the named comma-delimited targets.
	@# This is equivalent to 'make target1 || .. || make targetN'.  See also 'flux.and'.
	@#
	@# USAGE: (generic)
	@#   ./compose.mk flux.or/<t1>,<t2>,..
	@#
	@# USAGE: (example)
	@#   ./compose.mk flux.or/flux.fail,flux.ok
	@#
	$(trace_maybe) \
	&& echo "${*}" | sed 's/,/\n/g' \
	| xargs -I% echo "|| make %" | xargs | sed 's/^||//' \
	| bash

flux.pipeline/%:
	@# Runs the given comma-delimited targets in a bash-style command pipeline.
	@# Besides working with targets and allowing for DAG composition, this has 
	@# the advantage of giving visibility to the pipeline's intermediate results.
	@#
	@# There are several caveats though: all targets *must* be pipe safe on stdout, 
	@# and downstream targets must consume stdin.  Note also that this does not use
	@# pure streams, and tmp files are created as part of an attempt to debuffer and 
	@# avoid reordering stderr output.  Error handling is also probably not great!
	@#
	@# USAGE: (example)
	@#   ./compose.mk flux.pipeline/extract,transform,load
	@#    => roughly equivalent to `make extract | make transform | make load`
	@#
	$(trace_maybe) \
	&& $(call io.mktemp) \
	&& targets="${*}" \
	&& export opipe="$${opipe:-${*}}" \
	&& header="${GLYPH_FLUX} flux.pipeline ${sep} ${dim_cyan}$${opipe} ${no_ansi_dim}${sep}" \
	&& first=`echo "$${targets}"|cut -d, -f1` \
	&& rest=`echo "$${targets}"|cut -s -d, -f2-`  \
	&& $(call log, $${header} ${bold_green}$${first} ${no_ansi_dim}stage ) \
	&& ${make} $${first} >> $${tmpf} 2> >(tee /dev/null >&2) \
	&& if [ -z "$${rest:-}" ]; \
		then cat $${tmpf}; \
		else ( \
			([ -z "$${quiet:-}" ] \
				&& ($(call log, $${header} ${no_ansi_dim}result preview) \
				; cat $${tmpf} | ${stream.dim.indent.stderr}; printf '\n'>/dev/stderr) \
				|| true) \
			; cat $${tmpf} | ${make} flux.pipeline/$${rest}); fi
flux.pipeline.quiet/%:
	@# A quiet version of `flux.pipeline`.  
	@# Pipeline components are still announced individually, 
	@# but the usual result previews for the intermediate stages are skipped.
	@# 
	quiet=1 ${make} flux.pipeline/${*}

flux.pipeline/: flux.noop
	@# No-op.  This just bottoms out the recursion on `flux.pipeline`.

flux.mux flux.join:
	@# Runs the given comma-delimited targets in parallel, then waits for all of them to finish.
	@# For stdout and stderr, this is a many-to-one mashup of whatever writes first, and nothing
	@# about output ordering is guaranteed.  This works by creating a small script, displaying it,
	@# and then running it.  It is not very sophisticated!  The script just tracks pids of
	@# launched processes, then waits on all pids.
	@#
	@# If the named targets are all well-behaved, this *might* be pipe-safe, but in
	@# general it's possible for the subprocess output to be out of order.  If you do
	@# want *legible, structured output* that *prints* in ways that are concurrency-safe,
	@# here's a hint: emit nothing, or emit minified JSON output with printf and 'jq -c',
	@# and there is a good chance you can consume it.  Printf should be atomic on most
	@# platforms with JSON of practical size? And crucially, 'jq .' handles object input,
	@# empty input, and streamed objects with no wrapper (like '{}<newline>{}').
	@#
	@# EXAMPLE: (runs 2 commands in parallel)
	@#   targets="io.time.wait/1,io.time.wait/3" ./compose.mk flux.mux | jq .
	@#
	header="${GLYPH_FLUX} flux.mux${no_ansi_dim}" \
	&& header+=" ${sep} ${no_ansi_dim}$${targets//,/ ; }${no_ansi}\n" \
	&& printf "$${header}" > ${stderr}
	$(call io.mktemp) && \
	mcmds=`printf $${targets} \
	| tr ',' '\n' \
	| xargs -I% printf 'make % & pids+=\"$$! \"\n' \
	` \
	&& (printf 'pids=""\n' \
		&& printf "$${mcmds}\n" \
		&& printf 'wait $${pids}\n') > $${tmpf} \
	&& $(call log, ${cyan_flow_left} script \n${dim}) \
	&& cat $${tmpf} | ${stream.peek} | bash ${dash_x_maybe} 

flux.mux/%:
	@# Alias for flux.mux, but accepts arguments directly
	targets="${*}" ${make} flux.mux

flux.negate/%:; ! ${make} ${*}
	@# Negates the status for the given target.
	@#
	@# USAGE: 
	@#   `./compose.mk flux.negate/flux.fail`
	@#

flux.noop:; exit 0
	@# NO-OP mostly used for testing.  
	@# Similar to 'flux.ok', but this doesn't include logging.
	@#
	@# USAGE:	
	@#  ./compose.mk flux.noop
	@#

flux.ok:
	@# Alias for 'exit 0', which is success.
	@# This is mostly for used for testing other pipelines.  
	@#
	@# See also `flux.fail`
	@#
	$(call log, ${GLYPH_FLUX} flux.ok${no_ansi_dim} ${sep} ${no_ansi} succceeding as requested!) \
	&& exit 0

flux.split/%:
	@# Alias for flux.split, but accepts arguments directly
	export targets="${*}" && make flux.split

flux.sh.tee:
	@# Helper for constructing a parallel process pipeline with `tee` and command substitution.
	@# Pipe-friendly, this works directly with stdin.  This exists mostly to enable `flux.dmux`
	@# but it can be used directly.
	@#
	@# Using this is easier than the alternative pure-shell version for simple commands, but it is
	@# also pretty naive, and splits commands on commas; probably better to avoid loading other
	@# pipelines as individual commands with this approach.
	@#
	@# USAGE: ( pipes the same input to 'jq' and 'yq' commands )
	@#   echo {} | ./compose.mk flux.sh.tee cmds="jq,yq"
	@#
	src="`\
		echo $${cmds} \
		| tr ',' '\n' \
		| xargs -I% \
			printf  ">($${tee_pre:-}%$${tee_post:-}) "`" \
	&& header="${GLYPH_FLUX} flux.sh.tee${no_ansi} ${sep}${dim} starting pipe" \
	&& cmd="cat ${stdin} | tee $${src} " \
	&& $(call log, $${header} (${no_ansi}${bold}$$(echo $${cmds} \
		| grep -o ',' \
		| wc -l | sed 's/ //g')${no_ansi_dim} components)) \
	&& $(call log, ${no_ansi_dim}${GLYPH_FLUX} ${no_ansi_dim}flux.sh.tee${no_ansi} ${sep} ${no_ansi_dim}$${cmd}) \
	&& eval $${cmd} | cat

FLUX_POLL_DELTA?=5
flux.retry/%:
	@# Retries the given target a certain number of times.
	@#
	@# USAGE: (using default interval of FLUX_POLL_DELTA)
	@#   ./compose.mk flux.retry/<times>/<target>
	@#
	@# USAGE: (explicit interval in seconds)
	@#   interval=3 ./compose.mk flux.retry/<times>/<target>
	@#
	times=`printf ${*}|cut -d/ -f1` \
	&& target=`printf ${*}|cut -d/ -f2-` \
	&& header="${GLYPH_IO} flux.retry ${sep} ${dim_cyan}${underline}$${target}${no_ansi} (${yellow}$${times}x${no_ansi}) ${sep}" \
	&& $(call log, $${header}  ${dim_green}starting..) \
	&& ( r=$${times};\
		 while ! (\
			${make} $${target} \
			|| ( $(call log, $${header} (${no_ansi}${yellow}failed.${no_ansi_dim} waiting ${dim_green}${FLUX_POLL_DELTA}s${no_ansi_dim})) \
				; exit 1) \
		); do ((--r)) || exit; sleep $${interval:-${FLUX_POLL_DELTA}}; done)

flux.each/%:
	@# Maps the newline/space separated input on to the named target.
	@# This works via xargs, runs sequentially, and fails fast.
	@# The named target must be parametric so it can accept the
	@# argument that's passed through!
	@#
	@# USAGE:
	@#
	@#  printf 'one\ntwo' | ./compose.mk stream.nl.flux.each/<target>
	@#
	${stream.stdin} | ${stream.space.to.nl} \
	| xargs -I% -n1 sh ${dash_x_maybe} -c "${make} ${*}/%||exit 255"

FLUX_STAGES=
export FLUX_STAGE?=
flux.stage.file=.flux.stage.${*}

flux.stage.file/%:
	@# Returns the name of the current stage file.
	echo "${flux.stage.file}"

flux.stage.pop/%:
	@# Pops the stack for the named stage.  
	@# Caller should handle empty value, this will not throw an error.
	@#
	@# USAGE:
	@#   ./compose.mk flux.stage.pop/<stage_name>
	@#   {"key":"val"}
	@#
	$(call log, ${GLYPH_FLUX} flux.stage.pop ${sep} ${*}) 
	$(call io.stack.pop, ${flux.stage.file})

flux.stage.push/%: 
	@# Push the JSON data on stdin into the stack for the named stage.
	@#
	@# USAGE:
	@#   echo '<json_data>' | ./compose.mk flux.stage.push/<stage_name>
	@#
	header="${GLYPH_FLUX} flux.stage.push ${sep} ${bold}${underline}${*}${no_ansi}" \
	&& $(call log, $${header} ${sep}${dim} pushing to stack file @ ${dim_cyan} ${flux.stage.file}) \
	&& test -p ${stdin}; st=$$?; case $${st} in \
		0) ${stream.stdin} | ${make} io.stack.push/${flux.stage.file}; ;; \
		*) $(call log, $${header} ${sep} ${red}Failed pushing data${no_ansi} because no data is present on stdin); ;; \
	esac

flux.stage.push:
	@# Push the JSON data on stdin into the stack for the implied stage 
	${make} flux.stage.push/${FLUX_STAGE}

flux.stage.clean/%:
	@# Cleans only stage files that belong to the given stage.
	@#
	@# USAGE: 
	@#   ./compose.mk flux.stage.clean/<pid>
	@#
	header="${GLYPH_FLUX} flux.stage.clean ${sep} ${bold}${underline}${*}${no_ansi} ${sep}" \
	&& $(call log, $${header} ${dim} removing stack file @ ${dim_cyan} ${flux.stage.file}) \
	&& rm ${flux.stage.file} 2>/dev/null || $(call log, $${header} ${yellow} stack file not found)

flux.stage.clean flux.stage.clean/:
	@# Cleans all stage-files from all runs, including ones that don't belong to this pid.
	@# No arguments.
	@#
	[ -z ${FLUX_STAGE} ] \
	&& $(call log, ${GLYPH_FLUX} flux.stage.clean ${sep}${dim} no stage activated yet.) \
	|| ${make} flux.stage.clean/${FLUX_STAGE}

# ${make} flux.stage.clean/${flux.stage.file}
# exit 1 
# echo
# find . | grep .flux.stage | ${stream.peek} | xargs rm 2>/dev/null || true

flux.stage: mk.get/FLUX_STAGE
	@# Returns the name of the current stage. No Arguments.

flux.stage.stack:
	@# Retrieves all the data on the current stack-file.  No arguments.
	$(call log, ${GLYPH_FLUX} flux.stage.stack ${sep} ) 
	$(call io.stack, ${flux.stage.file})
flux.stage.stack=$(call io.stack, ${flux.stage.file})

flux.stage/%:
	@# Declares entry for the given stage.
	@# Stage names are generally target names or similar, no spaces allowed.
	@#
	@# This is generally used to just to print a pretty divider that makes output 
	@# easier to parse, but stages also add an idea of persistence to otherwise 
	@# stateless workflows, via a file-backed JSON stack object that cooperating 
	@# tasks can push to / pop from.
	@#
	@# Stack files contain at least the parent pid for this 'make' process.
	@#
	@# USAGE:
	@#  ./compose.mk flux.stage/<stage_name>
	@# 
	stagef="${flux.stage.file}" \
	&& header="${GLYPH_IO} flux.stage ${sep} ${bold}${underline}${*}${no_ansi} ${sep}" \
	&& trap "rm -f $${stagef}" INT TERM \
	&& label="${*}" ${make} io.gum.style/2 \
	&& true $(eval export FLUX_STAGE=${*}) $(eval export FLUX_STAGES+=${*}) \
	&& $(call log, $${header} ${dim} stack file @ ${dim_cyan} $${stagef})
# && (echo ppid=$${PPID} | ${make} jb | ${make} flux.stage.push/${*} \
# 	|| $(call log, ${yellow}WARNING:${no_ansi} could not push pid-data to stage-file)) \
# && true $(eval export FLUX_STAGE=${*}) $(eval export FLUX_STAGES+=${*}) \

flux.timer/%:
	@# Emits run time for the given make-target in seconds.
	@# Pipe safe if you wanted runtime, but target stdout is sent to stderr.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timer/<target_to_run>
	@#
	start_time=$$(date +%s%N) \
	&& make ${*} \
	&& end_time=$$(date +%s%N) \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& $(call log.noindent, ${GLYPH_FLUX} flux.timer ${sep} Finished in ${yellow}$$(echo "scale=9; $$time_diff_ns / 1000000000" | bc)s)

flux.timeout/%:
	@# Runs the given target for the given number of seconds, then stops it with TERM.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timeout/<seconds>/<target>
	@#
	timeout=`printf ${*} | cut -d/ -f1` \
	&& target=`printf ${*} | cut -d/ -f2-` \
	timeout=$${timeout} cmd="make $${target}" make flux.timeout.sh

flux.timeout.sh:
	@# Runs the given command for the given amount of seconds, then stops it with TERM.
	@# Exit status is ignored
	@#
	@# USAGE: (tails docker logs for up to 10s, then stops)
	@#   ./compose.mk flux.timeout.sh cmd='docker logs -f xxxx' timeout=10
	@#
	timeout=$${timeout:-5} \
	&& $(call log, ${GLYPH_IO} flux.timeout.sh${no_ansi_dim} (${yellow}$${timeout}s${no_ansi_dim}) ${sep} ${no_ansi_dim}$${cmd}) \
	&& $(trace_maybe) \
	&& trap "set -x && echo bye" EXIT INT TERM \
	&& signal=$${signal:-TERM} \
	&& eval "$${cmd} &" \
	&& export command_pid=$$! \
	&& sleep $${timeout} \
	&& $(call log, ${dim}${GLYPH_IO} flux.timeout.sh${no_ansi_dim} (${yellow}$${timeout}s${no_ansi_dim}) ${sep} ${no_ansi}${yellow}finished) \
	&& trap '' EXIT INT TERM \
	&& kill -$${signal} `ps -o pid --no-headers --ppid $${command_pid}` 2>/dev/null || true

flux.try.except.finally/%:
	@# Performs a try/except/finally operation with the named targets.
	@# See also 'flux.finally'.
	@#
	@# USAGE: (generic)
	@#  ./compose.mk flux.try.except.finally/<try_target>,<except_target>,<finally_target>
	@#
	@# USAGE: (concrete)
	@#  ./compose.mk flux.try.except.finally/flux.fail,flux.ok,flux.ok
	@#
	$(trace_maybe) \
	&& try=`echo ${*}|cut -s -d, -f1` \
	&& except=`echo ${*} | cut -s -d, -f2` \
	&& finally=`echo ${*}|cut -s -d, -f3` \
	&& header="${GLYPH_IO} flux.try.except.finally ${sep}${no_ansi_dim}" \
	&& $(call log, $${header} ${*} ${no_ansi}) \
	&& ${make} $${try} && exit_status=0 || exit_status=1 \
	&& case $${exit_status} in \
		0) true; ;; \
		1) ${make} $${except} && exit_status=0 || (echo 'keeping 1'; exit_status=1); ;; \
	esac \
	&& ${make} $${finally} \
	&& exit $${exit_status}
	

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: flux.* targets
## BEGIN: stream.* targets
##
## The `stream.*` targets support IO streams, including basic stuff with JSON, newline-delimited, and space-delimited formats.
##
## **General purpose tools:**
##
## * For conversion, see `stream.nl.to.comma`, `stream.comma.to.nl`, etc.
## * For generation json, see `stream.jb`[2] and `stream.json.append.*`.
## * For formatting and printing, see `stream.dim.*`, etc.
##
## ----------------------------------------------------------------------------
##
## **Macro Equivalents:**
##
## Most targets here are also available as macros, which can be used programmatically as an optimization since it saves a process.  
## 
## ```bash 
##   # For example, from a makefile, these are equivalent commands:
##   echo "one,two,three" | ${stream.comma.to.nl}
##   echo "one,two,three" | make stream.comma.to.nl
## ```
## ----------------------------------------------------------------------------
## DOCS:
## 
##   * `[1]:` https://github.com/robot-wranglers/compose.mk/docs/api#api-stream
##   * `[2]:` https://github.com/h4l/json.bash
##   * `[1]:` https://github.com/robot-wranglers/compose.mk/docs/api#api-stream
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

stream.stdin=cat /dev/stdin
stream.trim=awk 'NF {if (first) print ""; first=0; print} END {if (first) print ""}'| awk '{if (NR > 1) printf "%s\n", p; p = $$0} END {printf "%s", p}'

stream.jb= ( ${jb.run} `${stream.stdin}` )
stream.jb:; ${stream.jb}
	@# Interface to jb[1].  You can use this to build JSON on the fly.
	@#
	@# EXAMPLE:
	@#   $ echo foo=bar | ./compose.mk stream.jb
	@#   {"foo":"bar"}

stream.glow:=${charm.glow} ${stream.stdin} 
stream.markdown:=${charm.glow} ${stream.stdin} 
stream.glow stream.markdown:; ${stream.glow} 
	@# Renders markdown from stdin to stdout.
	@# See also: `charm.glow`

stream.lstrip=( ${stream.stdin} | sed 's/^[ \t]*//' )
stream.lstrip:; ${stream.lstrip}
	@# Left-strips the input stream.
	
stream.strip:
	@# Pipe-friendly helper for stripping whitespace.
	@#
	cat ${stdin} | awk '{gsub(/[\t\n]/, ""); gsub(/ +/, " "); print}' ORS=''

stream.ini.pygmentize:; cat ${stdin} | lexer=ini make stream.pygmentize
	@# Highlights input stream using the 'ini' lexer.

stream.csv.pygmentize:
	@# Highlights the input stream as if it were a CSV.  Pygments actually
	@# doesn't have a CSV lexer, so we have to fake it with an awk script.  
	@#
	@# USAGE: ( concrete )
	@#   echo one,two | ./compose.mk stream.csv.pygmentize
	@#
	cat ${stdin} | awk 'BEGIN{FS=",";H="\033[1;36m";E="\033[0;32m";O="\033[0;33m";N="\033[0;35m";S="\033[2;37m";R="\033[0m";r=0}{r++;l="";c=(r==1)?H:(r%2==0)?E:O;for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$$/,"",$$i);f=($$i~/^[0-9]+(\.[0-9]+)?$$/)?N:S;l=l c f $$i R;if(i<NF)l=l c "," R}print l}'

stream.dim.indent=( ${stream.stdin} | ${stream.dim} | ${stream.indent} )
stream.dim.indent:; ${stream.dim.indent}
	@# Like 'io.print.indent' except it also dims the text.

stream.dim.indent.stderr=( ${stream.dim.indent} > ${stderr}; printf "\n" >/dev/stderr)
stream.dim.indent.stderr:; ${stream.dim.indent.stderr}
	@# Dims the input stream, indents it, and sends it to stderr.

stream.help:; ${make} mk.namespace.filter/stream.
	@# Lists only the targets available under the 'stream' namespace.

stream.nl.to.space=xargs
stream.nl.to.space:; ${stream.nl.to.space}
	@# Converts newline-delimited input stream to space-delimited output
	@#
	@# EXAMPLE: 
	@#   $ echo '\nfoo\nbar' | ./compose.mk stream.nl.to.space
	@#   > foo bar
stream.space.to.comma=(cat ${stdin} | sed 's/ /,/g')
stream.comma.to.nl=( cat ${stdin} | sed 's/,/\n/g')
stream.comma.to.nl:; ${stream.comma.to.nl}
	@# Converts comma-delimited input stream to newline-delimited output
	@#
	@# EXAMPLE: 
	@#   > echo 'foo,bar' | ./compose.mk stream.comma.to.nl
	@#   foo
	@#   bar
	@#
	
stream.comma.to.space=( cat ${stdin} | sed 's/,/ /g')
stream.comma.to.space:; ${stream.comma.to.space}
	@# Converts comma-delimited input stream to space-delimited output

stream.comma.to.json:
	@# Converts comma-delimited input into minimized JSON array
	@#
	@# EXAMPLE:
	@#   $ echo 1,2,3 | ./compose.mk stream.comma.to.json
	@#   ["1","2","3"]
	@#
	cat ${stdin} | ${stream.comma.to.nl} | ${make} stream.nl.to.json.array

stream.dim=printf "${dim}`cat ${stdin}`${no_ansi}"
stream.dim:; ${stream.dim}
	@# Pipe-friendly helper for dimming the input text.  
	@#
	@# USAGE:
	@#   $ echo "logging info" | ./compose.mk stream.dim

stream.echo:; cat ${stdin}
	@# Just echoes the input stream.  Mostly used for testing.
	@#
	@# EXAMPLE:
	@#   $ echo hello-world | ./compose.mk stream.echo

stream.img stream.chafa stream.img.preview: tux.require
	@# Given an image file on stdin, this shows a preview on the console. 
	@# Under the hood, this works using a dockerized version of `chafa`.
	@#
	@# USAGE: ( generic )
	@#   cat <path_to_image> | ./compose.mk stream.img.preview
	@#
	${stream.img}
stream.img=${stream.stdin} | docker run -i --entrypoint chafa compose.mk:tux /dev/stdin
stream.chafa=${stream.img}

stream.indent=( cat ${stdin} | sed 's/^/  /' )
stream.indent:; ${stream.indent}
	@# Indents input stream

stream.json.array.append:
	@# Appends <val> to input array
	@#
	@# EXAMPLE:
	@#   echo "[]" | val=1 ./compose.mk stream.json.array.append | val=2 make stream.json.array.append
	@#   [1,2]
	@#
	cat ${stdin} | jq "[.[],\"$${val}\"]"

stream.json.object.append stream.json.append:
	@# Appends the given key/val to the input object.
	@# This is usually used to build JSON objects from scratch.
	@#
	@# EXAMPLE:
	@#	 echo {} | key=foo val=bar ./compose.mk stream.json.object.append
	@#   {"foo":"bar"}
	@#
	cat ${stdin} | jq ". + {\"$${key}\": \"$${val}\"}"

define Dockerfile.stream.pygmentize
FROM python:3.11-slim-bookworm
RUN pip3 install --break-system-packages pygments
endef
stream.pygmentize:
	@# Syntax highlighting for the input stream.
	@# Lexer will be autodetected unless override is provided.
	@# Style defaults to 'trac', which works best with dark backgrounds.
	@#
	@# EXAMPLE: (using JSON lexer)
	@#   echo {} | lexer=json ./compose.mk stream.pygmentize
	@#
	@# REFS:
	@# [1]: https://pygments.org/
	@# [2]: https://pygments.org/styles/
	@#
	lexer=`[ -z $${lexer:-} ] && echo '-g' || echo -l $${lexer}` \
	&& style="-Ostyle=$${style:-trac}" \
	&& src="entrypoint=pygmentize" \
	&& src="$${src} cmd=\"$${style} $${lexer} -f terminal256 $${fname:-}\"" \
	&& src="$${src} img=${@} ${make} docker.from.def/${@} mk.docker.run.sh" \
	&& [ -p ${stdin} ] && ${stream.stdin} | eval $${src} || eval $${src}

stream.json.pygmentize:; lexer=json make stream.pygmentize
	@# Syntax highlighting for the JSON on stdin.
	@#
stream.indent.to.stderr=( ${stream.stdin} | ${stream.indent} | ${stream.to.stderr} )
stream.indent.to.stderr:; ${stream.indent.to.stderr}
	@# Shortcut for ' | stream.indent | stream.to.stderr'

stream.peek=( \
	( $(call io.mktemp) && cat ${stdin} > $${tmpf} \
		&& cat $${tmpf} | ${stream.dim.indent.stderr} \
		| ${stream.trim} && cat $${tmpf}); )
stream.peek:; ${stream.peek}
	@# Prints the entire input stream as indented/dimmed text on stderr,
	@# Then passes-through the entire stream to stdout.  Note that this uses
	@# a tmpfile because proc-substition seems to disorder output.
	@#
	@# EXAMPLE:
	@#   echo hello-world | ./compose.mk stream.peek | cat
	@#
stream.peek.maybe=( [ "${TRACE}" == "0" ] && cat ${stdin} || ${stream.peek} )
stream.peek.40=( $(call io.mktemp) && cat ${stdin} > $${tmpf} && cat $${tmpf} | fmt -w 35 | ${stream.dim.indent.stderr} && cat $${tmpf} )

# WARNING: long options won't work with macos 
stream.nl.enum=( cat ${stdin} | nl -v0 -n ln )
stream.nl.enum:; ${stream.nl.enum}
	@# Enumerates the newline-delimited input stream, zipping index with values
	@#
	@# EXAMPLE:
	@#   > printf "one\ntwo" | ./compose.mk stream.nl.enum
	@# 		0	one
	@# 		1	two

stream.nl.to.comma=( cat ${stdin} | xargs | sed 's/ /,/g' )

# FIXME: rewrite with 'jb'
stream.nl.to.json.array:
	@#  Converts newline-delimited input stream into a JSON array
	@#
	src=`\
		cat ${stdin} \
		| xargs -I% printf "| val=\"%\" make stream.json.array.append "\
	` \
	&& src="echo '[]' $${src} | jq -c ." \
	&& tmp=`eval $${src}` \
	&& echo $${tmp}

stream.space.enum:
	@# Enumerates the space-delimited input list, zipping indexes with values in newline delimited output.
	@#
	@# EXAMPLE:
	@#   printf one two | ./compose.mk stream.space.enum
	@# 		0	one
	@# 		1	two
	@#
	${stream.stdin} | ${stream.space.to.nl} | ${stream.nl.enum}


stream.space.to.nl=xargs -n1 echo
stream.space.to.nl:; ${stream.space.to.nl}
	@# Converts a space-separated stream to a newline-separated one


stream.to.stderr=( cat ${stdin} > ${stderr} )
stream.to.stderr stream.preview:; ${stream.to.stderr}
	@# Sends input stream to stderr.
	@# Unlike 'stream.peek', this does not pass on the input stream.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: stream.* targets
## BEGIN: tux.* targets
##
## The *`tux.*`* targets allow for creation, configuration and automation of an embedded TUI interface.  This works by sending commands to a (dockerized) version of tmux.  See also the public/private sections of the tux API[1], the general docs for the TUI[2], or the spec for the 'compose.mk:tux' container for more details.
## 
## ----------------------------------------------------------------------------
##
## DOCS:
##   * `[1]`: https://github.com/robot-wranglers/compose.mk/docs/api#api-tux
##   * `[2]`: https://github.com/robot-wranglers/compose.mk/#embedded-tui
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: TUI Environment Variables
##
## TUI_BOOTSTRAP        | *Target-name that's used to bootstrap the TUI.  *                            |
## TUX_BOOTSTRAPPED     | *Contexts for which the TUI has already been bootstrapped.*                  |
## TUI_SVC_NAME         | *The name of the primary TUI svc.*                                           |
## TUI_THEME_NAME       | *The name of the theme.*                                                     |
## TUI_TMUX_SOCKET      | *The path to the tmux socket.*                                               |
## TUI_THEME_HOOK_PRE   | *Target called when init is in progress but the core layout is finished*     |
## TUI_THEME_HOOK_POST  | *Name of the post-theme hook to call.  This is required for buttons.*        |
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


ICON_DOCKER:=https://cdn4.iconfinder.com/data/icons/logos-and-brands/512/97_Docker_logo_logos-512.png
# Geometry constants, used by the different commander-layouts
GEO_DOCKER="868d,97x40,0,0[97x30,0,0,1,97x9,0,31{63x9,0,31,2,33x9,64,31,4}]"
GEO_DEFAULT="37e6,82x40,0,0{50x40,0,0,1,31x40,51,0[31x21,51,0,2,31x9,51,22,3,31x8,51,32,4]}"
GEO_TMP="5bbe,202x49,0,0{151x49,0,0,1,50x49,152,0[50x24,152,0,2,50x12,152,25,3,50x11,152,38,4]}"

export TUI_BOOTSTRAP?=tux.require
export TUX_BOOTSTRAPPED= 
export COMPOSE_EXTRA_ARGS?=
export TUI_COMPOSE_FILE?=${CMK_COMPOSE_FILE}
export TUI_SVC_NAME?=tux
export TUI_INIT_CALLBACK?=.tux.init

export TUI_TMUX_SOCKET?=/workspace/tmux.sock
export TMUX:=${TUI_TMUX_SOCKET}
export TUI_TMUX_SESSION_NAME?=tui
export _TUI_TMUXP_PROFILE_DATA_ = $(value _TUI_TMUXP_PROFILE)

export TUI_THEME_NAME?=powerline/double/green
export TUI_THEME_HOOK_PRE?=.tux.init.theme
export TUI_THEME_HOOK_POST?=.tux.init.buttons
export TUI_CONTAINER_IMAGE?=compose.mk:tux
export TUI_SVC_BUILD_ORDER?=dind_base,tux
export TUX_LAYOUT_CALLBACK?=.tux.commander.layout
export TMUXP:=.tmp.tmuxp.yml

tui.demo tux.demo:
	@# Demonstrates the TUI.  This opens a 4-pane layout and blasts them with tte[1].
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/ChrisBuilds/terminaltexteffects
	@#
	$(call tux.log, tui.demo ${sep} ${dim}Starting demo) \
	&& TUX_LAYOUT_CALLBACK=.${@}.layout \
		TUX_CMDR_PANE_COUNT=4 \
			${make} tux.commander

.tui.demo.layout .tux.demo.layout: 
	$(call tux.log, tui.demo.layout ${sep} ${dim}Laying out panes) \
	&& ${make} .tux.layout.spiral \
		.tux.pane/0/flux.apply/.tte/${CMK_SRC} \
		.tux.pane/1/flux.apply/.tte/${CMK_SRC} \
		.tux.pane/2/flux.apply/.tte/${CMK_SRC} \
		.tux.pane/3/flux.apply/.tte/${CMK_SRC}

tux.pane/%:
	@# Sends the given make-target into the given pane.
	@# This is a public interface & safe to call from the docker-host.
	@#
	@# USAGE:
	@#   ./compose.mk tux.pane/<int>/<target>
	@#
	pane_id=`printf "${*}"|cut -d/ -f1` \
	&& target=`printf "${*}"|cut -d/ -f2-` \
	&& make tux.dispatch/tui/.tux.pane/${*}

# Possible optimization: this command is *usually* but not 
# always called from  `MAKELEVEL<3` and above that it is 
# probably cached already?
tux.require: ${CMK_COMPOSE_FILE} compose.validate.quiet/${CMK_COMPOSE_FILE}
	@# Require the embedded-TUI stack to finish bootstrap.  This is time-consuming, 
	@# so it should be called strategically and only when needed.  Note that this might 
	@# be required for things like 'gum' and for anything that depends on 'dind_base', 
	@# so strictly speaking it's not just for TUIs.  
	@#
	@# This tries to take advantage of caching, but each service 
	@# in `TUI_SVC_BUILD_ORDER` needs to be visited, and even that is slow.
	@# 
	header="${GLYPH_TUI} tux.require ${sep}" \
 	&& $(call log.trace, $${header} ${dim}Ensuring TUI containers are ready: "${TUI_SVC_BUILD_ORDER}") \
	&& (true \
		&& ([ -z "$${TUX_BOOTSTRAPPED:-}" ] || $(call log, $${header}${red}bootstrapped already); exit 0) \
		&& (local_images=`${docker.images}|xargs` \
			&& $(call log.trace.fmt, $${header} ${dim}local-images ${sep}, ${dim}$${local_images}) \
			&& items=`printf "${TUI_SVC_BUILD_ORDER}" | ${stream.comma.to.space}` \
			&& count=`printf "$${items}"|wc -w` \
			&& $(call log.trace.loop.top, $${header} ${yellow}$${count}${no_ansi_dim} items) \
			&& for item in $${items}; do \
				($(call log.trace.loop.item, ${dim}$${item}) \
				&& printf "$${local_images}" | grep -w $${item}>/dev/null \
					|| ($(call log.trace.loop.item, ${red}grep failed for $${item}) \
					&& svc=$${item} ${make} compose.build/${TUI_COMPOSE_FILE} ) \
			); done \
			&& exit 0 ) \
		)

tux.commander: tux.require
	@# Starts a tmux layout defaulting to 4 panes, using the "commander" layout callback.
	@# See `.tux.commander.layout` for more details.
	@#
	@# USAGE:
	@#  ./compose.mk tux.commander
	@#
	${make} tux.mux.count/$${TUX_CMDR_PANE_COUNT:-4}

tux.commander/%:
	@# A 4-pane session using the commander layout, 
	@# proxying the given targets into the main pane.
	@# See `.tux.commander.layout` for more details.
	@#
	@# EXAMPLE: (Runs 'io.env' target in the primary pane)
	@#   ./compose.mk tux.commander/io.env
	@#
	tux_commander_targets="${*}" ${make} tux.commander

tux.open/%: tux.require
	@# Opens the comma-separated targets in tmux panes.
	@# This requires at least two targets, and defaults to a spiral layout.
	@#
	@# USAGE:
	@#   layout=horizontal ./compose.mk tux.open/flux.ok,flux.ok
	@#
	orient=$${layout:-spiral} \
	&& targets="${*}" \
	&& count=`printf "$${targets},"|${stream.comma.to.nl}|wc -l` \
	&& $(call tux.log, tux.open ${sep} ${dim}layout=${bold}$${orient}${no_ansi_dim} pane_count=${bold}$${count}) \
	&& $(call tux.log, tux.open ${sep} ${dim}targets=$${targets}) \
	&& TUX_LAYOUT_CALLBACK=tux.layout.$${orient}/$${targets} ${make} tux.mux.count/$${count}

tux.open.service_shells/%:
	@# Treats the comma-separated input arguments as if they are service-names, 
	@# then opens shells for each of those services in individual TUI panes.
	@# 
	@# This assumes the compose-file has already been imported, either by 
	@# use of `compose.import` or by use of `loadf`.  It also assumes the 
	@# `<svc>/shell` target actually works, and this might not be true if 
	@# the container does not ship with bash!
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk tux.open.service_shells/alpine,debian,ubuntu
	@#
	targets=`echo "${*}"|${stream.comma.to.nl}|xargs -I% echo %/shell|${stream.nl.to.comma}` \
	&& ${make} tux.open/$${targets}

tux.open.h/% tux.open.horizontal/%:; layout=horizontal ${make} tux.open/${*}
	@# Opens the given targets in a horizontal orientation.

tux.open.v/% tux.open.vertical/%:; layout=vertical ${make} tux.open/${*}
	@# Opens the given targets in a vertical orientation.

tux.open.spiral/% tux.open.s/%:; layout=spiral ${make} tux.open/${*}
	@# Opens the given targets in a spiral orientation.

tux.callback/%:
	@# Runs a layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   layout=.. ./compose.mk tux.spiral/<t1>,<t2>
	@#
	pane_targets=`printf "${*}" | ./compose.mk stream.comma.to.nl | nl -v0 | awk '{print ".tux.pane/" $$1 "/" substr($$0, index($$0,$$2))}'` \
	&& pane_targets=".tux.layout.$${layout} $${pane_targets}" \
	&& layout="flux.apply/$${pane_targets}" \
	&& layout=`echo $$layout|${stream.space.to.comma}` \
	&& $(call log.trace, tux.callback ${sep} ${no_ansi_dim}Generated layout callback:\n  $${layout}) \
	&& ${make} $${layout}

tux.layout.horizontal/%:
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>
	@#
	layout=horizontal ${make} tux.callback/${*}
	
tux.layout.spiral/%:
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>
	@#
	layout=spiral ${make} tux.callback/${*}
tux.layout.vertical/%:
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>
	@#
	layout=vertical ${make} tux.callback/${*}

tux.dispatch/%:
	@# Runs the given target inside the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.dispatch/<target_name>
	@#
	$(trace_maybe) \
	&& cmd="${make} ${*}" ${tux.dispatch.sh}

tux.dispatch.sh=sh ${dash_x_maybe} -c "svc=tux cmd=\"$${cmd}\" ${make} tux.require compose.dispatch.sh/${TUI_COMPOSE_FILE}" 
tux.dispatch.sh:; ${tux.dispatch.sh}
	@# Runs the given <cmd> inside the embedded TUI container.
	@#
	@# USAGE:
	@#   cmd=... ./compose.mk tux.dispatch.sh
	@#
	
tux.help:; ${make}  mk.namespace.filter/tux.
	@# Lists only the targets available under the 'tux' namespace.

tux.mux/%:
	@# Maps execution for each of the comma-delimited targets
	@# into separate panes of a tmux (actually 'tmuxp') session.
	@#
	@# USAGE:
	@#   ./compose.mk tux.mux/<target1>,<target2>
	@#
	$(call tux.log, tux.mux ${sep} ${bold}${*})
	targets=$(shell printf ${*}| sed 's/,$$//') \
	&& export reattach=".tux.attach" \
	&& $(trace_maybe) && ${make} tux.mux.detach/$${targets}

.tux.attach:;  
	@#
	@#
	label='Reattaching TUI' ${make} io.print.div
	$(trace_maybe) && tmux attach -t ${TUI_TMUX_SESSION_NAME}
tux.mux.detach/%: 
	@# Like 'tux.mux' except without default attachment.
	@#
	@# This is mostly for internal use.  Detached sessions are used mainly
	@# to allow for callbacks that need to alter the session-configuration,
	@# prior to the session itself being entered and becoming blocking.
	@#
	${trace_maybe} \
	&& reattach="$${reattach:-flux.ok}" \
	&& header="tux.mux.detach ${sep} ${no_ansi_dim}" \
	&& $(call tux.log, $${header} ${bold}${*}) \
	&& $(call tux.log, $${header} reattach=${dim_red}$${reattach}) \
	&& $(call tux.log, $${header} TUI_SVC_NAME=${dim_green}$${TUI_SVC_NAME}) \
	&& $(call tux.log, $${header} TUI_INIT_CALLBACK=${dim_green}$${TUI_INIT_CALLBACK}) \
	&& $(call tux.log, $${header} TUX_LAYOUT_CALLBACK=${dim_green}$${TUX_LAYOUT_CALLBACK}) \
	&& $(call log.part1, ${GLYPH_TUI} $${header} Generating pane-data) \
	&& export panes=$(strip $(shell ${make} .tux.panes/${*})) \
	&& $(call log.part2, ${dim_green}ok) \
	&& $(call log.part1, ${GLYPH_TUI} $${header} Generating tmuxp profile) \
	&& eval "$${_TUI_TMUXP_PROFILE_DATA_}" > $${TMUXP}  \
	&& $(call log.part2, ${dim_green}ok) \
	&& cmd="${trace_maybe}" \
	&& cmd="$${cmd} && tmuxp load -d -S ${TUI_TMUX_SOCKET} $${TMUXP}" \
	&& cmd="$${cmd} && TMUX=${TMUX} tmux list-sessions" \
	&& cmd="$${cmd} && label='TUI Init' ${make} io.print.div $${TUI_INIT_CALLBACK}" \
	&& cmd="$${cmd} && label='TUI Layout' ${make} io.print.div $${TUX_LAYOUT_CALLBACK}" \
	&& cmd="$${cmd} && ${make} $${reattach}" \
	&& trap "${docker.compose} -f ${TUI_COMPOSE_FILE} stop -t 1" exit \
	&& $(call tux.log, $${header} Enter main loop for TUI) \
	&& ${docker.compose} -f ${TUI_COMPOSE_FILE} \
		$${COMPOSE_EXTRA_ARGS} run --rm --remove-orphans \
		-e TUI_TMUX_SOCKET="${TUI_TMUX_SOCKET}" \
		-e TUI_TMUX_SESSION_NAME="${TUI_TMUX_SESSION_NAME}" \
		-e TUI_INIT_CALLBACK="$${TUI_INIT_CALLBACK}" \
		-e TUX_LAYOUT_CALLBACK="$${TUX_LAYOUT_CALLBACK}" \
		-e TUI_SVC_STARTED=1 \
		-e reattach="$${reattach}" \
		-e k8s_commander_targets="$${k8s_commander_targets:-}" \
		-e tux_commander_targets="$${tux_commander_targets:-}" \
		--entrypoint bash $${TUI_SVC_NAME} ${dash_x_maybe} -c "$${cmd}" $(_compose_quiet) \
	; st=$$? \
	&& case $${st} in \
		0) $(call tux.log, TUI finished. ${dim_green}ok ); ;; \
		*) $(call tux.log, ${red}TUI failed with code $${st} ); ;; \
	esac

tux.mux.svc/% tux.mux.count/%:
	@# Starts a split-screen display of N panes inside a tmux (actually 'tmuxp') session.
	@#
	@# If argument is an integer, opens the given number of shells in tmux.
	@# Otherwise, executes one shell per pane for each of the comma-delimited container-names.
	@#
	@# USAGE:
	@#   ./compose.mk tux.mux.svc/<svc1>,<svc2>
	@#
	@# This works without a tmux requirement on the host, by default using the embedded
	@# container spec @ 'compose.mk:tux'.  The TUI backend can also be overridden by using
	@# the variables for TUI_COMPOSE_FILE & TUI_SVC_NAME.
	@#
	$(call tux.log, tux.mux.count ${sep}${dim} Starting ${bold}${*}${no_ansi_dim} panes..)
	case ${*} in \
		''|*[!0-9]*) \
			targets=`echo $(strip $(shell printf ${*}|sed 's/,/\n/g' | xargs -I% printf '%/shell,'))| sed 's/,$$//'` \
			; ;; \
		*) \
			targets=`seq ${*}|xargs -I% printf "io.bash,"` \
			; ;; \
	esac \
	&& ${trace_maybe} \
	&& ${make} tux.mux/$(strip $${targets})
	
tux.pane/%:
	@# Remote control for the TUI, from the host, running the given target.
	@#
	@# USAGE:
	@#   ./compose.mk tux.pane/1/<target_name>
	@#
	make tux.dispatch/.tux.pane/${*}

tux.panic:
	@#
	@#
	@# USAGE:
	@#  ./compose.mk tui.panic
	@#
	$(call tux.log, tux.panic ${sep}${dim} Stopping all TUI sessions)
	${make} tux.ps | xargs -I% bash -c "id=% ${make} docker.stop" | ${stream.dim.indent}

tux.ps:
	@# Lists ID's for containers related to the TUI.
	@#
	@# USAGE:
	@#  ./compose.mk tux.ps
	@#
	$(call tux.log, tux.ps ${sep} $${TUI_CONTAINER_IMAGE} ${sep} ${dim} Looking for TUI containers)
	docker ps | grep k8s:tui | awk '{print $$1}'
	docker ps | grep compose.mk:tux | awk '{print $$1}'

tux/shell:
	@# Bridge compatability.
	@#
	@# USAGE:
	@#  ./compose.mk tux/shell
	@#
	svc=tux entrypoint=bash ${make} compose.dispatch.sh/${TUI_COMPOSE_FILE}

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: tux.*' public targets
## BEGIN: TUI private targets
##
## These targets mostly require tmux, and so are only executed *from* the
## TUI, i.e. inside either the compose.mk:tux container, or inside k8s:tui.
## See instead 'tux.*' for public (docker-host) entrypoints.  See usage of
## the 'TUX_LAYOUT_CALLBACK' variable and '*.layout.*' targets for details.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

.tux.commander.layout:
	@# Configures a custom geometry on up to 4 panes.
	@# This has a large central window and a sidebar.
	@#
	# tmux display-message ${@}
	header="${GLYPH_TUI} ${@} ${sep}"  \
	&& $(call log, $${header} ${dim}Initializing geometry) \
	&& geometry="$${geometry:-${GEO_DEFAULT}}" ${make} .tux.geo.set \
	&& case $${tux_commander_targets:-} in \
		"") \
			$(call log, $${header}${dim} User-provided targets for main pane ${sep} None); ;; \
		*) \
			$(call log, $${header}${dim} User-provided targets for main pane ${sep} $${tux_commander_targets:-} ) \
			&& ${make} .tux.pane/0/flux.and/$${tux_commander_targets} \
			|| $(call log, $${header} ${red}Failed to send commands to the primary pane.${dim}  ${yellow}Is it ready yet?) \
			; ;; \
	esac

.tux.init:
	@# Initialization for the TUI (a tmuxinator-managed tmux instance).
	@# This needs to be called from inside the TUI container, with tmux already running.
	@#
	@# Typically this is used internally during TUI bootstrap, but you can call this to
	@# rexecute the main setup for things like default key-bindings and look & feel.
	@#
	$(call tux.log, ${@} ${sep} ${dim}Initializing TUI make ${MAKE_FLAGS} // $${MAKEFILE_LIST// / -f})
	$(trace_maybe) \
	&& ${make} .tux.init.panes .tux.init.bind_keys .tux.theme || exit 1
	tmux set -g pane-border-style fg=green \
	&& tmux set -g pane-active-border-style "bg=black fg=lightgreen" \
	&& index=0 \
	&& cat .tmp.tmuxp.yml | yq -r .windows[].panes[].name \
	| while read item; do \
		tmux select-pane -t $${index} -T " ┅ $${item} " \
		; ((index++)); \
	done
	tmux set -g pane-border-format "#{pane_index} #{pane_title}"
	$(call tux.log, ${@} ${sep} ${dim}Done initializing TUI)
.tux.init.bind_keys:
	@# Private helper for .tux.init.
	@# This binds default keys for pane resizing, etc.
	@# See also: xmonad defaults[1] 
	@#
	@# [1]: https://gist.github.com/c33k/1ecde9be24959f1c738d
	@#
	@#
	$(call tux.log, ${@} ${sep} ${dim}Binding keys)
	true \
	&& tmux bind -n M-6 resize-pane -U 5 \
	&& tmux bind -n M-Up resize-pane -U 5 \
	&& tmux bind -n M-Down resize-pane -D 5 \
	&& tmux bind -n M-v resize-pane -D 5 \
	&& tmux bind -n M-Left resize-pane -L 5 \
	&& tmux bind -n M-, resize-pane -L 5 \
	&& tmux bind -n M-Right resize-pane -R 5 \
	&& tmux bind -n M-. resize-pane -R 5 \
	&& tmux bind -n M-t run-shell "${make} .tux.layout.shuffle" \
	&& tmux bind -n Escape run-shell "${make} .tux.quit"

# .tux.init.panes:
# 	@# Private helper for .tux.init.  (This fixes a bug in tmuxp with pane titles)
# 	@#
# 	$(call tux.log, ${@} ${sep}${dim} Initializing Panes) \
# 	&& ${trace_maybe} \
# 	&& tmux set -g base-index 0 \
# 	&& tmux setw -g pane-base-index 0 \
# 	&& tmux set -g pane-border-style fg=green \
# 	&& tmux set -g pane-active-border-style "bg=black fg=lightgreen" \
# 	&& tmux set -g pane-border-status top \
# 	&& index=0 \
# 	&& cat .tmp.tmuxp.yml | yq -r .windows[].panes[].name \
# 	| ${stream.peek} \
# 	| while read item; do \
# 		tmux select-pane -t $${index} -T "$${item} ┅ ( #{pane_index} )" \
# 		; ((index++)); \
# 	done
 
.tux.init.panes:
	@# Private helper for .tux.init.  (This fixes a bug in tmuxp with pane titles)
	@#
	$(call tux.log, ${@} ${sep}${dim} Initializing Panes) \
	&& ${trace_maybe} && tmux set -g base-index 0 \
	&& tmux setw -g pane-base-index 0 \
	&& tmux set -g pane-border-status top \
	&& ${make} .tux.pane.focus/0 || true
	# cat .tmp.tmuxp.yml | yq .windows[].panes[].name -c| xargs)))
# $(eval export tmpseq=$(shell seq 1 $(words ${tmp})))
# $(foreach i, $(tmpseq), $(shell bash -x -c "tmux select-pane -t `echo "${i}+1"|bc` -T $(strip $(shell echo ${tmp}| cut -d' ' -f ${i}));"))
# Ensure window index numbers get reordered on delete.
# tmux set-option -g renumber-windows on

.tux.init.buttons:
	@# Generates tmux-script that configures the buttons for "New Pane" and "Exit".
	@# This isn't called directly, but is generally used as the post-theme setup hook.
	@# See also 'TUI_THEME_HOOK_POST'
	@#
	wscf=`make mk.def.read/_tux.theme.buttons | xargs -I% printf "$(strip %)"` \
	&& tmux set -g window-status-current-format "$${wscf}" \
	&& ___1="" \
	&& __1="{if -F '#{==:#{mouse_status_range},exit_button}' {kill-session} $${___1}}" \
	&& _1="{if -F '#{==:#{mouse_status_range},new_pane_button}' {split-window} $${__1}}" \
	&& tmux bind -Troot MouseDown1Status "if -F '#{==:#{mouse_status_range},window}' {select-window} $${_1}"
define _tux.theme.buttons
#{?window_end_flag,#[range=user|new_pane_button][ NewPane ]#[norange]#[range=user|exit_button][ Exit ]#[norange],}
endef

.tux.init.status_bar:
	@# Stuff that has to be set before importing the theme
	@#
	$(call tux.log, ${@} ${sep} ${dim}Initializing status-bar)
	setter="tmux set -goq" \
	&& $${setter} @theme-status-interval 1 \
	&& $${setter} @themepack-status-left-area-right-format \
		"wd=#{pane_current_path}" \
	&& $${setter} @themepack-status-right-area-middle-format \
		"cmd=#{pane_current_command} pid=#{pane_pid}"

.tux.init.theme: .tux.init.status_bar
	@# This configures a green theme for the statusbar.
	@# The tmux themepack green theme is actually yellow!
	@#
	@# REFS:
	@#   * `[1]`: Colors at https://www.ditig.com/publications/256-colors-cheat-sheet
	@#   * `[2]`: Gallery at https://github.com/jimeh/tmux-themepack
	@#
	$(call tux.log, ${@} ${sep} ${dim}Initializing theme)
	setter="tmux set -goq" \
	&& $${setter} @powerline-color-main-1 colour2 \
	&& $${setter} @powerline-color-main-2 colour2 \
	&& $${setter} @powerline-color-main-3 colour65 \
	&& $${setter} @powerline-color-black-1 colour233 \
	&& $${setter} @powerline-color-grey-1 colour233 \
	&& $${setter} @powerline-color-grey-2 colour235 \
	&& $${setter} @powerline-color-grey-3 colour238 \
	&& $${setter} @powerline-color-grey-4 colour240 \
	&& $${setter} @powerline-color-grey-5 colour243 \
	&& $${setter} @powerline-color-grey-6 colour245

.tux.layout.vertical:
	@# Alias for the vertical layout.
	@# See '.tux.dwindle' docs for more info
	tmux select-layout even-horizontal
.tux.layout.horizontal .tux.layout.h:
	@# Alias for the horizontal layout.
	tmux select-layout even-vertical
.tux.layout.spiral: .tux.dwindle/s
	@# Alias for the dwindle spiral layout.
	@# See '.tux.dwindle' docs for more info

.tux.layout/% .tux.layout.dwindle/% .tux.dwindle/%:
	@# Sets geometry to the given layout, using tmux-layout-dwindle.
	@# This is installed by default in k8s-tools.yml / k8s:tui container.
	@#
	@# See [1] for general docs and discussion of options.
	@#
	@# USAGE:
	@#   ./compose.mk .tux.layout/<layout_code>
	@#
	@# REFS:
	@#   * `[1]`: https://raw.githubusercontent.com/sunaku/home/master/bin/tmux-layout-dwindle
	@#
	tmux-layout-dwindle ${*}
.tux.layout.shuffle:
	@#
	@#
	@#
	$(call tux.log, ${@} ${sep} shuffling layout )
	tmp=`printf "h tlvc v h trvc h blvc brvc tlvs trvs brvs v blvs h tlhc v trhc blhc brhc tlhs trhs blhs brhs" | tr ' ' '\n' | shuf -n 1` \
	&& $(call tux.log, tux.layout.shuffle ${sep} shuffling to new layout: $${tmp}) \
	&& ${make} .tux.dwindle/$${tmp}
	
.tux.geo.get:
	@# Gets the current geometry for tmux.  No arguments.
	@# Output format is suitable for use with '.tux.geo.set' so that you can save manual changes.
	@#
	@# USAGE:
	@#  ./compose.mk .tux.geo.get
	@#
	tmux list-windows | sed -n 's/.*layout \(.*\)] @.*/\1/p'

.tux.geo.set:
	@# Sets tmux geometry from 'geometry' environment variable.
	@#
	@# USAGE:
	@#   geometry=... ./compose.mk .tux.geo.set
	@#
	true \
	&& $(call log.part1, ${GLYPH_TUI} ${@} ${sep} ${dim}Setting geometry) \
	&& tmux select-layout "$${geometry}" \
	; case $$? in \
		0) $(call log.part2, ${dim_green}geometry ok); ;; \
		*) $(call log.part2, ${red}error setting geometry); ;; \
	esac 
# ${GLYPH_TUI} ${@} ${sep} ${red}Error setting geometry:${no_ansi_dim}\n `printf "$${geometry}"|fmt -w 20|${stream.indent}`)


.tux.msg:
	@# Flashes a message on the tmux UI.
	@#
	tmux display-message "$${msg:-?}"

.tux.pane.focus/%:
	@# Focuses the given pane.  This always assumes we're using the first tmux window.
	@#
	@# USAGE: (focuses pane #1)
	@#  ./compose.mk .tux.pane.focus/1
	@#
	$(call tux.log, ${@} ${sep} ${dim}Focusing pane ${*})
	tmux select-pane -t 0.${*} || true
.tux.pane/%:
	@# Dispatches the given make-target to the tmux pane with the given id.
	@#
	@# USAGE:
	@#   ./compose.mk .tux.pane/<pane_id>/<target_name>
	@#
	pane_id=`printf "${*}"|cut -d/ -f1` \
	&& target=`printf "${*}"|cut -d/ -f2-` \
	&& cmd="$${env:-} ${make} $${target}" ${make} .tux.pane.sh/${*}

.tux.pane.sh/%:
	@# Runs command on the given tmux pane with the given ID.
	@# (Like '.tux.pane' but works with a generic shell command instead of a target-name.)
	@#
	@# USAGE:
	@#   cmd="echo hello tmux pane" ./compose.mk .tux.pane.sh/<pane_id>
	@#
	pane_id=`printf "${*}"|cut -d/ -f1` \
	&& session_id="${TUI_TMUX_SESSION_NAME}:0" \
	&& tmux send-keys \
		-t $${session_id}.$${pane_id} \
		"$${cmd:-echo hello .tux.pane.sh}" C-m

.tux.pane.title/%:
	@# Sets the title for the given pane.
	@#
	@# USAGE:
	@#   title=hello-world ./compose.mk .tux.pane.title/<pane_id>
	@#
	pane_id=`printf "${*}"|cut -d/ -f1` \
	tmux select-pane -t ${*} -T "$${title:?}"

.tux.panes/%:
	@# This generates the tmuxp panes data structure (a JSON array) from comma-separated target list.
	@# (Used internally when bootstrapping the TUI, regardless of what the TUI is running.)
	@#
	# printf "${GLYPH_TUI} ${@} ${sep} ${dim}Generating panes... ${no_ansi}\n" > ${stderr}
	echo $${*} \
	&& export targets="${*}" \
	&& ( printf "$${targets}" \
		 | ${stream.comma.to.nl}  \
		 | xargs -I% echo "{\"name\":\"%\",\"shell\":\"${make} %\"}" \
	) | jq -s -c | echo \'$$(cat ${stdin})\' | ${stream.peek.maybe}

.tux.quit .tux.panic:
	@# Closes the entire session, from inside the session.  No arguments.
	@# This is used by the 'Exit' button in the main status-bar.
	@# See also 'tux.panic', which can be used from the docker host, and which stops *all* sessions.
	@#
	$(call tux.log, ${@} ${sep} killing session )
	tmux kill-session
	
.tux.theme:
	@# Setup for the TUI's tmux theme.
	@#
	@# This does nothing directly, and just honors the environment's settings
	@# for TUI_THEME_NAME, TUI_THEME_HOOK_PRE, & TUI_THEME_HOOK_POST
	@#
	$(trace_maybe) \
	&& ${make} ${TUI_THEME_HOOK_PRE} \
	&& ${make} .tux.theme.set/${TUI_THEME_NAME}  \
	&& [ -z ${TUI_THEME_HOOK_POST} ] \
		&& true \
		|| ${make} ${TUI_THEME_HOOK_POST}

.tux.theme.set/%:
	@# Sets the named theme for current tmux session.
	@#
	@# Requires themepack [1] (installed by default with compose.mk:tux container)
	@#
	@# USAGE:
	@#   ./compose.mk .tux.theme.set/powerline/double/cyan
	@#
	@# [1]: https://github.com/jimeh/tmux-themepack.git
	@# [2]: https://github.com/tmux/tmux/wiki/Advanced-Use
	@#
	tmux display-message "io.tmux.theme: ${*}" \
	&& tmux source-file $${HOME}/.tmux-themepack/${*}.tmuxtheme

.tux.widget.ticker tux.widget.ticker:
	@# A ticker-style display for the given text, suitable for usage with tmux status bars,
	@# in case the full text won't fit in the space available. Like most TUI widgets,
	@# this loops forever, but unlike most it is pure bash, no ncurses/tmux reqs.
	@#
	@# USAGE:
	@#   text=mytext ./compose.mk tux.widget.ticker
	@#
	text=$${text:-no ticker text} \
	&& while true; do \
		for (( i=0; i<$${#text}; i++ )); do \
			echo -ne "\r$${text:i}$${text:0:i}" \
			&& sleep $${delta:-0.2}; \
		done; \
	done

.tux.widget.img:
	@# Displays the given image URL or file-path forever, as a TUI widget.
	@# This functionality requires a loop, otherwise chafa won't notice or adapt
	@# to any screen or pane resizing.  In case of a URL, it is downloaded
	@# only once at startup.
	@#
	@# USAGE:
	@#   url=... make .tux.widget.img
	@#   path=... make .tux.widget.img
	@#
	@# Besides supporting proper URLs, this works with file-paths.
	@# The path of course needs to exist and should actually point at an image.
	@#
	url="$${path:-$${url:-${ICON_DOCKER}}}" \
	&& case $${url} in \
		http*) \
			export suffix=.png && $(call io.mktemp) \
			&& curl -sL $${url:-"${ICON_DOCKER}"} > $${tmpf} \
			&& fname=$${tmpf}; ;; \
		*) fname=$${url}; ;; \
	esac \
	&& interval=$${interval:-10} \
		${make} flux.loopf/.tux.img.display/$${fname}

.tux.img.display/%:
	@# Displays the named file using chafa, and centering it in the available terminal width.
	@#
	@# USAGE:
	@#  ./compose.mk .tux.img.display/<fname>
	@#
	chafa --clear --center on ${*}

.tux.widget.img.var/%:
	@# Unpacks an image URL from the given make/shell variable name, then displays it as TUI widget.
	@#
	@# The variable of course needs to exist and should actually point at an image.
	@# Besides supporting proper URLs, this works with file-paths.  See '.tux.widget.img'
	@#
	@# USAGE:
	@#  ./compose.mk .tux.widget.img.var/<var_name>
	@#
	url="$${${*}:-${${*}}}" make .tux.widget.img

.tux.widget.lazydocker: .tux.widget.lazydocker/0

.tux.widget.lazydocker/%:
	@# Starts lazydocker in the TUI, then switches to the "statistics" tab.
	@#
	pane_id=`echo ${*}|cut -d/ -f1` \
	&& filter=`echo ${*}|cut -s -d/ -f2` \
	&& $(trace_maybe) \
	&& tmux send-keys -t 0.$${pane_id} "lazydocker" Enter "]" \
	&& [ -z "$${filter:-}" ] && true || ( \
		tmux send-keys -t 0.$${pane_id} "/$${filter}" C-m \
		&& tmux send-keys -t 0.$${pane_id} Down; \
		)

.tte/%:
	@# Interface to terminal-text-effects[1], just for fun.  Used as part of the main TUI demo.
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/ChrisBuilds/terminaltexteffects
	@#
	cat ${*} | head -`echo \`tput lines\`-1|bc` \
	| tte matrix --rain-time 1 \
	&& ${make} io.bash

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: .tux.*' Targets
## BEGIN: Embedded Files
##
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define FILE.TUX_COMPOSE
# ${TUI_COMPOSE_FILE}:
# This is an embedded/JIT compose-file, generated by compose.mk.
#
# Do not edit by hand and do not commit to version control.
# It's left just for reference & transparency, and is regenerated
# on demand, so you can also feel free to delete it.
#
# This describes a stand-alone config for a DIND / TUI base container.
# If you have a docker-compose file that you're using with 'compose.import',
# you can build on this container by using 'FROM compose.mk:tux'
# and then adding your own stuff.
#
services:
  # https://github.com/efrecon/docker-images/tree/master/chafa
  dind_base: &dind_base
    tty: true
    build:
      tags: ["compose.mk:dind_base"]
      context: .
      dockerfile_inline: |
        FROM ${DEBIAN_CONTAINER_VERSION:-debian:bookworm}
        RUN groupadd --gid ${DOCKER_GID:-1000} ${DOCKER_UGNAME:-root}||true
        RUN useradd --uid ${DOCKER_UID:-1000} --gid ${DOCKER_GID:-1000} --shell /bin/bash --create-home ${DOCKER_UGNAME:-root} || true
        RUN echo "${DOCKER_UGNAME:-root} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
        RUN apt-get update && apt-get install -y curl uuid-runtime git
        RUN curl -fsSL https://get.docker.com -o get-docker.sh && bash get-docker.sh
        RUN yes|apt-get install -y sudo
        RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
        RUN adduser ${DOCKER_UGNAME:-root} sudo
        USER ${DOCKER_UGNAME:-root}
  # tux: for dockerized tmux!
  # This is used for TUI scripting by the 'tui.*' targets
  # Manifest:
  #   [1] tmux 3.4 by default (slightly newer than bookworm default)
  #   [2] tmuxp, for working with profiled sessions
  #   [3] https://github.com/hpjansson/chafa
  #   [4] https://github.com/efrecon/docker-images/tree/master/chafa
  #   [5] https://raw.githubusercontent.com/sunaku/home/master/bin/tmux-layout-dwindle
  #   [6] https://github.com/tmux-plugins/tmux-sidebar/blob/master/docs/options.md
  #   [7] https://github.com/ChrisBuilds/terminaltexteffects
  tux: &tux
    <<: *dind_base
    depends_on:  ['dind_base']
    hostname: tux
    tty: true
    working_dir: /workspace
    volumes:
      # Share the docker sock.  Almost everything will need this
      - ${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock
      # Share /etc/hosts, so tool containers have access to any custom or kubefwd'd DNS
      - /etc/hosts:/etc/hosts:ro
      # Share the working directory with containers.
      # Overrides are allowed for the workspace, which is occasionally useful with DIND
      - ${workspace:-${PWD}}:/workspace
      - "${KUBECONFIG:-~/.kube/config}:/home/${DOCKER_UGNAME:-root}/.kube/config"
    environment: &tux_environment
      DOCKER_UID: ${DOCKER_UID:-1000}
      DOCKER_GID: ${DOCKER_GID:-1000}
      DOCKER_UGNAME: ${DOCKER_UGNAME:-root}
      DOCKER_HOST_WORKSPACE: ${DOCKER_HOST_WORKSPACE:-${PWD}}
      TERM: ${TERM:-xterm-256color}
      CMK_DIND: "1"
      KUBECONFIG: /home/${DOCKER_UGNAME:-root}/.kube/config
      TMUX: "${TUI_TMUX_SOCKET:-/workspace/tmux.sock}"
    image: 'compose.mk:tux'
    build:
      tags: ['compose.mk:tux']
      context: .
      dockerfile_inline: |
        FROM ghcr.io/charmbracelet/gum as gum
        FROM compose.mk:dind_base
        COPY --from=gum /usr/local/bin/gum /usr/bin
        USER root
        RUN apt-get update && apt-get install -y python3-pip wget tmux libevent-dev build-essential yacc ncurses-dev
        RUN wget https://github.com/tmux/tmux/releases/download/${TMUX_CLI_VERSION:-3.4}/tmux-${TMUX_CLI_VERSION:-3.4}.tar.gz
        RUN apt-get install -y jq yq bc ack-grep tree pv
        RUN pip3 install tmuxp --break-system-packages
        RUN tar -zxvf tmux-${TMUX_CLI_VERSION:-3.4}.tar.gz
        RUN cd tmux-${TMUX_CLI_VERSION:-3.4} && ./configure && make && mv ./tmux `which tmux`
        RUN mkdir -p /home/${DOCKER_UGNAME:-root}
        RUN curl -sL https://raw.githubusercontent.com/sunaku/home/master/bin/tmux-layout-dwindle > /usr/bin/tmux-layout-dwindle
        RUN chmod ugo+x /usr/bin/tmux-layout-dwindle
        RUN apt-get install -y chafa figlet jp2a
        RUN wget https://github.com/jesseduffield/lazydocker/releases/download/v${LAZY_DOCKER_CLI_VERSION:-0.23.1}/lazydocker_${LAZY_DOCKER_CLI_VERSION:-0.23.1}_Linux_x86_64.tar.gz
        RUN tar -zxvf lazydocker*
        RUN mv lazydocker /usr/bin && rm lazydocker*
        RUN pip install terminaltexteffects --break-system-packages
        USER ${DOCKER_UGNAME:-root}
        WORKDIR /home/${DOCKER_UGNAME:-root}
        RUN git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
        RUN git clone https://github.com/jimeh/tmux-themepack.git ~/.tmux-themepack
        # Write default tmux conf
        RUN tmux show -g | sed 's/^/set-option -g /' > ~/.tmux.conf
        # Really basic stuff like mouse-support, standard key-bindings
        RUN cat <<EOF >> ~/.tmux.conf
          set -g mouse on
          set -g @plugin 'tmux-plugins/tmux-sensible'
          bind-key -n  M-1 select-window -t :=1
          bind-key -n  M-2 select-window -t :=2
          bind-key -n  M-3 select-window -t :=3
          bind-key -n  M-4 select-window -t :=4
          bind-key -n  M-5 select-window -t :=5
          bind-key -n  M-6 select-window -t :=6
          bind-key -n  M-7 select-window -t :=7
          bind-key -n  M-8 select-window -t :=8
          bind-key -n  M-9 select-window -t :=9
          bind | split-window -h
          bind - split-window -v
          run -b '~/.tmux/plugins/tpm/tpm'
        EOF
        # Cause 'tpm' to installs any plugins mentioned above
        RUN cd ~/.tmux/plugins/tpm/scripts \
          && TMUX_PLUGIN_MANAGER_PATH=~/.tmux/plugins/tpm \
            ./install_plugins.sh
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Default TUI Keybindings
##
## | Shortcut         | Purpose                                                |
## | ---------------- | ------------------------------------------------------ |
## | `Escape`           | *Exit TUI*                                             |
## | `Ctrl b |`         | *Split pane vertically*                                |
## | `Ctrl b -`         | *Split pane horizontally*                              |
## | `Alt t`            | *Shuffle pane layout*                                  |
## | `Alt ^`            | *Grow pane up*                                         |
## | `Alt v`            | *Grow pane down*                                       |
## | `Alt <`            | *Grow pane left*                                       |
## | `Alt >`            | *Grow pane right*                                      |
## | `Alt <left>`       | *Grow pane left*                                       |
## | Alt <right>`      | *Grow pane right*                                      |
## | Alt <up>`         | *Grow pane up*                                         |
## | Alt <down>`       | *Grow pane down*                                       |
## | `Alt-1`            | *Select pane 1*                                        |
## | `Alt-2`            | *Select pane 2*                                        |
## | ...              | *...*                                                  |
## | `Alt-N`            | *Select pane N*                                        |
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define _TUI_TMUXP_PROFILE
cat <<EOF
# This tmuxp profile is generated by compose.mk.
# Do not edit by hand and do not commit to version control.
# It's left just for reference & transparency, and is regenerated
# on demand, so you can feel free to delete it.
session_name: tui
start_directory: /workspace
environment: {}
global_options: {}
options: {}
windows:
  - window_name: TUI
    options:
      automatic-rename: on
    panes: ${panes:-[]}
EOF
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Import macros
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Macro to yank all the compose-services out of YAML.  Important Note:
# This runs for each invocation of make, and unfortunately the command
# 'docker compose config' is actually pretty slow compared to parsing the
# yaml any other way! But we can't say for sure if 'yq' or python+pyyaml
# are available. Inside service-containers, docker compose is also likely
# unavailable.  To work around this, the CMK_INTERNAL env-var is checked,
# so that inside containers `compose.get_services` always returns nothing.
# As a side-effect, this prevents targets-in-containers from calling other
# targets-in-containers (which won't work anyway unless those containers
# also have docker).  This is probably a good thing!
define compose.get_services
	$(shell if [ "${CMK_INTERNAL}" = "0" ]; then \
		${docker.compose} -f ${1} config --services; \
	else \
		echo -n ""; fi)
endef

# Macro to create all the targets for a given compose-service.
# See docs @ https://github.com/robot-wranglers/compose.mk/#composemk-api-dynamic
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval import_to_root := $(strip $3))
$(eval compose_file := $(strip $4))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval compose_file_stem:=$(shell basename -s .yml $(compose_file)))
${compose_file_stem}.dispatch/%:
	@# Dispatches the named target inside the named service.
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.dispatch/<svc>/<target>
	@#
	entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} `printf $${*}|cut -d/ -f2-`" \
	${make} $${compose_file_stem}/`printf $${*}|cut -d/ -f1`

${compose_file_stem}.exec/%:
	@# Like ${compose_file_stem}.dispatch, but using exec instead of run
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.exec/<svc>/<target>
	@#
	set -x \
	&& docker compose -f ${compose_file} \
		exec `printf $${*}|cut -d/ -f1` \
		${make} `printf $${*}|cut -d/ -f2-`

${compose_file_stem}/$(compose_service_name)/get_shell:
	@# Detects the best shell to use with the `$(compose_service_name)` container @ ${compose_file}
	@#
	${docker.compose} -f $$(compose_file) \
		run --rm --remove-orphans --entrypoint sh $$(shell echo $$@|awk -F/ '{print $$$$2}') \
		-c "which bash || which sh" 2> ${devnull} \
		|| ( [ $${TRACE} == 1 ] \
			&& printf "${yellow}Neither 'bash' nor 'sh' are available!\n (service=$${compose_service_name} @ $${compose_file})\n${no_ansi}" > ${stderr} \
			|| true )

${compose_file_stem}/$(compose_service_name)/shell:
	@# Starts a shell for the "$(compose_service_name)" container defined in the $(compose_file) file.
	@#
	export entrypoint=`${make} ${compose_file_stem}/$(compose_service_name)/get_shell` \
	&& printf "${green}⇒${no_ansi}${dim} ${compose_file_stem}/$(compose_service_name)/shell (${green}`env|grep entrypoint\=`${no_ansi}${dim})${no_ansi}\n" \
		&& ${make} ${compose_file_stem}/$(compose_service_name)

# NB: implementation must NOT use 'io.mktemp'!
${compose_file_stem}/$(compose_service_name)/shell/pipe:
	@# Pipes data into the shell, using stdin directly.  This uses bash by default.
	@#
	@# EXAMPLE:
	@#   echo <commands> | ./compose.mk ${compose_file_stem}/$(compose_service_name)/shell/pipe
	@#
	@$$(eval export shellpipe_tempfile:=$$(shell mktemp))
	trap "rm -f $${shellpipe_tempfile}" EXIT \
	&& cat ${stdin} > $${shellpipe_tempfile} \
	&& eval "cat $${shellpipe_tempfile} \
	| pipe=yes \
	  entrypoint="bash" \
	  ${make} ${compose_file_stem}/$(compose_service_name)"

${compose_file_stem}/$(compose_service_name)/pipe:
	@# A pipe into the $(compose_service_name) container @ $(compose_file).
	@# Specify 'entrypoint=...' to override the default spec.
	@#
	@# EXAMPLE: 
	@#   echo echo hello-world | ./compose.mk  ${compose_file_stem}/$(compose_service_name)/pipe
	@#
	cat ${stdin} | pipe=yes make ${compose_file_stem}/$(compose_service_name)

$(eval ifeq ($$(import_to_root), TRUE)
$(compose_service_name): $(target_namespace)/$(compose_service_name)
	@# Target wrapping the '$(compose_service_name)' container (via compose file @ ${compose_file})

$(compose_service_name)/pipe:;  pipe=yes make ${compose_file_stem}/$(compose_service_name)
	@# Pipe into the default shell for the '$(compose_service_name)' container (via compose file @ ${compose_file})

$(compose_service_name)/shell: ${compose_file_stem}/$(compose_service_name)/shell
	@# Shortcut for ${compose_file_stem}/$(compose_service_name)/shell

$(compose_service_name)/get_shell: ${compose_file_stem}/$(compose_service_name)/get_shell
	@# Shorthand for ${compose_file_stem}/$(compose_service_name)/get_shell

$(compose_service_name)/clean: ${compose_file_stem}.clean/$(compose_service_name)
	@# Cleans the given service, removing local image cache etc.
	@#
	@# Shorthand for ${compose_file_stem}.clean/$(compose_service_name)

$(compose_service_name)/build: ${compose_file_stem}.build/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.build/$(compose_service_name)

$(compose_service_name)/up: ${compose_file_stem}.up/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.up/$(compose_service_name)

$(compose_service_name)/up.detach: ${compose_file_stem}.up.detach/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.up.detach/$(compose_service_name)

$(compose_service_name)/shell/pipe: ${compose_file_stem}/$(compose_service_name)/shell/pipe
	@# Shorthand for ${compose_file_stem}/$(compose_service_name)/shell/pipe

$(compose_service_name)/dispatch/%:
	@# Shorthand for ${compose_file_stem}.dispatch/$(compose_service_name)/<target_name>
	${make} ${compose_file_stem}.dispatch/$(compose_service_name)/$${*}
$(compose_service_name)/exec/%:
	@# Shorthand for ${compose_file_stem}.exec/$(compose_service_name)/<target_name>
	set -x && ${make} ${compose_file_stem}.exec/$(compose_service_name)/$${*}

# $(compose_service_name)/qdispatch/%:
# 	@# Shorthand for ${compose_file_stem}.qdispatch/$(compose_service_name)/<target_name>
# 	${make} ${compose_file_stem}.qdispatch/$(compose_service_name)/$${*}

endif)

${target_namespace}/$(compose_service_name):
	@# Target dispatch for $(compose_service_name)
	@#
	[ -z "${MAKE_CLI_EXTRA}" ] && true || CMK_DEBUG=0 \
	&& make ${compose_file_stem}/$$(shell echo $$@|awk -F/ '{print $$$$2}') `[ -z "${MAKE_CLI_EXTRA}" ] && echo || printf " -- ${MAKE_CLI_EXTRA}"`

${target_namespace}/$(compose_service_name)/%:
	@# Dispatches the named target inside the $(compose_service_name) service, as defined in the ${compose_file} file.
	@#
	@# This is normally used programmatically from Makefiles, not from the CLI.
	@#
	@# EXAMPLE: 
	@#  # mapping a public Makefile target to a private one that's executed in a container
	@#  my-public-target: ${target_namespace}/$(compose_service_name)/myprivate-target
	@#
	#
	@$$(eval export pipe:=$(shell \
		if [ -p ${stdin} ]; then echo "yes"; else echo ""; fi))
	pipe=$${pipe} entrypoint=make cmd="${MAKE_FLAGS} -f ${MAKEFILE} $${*}" make -f ${MAKEFILE} ${compose_file_stem}/$(compose_service_name)
endef

# Macro to import services from strings
define compose.import.def
$(eval defname:=$(strip $(3)))
$(shell echo ${make} mk.def.read/${defname} > .tmp.${defname}.yml)
$(shell cat $(firstword $(MAKEFILE_LIST)) | awk '/define ${defname}/{flag=1; next} /endef/{flag=0} flag' > .tmp.${defname}.yml)
$(call compose.import, $(1), $(2), .tmp.${defname}.yml)
endef

# Main macro to import services from an entire compose file
define compose.import
$(eval target_namespace:=$(1))
$(eval import_to_root := $(if $(2), $(strip $(2)), FALSE))
$(eval compose_file:=$(strip $(3)))
$(eval compose_file_stem:=$(shell basename -s.yaml `basename -s.yml $(strip ${3}`)))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

# Operations on the compose file itself
# WARNING: these can't use '/' naming conventions as that conflicts with '<stem>/<svc>' !
${compose_file_stem}.services:
	@# Outputs newline-delimited list of services for the ${compose_file} file.
	@#
	@# NB: This must remain suitable for use with xargs, etc
	@#
	echo $(__services__) | sed -e 's/ /\n/g'

${compose_file_stem}.stat:
	@# Status for services in the ${compose_file} file.
	@#
	@# USAGE: 
	@#     ./compose.mk  <compose_stem>.stat
	@#
	printf "${GLYPH_IO} ${compose_file_stem}.stat${no_ansi} ${sep}\n $(__services__)\n" > ${stderr}

${compose_file_stem}.build:
	@# Noisy build for all services in the ${compose_file} file, or for the given services.
	@#
	@# USAGE: 
	@#   ./compose.mk  ${compose_file_stem}.build
	@#   svc=<svc_name> ./compose.mk  ${compose_file_stem}.build 
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	$(trace_maybe) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build $${no_cache} $${svc:-}

${compose_file_stem}.build.quiet:
	@# Quiet build for all services in the given file.
	@#
	@# USAGE: ./compose.mk  <compose_stem>.build.quiet
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	$(trace_maybe) && ${make} compose.build.quiet/${compose_file}

${compose_file_stem}.build.quiet/% ${compose_file_stem}.require/%:
	@# Quiet build for the named service in the ${compose_file} file
	@#
	@# USAGE: 
	@#   ./compose.mk  ${compose_file_stem}.build.quiet/<svc_name>
	@#
	$(trace_maybe) && ${make} io.quiet.stderr/${compose_file_stem}.build/$${*}

${compose_file_stem}.build/%:
	@# Builds the given service(s) for the ${compose_file} file.
	@#
	@# Note that explicit ordering is the only way to guarantee proper 
	@# build order, because compose by default does no other dependency checks.
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.build/<svc1>,<svc2>,..<svcN>
	@#
	echo $${*} \
	| ${stream.comma.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build %"

${compose_file_stem}.up/%:
	@# Ups the given service(s) for the ${compose_file} file.
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.up/<svc_name>
	@#
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up $${*}

${compose_file_stem}.up.detach/%:
	@# Ups the given service(s) for the ${compose_file} file, with implied --detach
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.up.detach/<svc_name>
	@#
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up -d $${*}

${compose_file_stem}.clean/%:
	@# Cleans the given service(s) for the '${compose_file}' file.
	@# See 'compose.clean' target for more details.
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.clean/<svc>
	@#
	echo $${*} \
	| ${stream.comma.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "svc=% ${make} compose.clean/${compose_file}"

${compose_file_stem}.stop:; ${docker.compose} -f $${compose_file} stop -t 1
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!

${compose_file_stem}.up:; ${docker.compose} -f $${compose_file} up $${svc:-}
	@# Brings up all services in the given compose file.
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!

${compose_file_stem}.clean:
	@# Runs 'compose.clean' for the given service(s), or for all services in the '${compose_file}' file if no specific service is provided.
	@#
	svc=$${svc:-} ${make} compose.clean/${compose_file}

# NB: implementation must NOT use 'io.mktemp'!
${compose_file_stem}/%:
	@# Generic dispatch for given service inside ${compose_file}
	@#
	@#
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${MAKE_CLI_EXTRA:-$${cmd:-}}))
	@$$(eval export pipe:=$(shell \
		if [ -z "$${pipe:-}" ]; then echo ""; else echo "-iT"; fi))
	@$$(eval export nsdisp:=${log.prefix.makelevel} ${green}${bold}$${target_namespace}${no_ansi})
	@$$(eval export header:=$${nsdisp} ${sep} ${bold}${dim_green}$${compose_file_stem}${no_ansi_dim} ${sep} ${bold}${green}${underline}$${svc_name}${no_ansi_dim} container ${GLYPH_DEBUG} (${MAKE_CLI_EXTRA})${no_ansi}\n)
	@$$(eval export entrypoint:=$(shell \
		if [ -z "$${entrypoint:-}" ]; \
		then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi))
	@$$(eval export user:=$(shell \
		if [ -z "$${user:-}" ]; \
		then echo ""; else echo "--user $${user:-}"; fi))
	@$$(eval export extra_env=$(shell \
		if [ -z "$${env:-}" ]; then echo "-e _=_"; else \
		printf "$${env:-}" | sed 's/,/\n/g' | xargs -I% echo --env %='☂$$$${%}☂'; fi))
	@$$(eval export base:=docker compose -f ${compose_file} \
		run --rm --remove-orphans --quiet-pull \
		$$(subst ☂,\",$${extra_env}) \
		--env CMK_INTERNAL=1 \
		--env TRACE=$${TRACE} \
		--env CMK_DEBUG=$${CMK_DEBUG} \
		 $${pipe} $${user} $${entrypoint} $${svc_name} $${cmd})
	@$$(eval export stdin_tempf:=$$(shell mktemp))
	@$$(eval export entrypoint_display:=${cyan}[${no_ansi}${bold}$(shell \
			if [ -z "$${entrypoint:-}" ]; \
			then echo "default${no_ansi} entrypoint"; else echo "$${entrypoint:-}"; fi)${no_ansi_dim}${cyan}]${no_ansi})
	@$$(eval export cmd_disp:=${no_ansi_dim}${ital}`[ -z "$${cmd}" ] && echo " " || echo " $${cmd}\n${log.prefix.makelevel}"`${no_ansi})
	
	@trap "rm -f $${stdin_tempf}" EXIT \
	&& if [ -z "$${pipe}" ]; then \
		([ $${CMK_DEBUG} == 1 ] && printf "$${header}${dim}$${nsdisp} ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${green_flow_left}  ${cyan}<${no_ansi}${bold}interactive${no_ansi}${cyan}>${no_ansi}${dim_ital}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
		&& ($(call log.trace, ${dim}$${base}${no_ansi})) \
		&& eval $${base}  2\> \>\(\
                 grep -vE \'.\*Container.\*\(Running\|Recreate\|Created\|Starting\|Started\)\' \>\&2\ \
                 \| grep -vE \'.\*Network.\*\(Creating\|Created\)\' \>\&2\ \
                 \) ; \
	else \
		cat ${stdin} > $${stdin_tempf} \
		&& ([ $${CMK_DEBUG} == 1 ] && printf "$${header}${dim}$${nsdisp} ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${cyan_flow_left} ${dim_ital}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
		&& cat "$${stdin_tempf}" | eval $${base} 2\> \>\(\
                 grep -vE \'.\*Container.\*\(Running\|Recreate\|Created\|Starting\|Started\)\' \>\&2\ \
                 \| grep -vE \'.\*Network.\*\(Creating\|Created\)\' \>\&2\ \
                 \)  \
	; fi \
	&& ([ -z "${MAKE_CLI_EXTRA}" ] && true || ${make} mk.interrupt)

$(foreach \
 	compose_service_name, \
 	$(__services__), \
	$(eval \
		$(call compose.create_make_targets, \
			$${compose_service_name}, \
			${target_namespace}, ${import_to_root}, ${compose_file}, )))
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: import-macros
## BEGIN: help targets & macros
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Define 'help' target iff it's not already defined.  This should be inlined
# for all files that want to be simultaneously usable in stand-alone
# mode + library mode (with 'include')
_help_id:=$(shell (uuidgen ${stderr_devnull} || cat /proc/sys/kernel/random/uuid 2>${devnull} || date +%s) | head -c 8 | tail -c 8)
define _help_gen
(LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : ${stderr_devnull} | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' | LC_ALL=C sort| uniq || true)
endef
help:
	@# Attempts to autodetect the targets defined in this Makefile context.
	@# Older versions of make dont have '--print-targets', so this uses the 'print database' feature.
	@# See also: https://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile
	@#
	$(call io.mktemp) \
	&& case $${search:-} in \
		"") export key=`echo "$${MAKE_CLI#*help}"|awk '{$$1=$$1;print}'` ;; \
		*) export key="$${search}" ;;\
	esac \
	&& count=`echo "$${key}" |wc -w` \
	&& header="${GLYPH_DOCKER} help ${sep}" \
	&& case $${count} in \
		0) ( $(call _help_gen) > $${tmpf} \
			&& count=`cat $${tmpf}|wc -l` && count="${yellow}$${count}${dim} items" \
			&& $(call log, $${header} ${dim}Answering help for: ${no_ansi}${bold}top-level ${sep} $${count}) \
			&&  cat $${tmpf} \
			&& $(call log, $${header} ${dim}Answered help for: ${no_ansi}${bold}top-level ${sep} $${count}) \
		); ;; \
		1) ( ( ${make} mk.help.module/$${key} | ${stream.trim}\
				; ${make} mk.help.target/$${key} | ${stream.glow} \
				; ${make} mk.help.search/$${key} \
			) \
			; ${make} mk.interrupt \
		); ;; \
		*) ( $(call log.stdout, $${header} ${red}Not sure how to help with $${key} ($${count}) ${no_ansi}$${key}) \
			; exit 77); ;; \
	esac 
# $(eval help: _help_${_help_id})

define _loadf
cat <<EOF
#!/usr/bin/env -S make -sS --warn-undefined-variables -f
# Generated by compose.mk, for ${fname}.
#
# Do not edit by hand and do not commit to version control.
# It's left just for reference & transparency, and is regenerated
# on demand, so you can feel free to delete it.
#
SHELL:=bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
include ${CMK_SRC}
\$(eval \$(call compose.import, ▰, TRUE, ${fname}))
EOF
endef
export _TUI_TMUXP_PROFILE_DATA_ = $(value _TUI_TMUXP_PROFILE)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: Macros
## BEGIN: Special targets (only available in stand-alone mode)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
ifeq ($(CMK_STANDALONE),1)
export LOADF = $(value _loadf)
loadf: compose.loadf

endif

yq:
	@# A wrapper for yq.  
	after=`echo -e "$${MAKE_CLI#*yq}"` \
	&& cmd=$${cmd:-$${after:-.}} \
	&& dcmd="${yq.run.pipe} $${cmd}" \
	&& ([ -p ${stdin} ] && dcmd="cat ${stdin} | $${dcmd}" || true) \
	&& eval $${dcmd}; ${make} mk.interrupt

jq:
	@# A wrapper for jq.  
	after=`echo -e "$${MAKE_CLI#*jq}"` \
	&& cmd=$${cmd:-$${after:-.}} \
	&& dcmd="${jq.run.pipe} $${cmd}" \
	&& ([ -p ${stdin} ] && dcmd="cat ${stdin} | $${dcmd}" || true) \
	&& eval $${dcmd}; ${make} mk.interrupt

jb jb.pipe:
	@# An interface to `jb`[1] tool for building JSON from the command-line.
	@#
	@# This tries to use jb directly if possible, and then falls back to usage via docker.
	@# Note that dockerized usage can make it pretty hard to access all of the more advanced 
	@# features like process-substitution, but simple use-cases work fine.
	@#
	@# USAGE: ( Use when supervisors and signals[2] are enabled )
	@#   ./compose.mk jb foo=bar 
	@#   {"foo":"bar"}
	@# 
	@# EXAMPLE: ( Otherwise, use with pipes )
	@#   echo foo=bar | ./compose.mk jb 
	@#   {"foo":"bar"}
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/h4l/json.bash
	@#   * `[2]`: https://github.com/robot-wranglers/compose.mk/tree/master/#signals-and-supervisors
	@#
	case $$(test -p /dev/stdin && echo pipe) in \
		pipe) sh ${dash_x_maybe} -c "${jb.run} `${stream.stdin}`"; ;; \
		*) sh ${dash_x_maybe} -c "${jb.run} `echo "$${MAKE_CLI#*jb}"`"; ;; \
	esac

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#*/