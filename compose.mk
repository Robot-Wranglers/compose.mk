#!/usr/bin/env -S bash
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
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
#   $(eval $(call compose.import.generic, ▰, ., docker-compose.yml))
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
#   make <stem_of_compose_file>/<name_of_compose_service>.shell
#
#   # stream data into container
#   echo echo hello-world | make <stem_of_compose_file>/<name_of_compose_service>.shell.pipe
#
#   # show full interface (see also: https://github.com/robot-wranglers/compose.mk/bridge)
#   make help
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Let's get into the horror and the delight right away with shebang hacks. 
# The block below these comments looks like a comment, but it is not. That line,
# and a matching one at EOF, makes this file a polyglot so that it is executable
# simultaneously as both a bash script and a Makefile.  This allows for some improvement 
# around the poor signal-handling that Make supports by default, and each CLI invocation 
# that uses this file directly is wrapped to bootstrap handlers. If relevant signals are 
# caught, they are passed back to make for handling.  (Only SIGINT is currently supported.)
#
# Signals are used sometimes to short-circuit `make` from attempting to parse the full CLI. 
# This supports special cases like `./compose.mk loadf ...` and other tool-wrappers.
# See docs & usage of `mk.interrupt` and `mk.yield` for details.
#
#/* \
_make_="make -sS --warn-undefined-variables -f ${0}"; trace="${TRACE:-${trace:-0}}"; \
no_ansi="\033[0m"; green="\033[92m"; dim="\033[2m"; sep="${no_ansi}//${dim}";\
export CMK_BIN=${0}; export __file__=${0}; \
case ${CMK_SUPERVISOR:-1} in \
	0) ([ "${trace}" == 0 ] || \
		printf "ᐂ ${sep}Skipping setup for signal handlers..\n${no_ansi}">/dev/stderr); \
		${_make_} ${@}; st=$?; ;; \
	1) ([ "${trace}" == 0 ] || \
		printf "ᐂ ${sep} Installing supervisor..\n\033[0m" > /dev/stderr); \
		export MAKE_SUPER=$(exec sh -c 'echo "$PPID"'); \
		[ "${trace}" == 1 ] && set -x || true;  \
		trap "CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} mk.supervisor.trap/SIGINT; " SIGINT; \
		case ${CMK_DISABLE_HOOKS:-0} in \
			0) _targets="`echo ${@:-mk.__main__} | CMK_INTERNAL=1 quiet=1 ${_make_} io.awk/.awk.rewrite.targets.maybe`";; \
			1) _targets="${@:-mk.__main__}";; \
		esac; \
		${_make_} mk.supervisor.enter/${MAKE_SUPER} ${_targets} \
			2> >(sed '/^make.*:.*mk.interrupt\/SIGINT.*Killed/,/^make:.*Error.*/d' >/dev/stderr); \
		st=$? ; CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} mk.supervisor.exit/${st}; st=$?; ;; \
esac \
; exit ${st}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: Supervisor & Signals Boilerplate
## BEGIN: Constants for colors, glyphs, logging, and other Makefile-related boilerplate
##
## This includes hints for determining Makefile invocations:
##   MAKE:          Prefer `make` instead as an expansion for recursive calls.
##   MAKEFILE:      The path to the Makefile being used at the top-level
##   MAKE_CLI:      A *complete* CLI invocation for this process (Reliable with Linux, somewhat broken for OSX?)
##   MAKEFILE_LIST: Prefer instead `makefile_list`, derived from `MAKE_CLI`.  
##                  This is a list of includes, either used with 'include ..' or present at CLI with '-f ..'
##
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
SHELL:=bash
MAKEFLAGS:=-s -S --warn-undefined-variables --no-builtin-rules
.SUFFIXES:
.INTERMEDIATE: .tmp.* .flux.*
export TERM?=xterm-256color
OS_NAME:=$(shell uname -s)

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
bold.underline=${bold}${underline}

dim_green=${dim}${green}
dim_ital=${dim}${ital}
dim_ital_cyan=${dim_ital}${cyan}
no_ansi_dim=${no_ansi}${dim}
cyan_flow_left=${bold_cyan}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
cyan_flow_right=${no_ansi_dim}⋙${dim}${cyan}⋙${no_ansi}${bold_cyan}⋙${no_ansi} 
green_flow_left=${bold_green}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
green_flow_right=${no_ansi_dim}⋙${dim_green}⋙${no_ansi}${green}⋙${bold_green}⋙ 
sep=${no_ansi}//

# Glyphs used in log messages 📢 🤐
_GLYPH_COMPOSE=${bold}≣${no_ansi}
GLYPH_COMPOSE=${green}${_GLYPH_COMPOSE}${dim_green}
_GLYPH.DOCKER=${bold}≣${no_ansi}
_GLYPH_MK=${bold}✱${no_ansi}
GLYPH_MK=${green}${_GLYPH_MK}${dim_green}
GLYPH.DOCKER=${green}${_GLYPH.DOCKER}${dim_green}
_GLYPH_IO=${bold}⇄${no_ansi}
GLYPH_IO=${green}${_GLYPH_IO} ${dim_green}
_GLYPH_TUI=${bold}⏣${no_ansi}
GLYPH_TUI=${green}${_GLYPH_TUI}${dim_green}
_GLYPH_FLUX=${bold}Φ${no_ansi}
GLYPH_FLUX=${green}${_GLYPH_FLUX}${dim_green}
GLYPH_DEBUG=${dim}(debug=${no_ansi}${verbose}${dim})${no_ansi}${dim}(quiet=${no_ansi}$(shell echo $${quiet:-})${dim})${no_ansi}${dim}(trace=${no_ansi}$(shell echo $${trace:-})${dim})
GLYPH_SPARKLE=✨
GLYPH_CHECK=✔
GLYPH_SUPER=${green}ᐂ${dim_green}
GLYPH_NUMS=① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩
GLYPH.NUM=${dim_green}$(word $(shell echo $$((${1} + 1))),${GLYPH_NUMS})${no_ansi}
# GLYPH_ARRS=🡨 🡩 🡪 🡫 🡬 🡭 🡮 🡯 🡒 🡑 
GLYPH_ARRS=▋ ▊ ▉ █ █ █ █ █ ▏ ▎ ▍ 
GLYPH.ARRS=${dim_green}$(word $(shell echo $$((${1} + 1))),${GLYPH_ARRS})${no_ansi}
GLYPH.tree_item:=├┈

# FIXME: docs 
export DOCKER_HOST_WORKSPACE?=$(shell pwd)

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

export MAKE_CLI_EXTRA:=$(shell printf "${MAKE_CLI}"|awk -F' -- ' '{print $$2}')
export MAKEFILE_LIST:=$(call strip,${MAKEFILE_LIST})
export MAKE_FLAGS:=$(shell [ `echo ${MAKEFLAGS} | cut -c1` = - ] && echo "${MAKEFLAGS}" || echo "-${MAKEFLAGS}")
export MAKEFILE?=$(firstword $(MAKEFILE_LIST))
export TRACE?=$(shell echo "$${TRACE:-$${trace:-0}}")

# Returns everything on the CLI *after* the current target.
# WARNING: do not refactor as VAR=val !
define mk.cli.continuation
$${MAKE_CLI#*${@}}
endef

# IMPORTANT: this is the way to safely call `make` recursively. 
# It determines better-than-default values for MAKE and MAKEFILE_LIST,
# and uses the lowercase.  Defaults are not reliable! 
makefile_list=$(addprefix -f,$(shell echo "${MAKE_CLI}"|awk '{for(i=1;i<=NF;i++)if($$i=="-f"&&i+1<=NF){print$$(++i)}else if($$i~/^-f./){print substr($$i,3)}}' | xargs))
make=make ${MAKE_FLAGS} ${makefile_list}

# Stream constants
stderr:=/dev/stderr
stdin:=/dev/stdin
devnull:=/dev/null
stderr_stdout_indent=2> >(sed 's/^/  /') 1> >(sed 's/^/  /')
stderr_devnull:=2>${devnull}
all_devnull:=2>&1 > /dev/null
streams.join:=2>&1 


# Literal newline and other constants
# See also: https://www.gnu.org/software/make/manual/html_node/Syntax-of-Functions.html#Special-Characters
empty:=
space:= $(empty) $(empty)
define nl

endef
comma=,

# Returns "-x" iff trace is enabled.  (This is used with calls to bash/sh to show the command)
dash_x_maybe:=`[ $${TRACE} == 1 ] && echo -x || true`
export HOSTNAME?=$(shell hostname)
GLYPH_HOSTNAME= ${bold}[${no_ansi_dim}${ital}$${HOSTNAME}${no_ansi}${bold}]${no_ansi}
trace_maybe=[ "${TRACE}" == 1 ] && set -x || true 
log.prefix.makelevel.glyph=${dim}$(call GLYPH.NUM, ${MAKELEVEL})${no_ansi}
log.prefix.makelevel.glyph=${dim}$(call GLYPH.NUM, ${MAKELEVEL})
# log.prefix.makelevel.indent=$(foreach x,$(shell seq 1 $(MAKELEVEL)),)
log.prefix.makelevel.indent=
log.prefix.makelevel=${log.prefix.makelevel.glyph} ${log.prefix.makelevel.indent}
log.prefix.loop.inner=${log.prefix.makelevel}${bold}${dim_green}${GLYPH.tree_item}${no_ansi}
log.stdout=printf "${log.prefix.makelevel} $(strip $(if $(filter undefined,$(origin 1)),...,$(1))) ${no_ansi}\n"
log=([ "$(shell echo $${quiet:-0})" == "1" ] || ( ${log.stdout} >${stderr} ))
log.noindent=(printf "${log.prefix.makelevel.glyph} `echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr})
log.fmt=( ${log} && (printf "${2}" | fmt -w 55 | ${stream.indent} | ${stream.indent} | ${stream.indent.to.stderr} ) )
log.json=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.docker} ${1} | ${jq.run} . | ${stream.as.log}
log.json.trace=( [ "${TRACE}" == "0" ] && true || $(call log.json, ${1}) )
log.json.min=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.docker} ${1} | ${jq.run} -c . | ${stream.as.log}
log.target=$(call log.io, ${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep}${dim_ital} $(strip $(or $(1),$(shell printf "${@}" | cut -d/ -f2-))))
log.target.part1=([ -z "$${quiet:-}" ] && (printf "${log.prefix.makelevel}${GLYPH_IO}${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep}${dim_ital} `echo "$(strip $(or $(1),))"| ${stream.lstrip}`${no_ansi_dim}..${no_ansi}") || true )>${stderr}
log.target.part2=([ -z "$${quiet:-}" ] && $(call log.part2, ${1}))
log.test_case=$(call log.io, ${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep} ${dim}..\n  ${cyan_flow_right}${dim_ital_cyan}$(or $(1),$(shell printf "${@}" | cut -d/ -f2-)))
log.test=${log.test_case}
log.trace=[ "${TRACE}" == "0" ] && true || (printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr} )
log.trace.fmt=( ${log.trace} && [ "${TRACE}" == "0" ] && true || (printf "${2}" | fmt -w 70 | ${stream.indent.to.stderr} ) )
log.trace.part1=[ "${TRACE}" == "0" ] && true || $(call log.part1, ${1})
log.trace.part2=[ "${TRACE}" == "0" ] && true || $(call log.part2, ${1})
log.target.rerouting=$(call log, ${dim}${_GLYPH_IO}${dim} $(shell echo ${@} | sed 's/\/.*//') ${sep}${dim} Invoked from top; rerouting to tool-container)
log.trace.target.rerouting=( [ "${TRACE}" == "0" ] && true || $(call log.target.rerouting) )
log.file.contents=$(call log.target, file=$(strip ${1})) && cat ${1} | ${stream.as.log}
log.preview.file=$(call log.target, ${cyan}$(strip ${1})) ; $(call io.preview.file, ${1})
log.compiler=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log, ${GLYPH_MK} ${1}))
log.docker=$(call log, ${GLYPH.DOCKER} ${1})
log.flux=$(call log, ${GLYPH_FLUX} ${1})
log.io=$(call log,${GLYPH_IO} $(1))
log.mk=$(call log, ${GLYPH_MK} ${1})
log.tux=$(call log,${GLYPH_TUI} $(1))

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
log.stdout.part1=(case $${quiet:-} in \
	""|0) printf "${log.prefix.makelevel} $(strip $(or $(1),)) ${no_ansi_dim}..${no_ansi}";; esac)
# Call this to show the result
log.stdout.part2=(case $${quiet:-} in \
	""|0) printf "${no_ansi} $(strip $(or $(1),)) ${no_ansi}\n";; esac)
	
log.part1=(${log.stdout.part1}>${stderr})
log.part2=(${log.stdout.part2}>${stderr})
log.maybe=([ "$${quiet:-0}" == "1" ] || $(call log, ${1}))

# Completely silent output iff quiet is set and quiet!=0
quiet.maybe=$(shell [ "$${quiet:-0}" == "0" ] && echo '' || echo '> /dev/null 2>/dev/null' )

define _compose_quiet
2> >( grep -vE \
		'.*Container.*(Running|Recreate|Created|Starting|Started)' >&2 \
	  | grep -vE '.*Network.*(Creating|Created)' >&2 )
endef
docker.run.base:=docker run --rm -i 

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Environment Variables
##
## Variables used internally:
##
## | Variable               | Meaning                                                               |
## | ---------------------- | ----------------------------------------------------------------------|
## | CMK_COMPOSE_FILE       | *Temporary file used for the embedded-TUI*                            |
## | CMK_COMPILER_VERBOSE   | 1 if debugging-messages from compilation are allowed                  |
## | CMK_DIND               | *Determines whether docker-in-docker is allowed*                      |
## | CMK_SRC:               | path to compose.mk source code                                        |
## | CMK_SUPERVISOR         | *1 if supervisor/signals is enabled, otherwise 0*                     |
## | DOCKER_HOST_WORKSPACE  | *Needs override for correctly working with DIND volumes*              |
## | TRACE:                 | 1 if increase verbosity desired (more detailed than verbose)          |
## | verbose:               | 1 if normal debugging output should be shown, otherwise 0             |
## | __file__:              | val of CMK_SRC if stand-alone mode, invoked file if in library mode   |
## | __interpreter__        | `./${CMK_SRC}` unless overridden                                      |
## | __interpreting__       | CMK_SRC unless overridden; sometimes useful for extensions            |
## | trace:                 | alias for setting TRACE                                               |
##
## CMK_INTERNAL: 
## : 1 if runtime is dispatched inside a container, otherwise 0
##   Setting CMK_INTERNAL=1 rather than detecting it effectively controls whether DIND is enabled, 
##   and can be used as an optimization. This sets all `compose.imports` to no-op.
##
## Other Variables
## | Variable               | Meaning                                                               |
## | ---------------------- | ----------------------------------------------------------------------|
## | COMPOSE_IGNORE_ORPHANS | *Honored by 'docker compose', this helps to quiet output*             |
## | GITHUB_ACTIONS:        | true if running inside github actions, false otherwise                |
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
export CMK_COMPILER_VERBOSE?=1
export COMPOSE_IGNORE_ORPHANS?=True
export CMK_AT_EXIT_TARGETS?=flux.noop
export CMK_COMPOSE_FILE?=.tmp.compose.mk.yml
export CMK_DIND?=0
export verbose:=$(shell [ "$${quiet:-0}" == "1" ] && echo 0 || echo $${verbose:-1})
export CMK_INTERNAL?=0
# export CMK_SRC:=$(shell echo ${MAKEFILE_LIST} | sed 's/ /\n/g' | grep compose.mk)
export CMK_SRC=compose.mk
export CMK_BIN?=${CMK_SRC}
export __interpreter__:=$(shell \
	 ([ -z "$${__interpreter__:-}" ] \
		&& echo `dirname ${CMK_SRC} || echo .`/`basename ${CMK_SRC}||echo compose.mk` \
		||  echo $${__interpreter__:-} ))
export CMK_SUPERVISOR?=1
export CMK_EXTRA_REPO?=.
export GITHUB_ACTIONS?=false
export __interpreting__?=

##
export __script__?=None
.DEFAULT_GOAL:=__main__

ifneq ($(findstring compose.mk, ${MAKE_CLI}),)
export CMK_LIB=0
export CMK_STANDALONE=1
export CMK_SRC=$(findstring compose.mk, ${MAKE_CLI})

else

export CMK_LIB=1
export CMK_STANDALONE=0

ifeq ($(strip ${__interpreting__}),)
export __file__?=$(word 1, $(MAKEFILE_LIST))
export __script__:=$(shell \
	 ([ -z "$${__script__:-}" ] \
		&& ([ "${__interpreter__}" = "$(word 1, $(MAKEFILE_LIST))" ] && printf "None" || printf "$(word 1, $(MAKEFILE_LIST))") \
		||  echo $${__script__:-} ))
else
export __file__=${__interpreting__}
export __script__:=$(shell \
	 ([ -z "$${__script__:-}" ] \
		&& ([ "${__interpreter__}" = "${__interpreting__}" ] && printf "None" || printf "${__interpreting__}") \
		||  echo $${__script__:-} ))
endif
endif
ifeq ($(strip ${CMK_SRC}),)
export CMK_SRC=compose.mk
endif
# Default base versions for a few important containers, allowing for override from environment
export DEBIAN_CONTAINER_VERSION?=debian:bookworm
export ALPINE_VERSION?=3.21.2

IMG_CARBONYL?=fathyb/carbonyl
IMG_IMGROT?=robotwranglers/imgrot:07abe6a
IMG_MONCHO_DRY=moncho/dry@sha256:6fb450454318e9cdc227e2709ee3458c252d5bd3072af226a6a7f707579b2ddd

# Used internally.  If this is container-dispatch and DIND,
# then DOCKER_HOST_WORKSPACE should be treated carefully
ifeq ($(shell echo $${CMK_DIND:-0}), 1)
export workspace?=$(shell echo ${DOCKER_HOST_WORKSPACE})
export CMK_INTERNAL=0
endif

docker.env.standard=-e DOCKER_HOST_WORKSPACE=$${DOCKER_HOST_WORKSPACE:-$${PWD}} -e TERM=$${TERM:-xterm} -e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE}

ifeq (${TRACE},1)
$(shell printf "trace=$${TRACE} quiet=$${quiet} verbose=$${verbose:-} ${yellow}CMK_INTERNAL=$${CMK_INTERNAL} CMK_DIND=$${CMK_DIND} ${MAKE_CLI}${no_ansi}\n" > /dev/stderr)
endif 

# External tool used for parsing Makefile metadata
PYNCHON_VERSION?=a817d58
pynchon=$(trace_maybe) && ${pynchon.run}
# pynchon.run=python -m pynchon.util.makefile
pynchon.docker=${docker.run.base} -v `pwd`:/workspace -w/workspace --entrypoint python robotwranglers/pynchon:${PYNCHON_VERSION} 
pynchon.run:=$(shell which pynchon >/dev/null 2>/dev/null && echo python || echo "${pynchon.docker}") -m pynchon.util.makefile

# Macros for use with jq/yq/jb, using local tools if available and falling back to dockerized versions
jq.docker=${docker.run.base} -e key=$${key:-} -v $${DOCKER_HOST_WORKSPACE:-$${PWD}}:/workspace -w/workspace ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}
yq.docker=${docker.run.base} -e key=$${key:-} -v `pwd`:/workspace -w/workspace mikefarah/yq:$${YQ_VERSION:-4.43.1}
yq.run:=$(shell which yq 2>/dev/null || echo "${yq.docker}")
jq.run:=$(shell which jq 2>/dev/null || echo "${jq.docker}")
jq.run.pipe:=$(shell which jq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} -v `pwd`:/workspace -w/workspace ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}")
yq.run.pipe:=$(shell which yq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} -v `pwd`:/workspace -w/workspace mikefarah/yq:$${YQ_VERSION:-4.43.1}")
jb.docker:=docker container run --rm ghcr.io/h4l/json.bash/jb:$${JB_CLI_VERSION:-0.2.2}
jb=${jb.docker}
json.from=${jb}
jq=${jq.run}
yq=${yq.run}
# _yml.stem=$(shell basename -s .yml `basename -s .yaml ${1}`)

IMG_GUM?=v0.16.0
GLOW_VERSION?=v1.5.1
GLOW_STYLE?=dracula

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: compose.* targets
## ----------------------------------------------------------------------------
##
## Targets for working with docker compose, without using the `compose.import` macro.  
##
## These targets support basic operations on compose files like 'build' and 'clean', 
## so in some cases scaffolded targets will chain here.
##
##-------------------------------------------------------------------------------
##
## DOCS:
##  * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-compose)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

${CMK_COMPOSE_FILE}:
	ls ${CMK_COMPOSE_FILE} 2>/dev/null >/dev/null \
	|| verbose=0 ${mk.def.to.file}/FILE.TUX_COMPOSE/${CMK_COMPOSE_FILE}

compose.build/%:
	@# Builds all services for the given compose file.
	@# This optionally runs for just the given service, otherwise on all services.
	@#
	@# USAGE:
	@#   ./compose.mk compose.build/<compose_file>
	@#   svc=<svc_name> ./compose.mk compose.build/<compose_file>
	@#
	$(call log.docker, \
		compose.build ${sep} ${green}$(shell basename ${*}) ${sep} ${dim_ital}$${svc:-all services})
	label='build finished.' ${make} flux.timer/.compose.build/${*}
.compose.build/%:
	case $${force:-0} in \
		""|0) force='';; \
		*) force='--no-cache' ;; \
	esac \
	&& case $${quiet:0} in \
		""|0) quiet='';; \
		*) quiet='--quiet' ;; \
	esac \
	&& $(trace_maybe) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} \
		-f ${*} build $${quiet} $${force} $${svc:-} \
			2> >(grep -v Built$$ >/dev/stderr)

compose.clean/%:
	@# Runs `docker compose down` for the given compose file, 
	@# including reasonable cleanup like --rmi and --remove-orphans, etc.
	@# This optionally runs on a given service, otherwise on all services.
	@#
	@# USAGE:
	@#   ./compose.mk compose.clean/<compose_file>
	@#   svc=<svc_name> ./compose.mk compose.clean/<compose_file> 
	@#
	$(trace_maybe) \
	&& $(call log.docker, \
		compose.clean ${dim}file=${*} ${sep} ${dim_ital}$${svc:-all services}) \
	&& ${docker.compose} -f ${*} \
		--progress quiet down -t 1 --remove-orphans --rmi local $${svc:-}

compose.dispatch.sh/%:
	@# Similar interface to the scaffolded '<compose_stem>.dispatch' target,
	@# except that this is a backup plan for when 'compose.import' has not
	@# imported services more directly.
	@#
	@# USAGE: 
	@#   cmd=<shell_cmd> svc=<svc_name> compose.dispatch.sh/<fname>
	@#
	$(call log.trace, ${GLYPH.DOCKER} compose.dispatch ${sep} ${green}${*}) \
	&& ${trace_maybe} \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${*} run \
		--rm --remove-orphans \
		--entrypoint $${entrypoint:-bash} $${svc} ${dash_x_maybe} \
		-c "$${cmd:-true}" $(_compose_quiet)

compose.get.stem/%:; basename -s .yml `basename -s .yaml ${*}`
	@# Returns a normalized version of the stem for the given compose-file.
	@# (A "stem" is just the basename without a suffix.)
	@#
	@# USAGE: ./compose.mk compose.get.stem/<fname>

compose.images/%:; ${docker.compose} -f ${*} config --images
	@# Returns all images used with the given compose file.

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
	&& header="loadf ${sep} ${dim_green}${underline}$${fname}${no_ansi} ${sep}" \
	&& $(call log.io, $${header} $${cmd_disp}) \
	&& ls $${fname} > ${devnull} || (printf "No such file"; exit 1) \
	&& tmpf=./.tmp.mk \
	&& stem=`${make} compose.get.stem/$${fname}` \
	&& eval "$${LOADF}" > $${tmpf} \
	&& chmod ugo+x $${tmpf} \
	&& ( [ "$${TRACE}" == 1 ] \
		 && ( ( style=monokai ${make} io.preview.file/$${fname} \
		        && ${make} io.preview.file/$${tmpf} ) \
					2>&1 | ${stream.indent} ) \
		 || true ) \
	&& ( \
			$(call log.part1, ${green}${GLYPH_IO} $${header} ${dim}Validating services) \
			&& validation=`$${tmpf} $${stem}.services` \
			&& count=`printf "$${validation}"|${stream.count.words}` \
			&& validation=`printf "$${validation}" \
				| xargs | fmt -w 60 \
				| ${stream.indent} | ${stream.indent}` \
			&& $(call log.part2, ${dim_green}ok${no_ansi_dim} ($${count} services total)) \
		) \
	&& first=`make -f $${tmpf} $${stem}.services \
		| head -5 | xargs -I% printf "% " \
		| sed 's/ /,/g' | sed 's/,$$//'` \
	&& msg=`[ -z "$${words:-}" ] && echo 'Starting TUI' || echo "Starting downstream targets"` \
	&& $(call log.io, $${header} ${dim}$${msg}) \
	&& ${trace_maybe} \
	&& $(call log.trace, $${header} Handing off to generated makefile) \
	&& $(call mk.yield, ${io.shell.isolated} make ${MAKE_FLAGS} -f $${tmpf} $${words:-tux.open.service_shells/$${first}})

compose.select/%:
	@# Interactively selects a container from the given docker compose file,
	@# then drops into an interactive shell for that container.  
	@#
	@# The container must already have sh or bash.
	@#
	@# USAGE:
	@#  ./compose.mk compose.select/demos/data/docker-compose.yml
	@#
	choices="`CMK_INTERNAL=1 ${make} compose.services/${*}|${stream.nl.to.space}`" \
	&& header="Choose a container:" && ${io.get.choice} \
	&& set -x && ${io.shell.isolated} ${__interpreter__} loadf ${*} $${chosen}.shell

compose.services/%:
	@# Returns space-delimited names for non-abstract services defined by the given composefile.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk compose.services/demos/data/docker-compose.yml
	set -o pipefail \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS:-} -f ${*} config --services 2>/dev/null \
	| sort | grep -v abstract | grep -v "no such file or directory" | ${stream.nl.to.space}

compose.validate/%:
	@# Validates the given compose file (i.e. asks docker compose to parse it)
	@#
	@# USAGE:
	@#   ./compose.mk compose.validate/<compose_file>
	@#
	header="${GLYPH_IO} compose.validate ${sep}" \
	&& $(call log.trace, $${header}  ${dim}extra="$${COMPOSE_EXTRA_ARGS}") \
	&& $(call log.part1, $${header} ${dim}$${label:-Validating compose file} ${sep} ${*}) \
	&& CMK_INTERNAL=1 ${make} compose.services/${*} ${all_devnull} \
	; case $$? in \
		0) $(call log.part2, ${GLYPH_CHECK} ok) && exit 0; ;; \
		*) $(call log.part2, ${red}failed) && exit 1; ;; \
	esac

compose.validate.quiet/%:; CMK_INTERNAL=1 ${make} compose.validate/${*} >/dev/null 2>/dev/null
	@# Like `compose.validate`, but silent.

compose.require:
	@# Asserts that docker compose is available.
	docker info --format json | ${jq} -e '.ClientInfo.Plugins[]|select(.Name=="compose")'
compose.size/%:
	@# Returns image sizes for all services in the given compose file,
	@# i.e. JSON like `{ "repo:tag" : "human friendly size" }`
	@#
	filter="`${make} compose.images/${*} | ${stream.as.grepE}`" \
	&& ${make} docker.size.summary | grep -E "$${filter}" | ${jq.column.zipper}

compose.versions/%: 
	@# Attempts to extract version-defaults from the given compose file.
	cat ${*} \
		| grep -o -w '[$$]{[^}]*}' | grep ':-' | uniq | sort \
		| sed 's/^..//' \
		| sed 's/.$$//' | sed 's/:-/=/' | grep VERSION
compose.versions_table/%:
	@# Like `.versions` but returns a markdown table of results 
	( printf "| Component | Version |\n|---|---|\n" \
		&& ${make} compose.versions/${*} \
		| awk -F= '{print "| " $$1 " | " $$2 " |" }' )


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: docker.* targets
##
## The `docker.*` targets cover a few helpers for working with docker. 
##
## This interface is deliberately minimal, focusing on verbs like 'stop' and 
## 'stat' more than verbs like 'build' and 'run'. That's because containers that
# are managed by docker compose are preferred, but some ability to work with 
# inlined Dockerfiles for simple use-cases is supported. For an example see the
## implementation of `stream.pygmentize`.
##
##-------------------------------------------------------------------------------
##
## DOCS:
##  * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-docker)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

jq.column.zipper=${jq} -R 'split(" ")' \
	| ${jq} '{(.[0]) : .[1]}' \
	| ${jq} -s 'reduce .[] as $$item ({}; . + $$item)' \
	| ${jq} 'to_entries | sort_by(.value) | from_entries' 

docker.compose:=$(shell docker compose >/dev/null 2>/dev/null && echo docker compose || echo echo DOCKER-COMPOSE-MISSING;) 

docker.containers.all:=docker ps --format json

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

docker.image.entrypoint: 
	@# Returns the current entrypoint for the given image.
	$(call mk.assert.env, img)
	docker inspect $${img} --format='{{.Config.Entrypoint}}'

docker.image.sizes:; ${make} docker.size.summary | ${jq.column.zipper}
	@# Shows disk-size summaries for all images. 
	@# Returns JSON like `{ "repo:tag" : "human friendly size" }`
	@# See `docker.size.summary` for similar column-oriented output
	
# docker.image.stop/%:; img=${*} ${make} docker.image.stop
docker.image.stop:
	@# Stops one or more running instances launched from given image.
	$(call mk.assert.env, img)
	${trace_maybe} \
	&& id=`docker ps --filter name= --format json \
		| ${jq} -r ".|select(.Image==\"$${img}\").ID" \
		| ${stream.nl.to.space}` \
		img="" ${make} docker.stop 

docker.size.summary:
	@# Shows disk-size summaries for all images. 
	@# Returns nl-delimited output like `repo:tag human_friendly_size`
	@# See `docker.image.sizes` for similar JSON output.
	@#
	docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' \
		| grep -v '<none>:<none>' |grep -v '^hello-world:' \
		| awk 'NF >= 2 {print $$1, substr($$0, index($$0, $$2))}'

docker.host_ip:
	@# Attempts to return the address for the docker host.  
	@# This is the IP that *containers* can use to contact the host machine from, 
	@# if the network bridge is setup as usual.  This can be useful for things 
	@# like testing kind/k3d cluster services from the outside.
	@#
	@# This must run on the host and the details can be *passed* to containers; 
	@# it will not run inside containers. This  probably does not work outside of linux.
	@#
	ip addr show docker0 | grep -Po 'inet \K[\d.]+'
	# Helper for defining targets, this curries the 
# given parameter as a command to the given docker image 
#
# USAGE: ( concrete )
#   my-target/%:; ${docker.image.curry.command}/alpine,cat
#
# USAGE: ( generic )
#   my-target/%:; ${docker.image.curry.command}/<img>,<entrypoint>
docker.curry.command=cmd="${*}" ${make} flux.apply
docker.image.curry.command=cmd="${*}" ${make} docker.image.run
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
	@# Also available as a function.
	@# See 'docker.images' for more details.

docker.build/% Dockerfile.from.fs/% docker.from.file/%:
	@# Standard noisy docker build for the given filename.
	@#
	@# For embedded Dockerfiles see instead `Dockerfile.build/<def_name>`
	@# For remote Dockerfiles, see instead`docker.from.url`
	@#
	@# USAGE:
	@#   tag=<tag_to_use> ./compose.mk docker.build/<name>
	@#
	$(call mk.assert.env, tag)
	case ${*} in \
		-) true;; \
		*) ls ${*} >/dev/null;; \
	esac && label='build finished.' ${make} flux.timer/.docker.build/${*}

.docker.build/%:
	${trace_maybe} \
	&& case $${quiet:-1} in \
		0) quiet=;; \
		*) quiet=-q;; \
	esac \
	&& set -x && docker build $${quiet} $${build_args:-} -t $${tag} $${docker_args:-} -f ${*} .

docker.commander:
	@# TUI layout providing an overview for docker.
	@# This has 3 panes by default, where the main pane is lazydocker, 
	@# plus two utility panes. Automation also ensures that lazydocker 
	@# always starts with the "statistics" tab open.
	@#
	$(call log.docker, ${@} ${sep} ${no_ansi_dim}Opening commander TUI for docker)
	tui_spec="flux.wrap/docker.stat:.tux.widget.ctop" \
	&& tui_spec="flux.loopf/$${tui_spec},.tux.widget.img.rotate" \
	&& tui_spec=".tux.widget.lazydocker,$${tui_spec}" \
	&& geometry="${GEO_DOCKER}" ${make} tux.open/$${tui_spec}

docker.context:; docker context inspect
	@# Returns all of the available docker context. 
	@# JSON output, pipe-friendly.

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
	ctx=`docker context show` \
	&& case "$(*)" in \
		current) \
			${make} docker.context \
			|  ${jq.run} ".[]|select(.Name=\"$${ctx}\")" -r; ;; \
		*) \
			${make} docker.context \
			| ${jq.run} ".[]|select(.Name=\"${*}\")" -r; ;; \
	esac

docker.def.is.cached/%:
	@# Answers whether the named define has a cached docker image
	@#
	@# This never fails and exits with "yes" if the image has been
	@# built at least once, and "no" otherwise, but it also respects
	@# whether 'force=1' has been set.
	@#
	header="${GLYPH.DOCKER} ${no_ansi_dim} Checking if ${dim_cyan}${ital}${*}${no_ansi_dim} is cached" \
	&& $(call log.trace.part1, $${header} ) \
	&& ( ${docker.images} || true) | grep --word-regexp "${*}" 2>/dev/null >/dev/null \
	; case $$? in \
		0) ( case $${force:-0} in \
				1) ($(call log.trace.part2, ${yellow}no${no_ansi_dim} (force is set)) && echo no;);; \
				*) ($(call log.trace.part2, ${dim_green}yes) && echo yes;);;  \
			esac); ;;  \
		*) $(call log.trace.part2, missing) && echo no; ;; \
	esac

docker.def.run/%:
	@# Builds, then runs the docker-container for the given define-block
	@#
	${make} docker.from.def/${*} docker.dispatch/${*}

docker.def.start/% docker.start.def/%:
	@# Starts a container represented by named define-block.
	@# (This is like docker.run.def but assumes default entrypoint)
	@#
	${make} docker.from.def/${*} docker.start/compose.mk:${*}

docker.dispatch=${make} docker.dispatch
docker.dispatch/%:
	@# Runs the named target inside the named docker container.
	@# This works for any image as given; See instead 'mk.docker.run' 
	@# for a version that implicitly uses internally generated containers.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#  img=<img> make docker.dispatch/<target>
	@#
	@# EXAMPLE:
	@#  img=debian/buildd:bookworm ./compose.mk docker.dispatch/flux.ok
	@#
	$(trace_maybe) \
	&& entrypoint=make \
		cmd="${MAKE_FLAGS} ${makefile_list} ${*}" \
			img=$${img} ${make} docker.run.sh

docker.images=(\
	$(call docker.tags.by.repo,compose.mk) \
	; $(call docker.tags.by.repo,${CMK_EXTRA_REPO})) | sort | uniq

docker.image.dispatch=${make} docker.image.dispatch
docker.image.dispatch/%:
	@# Similar to `docker.dispatch/<arg>`, but accepts both the image
	@# and the target as arguments instead of using environment variables.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk docker.image.dispatch/<img>/<target>
	tty=1 img=`printf "${*}" | cut -d/ -f1` \
	${make} docker.dispatch/`printf "${*}" | cut -d/ -f2-`

# NB: exit status does not work without grep..
docker.images.filter=docker images --filter reference=${1} \
	--format "{{.Repository}}:{{.Tag}}" | grep ${1}

docker.image.run/%:
	@# Runs the named image, using the (optional) named entrypoint.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk docker.image.run/<img>,<entrypoint>
	@# 
	export img="`printf ${*}|cut -d, -f1`" \
	&& entrypoint="$${entrypoint:-`printf ${*}|cut -s -d, -f2-`}" \
	&& ${trace_maybe} \
	&& entrypoint="`[ -z "$${entrypoint:-}" ] \
	&& echo "none" || echo "$${entrypoint}"`" \
	${make} docker.run.sh
docker.image.run=${make} docker.image.run

docker.init:
	@# Checks if docker is available, then displays version/context (no real setup)
	@#
	( dctx="`docker context show 2>/dev/null`" \
		; $(call log.docker, ${@} ${sep} ${no_ansi_dim}context ${sep} ${ital}$${dctx}${no_ansi}) \
		&& dver="`docker --version`" \
		&& $(call log.docker, ${@} ${sep} ${no_ansi_dim}version ${sep} ${ital}$${dver}${no_ansi})) \
	| ${stream.dim} | $(stream.to.stderr)
	${make} docker.init.compose

docker.init.compose:
	@# Ensures compose is available.  Note that
	@# build/run/etc cannot happen without a file,
	@# for that, see instead targets like '<compose_file_stem>.build'
	@#
	cver="`${docker.compose} version`" \
	; $(call log.docker, ${@} ${sep} ${no_ansi_dim} version ${sep} ${ital}$${cver}${no_ansi})

docker.lambda/%:
	@# Similar to `docker.def.run`, but eschews usage of tags 
	@# and rebuilds implicitly on every single invocation. 
	@#
	@# Note that technically, this is still caching and 
	@# still actually  involves tags, but the tags are naked SHAs.
	@#
	entrypoint=`if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi` \
	&& cmd=`if [ -z "$${cmd:-}" ]; then echo ""; else echo "$${cmd:-true}"; fi` \
	&& sha=`docker build -q - <<< $$(${make} mk.def.read/Dockerfile.${*})` \
	&& docker run -i $${entrypoint} \
		${docker.env.standard} \
		-v $${workspace:-$${PWD}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		-w /workspace --rm $${sha} $${cmd}

docker.logs/%:
	@# Tails logs for the given container ID.
	@# This is non-blocking.
	@#
	$(call log.docker, docker.logs ${sep} tailing logs for ${*})
	docker logs ${*}
docker.logs.follow/%:
	@# Tails logs for the given container ID.
	@# This is blocking, and never exits.
	$(call log.docker, docker.logs.follow ${sep} reattaching to ${*})
	docker logs --follow  ${*} 
docker.logs.follow/:
	@# Error handler, only called when `docker.ps` output was null
	$(call log.docker, docker.logs.follow ${sep} ${yellow}No container ID to get logs from.)
docker.logs.timeout/%:
	@# Like docker.logs.follow, but times out after the given number of seconds.
	@# USAGE: docker.logs.timeout/<timeout_in_seconds>,<id>
	timeout=$(call mk.unpack.arg,1) \
	&& id=$(call mk.unpack.arg,2,$${id:-}) \
	quiet=1 CMK_INTERNAL=1 \
	cmd="docker logs -f $${id} 2>&1" timeout=3 ${make} flux.timeout.sh 

docker.from.def/% docker.build.def/% Dockerfile.build/%:
	@# Builds a container, treating the given 'define' block as a Dockerfile.
	@# This implicitly prefixes the named define with 'Dockerfile.' to enforce 
	@# naming conventions, and make for easier cleanup.  Container tags are 
	@# determined by 'tag' var if provided, falling back to the name used 
	@# for the define-block.  Tags are implicitly prefixed with 'compose.mk:',
	@# for the same reason as the other prefixes.
	@#
	@# USAGE: ( explicit tag )
	@#   tag=<my_tag> make docker.from.def/<my_def_name>
	@#
	@# USAGE: ( implicit tag, same name as the define-block )
	@#   make docker.from.def/<my_def_name>
	@#
	@# REFS:
	@#  [1]: https://robot-wranglers.github.io/compose.mk/#demos
	@#
	${trace_maybe} && inp=`printf ${*}|sed 's/compose.mk://'` \
	&& def_name="Dockerfile.$${inp}" \
	&& tag="compose.mk:$${tag:-$${inp}}" \
	&& header="${GLYPH.DOCKER} Dockerfile.build ${sep} ${dim_cyan}${ital}$${def_name}${no_ansi_dim}" \
	&& $(call log.trace, $${header} ) \
	&& $(trace_maybe) \
	&& $(call io.mktemp) \
	&& ${mk.def.to.file}/$${def_name}/$${tmpf} \
	&& case `${make} docker.def.is.cached/$${inp}` in \
		yes) true;; \
		no) ( $(call log.docker, $(shell echo ${@}|cut -d/ -f1) \
					${sep} ${ital}${dim_cyan}$(shell echo ${@}|cut -d/ -f2) ${sep} ${dim}tag=${no_ansi}$${tag}${no_ansi_dim}) \
				&& cat $${tmpf} | ${stream.as.log} \
				&& $(call log, ${cyan_flow_right} ${bold}Building..) \
				&& tag=$${tag} ${make} docker.build/$${tmpf} ); ;; \
	esac
docker.from.github:
	@# Helper that constructs an appropriate url, then chains to `docker.from.url`.
	@#
	@# Note that the output tag will not be the same as the input tag here!  See 
	@# `docker.from.url` for more details.
	@#
	@# USAGE:
	@#  user=alpine-docker repo=git tag="1.0.38" ./compose.mk docker.from.github
	@#  
	url="https://github.com/$${user}/$${repo}.git#$${tag}:$${subdir:-.}" \
	tag=$${user}-$${repo}-$${tag} \
	${make} docker.from.url
docker.from.url:
	@# Builds a container, treating the given 'url' as a Dockerfile.  
	@# The 'tag' and 'url' env-vars are required.  Note that incoming 
	@# tags will get the standard repo prefix, i.e. end up as `compose.mk:<tag>`
	@#
	@# See also the docs about supported URL syntax:
	@#  https://docs.docker.com/build/concepts/context/#git-repositories
	@#
	@# FIXME: this currently does not respect 'force'
	@#
	@# USAGE:
	@#   url="<repo_url>#<branch_or_tag>:<sub_dir>" tag="<my_tag>" make docker.from.url
	@#
	$(call log.target.part1, ${dim_ital_cyan}$${tag})
	${docker.images} | grep -w "$${tag}" ${stream.obliviate} \
	&& ($(call log.target.part2, ${dim_green}already cached);  exit 0 )\
	|| ( $(call log.target.part2, ${yellow}not cached) \
		&& $(call log.target.part1, building) \
		&& $(call log.target.part2,\n${cyan_flow_right} ${dim_ital}$${url}) \
		&& quiet=$${quiet:-1} \
		&& quiet=`[ -z "$${quiet:-}" ] && true || echo "-q"` \
		&& ${trace_maybe} \
		&& docker build $${quiet} -t compose.mk:$${tag} $${url})

docker.help: mk.namespace.filter/docker.
	@# Lists only the targets available under the 'docker' namespace.
	@#

docker.network.panic:; docker network prune -f
	@# Runs 'docker network prune' for the entire system.
docker.network.connect/%:
	@# USAGE: ./compose.mk docker.network.connect/net1,net2
	$(call bind.args.from_params) \
	&& docker network connect $${_1st} $${_2nd}

docker.panic: docker.stop.all docker.network.panic docker.volume.prune docker.system.prune
	@# Debugging only!  This is good for ensuring a clean environment,
	@# but running this from automation will nix your cache of downloaded
	@# images, and then you will probably quickly hit rate-limiting at dockerhub.
	@# It tears down volumes and networks also, so you do not want to run this in prod.
	@#
	docker rm -f $$(docker ps -qa | tr '\n' ' ') 2>/dev/null || true

docker.prune docker.system.prune:
	@# Debugging only! Runs 'docker system prune' for the entire system.
	@# 
	set -x && docker system prune -a -f

docker.prune.old:; docker system prune --all --force --filter "until=168h"
	@# Debugging only! Runs 'docker system prune --all --force --filter "until=168h"'

docker.ps:; docker ps --format json | ${jq} .
	@# Like 'docker ps', but always returns JSON.

docker.run.def:
	@# Treats the named define-block as a script, then runs it inside the given container.
	@#
	@# USAGE:
	@#  entrypoint=<entry> def=<def_name> img=<image> ./compose.mk docker.run.def
	@#
	true \
	&& $(call log.docker, docker.run.def ${no_ansi}${sep} ${dim_cyan}${ital}$${def}${no_ansi} ${sep} ${bold}${underline}$${img}) \
	&& case $${docker_args:-}} in \
		"") true;; \
		*) quiet=$${quiet:-0};; \
	esac \
	&& $(call io.mktemp) \
	&& ${make} mk.def.to.file/$${def}/$${tmpf} \
	&& (script_pre="$${cmd:-}" \
		&& unset cmd \
		&& script="$${script_pre} $${tmpf}" \
			img=$${img} ${make} docker.run.sh) \
	${stderr_stdout_indent}

docker.run.sh:
	@# Runs the given command inside the named container.
	@#
	@# This automatically detects whether it is used as a pipe & proxies stdin as appropriate.
	@# This always shares the working directory as a volume & uses that as a workspace.
	@# If 'env' is provided, it should be a comma-delimited list of variable names; 
	@# those variables will be dereferenced and passed into docker's "-e" arguments.
	@#
	@# USAGE:
	@#   img=... entrypoint=... cmd=... env=var1,var2 docker_args=.. ./compose.mk docker.run.sh
	@#
	${trace_maybe} \
	&& image_tag="$${img}" \
	&& entry=`[ "$${entrypoint:-}" == "none" ] && echo ||  echo "--entrypoint $${entrypoint:-bash}"` \
	&& net=`[ "$${net:-}" == "" ] && echo ||  echo "--net=$${net}"` \
	&& case "$${hostname:-}"  in \
		"") hostname="--hostname=$(shell echo $${img}| cut -d'@' -f1 | cut -d: -f1)";; \
		*) hostname="--hostname=$${hostname}";; \
	esac \
	&& cmd="$${cmd:-$${script:-}}" \
	&& disp_cmd="`echo $${cmd} | sed 's/${MAKE_FLAGS}//g'|${stream.lstrip}`" \
	&& ( \
		[ -z "$${quiet:-}" ] \
		&& ( \
			$(call log.docker, docker.run ${sep} ${dim}img=${no_ansi}$${image_tag}) \
			&& case $${docker_args:-} in \
				"") true=;; \
				*) $(call log.docker, docker.run ${sep}${dim} docker_args=${no_ansi}${ital}$${docker_args:-});; \
			esac \
			&& $(call log, ${green_flow_right} ${dim_cyan}[${no_ansi}${bold}$${entrypoint:-}${no_ansi}${cyan}] ${no_ansi_dim}$${disp_cmd})  \
			) \
		|| true ) \
	&& extra_env=`[ -z $${env:-} ] && true || ${make} .docker.proxy.env/$${env}` \
	&& tty=`[ -z $${tty:-} ] && echo \`[ -t 0 ] && echo "-t"|| true\` || echo "-t"` \
	&& cmd_args="\
		--rm -i $${tty} $${extra_env} \
		$${hostname} \
		-e CMK_INTERNAL=1 \
		${docker.env.standard} \
		-v $${workspace:-$${PWD}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		-w /workspace \
		$${entry} \
		$${docker_args:-}" \
	&& dcmd="docker run -q $${net} $${cmd_args}" \
	&& ([ -p ${stdin} ] && dcmd="${stream.stdin} | eval $${dcmd}" || true) \
	&& eval $${dcmd} $${image_tag} $${cmd}
.docker.proxy.env/%:
	@# Internal usage only.  This generates code that has to be used with eval.
	@# See 'docker.run.sh' for an example of how this is used.
	$(call log.docker, docker.proxy.env${no_ansi} ${sep} ${dim}${ital}$${env:-}) \
	&& printf ${*} | ${stream.comma.to.nl} \
	| xargs -I% bash -c "[[ -v % ]] && printf '%\n' || true " \
	| xargs -I% printf " -e %=\"\`echo \$${%}\`\""; printf '\n'


docker.start:; ${make} docker.start/$${img}
	@# Like 'docker.run', but uses the default entrypoint.
	@# USAGE: 
	@#   img=.. ./compose.mk docker.start

docker.run/% docker.start/%:; img="${*}" entrypoint=none ${make} docker.run.sh
	@# Starts the named docker image with the default entrypoint
	@# USAGE: 
	@#   ./compose.mk docker.start/<img>
.docker.start/%:; ${make} docker.start/compose.mk:${*}
	@# Like 'docker.start' but implicitly uses 'compose.mk' prefix. This is used with "local" images.

docker.start.tty/%:; tty=1 ${make} docker.start/${*}
	@# Like `docker.start/..`, but sets tty=1
docker.start.tty:; tty=1 ${make} docker.start
	@# Like `docker.start`, but sets tty=1

docker.socket:; ${make} docker.context/current | ${jq.run} -r .Endpoints.docker.Host
	@# Returns the docker socket in use for the current docker context.
	@# No arguments & pipe-friendly.

docker.stat: docker.init
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
	export CMK_INTERNAL=1 && $(call io.mktemp) && \
	${make} docker.context/current > $${tmpf} \
	&& $(call log.docker, ${@}) \
	&& ${jb} \
		version="`docker --version | sed 's/Docker " //' | cut -d, -f1|cut -d' ' -f3`" \
		container_count="`docker ps --format json| ${jq.run} '.Names'|${stream.count.lines}`" \
		socket="`cat $${tmpf} | ${jq.run} -r .Endpoints.docker.Host`" \
		context_name="`cat $${tmpf} | ${jq.run} -r .Name`"

docker.stop:
	@# Stops one or more containers, with optional timeout,
	@# filtering by the given id, name, or image.
	@#
	@# USAGE:
	@#   id=8f350cdf2867 ./compose.mk docker.stop 
	@#   name=my-container ./compose.mk docker.stop 
	@#   name=my-container timeout=99 ./compose.mk docker.stop
	@#   img=debian:latest ./compose.mk docker.stop
	@#
	case $${img} in \
		"") true;; \
		*) ${make} docker.image.stop && exit 0;; \
	esac \
	&& case "$${id:-$${name:-}}" in \
		"") \
			$(call log.docker, ${@} ${sep} ${yellow}Nothing to stop) \
			&& exit 0;; \
	esac \
	&& $(call log.docker, docker.stop${no_ansi_dim} ${sep} ${green}$${id:-$${name}}) \
	&& ${trace_maybe} \
	&& export cid=`[ -z "$${id:-}" ] \
		&& docker ps --filter name=$${name} --format json \
			| ${jq.run} -r .ID || echo $${id}` \
	&& case "$${cid:-}" in \
		"") \
			$(call log.docker, ${@} ${sep} ${yellow}No containers found); ;; \
		*) \
			${trace_maybe} \
			&& docker stop -t $${timeout:-1} $${cid} >/dev/null; ;; \
	esac ${quiet.maybe}

docker.stop.all:
	@# Non-graceful stop for all running containers.
	@#
	@# USAGE:
	@#   ./compose.mk docker.stop name=my-container timeout=99
	@#
	ids=`docker ps -q | tr '\n' ' '` \
	&& count=`printf "$${ids:-}" | ${stream.count.words}` \
	&& $(call log.docker, docker.stop.all ${sep} ${dim}(${dim_green}$${count}${no_ansi_dim} containers total)) \
	&& [ -z "$${ids}" ] && true || (set -x && docker stop -t $${timeout:-1} $${ids})


docker.volume.prune:; set -x && docker volume prune -f
	@# Runs 'docker volume prune' for the entire system.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: docker.* targets
## BEGIN: io.* targets
##
## The `io.*` namespace has misc helpers for working with input/output, including
## utilities for working with temp files and showing output to users.  User-facing 
## output leverages  charmbracelet utilities like gum[2] and glow[3].  Generally we 
## use tools directly if they are available, falling back to utilities in containers.
##
##-------------------------------------------------------------------------------
##
## DOCS:
##  * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-io)
##  * `[2]:` [gum documentation](https://github.com/charmbracelet/gum)
##  * `[3]:` [glow documentation](https://github.com/charmbracelet/glow)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Helper for working with temp files.  Returns filename,
# and uses 'trap' to handle at-exit file-deletion automatically.
# Note that this has to be macro for reasons related to ONESHELL.
# You should chain commands with ' && ' to avoid early deletes
ifeq (${OS_NAME},Darwin)
col_b=LC_ALL=C col -b
io.mktemp=export tmpf=$$(mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
# Similar to io.mktemp, but returns a directory.
io.mktempd=export tmpd=$$(mktemp -u ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -r $${tmpd}" EXIT
else
col_b=col
io.mktemp=export tmpf=$$(TMPDIR=`pwd` mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
# Similar to io.mktemp, but returns a directory.
io.mktempd=export tmpd=$$(TMPDIR=`pwd` mktemp -d ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -r $${tmpd}" EXIT
endif

# Helpers for asserting environment variables are present and non-empty 
mk.assert.env_var=[[ -z "$${$(strip ${1})}" ]] && { $(call log.io, ${red}Error:${no_ansi_dim} required variable ${no_ansi}${underline}$(strip ${1})${no_ansi_dim} is unset or empty!); exit 39; } || true
mk.assert.env=$(foreach var_name, ${1}, $(call mk.assert.env_var, ${var_name});)

# USAGE:
#   $(call mk.declare, K8S_PROJECT_LOCAL_CLUSTER)
mk.declare=$(call ${1})

# This is a hack because charmcli/gum is distroless, but the spinner needs to use "sleep", etc
# io.gum.alt.dumb=docker run -it -e TERM=dumb --entrypoint /usr/local/bin/gum --rm `docker build -q - <<< $$(printf "FROM alpine:${ALPINE_VERSION}\nRUN apk add -q --update --no-cache bash\nCOPY --from=charmcli/gum:${IMG_GUM} /usr/local/bin/gum /usr/local/bin/gum")`
glow.docker:=docker run -q -i charmcli/glow:${GLOW_VERSION} -s ${GLOW_STYLE}

# WARNING: newer glow is broken with pipes & ptys.. 
# so we force docker rather than defaulting to a host tool 
# see https://github.com/charmbracelet/glow/issues/654
# glow.run:=$(shell which glow >/dev/null 2>/dev/null && echo "`which glow` -s ${GLOW_STYLE}" || echo "${glow.docker}")
glow.run:=${glow.docker}


io.awk=CMK_INTERNAL=1 ${make} io.awk
io.awk/%:; ${stream.stdin} | awk -f <(${mk.def.read}/${*}) $${awk_args:-}
	@# Treats the given define-block name as an awk script, 
	@# always running it on stdin. Used internally.  
	@# Must remain silent, does not support args.  
	@# Also available as a macro.
	@#
	@# USAGE: io.awk/<def_name>

io.bash=CMK_INTERNAL=1 ${make} io.bash
io.bash/%:
	@# Treats the given define-block name as a bash script.
	@# Also available as a macro.
	@#
	@# USAGE: io.bash/<def_name>,<optional_args>
	is_pipe="`[ -p /dev/stdin ] && echo pipe || echo 'no input'`" \
	&& hdr="io.bash ${sep}${dim_cyan} ${*} ${sep}${dim}" \
	&& $(call log.io, $${hdr} Running script with ${no_ansi_dim}$${is_pipe}) \
	&& defname="`echo ${*} | cut -d, -f1`" \
	&& ${io.mktemp} && (${mk.def.read}/$${defname}) > $${tmpf} \
	&& args="`echo ${*} | cut -s -d, -f2- | ${stream.comma.to.space}`" \
	&& sloc=`cat $${tmpf} | ${stream.count.lines}` \
	&& $(call log.io, $${hdr} sloc=$${sloc} args=$${args:-..}) \
	&& case $${verbose:-0} in \
		"1") $(call log.file.contents,$${tmpf});; \
	esac \
	&& (case $${is_pipe} in \
		"pipe") cat /dev/stdin ;; \
		*) echo ;; \
	esac) | bash -euo pipefail ${dash_x_maybe} $${tmpf} $${args}

io.shell:
	@# Starts an interactive shell with all the environment variables set
	@# by the parent environment, plus those set by this Makefile context.
	$(call log.io, ${@} ${sep} ${ital}${bold}Interactive)
	$(call log.io, ${@} ${sep} ${dim}${GLYPH_CHECK}.. environment will match make-context)
	export PS1="${bold}[${no_ansi_dim}lvl=${MAKELEVEL}${no_ansi}${bold}]${no_ansi} ${dim}[${green}make-debug${no_ansi_dim}] \w $$ " \
	&& bash --norc -i </dev/tty >/dev/tty 2>&1
io.browser/%:; url="`CMK_INTERNAL=1 ${make} mk.get/${*}`" ${make} io.browser
	@# Like `io.browser`, but accepts a variable-name as an argument.
	@# Variable will be dereferenced and stored as 'url' before chaining.
	@# NB: This requires python on the host and can not run from docker.

io.browser:
	@# Tries to open the given URL in a browser.
	@# NB: This requires python on the host and can not run from docker.
	@#
	@# USAGE: 
	@#  url="..." ./compose.mk io.browser
	@#
	$(call log.target, ${red}opening $${url})
	python3 -c"import webbrowser; webbrowser.open(\"$${url}\")" \
		|| $(call log.target, ${red}failure: ${sep} browser failed to open or was killed)

IMG_CURL=curlimages/curl:8.13.0
io.curl=$(shell which curl 2>/dev/null || echo docker run --rm ${IMG_CURL}) $(if $(filter undefined,$(origin 1)),,$(1))
_io.curl=${io.curl} ${1}
io.curl.stat=bash ${dash_x_maybe} -c '${io.curl} -s -o /dev/null $(if $(filter undefined,$(origin 1)),$${1},$(1)) > /dev/null' -- 
io.curl.quiet=$(call io.curl, -s $(if $(filter undefined,$(origin 1)),,$(1)))
io.log.curl=$(call io.curl.quiet, nginx-tcp:8080) | ${stream.as.log}

io.echo:; ${stream.stdin}
	@# Echos data from input stream. Alias for the `stream.stdin` macro.

io.env:
	@# Dumps a relevant subset of environment variables for the current context.
	@# No arguments.  Pipe-safe since this is just filtered output from 'env'.
	@#
	@# USAGE: ./compose.mk io.env
	CMK_INTERNAL=1 ${make} io.env.filter.prefix/PWD,CMK,KUBE,K8S,MAKE,TUI,DOCKER,__

io.env/% io.env.filter.prefix/%:
	@# Filters environment variables by the given prefix or (comma-delimited) prefixes.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk io.env/<prefix1>,<prefix2>
	echo ${*} | ${_io.env} | ${stream.grep.safe} | grep -v ___ | sort
_io.env=sed 's/,/\n/g' | xargs -I% sh -c "env | ${stream.grep.safe} | grep \"^%.*=\" || true" 
io.env=bash -c 'echo $${1\#/} | ${_io.env}' -- 
io.env.filter.prefix=${io.env}

io.envp=CMK_INTERNAL=1 ${make} io.envp
io.envp io.env.pretty: flux.pipeline/io.env,stream.ini.pygmentize
	@# Pretty version of io.env, this includes some syntax highlighting.
	@# No arguments.  See 'io.envp/<arg>' for a version that supports filtering.
	@#
	@# USAGE: ./compose.mk io.envp
	
io.envp/% io.env.pretty/%:
	@# Pretty version of 'io.env/<arg>', this includes syntax highlighting and also filters the output.
	@#
	@# USAGE:
	@#  ./compose.mk io.envp/<prefix_to_filter_for>
	@#
	@# USAGE: (only vars matching 'TUI*')
	@#  ./compose.mk io.envp/TUI
	@#
	${make} io.env/${*} | ${make} stream.ini.pygmentize
io.figlet/%:; label="${*}"; ${io.figlet}
	@# Treats the argument as a label, and renders it with `figlet`. 
	@# NB: This requires the embedded tui is built.  
	
io.figlet:; ${io.figlet} 
	@# Pulls `label` from the environment and renders it with `figlet`. 
	@# Also available as a macro. NB: This requires the embedded tui is built.
io.figlet=printf "figlet -f$${font:-3d} $${label}" | ${make} tux.shell.pipe >/dev/stderr

io.file.select=header="Choose a file: (dir=$${dir:-.})"; \
	choices="`ls $${dir:-.}/$${pattern:-} | ${stream.nl.to.space}`" \
	&& $(call log.io,io.file.select ${sep} $${dir:-.} ${sep} $${choices}) \
	&& ${io.get.choice} 
# Creates file w/ the 2nd argument as a command, iff the file given by the 1st arg is stale
io.file.gen.maybe=test \( ! -f ${1} -o -n "%$$(find ${1} -mtime +0 -mmin +$${freshness:-2.7} 2>/dev/null)" \) && ${2} > ${1}

io.get.url=$(call io.mktemp) && curl -sL $${url} > $${tmpf}
io.gum.docker=${trace_maybe} && docker run $$(if [ -t 0 ]; then echo "-it"; else echo "-i"; fi) -e TERM=$${TERM:-xterm} --entrypoint /usr/local/bin/gum --rm `docker build -q - <<< $$(printf "FROM alpine:${ALPINE_VERSION}\nCOPY --from=charmcli/gum:${IMG_GUM} /usr/local/bin/gum /usr/local/bin/gum\nRUN apk add --update --no-cache bash\n")`

ifeq ($(shell which gum >/dev/null 2> /dev/null && echo 1 || echo 0),1) 
io.gum.run:=`which gum`
io.get.choice=chosen=$$(${io.gum.run} choose --header="$${header:-Choose:}" $${choices})
else 
io.gum.run:=${io.gum.docker}
io.get.choice=$(call io.script.tmpf, ${io.gum.run} choose --header=\"$${header:-Choose:}\" _ $${choices}) \
	&& filter="`echo $${choices}|sed 's/ /|/g'`" \
	&& cat $${tmpf} | ${col_b} | grep -E "$${filter}" | tail -n-3 | tail -n-1 | awk -F"006l" '{print $$2}' | head -1 > $${tmpf}.selected \
	&& mv $${tmpf}.selected $${tmpf} && chosen="`cat $${tmpf}`"
endif
io.gum=(which gum >/dev/null && ( ${1} ) \
	|| (entrypoint=gum cmd="${1}" quiet=0 \
		img=charmcli/${IMG_GUM} ${make} docker.run.sh)) > /dev/stderr
io.gum.style=label="${1}" ${make} io.gum.style
io.gum.style.div:=--border double --align center --width $${width:-$$(echo "x=$$(tput cols 2>/dev/null ||echo 45) - 5;if (x < 0) x=-x; default=30; if (default>x) default else x" | bc)}
io.gum.style.default:=--border double --foreground 2 --border-foreground 2
io.gum.tty=export tty=1; $(call io.gum, ${1})

io.gum.choice/% io.gum.choose/%:
	@# Interface to `gum choose`.
	@# This uses gum if it is available, falling back to docker if necessary.
	@#
	@# USAGE:
	@#  ./compose.mk io.gum.choose/choice-one,choice-two
	choices="$(shell echo "${*}" | ${stream.comma.to.space})" \
	&& ${io.gum.run} choose $${choices}

io.gum.spin:
	@# Runs `gum spin` with the given command/label.
	@#
	@# EXAMPLE:
	@#   cmd="sleep 2" label=title ./compose.mk io.gum.spin
	@#
	@# REFS:
	@# [1] [gum documentation](https://github.com/charmbracelet/gum)
	@#
	${trace_maybe} \
	&& ${io.gum.docker} spin \
		--spinner $${spinner:-meter} \
		--spinner.foreground $${color:-39} \
		--title "$${label:-?}" -- $${cmd:-sleep 2};

# Labels automatically go through 'gum format' before 'gum style', so templates are supported.
io.gum.style io.draw.banner:; ${io.draw.banner}
	@# Helper for formatting text and banners using `gum style` and `gum format`.
	@# Expects label text under the `label variable, plus supporting optional `width`.
	@# Also available as a macro.  See instead `io.print.banner` for something simpler.
	@#
	@# REFS:
	@# [1] [gum documentation](https://github.com/charmbracelet/gum)
	@#
	@# EXAMPLE:
	@#   label="..." ./compose.mk io.draw.banner 
	@#   width=30 label='...' ./compose.mk io.draw.banner 
	
define io.draw.banner
	export label="$${label:-`date '+%T'`}" \
	&& ${io.gum.run} style ${io.gum.style.default} ${io.gum.style.div} $${label} \
	; case $$? in \
		0) true;; \
		*) (${io.print.banner});; \
	esac
endef

io.gum.style/% io.draw.banner/%:; label="${*}"; ${io.draw.banner}
	@# Prints a divider with the given label. 
	@# Invocation must be a legal target (Do not use spaces, etc!)
	@# See also `io.draw.banner` and `io.print.banner` for something simpler.
	@#
	@# USAGE: ./compose.mk io.draw.banner/<label>

io.help:; ${make} mk.namespace.filter/io.
	@# Lists only the targets available under the 'io' namespace.

io.gum.div=label=${@} ${make} io.gum.div
io.gum.div:; label=$${label:-${io.timestamp}} ${io.draw.banner}
	@# Draw a horizontal divider with gum.
	@# If `label` is not provided, this defaults to using a timestamp.
	@#
	@# USAGE:
	@#  label=".." ./compose.mk io.gum.div 
io.mkdir/%:; mkdir -p ${*}
	@# Runs `mkdir -p` for the named directory
io.preview.img/%:; cat ${*} | ${stream.img} 
	@# Console-friendly image preview for the given file. See also: `stream.img`
	@#
	@# USAGE: 
	@#   ./compose.mk io.preview.img/<path_to_img>

io.preview.markdown/%:; cat ${*} | ${stream.markdown} 
	@# Console-friendly markdown preview for the given file. See also `stream.markdown`

io.preview.pygmentize/%:; fname="${*}" ${make} stream.pygmentize
	@# Syntax highlighting for the given file.
	@# Lexer will autodetected unless override is provided.
	@# Style defaults to 'trac', which works best with dark backgrounds.
	@#
	@# USAGE:
	@#   ./compose.mk io.preview.pygmentize/<fname>
	@#   lexer=.. ./compose.mk io.preview.pygmentize/<fname>
	@#   lexer=.. style=.. ./compose.mk io.preview.pygmentize/<fname>
	@#
	@# REFS:
	@# [1]: https://pygments.org/
	@# [2]: https://pygments.org/styles/
	@#

io.preview.file=cat ${1} | ${stream.as.log}
io.preview.file/%:
	@# Outputs syntax-highlighting + line-numbers for the given filename to stderr.
	@#
	@# USAGE:
	@#  ./compose.mk io.preview.file/<fname>
	@#
	$(call log.io, io.preview.file ${sep} ${dim}${bold}${*}) \
	&& style=monokai ${make} io.preview.pygmentize/${*} \
	| ${stream.nl.enum} | ${stream.indent.to.stderr}

io.print.banner:; ${io.print.banner}
	@# Prints a divider on stdout, defaulting to the full 
	@# term-width, with optional label. If label is not set, 
	@# a timestamp will be used.  Also available as a macro.
	@#
	@# USAGE:
	@#  label=".." filler=".." width="..." ./compose.mk io.print.banner 
# io.print.banner=label="${@}" ${make} io.print.banner
define io.print.banner
	export width=$${width:-${io.terminal.cols}} \
	&& label=$${label:-${io.timestamp}} \
	&& label=$${label/./-} \
	&& if [ -z "$${label}" ]; then \
		filler=$${filler:-¯} && printf "%*s${no_ansi}\n" "$${width}" '' | sed "s/ /$${filler}/g"> /dev/stderr; \
	else \
		label=" $${label//-/ } " && default="#" \
		&& filler=$${filler:-$${default}} && label_length=$${#label} \
		&& side_length=$$(( ($${width} - $${label_length} - 2) / 2 )) \
		&& printf "\n${dim}%*s" "$${side_length}" | sed "s/ /$${filler}/g" > /dev/stderr \
		&& printf "${no_ansi_dim}${bold}${green}$${label}${no_ansi_dim}" > /dev/stderr \
		&& printf "%*s${no_ansi}\n\n" "$${side_length}" | sed "s/ /$${filler}/g" > /dev/stderr \
	; fi
endef
io.print.banner/%:; label="${*}"; ${io.print.banner}
	@# Like `io.print.banner` but accepts a label directly.
io.log=$(call log.io,${1})
io.log.part1=$(call log.part1,${GLYPH_IO} $(strip ${1}))
io.log.part2=$(call log.part2, $(strip ${1}))

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
	&& $(call log.io,  $${header} ${green}$${cmd_disp}) \
	&& header="${_GLYPH_IO} io.quiet.stderr ${sep}" \
	&& $(call log, $${header} ${dim}( Quiet output, except in case of error. ))\
	&& start=$$(date +%s) \
	&& ([ -p ${stdin} ] && cmd="${stream.stdin} | ${cmd}" || true) \
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

ifeq (${OS_NAME},Darwin)
# https://www.unix.com/man_page/osx/1/script/
io.script.tmpf=$(call io.mktemp) && script -q -r $${tmpf} sh ${dash_x_maybe} -c "${1}"
io.script=script -q sh ${dash_x_maybe} -c "${1}"
else 
# https://www.unix.com/man_page/linux/1/script/
io.script.tmpf=$(call io.mktemp) && script -qefc --return --command "${1}" $${tmpf}
io.script=script -qefc --return --command "${1}" /dev/null
io.script.trace=sh -x -c "script -qefc --return --command \"${1}\" /dev/null"
endif

io.selector/%: 
	@# Uses the given targets to generate and then handle choices.
	@# The 1st argument should be a nullary target; the 2nd must be unary.
	@#
	@# USAGE: 
	@#   ./compose.mk io.selector/<choice_generator>,<choice_handler>
	$(call io.selector, $(shell echo ${*}|cut -d, -f1),$(shell echo ${*} | cut -d, -f2-))
io.selector=choices=`${make} ${1} | ${stream.nl.to.space}` && ${io.get.choice} && ${make} ${2}/$${chosen}

io.shell.isolated=env -i TERM=$${TERM} COLORTERM=$${COLORTERM} PATH=$${PATH} HOME=$${HOME}
io.shell.iso=${io.shell.isolated}

io.stack/%:; $(call io.stack, ${*})
	@# Returns all the data in the named stack-file 
	@#
	@# USAGE:
	@#  ./compose.mk io.stack/<fname>
	@#  [ {.. data ..}, .. ]
io.stack=(${io.stack.require} && cat ${1} | ${jq.run} .)

io.stack.pop/%:
	@# Pops first item off the given stack file.  
	@# Not strict: popping an empty stack is allowed.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.pop/<fname>
	@#  {.. data ..}
	@#
	$(call log.io,  io.stack.pop ${sep} ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.pop, ${*})
io.stack.pop=(${io.stack} | ${jq.run} '.[-1]'; ${io.stack} | ${jq.run} '.[1:]' > ${1}.tmp && mv ${1}.tmp ${1})

io.stack.require=( ls ${1} >/dev/null 2>/dev/null || echo '[]' > ${1})
io.stack.push/%:
	@# Pushes new JSON data onto the named stack-file
	@#
	@# USAGE:
	@#   echo '<json>' | ./compose.mk io.stack.push/<fname>
	@#
	${trace_maybe} \
	&& $(call io.stack.require, ${*}) && $(call io.mktemp) \
	&& ([ "$${quiet:-0}" == "1" ] || $(call log.io,  io.stack.push ${sep} ${dim}stack@${no_ansi}${*} ${cyan_flow_left})) \
	&& ${stream.peek} | ${jq.run} -c . > $${tmpf} \
	&& ${jq} -n --slurpfile obj $${tmpf} --slurpfile stack ${*} '$$stack[0]+$$obj' > ${*}.tmp
	mv -f ${*}.tmp ${*}

io.string.hash=$(shell printf "${1}" | sed 's/ /_/g'|sed 's/[.]/_/g'|sed 's/\//_/g')

io.tail/%:
	@# Tails the named file.  Blocking.  Creates file first if necessary.
	@#
	@# USAGE: ./compose.mk io.tail/<fname>
	$(trace_maybe) && touch ${*} && tail -f ${*} 2>/dev/null

io.terminal.cols=$(shell which tput >/dev/null 2>/dev/null && echo `tput cols 2> /dev/null` || echo 50)

io.term.width=$(shell echo $$(( $${COLUMNS:-${io.terminal.cols}}-6)))

io.timestamp=`date '+%T'`

io.user_exit:
	@# Wait for user-input, then exit cleanly.
	@# This explicitly uses `mk.supervisor.exit`, 
	@# thus honoring `CMK_AT_EXIT_TARGETS`.
	$(call log.io, ${@} ${sep} $${label:-Waiting for user input} ${sep} ${yellow} Press enter to exit...)
	read -p "" _ignored \
	; CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${make} mk.supervisor.exit/0
io.user_exit=label="${1}" ${make} io.user_exit

io.wait io.time.wait: io.time.wait/1
	@# Pauses for 1 second.

io.wait/% io.time.wait/%:
	@# Pauses for the given amount of seconds.
	@#
	@# USAGE: ./compose.mk io.time.wait/<int>
	@#
	$(call log.io, ${@}${no_ansi} ${sep} ${dim}Waiting for ${*} seconds..) \
	&& sleep ${*}

io.with.file/%:
	@# Context manager.
	@# Creates a temp-file for the given define-block, then runs the 
	@# given (unary) target using the temp-file for an argument
	@#
	@# USAGE:
	@#   ./compose.mk io.with.file/<def_name>/<downstream_target>
	@#
	$(call io.mktemp) && def_name=$(shell echo ${*}|cut -d/ -f1) \
	&& target=$(shell echo ${*}|cut -d/ -f2-) \
	&& ${mk.def.read}/$${def_name} > $${tmpf} \
	&& CMK_INTERNAL=1 ${make} $${target}/$${tmpf}

io.with.color/%:
	@# A context manager that paints the given targets output as the given color.
	@# This outputs to stderr, and only assumes the original target-output was also on stderr.
	@#
	@# USAGE: ( colors the banner red )
	@#  ./compose.mk io.with.color/red,io.figlet/banner
	@#
	color="`echo ${*}| cut -d, -f1`" \
	&& target=`echo ${*}| cut -d, -f2-` \
	&& $(call io.mktemp) && ${make} $${target} 2>$${tmpf} \
	&& printf "$(value $(shell echo ${*}| cut -d, -f1))`cat $${tmpf}`${no_ansi}\n" >/dev/stderr

io.xargs=xargs -I% sh ${dash_x_maybe} -c
io.xargs.verbose=xargs -I% sh -x -c
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: io.* targets
## BEGIN: mk.* targets
##
## The 'mk.*' targets are meta-tooling that include various extensions to 
## `make` itself, including some support for reflection and runtime changes.
##
## A rough guide to stuff you can find here:
## 
## * `mk.supervisor.*` for signals and supervisors
## * `mk.def.*` for tools related to reading 'define' blocks
## * `mk.parse.*` for makefile parsing (used as part of generating help)
## * `mk.help.*` for help-generation
##
##-------------------------------------------------------------------------------
##
## DOCS:
## * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-mk)
## * `[2]:` [Signals & Supervisors](https:/robot-wranglers.github.io/compose.mk/signals)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# A macro to include a single define-block from another file in this file.
# (NB: for this to work, both files involved need to use `include compose.mk`)
#
# USAGE: $(eval $(call mk.include.def, def_name, path_to_makefile))
#
define mk.include.def
define ${1}
$(shell make -f ${2} mk.get/$(strip ${1}) > .tmp.$(strip ${1}))
$(file < .tmp.$(strip ${1})) $(shell rm .tmp.$(strip ${1}))
endef
endef

mk.assert.env/%:
	@# Asserts that the (comma-delimited) environment variables are set and non-empty.
	@# Also available as a macro.
	$(call mk.assert.env,$(shell echo ${*}|${stream.comma.to.space}))

mk.__main__:
	@# Runs the default goal, whatever it is.
	@# We need this for use with the supervisor because 
	@# usage of `mk.supervisor.enter/<pid>` is ALWAYS present,
	@# and that overrides default that would run with an empty CLI.
	case `echo ${MAKEFILE_LIST}|${stream.count.words}` in \
		1) case `echo ${MAKEFILE_LIST} | xargs basename` in \
				compose.mk) (\
					$(call log.trace,empty invocation for compose.mk-- returning help) \
					&& ${make} help);; \
				*) ${make} `CMK_INTERNAL=1 ${make} mk.get/.DEFAULT_GOAL`;; \
			esac ;; \
		0) $(call log, ${red}error: library list is empty);; \
		*) (\
			$(call log.trace, multiple library files; looking for a default goal..) \
			&& ${make} `${make} mk.get/.DEFAULT_GOAL`);; \
	esac

mk.def.dispatch/% polyglot.dispatch/%:
	@# Reads the given <def_name>, writes to a tmp-file,
	@# then runs the given interpreter on the tmp file.
	@# 
	@# This requires that the interpreter is actually available..
	@# for dockerized access to similar functionality, see `docker.run.def`
	@#
	@# USAGE:
	@#   ./compose.mk mk.def.dispatch/<interpreter>,<def_name>
	@#
	@# HINT: for testing, use 'make mk.def.dispatch/cat,<def_name>'
	@#
	$(call io.mktemp) \
	&& export intr=`printf "${*}"|cut -d, -f1` \
	&& export def_name=`printf "${*}" | cut -d, -f2-` \
	&& ${mk.def.to.file}/$${def_name}/$${tmpf} \
	&& [ -z $${preview:-} ] && true || ${make} io.preview.file/$${tmpf} \
	&& header="mk.def.dispatch${no_ansi}" \
	&& ([ $${TRACE} == 1 ] &&  printf "$${header} ${sep} ${dim}`pwd`${no_ansi} ${sep} ${dim}$${tmpf}${no_ansi}\n" > ${stderr} || true ) \
	&& $(call log.mk, $${header} ${sep} ${cyan}[${no_ansi}${bold}$${intr}${no_ansi}${cyan}] ${sep} ${dim}$${tmpf}) \
	&& which $${intr} > ${devnull} || exit 1 \
	&& $(trace_maybe) \
	&& src="$${intr} $${tmpf}" \
	&& [ -p ${stdin} ] && ${stream.stdin} | eval $${src} || eval $${src}
	
bind.def.to.env=export $(strip ${2})="$(shell ${make} mk.def.read/$(strip ${1}))"
mk.def.read=CMK_INTERNAL=1 ${make} mk.def.read
mk.def.read/%:
	@# Reads the named define/endef block from this makefile,
	@# emitting it to stdout. This works around normal behaviour 
	@# of completely wrecking indention/newlines and requiring 
	@# escaped dollar-signs present inside the block.  
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk mk.read_def/<name_of_define>
	@#
	$(eval def_name=${*})
	$(info $(value ${def_name}))

mk.def.to.file=${make} mk.def.to.file
mk.def.to.file/%:
	@# Reads the given define/endef block from this makefile context, 
	@# writing it to the given output file. Also available as a macro.
	@#
	@# USAGE: ( explicit filename for output )
	@#   ./compose.mk mk.def.to.file/<def_name>/<fname>
	@#
	@# USAGE: ( use <def_name> as filename )
	@#   ./compose.mk mk.def.to.file/<def_name>
	@#
	def_name=`printf "${*}" | cut -d/ -f1` \
	&& out_file=`printf "${*}" | cut -d/ -f2-` \
	&& header="${GLYPH_MK} mk.def ${sep}" \
	&& ([ ${verbose} == 1 ] && \
		$(call log, $${header} ${dim_cyan}${ital}$${def_name} ${green_flow_right} ${dim}${bold}$${out_file}) \
		|| true) \
	&& ${mk.def.read}/$${def_name} > $${out_file}
mk.ifdef=echo "${.VARIABLES}" | grep -w ${1} ${all_devnull}
mk.ifdef/%:; $(call mk.ifdef, ${*})
	@# Answers whether the given variable is defined.
	@# This is silent, and only communicates via the exit code.
	
mk.ifndef=echo "${.VARIABLES}" | grep -v -w ${1} ${all_devnull}
mk.ifndef/%:; $(call mk.ifndef,${*})
	@# Flips the assertion for 'mk.ifdef'.

mk.docker.dispatch/%:; img="compose.mk:$${img}" ${make} docker.dispatch/${*}
	@# Like `docker.run` but insists that image is "local" or internally 
	@# managed by compose.mk, i.e. using the  "compose.mk:" prefix.
	@# Also available as a macro.
mk.docker.dispatch=${make} mk.docker.dispatch

mk.docker/% mk.docker.image/%:; ${make} docker.image.run/compose.mk:${*}
	@# Like `docker.image.run`, but automatically adds the `compose.mk:` prefix.
	@# This is used with "local" images that are managed by compose.mk itself, 
	@# e.g. embedded images that are built with `Dockerfile.build/..`, etc.
mk.docker.prune:
	@# Like `docker.prune` but only covers "local" images internally 
	@# managed by compose.mk, i.e. using the  "compose.mk:" prefix.
	docker images | grep -E '^(compose.mk|composemk)' | ${stream.peek} \
	| awk '{print $$3}' | ${io.xargs} "docker rmi -f %"
	
mk.docker=${make} mk.docker
mk.docker:; ${mk.docker}/$${img}
	@# Like `mk.docker/..` but expects `img` argument is available from environment.

mk.docker.run.sh:; hostname="$${img}" img="compose.mk:$${img}" ${make} docker.run.sh
	@# Like docker.run.sh, but implicitly assumes the 'compose.mk:' prefix.

mk.get/%:; $(info ${${*}})
	@# Returns the value of the given make-variable

mk.help: mk.namespace.filter/mk.
	@# Lists only the targets available under the 'mk' namespace.

mk.help.module/%:
	@# Shows help for the named module.
	@# USAGE: ./compose.mk mk.help.module/<mod_name>
	$(call io.mktemp) && export key="${*}" \
	&& (CMK_INTERNAL=1 ${make} mk.parse.module.docs/${MAKEFILE} \
		| ${jq} ".$${key}"  2>/dev/null | ${jq} -r '.[1:-1][]' 2>/dev/null  \
	> $${tmpf}) \
	; [ -z "`cat $${tmpf}`" ] && exit 0 \
	|| ( \
		$(call log.mk, mk.help.module ${sep} ${bold}$${key}) \
		&& cat $${tmpf} | ${stream.glow} >/dev/stderr ) 

mk.help.block/%:
	@# Shows the help-block matching the given pattern.
	@# Similar to module-docs, but this need not match a target namespace.
	@#
	@# USAGE: ./compose.mk mk.help.block/<pattern>
	pattern="${*}" ${make} mk.parse.block/${MAKEFILE} | ${stream.glow} 

mk.help.target/%:
	@# Shows rendered help for the named target.
	@#
	@# USAGE: ./compose.mk mk.help.target/<target_name>
	(tmp1=".tmp.$(shell echo `basename ${MAKEFILE}`.parsed.json)" \
	&& $(call io.file.gen.maybe,$${tmp1},${make} mk.parse/${MAKEFILE}) \
	&& $(call io.mktemp) && tmp2="$${tmpf}" \
	&& key="${*}" \
	&& $(call log.mk, ${no_ansi_dim}mk.help.target ${sep} ${dim_cyan}${bold}$${key} ) \
	&& cat $${tmp1} | ${jq} -r ".[\"$${key}\"].docs[]" 2>/dev/null > $${tmp2} \
	; case $$? in \
		0) $(call log.trace, ${@} ${sep} found literal) ;; \
		*) $(call log.trace, ${@} missed literal); cat $${tmp1} | ${jq} -r ".[\"$${key}/%\"].docs[]" 2>/dev/null >$${tmp2};; \
	esac \
	; case "`cat $${tmp2} | ${stream.trim}`" in \
		"") $(call log.mk,${cyan_flow_right} ${dim_ital}No help found.);; \
	esac \
	; case $$? in \
		0) cat $${tmp2} ;; \
		*) $(call log.mk, ${cyan_flow_right} No such target was found.);; \
	esac) | ${stream.glow}

help.local:
	@# Renders help for all local targets, i.e. just the ones that do NOT come from includes.
	@# Usually used from an included makefile, not with compose.mk itself. 
	@#
	$(call log.mk, ${no_ansi_dim}${@} ${sep} ${dim}Rendering help for${no_ansi} ${bold}${underline}${MAKEFILE}${no_ansi} ${dim_ital}(no includes)\n)
	targets="`${mk.targets.local.public} | grep -v '%' | grep "$${filter:-.}"`" \
	&& width=`echo|awk "{print int(.6*${io.term.width})}"` \
	&& printf "$${targets}" | ${stream.fold} | ${stream.as.log} \
	&& printf '\n' \
	&& printf "$${targets}" \
	| xargs -I% sh ${dash_x_maybe} -c "${make} mk.help.target/%"

help.local.filter/%:; filter="${*}" ${make} help.local
	@# Like `help.local`, but filters local targets first using the given pattern.
	@# Usually used from an included makefile, not with compose.mk itself. 
	@#
	@# USAGE: 
	@#   make help.local.filter/<pattern>

mk.help.search/%:
	@# Shows all targets matching the given prefix.
	@#
	@# USAGE:
	@#   ./compose.mk mk.help.search/<pattern>
	@#
	$(call io.mktemp) \
	&& ${make} mk.parse.targets/${MAKEFILE} | grep "^${*}" \
		| sed 's/\/%/\/<arg>/g' > $${tmpf} \
	&& max=5 && count="`cat $${tmpf}|${stream.count.lines}`" \
	&& case $${count} in \
		1) exit 0; ;; \
		*) ( \
			$(call log.mk, ${no_ansi_dim}mk.help.search ${sep} ${dim}pattern=${no_ansi}${bold}${*}) \
			; cat $${tmpf} | head -$${max} \
			| xargs -I% printf "  ${dim_green}${GLYPH.tree_item} ${dim}${ital}%${no_ansi}\n" \
			| ${stream.indent} >/dev/stderr \
			&& $(call log.mk, ${no_ansi_dim}mk.help.search ${sep}${dim} top ${no_ansi}$${max}${no_ansi_dim}${comma} of ${no_ansi}$${count}${no_ansi_dim} total )\
			); ;; \
	esac

mk.kernel:
	@# Executes the input data on stdin as a kind of "script" that 
	@# runs inside the current make-context.  This basically allows
	@# you to treat targets as an instruction-set without any kind 
	@# of 'make ... ' preamble.
	@#
	@# USAGE: ( concrete )
	@#  echo flux.ok | ./compose.mk kernel
	@#  echo flux.and/flux.ok,flux.ok | ./compose.mk kernel
	@#
	instructions="`${stream.stdin} | ${stream.nl.to.space}`" \
	&& printf "$${instructions}" | ${stream.as.log} \
	&& set -x && ${make} $${instructions}


define cmk.default.sugar
[
	["⋘", "⋙", "$(call compose.import.string, def=__NAME__ import_to_root=TRUE)"],
    ["⫻",  "⫻",  "$(call dockerfile.import.string, def=__NAME__)"],
	["⟦",  "⟧",  "$(call polyglot.__import__.__AS__,__NAME__,__WITH__)"],
	["🞹",  "🞹", "$(call compose.import.code, def=__NAME__)"],
	["⨖", "⨖", "__NAME__:; $(call __AS__,__WITH__)"]
]
endef
define cmk.default.dialect
[
	["ᝏ","; cmk.bind."], ["ᝏ ","; cmk.bind."],
	["⧐", ".dispatch/"],
	["🡆", "${stream.stdin} | ${jq} -r"], 
	["🡄", "${jb}"], 
	["this.", "${make} "]
]
endef 
# mk.aliases:
# 	printf "alias mk.compile='${CMK_BIN} mk.compile'\n"

mk.compile/% mk.compiler/%:; ls ${*} && export __interpreting__=${*} && cat ${*} | (${mk.compile})
	@# Like `mk.compile`, but accepts file as argument instead of using stdin.

mk.compile mk.compiler:
	@# This is a transpiler for the CMK language -> Makefile.
	@# Accepts streaming CMK source on stdin, result on stdout.
	@# Quiet by default, pass quiet=0 to preview results from intermediate stages.
	@#
	@# USAGE:
	@#  echo "<source_code>" | ./compose.mk mk.compiler
	@#
	${mk.compile}

define mk.compile
$(call log.trace, __file__=$${__file__} \
	__interpreter__=${__interpreter__} \
	__interpreting__="$${__interpreting__:-None}" \
	__script__=$${__script__}) \
&& case $${quiet:-1} in \
	*) runner=flux.pipeline;; \
	0) runner=flux.pipeline;; \
esac \
&& ${io.mktemp} && export inputf=`echo $${tmpf}` \
&& ${stream.stdin} > $${inputf} \
&& export CMK_INTERNAL=1 \
&& printf "#!/usr/bin/env -S __interpreting__=$${__interpreting__:-stdin} ${__interpreter__} mk.interpret\nMAKEFILE_LIST+=compose.mk\n" \
&& __interpreting__=$${__interpreting__:-stdin} \
	${make} mk.src \
&& cat $${inputf} | \
	style=monokai lexer=makefile \
	${make} $${runner}/mk.preprocess,io.awk/.awk.main.preprocess,io.awk/.awk.dispatch
endef
	
mk.src: 
	@# Returns source-code for this make-context (excluding compose.mk).
	@# This effectively flattens includes, basically concatenating 
	@# MAKEFILE_LIST in reverse order, and is used internally as part 
	@# of mk.compile.  This has a different meaning if called from extensions
	@# 
	$(call mk.assert.env,__script__)
	$(call log.mk,${@} ${sep}${dim} Generating source code for context)
	printf '\n# generated from context:\n'
	${jb} \
		MAKEFILE_LIST='${MAKEFILE_LIST}' \
		MAKEFILE=${MAKEFILE} \
		make='${make}' \
		__script__='$${__script__}' \
		__file__=$${__file__} \
		__interpreter__=$${__interpreter__} \
		__interpreting__='$${__interpreting__}' \
	 | ${jq} . | awk '{print "#  " $$0}'
	src_list="$(subst ${CMK_SRC},,${MAKEFILE_LIST})" \
	&& src_list="$(strip $(shell printf "$${src_list}" | tac))" \
	&& case "$${__script__}" in \
		""|None|"${__file__}") $(call log.trace, ${@} ${sep} no separate script was found);; \
		*) ( \
				$(call log.mk, ${@} ${sep} compiling with script ${__script__}) \
				&& $(call log.mk, ${@} ${sep} ${yellow}script will be included!) \
				&& cat $${__script__} && printf '\n'; \
			) \
	esac \
	&& case "$${src_list}" in \
		"") $(call log.trace, ${@} ${sep} no other sources to include);; \
		*) $(call log.trace, ${@} ${sep} ${yellow}possible extra source to include: $${src_list});; \
	esac

# a version of (eval (call ..)) which attempts to simulate nargs.
# used internally by transpiler-- it simplifies translation to assume  
# this is always available from all interpretted contexts.
define .awk.zip.linefeeds
BEGIN { in_define = 0; continuation_line = "" }
# Check for define block start
/^define / { in_define = 1; print; next }
# Check for define block end
/^endef[ \t]*$/ { in_define = 0; print; next }
in_define == 1 {print; next}
{   if (length(continuation_line) > 0) {
        gsub(/^[ \t]+/, "", $0)
        current_line = continuation_line $0; continuation_line = ""
    } else { current_line = $0 }
    if (match(current_line, /\\$/)) {
        sub(/\\$/, "", current_line); continuation_line = current_line
    } else { print current_line }
}
END { if (length(continuation_line) > 0) { print continuation_line } }
endef
mk.preprocess: 
	@# Runs the CMK input preprocessor on stdin.
	$(call log.compiler, ${@} ${sep} starting) \
	&& $(call io.mktemp) && export inputf=`echo $${tmpf}` \
	&& ${stream.stdin} > $${inputf} \
	&& export cmk_dialect=`cat $${inputf} | ${make} .mk.parse.dialect.hint` \
	&& export cmk_sugar=`cat $${inputf} | ${make} .mk.parse.sugar.hint` \
	&& case ${CMK_COMPILER_VERBOSE} in \
		1) runner=flux.pipeline;; \
		*) runner=flux.pipeline.quiet;; \
	esac \
	&& cat $${inputf} \
	| ${make} $${runner}/mk.preprocess.minify,mk.preprocess.decorators,mk.preprocess.dialect,mk.preprocess.sugar \
	| ${stream.nl.compress} \
	&& printf '\n'

mk.preprocess.minify:
	@# Assuming stdin is makefile source, minifies it and outputs to stdout
	${stream.stdin} | grep -a -v '^#' | sed '/^[ \t]*@#.*$$/d' | ${io.awk}/.awk.zip.linefeeds
mk.preprocess/%:
	@# A version of `mk.preprocess` that accepts a file-arg.
	@#
	@# USAGE: ./compose.mk mk.preprocess/<fname>
	@#
	fname=${*} && case ${*} in -) fname=/dev/stdin;; esac \
	&& cat $${fname} | ${make} mk.preprocess
mk.preprocess.decorators: io.awk/mk.preprocess.decorators
	@# Runs the decorator-preprocessor on stdin.
	@# NB: This must come before sugar/dialects.
define mk.preprocess.decorators
{   current_line = $0
    if (current_line ~ /ᝏ/) {
        decorator_line = current_line
        while ((getline next_line) > 0) {
            stripped_line = next_line
            clean=decorator_line
            if (clean ~ /[^"]\\[ \t]*$/) { gsub(/[ \t]*\\[ \t]*$/, "", clean) }
            if (stripped_line ~ /(^#|^@#)/) {
                print decorator_line; print next_line; decorator_line = ""; break }
            else if (next_line ~ /ᝏ/) { decorator_line = clean " " next_line }
            else if (next_line ~ /^[\t ]+[^#]/) {
                print clean "; " next_line; decorator_line = ""; break
            }
            else { print clean "\n" next_line; decorator_line = ""; break }
        }
        if (decorator_line != "") { print decorator_line }
    }
    else { print current_line } }
endef
	
mk.preprocess.dialect:
	@# Runs dialect preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	$(call io.mktemp) && export hint_file=$${tmpf} \
	&& $(call log.compiler.part1, ${@}) \
	&& case $${cmk_dialect} in \
		"") ( \
			dialect=$${dialect:-cmk.default.dialect} \
			&& $(call log.compiler.part2, ${dim}using ${ital}$${dialect}) \
			&& ${mk.def.read}/$${dialect} > $${hint_file} \
			);; \
		*) ( $(call log.compiler.part2, ${dim}using dialect from file) \
			&& printf "$${cmk_dialect}" > $${hint_file} \
			&& printf "# cmk_dialect ::: $${cmk_dialect} :::\n" );; \
	esac \
	&& $(call io.mktemp) && parser_file=$${tmpf} \
	&& cat $${hint_file} \
		| ${jq} -r ".[] | \" \
		| awk -v old='\(.[0])' -v new='\(.[1])' '${.awk.preprocess.dialect}'\"" \
		> $${parser_file} \
	&& printf '\n' \
	&& ${stream.stdin} \
		| eval ${stream.stdin} `cat $${parser_file}` \
	&& printf "# finished ${@} $${cmk_dialect}"
.awk.preprocess.dialect=\
	BEGIN{block=0} /^define/{block=1} /^endef/{block=0} !block{gsub(old,new)} 1

mk.preprocess.sugar:
	@# Runs sugar-preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	$(call io.mktemp) && export hint_file=$${tmpf} \
	&& $(call log.compiler.part1, ${@}) \
	&& case $${cmk_sugar} in \
		"") ( \
			sugar=$${sugar:-cmk.default.sugar} \
			&& $(call log.compiler.part2, ${dim}using ${ital}$${sugar}) \
			&& ${mk.def.read}/$${sugar} > $${hint_file} \
			);; \
		*) ( $(call log.compiler.part2, ${dim}using sugar from file) \
			&& printf "$${cmk_sugar}" > $${hint_file} \
			&& printf "# cmk_sugar ::: $${cmk_sugar} :::\n" );; \
	esac \
	&& $(call io.mktemp) && parser_file=$${tmpf} \
	&& cat $${hint_file} \
		| ${jq} -r ".[] | \" | awk -f <(${mk.def.read}/.awk.sugar) '\(.[0])' '\(.[1])' '\(.[2])' \"" \
	> $${parser_file} \
	&& eval cat /dev/stdin `cat $${parser_file}` \
	&& printf "# finished ${@} $${cmk_sugar}"
.mk.parse.sugar.hint:
	$(call log.trace, ${@} ${sep} parsing sugar hint..) 
	(   tmp=`${stream.stdin} | awk 'NR==1 && /^#!/{next} /^#/{print} !/#/{exit}'` \
		&& tmp="$${tmp#*cmk_sugar :::}" \
		&& echo "$${tmp//:::*}" \
		| sed 's/^#//g' \
		| ${jq} -c) 2>/dev/null || true
.mk.parse.dialect.hint:
	$(call log.trace, ${@} ${sep} parsing dialect hint..) 
	$(call io.mktemp) \
	&& ${stream.stdin} \
	| awk 'NR==1 && /^#!/{next} /^#/{print} !/#/{exit}' \
	| tr -d  '#\n' | awk -F':::' '{print $$2}' > $${tmpf} \
	&& if [ -s $${tmpf} ]; \
	then ( \
		cat $${tmpf} | ${jq} -c . \
		|| ($(call log.target, ${red}failed parsing dialect hint!); exit 79)) \
	else $(call log.trace, ${@} ${sep} ${yellow}no dialect hint in file) fi

mk.include/%:
	@# Dynamic includes. Experimental stuff for reflection support.
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
	$(call mk.yield, MAKEFILE=${*} ${make} -f${*} ${mk.cli.continuation})

mk.interpret!:
	@# Like `mk.interpret`, but runs CMK preprocessing/transpilation step first. 
	@#	
	@# USAGE: 
	@#   ./compose.mk mk.interpret! <fname>
	@#	
	cli="`echo ${mk.cli.continuation} | xargs`" \
	&& rest="`echo $${cli} | cut -d' ' -f2- -s`" \
	&& $(call io.mktemp) \
	&& fname="`echo $${cli}| cut -d' ' -f1`" \
	&& $(call log.compiler, ${@} ${sep} compiling ${sep} ${dim}file=${underline}$${fname}${no_ansi}) \
	&& [ -z "$${rest}" ] && true || $(call log.compiler, ${@} ${cyan_flow_right} ${dim_ital}$${rest:-}) \
	&& export __interpreting__=$${fname} \
	&& cat $${fname} | CMK_INTERNAL=1 ${make} mk.compile > $${tmpf} \
	&& chmod +x $${tmpf} \
	&& ${trace_maybe} \
	&& $(call mk.yield, continuation=\"$${rest}\" __interpreting__=$${fname} __script__=$${__script__} ${make} mk.interpret/$${tmpf})

mk.interpret:
	@# This is similar to `mk.include`, and (simulates) changes to the `make` runtime.
	@# It is mostly intended to be used as shebang, and essentially sets up `compose.mk` 
	@# as an alternative to using `make` as an interpreter.  By opting in to this, 
	@# extensions can inherit not only `compose.mk` code, but also the signals / supervisors. 
	@#
	@# See `mk.interpret!` for a version of this that does preprocessing.
	@# See https://robot-wranglers.github.io/compose.mk/signals/ for more information.
	@#
	@# USAGE:
	@#  ./compose.mk mk.interpret path/to/Makefile <target> .. <target> 
	@#
	${trace_maybe} && tmp="${mk.cli.continuation}" \
	&& tmp=`echo $${tmp} | ${stream.lstrip}` \
	&& fname="`echo $${tmp}| cut -d' ' -f1`" \
	&& rest="`echo $${tmp}| cut -d' ' -f2- -s`" \
	&& $(call log.mk, mk.interpret ${sep} ${dim}starting interpreter ${sep} ${dim}timestamp=${yellow}${io.timestamp}) \
	&& continuation="$${rest}" __interpreting__=$${__interpreting__:-$${fname}} ${make} mk.interpret/$${fname}
	$(call mk.yield, true)
log.compiler.part1=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.part1, ${GLYPH_MK} ${1}))
log.compiler.part2=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.part2, ${1}))

mk.interpret/%:
	@# A version of `mk.interpret` that accepts file-args.
	@#
	@# USAGE: ./compose.mk mk.interpret/<fname>
	@#
	case ${*} in \
		-) fname=/dev/stdin ;;\
		*) fname="${*}" ;; \
	esac \
	&& $(call log.trace, \
		__input__=$${fname} \
		__file__=${__file__} \
		__script__=${__script__} \
		__interpreter__=${__interpreter__} \
		__interpreting__="$${__interpreting__:-None}" ) \
	&& $(call io.mktemp) \
	&& $(call log.compiler.part1, mk.interpret) \
	&& ( cat ${CMK_SRC} \
			| sed -e '$$d' | grep -a -v '^# ' \
		&& printf '\n\n\n' \
		&& cat $${fname} \
		    | grep -a -v "^include ${CMK_SRC}" \
		    | grep -a -v "^include ${__script__}" \
		 && case "${__script__}" in \
		    ""|None) $(call log.trace,${yellow}script not set);; \
		    *) printf '\n#interpretted via __script__\ninclude ${__script__}\n' ;; \
		 esac \
		 && cat ${CMK_SRC} | tail -n1 ) \
	> $${tmpf} \
	&& $(call log.compiler.part2, ${dim}deduplicated includes from ${ital}$${fname}) \
	&& $(call log.compiler.part1, checking for __main__) \
	&& cat $${tmpf} | grep '^__main__:' > /dev/null \
	; case $$? in \
		0) $(call log.compiler.part2, ok);; \
		1) $(call log.compiler.part2, missing) \
			&& printf "__main__:; echo __main__ wasnt set" >> $${tmpf} ;; \
	esac \
	&& CMK_INTERNAL=0 ${make} mk.validate/$${tmpf} \
	&& chmod +x $${tmpf} \
	&& $(call log.trace, mk.interpret ${sep} ${dim_ital}$${continuation:-(no additional arguments passed)}) \
	&& export __interpreting__=$${__interpreting__:-${*}} \
	&& __script__=${__script__} MAKEFILE=$${tmpf} \
		stdbuf -o0 -e0 $${tmpf} $${continuation:-}

mk.let/%:
	@# Dynamic target assignment.
	@# This is experimental stuff for reflection support.
	@#
	@# This is basically a hack to work around the dreaded error 
	@# that "recipes may not define targets".  It should probably 
	@# be regarded as black magic that is best avoided!  
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
	&& printf "$${src}" >  $${tmpf} ; cp $${tmpf} tmpf \
	&& $(call log.part2, ${no_ansi_dim}$${tmpf}) \
	&& cmd="${make} -f $${tmpf} $${MAKE_CLI#*mk.let/${*}}" \
	&& $(call log.target,$${cmd}) \
	&& $(call mk.yield,$${cmd})

mk.namespace.list help.namespaces:
	@# Returns only the top-level target namespaces
	@# Pipe-friendly; stdout is newline-delimited target prefixes.
	@#
	tmp="`$(call _help_gen) | cut -d. -f1 |cut -d/ -f1 | uniq | grep -v ^all$$`" \
	&& count=`printf "$${tmp}"| ${stream.count.lines}` \
	&& $(call log, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} ) \
	&& printf "$${tmp}\n" \
	&& $(call log, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} )

mk.parse/%:
	@# Parses the given Makefile, returning JSON output that describes the targets, docs, etc.
	@# This parsing is "deep", i.e. it returns docs & metadata for *included* targets as well.
	@# This uses a dockerized version of the pynchon[1] tool.
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/elo-enterprises/pynchon/
	@#
	${pynchon} parse --markdown ${*} 2>/dev/null

mk.pkg:
	@# Like `mk.self`, but includes `compose.mk` source also.
	set -x && archive="$${archive} ${CMK_SRC}" ${make} mk.self

mk.pkg/%:
	@# Packages the given make target as a single-file executable.
	@#
	@# This works by using to `makeself` to bundle/freeze/release 
	@# a self-extracting archive where we include the current Makefile, 
	@# and try to automatically include any related dependencies.
	@#
	@# To add other explicit deps to the archive, set `archive` 
	@# as a space-separated list of files or directories.
	@#
	@# USAGE:
	@#  archive="file1 file2 dir1" make -f ... mk.pkg/<target_name>
	@#
	${make} .mk.pkg/${*}

ifeq (${__interpreting__},) 
.mk.pkg/%:; cmd=${*} ${make} mk.pkg.root
mk.pkg.root:
	@# Packages the application root, or the given command if provided.
	label=$${label:-${*}} bin=$${bin:-${*}} script=make \
	script_args="${MAKE_FLAGS} -f ${MAKEFILE} $${cmd:-}" \
	${make} mk.pkg
else 
mk.pkg.root:
	@# Packages the application root, or the given command if provided.
	label=$${label:-${*}} bin=$${bin:-${*}} script=./compose.mk \
	script_args="mk.interpret! ${__interpreting__} $${cmd:-}" \
	${make} mk.pkg
.mk.pkg/%:; cmd=${*} ${make} mk.pkg.root
endif
mk.namespace.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Simple, pipe-friendly output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.namespace.filter/<namespace>
	@#
	${trace_maybe} \
	&& pattern="${*}" && pattern="$${pattern//./[.]}" \
	&& ${make} mk.parse.targets/${MAKEFILE} | grep -v ^all$$ | grep ^$${pattern}

mk.require.tool/%:; $(call _mk.require.tool, ${*})
	@# Asserts that the given tool is available in the environment.
	@# Output is only on stderr, but this shows whereabouts if it is in PATH.
	@# If not found, this exits with an error.  Also available as a macro.
# Helper for asserting that tools are available with support for error messages.
# Alias for CMK-lang: 
#  USAGE: cmk.require.tool(tool_name, Error if missing)
_mk.require.tool=$(call log.part1,${GLYPH_IO} Looking for ${1} in path); which ${1} >/dev/null && $(call log.part2,${green}${GLYPH_CHECK} ${no_ansi_dim}`which ${1}`) || ($(call log.part2,${red} missing!);$(call log.io,${no_ansi}${bold}Error:${no_ansi} $(if $(filter undefined,$(origin 2)),Install tool and retry workflow.,$(2))); exit 1)
require.tool=${_mk.require.tool}

mk.run/%:; ${io.shell.isolated} make -f ${*} 
	@# A target that runs the given makefile.
	@# This uses `make` directly and naively, NOT using the current context.

mk.select mk.select.local: mk.select/${MAKEFILE}
	@# Interactive target selection / runner for the local Makefile

mk.select/%:
	@# Interactive target-selector for the given Makefile.
	@# This uses `gum choose` for user-input.
	@#
	choices=`${make} mk.targets.simple/${*} | ${stream.nl.to.space}` \
	&& header="Choose a target:" && ${io.get.choice} \
	&& ${io.shell.isolated} bash ${dash_x_maybe} -c "make -f ${*} $${chosen}"

mk.targets/% mk.parse.shallow/%:
	@# Returns only local targets from the given file, ignoring includes.
	@# Returns a newline-delimited list of targets inside the given Makefile.
	@# Unlike `mk.parse`, this is "flat" and too naive to parse targets that come 
	@# via includes.  Targets starting with "." are considered private, and 
	@# ommitted from the return value.
	@#
	cat ${*} | awk '/^define/ { in_define = 1 } /^endef/  { in_define = 0; next } !in_define { print }' \
	| grep '^[^#[:space:]].*:' | grep -v ':=' | cut -d\\ -f1|cut -d\; -f1 \
	| grep -v '.*[=].*[:]' | grep -v '^[.]' |grep -v '\$$' | cut -d\: -f1 | ${stream.space.to.nl}

mk.targets.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Simple, pipe-friendly output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.targets.filter/<namespace>
	@#
	${trace_maybe} && pattern="${*}" && pattern="$${pattern//./[.]}" \
	&& ${make} mk.targets | grep -v ^all$$ | grep ^$${pattern}

mk.parse.block/%:
	@# Pulls out documentation blocks that match the given pattern.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.block/<makefile>
	@#
	@# EXAMPLE:
	@#   pattern='*Keybindings*' make mk.parse.block/compose.mk
	@#
	CMK_INTERNAL=1 ${make} mk.parse.module.docs/${*} \
	| ${jq.run} "to_entries | map(select(.key | test(\".*$${pattern}.*\"))) | first | .value" \
	| ${jq.run} -r '.[1:-1][]'

mk.targets mk.parse.targets mk.targets.local mk.parse.local: mk.parse.shallow/${MAKEFILE}
	@# Returns only local targets for the current Makefile, ignoring includes
	@# Output of `mk.parse.shallow/` for the current val of MAKEFILE.

mk.parse.targets/%:
	@# Parses the given Makefile, returning target-names only. Simple, pipe-friendly output. 
	@# Also available as a macro.  
	@# WARNING: Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: 
	@#   ./compose.mk mk.parse.targets/<file>
	@#
	${make} mk.parse/${*} | ${jq.run} -r '. | keys[]'
mk.parse.targets=${make} mk.parse.targets
mk.targets.local=${mk.parse.targets} | sort | uniq
mk.targets.local.public=${mk.targets.local} | grep -v '^self.' | grep -v '^[.]' | sort -V

mk.parse.module.docs/%:
	@# Parses the given Makefile, returning module-level documentation.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.module.docs/<makefile>
	@#
	${trace_maybe} && (${pynchon} parse --module-docs ${*} 2>/dev/null || echo '{}') | ${jq} . || true

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
	header="${@}${no_ansi} ${sep}${dim}" \
	&& $(call log.io, $${header} Archive for ${no_ansi}${ital}$${archive}${no_ansi_dim} will be released as ${no_ansi}${bold}./$${bin}) \
	&& (ls $${archive} >/dev/null || exit 1) \
	&& $(call io.mktempd) \
	&& cp -rf $${archive} $${tmpd} \
	; archive_dir=$${tmpd} \
	&& file_count=`find $${archive_dir}|${stream.count.lines}` \
	&& $(call log.io, $${header} Total files: ${no_ansi}$${file_count}) \
	&& $(call log.io, $${header} Entrypoint: ${no_ansi}$${script}) \
	&& cmd="--noprogress --quiet --nomd5 --nox11 --notemp $${archive_dir} $${bin} \"$${label:-archive}\" $${script} $${script_args:-}" \
	img=compose.mk:makeself entrypoint=makeself ${make} docker.run.sh
	sed -i -e 's/quiet="n"/quiet="y"/' $${bin}

mk.set/%:
	@# Setter for make variables, available as a target. 
	@# This is experimental stuff for reflection support.
	@#
	@# USAGE: ./compose.mk mk.set/<key>/<val>
	$(eval $(shell echo ${*}|cut -s -d/ -f1):=$(shell echo ${*}|cut -s -d/ -f2-))

mk.stat:
	@# Shows version-information for make itself  & compose.mk
	@#
	@# USAGE: ./compose.mk mk.stat
	$(call log, ${GLYPH_MK} mk.stat${no_ansi_dim}:) \
	&& _version=`make --version | head -1 | awk '{print $$3}'` \
	&& _hash=`cat ${CMK_BIN} | md5sum |  cut -d' ' -f1` \
	&& ${jb} make_version=$${_version} compose.mk=$${_hash}

mk.supervisor.interrupt mk.interrupt: mk.interrupt/SIGINT
	@# The default interrupt.  This is shorthand for mk.interrupt/SIGINT

# WARNING: do not use ${make} here!
mk.interrupt=CMK_INTERNAL=1 ${MAKE} -f ${MAKEFILE} mk.interrupt

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
		"") (   header="${GLYPH_MK} mk.supervisor.pid ${sep} " \
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
	@# Sends the given signal to the process-tree supervisor, then kills this process with SIGKILL.
	@#
	@# This is mostly used to short-circuit  default command-line processing
	@# so that targets can be greedy about consuming the *whole* CLI, rather than 
	@# having make try to interpret everything as additional targets.
	@#
	@# This can be used without a supervisor process wrapping 'make', 
	@# but in that case the exit status is *always* failure, and there 
	@# is *always* an error that the user has to know they should ignore.
	@#
	@# To correct for exit status/error output, you will have to have a supervisor. 
	@# See the polyglot-wrapper at the top of this file for more info, and see 
	@# the 'mk.supervisor.*' namespace for handlers invoked by that supervisor.
	@#
	case $${CMK_SUPERVISOR} in \
		0) $(call log.trace, ${red}Supervisor disabled!); exit 0; ;; \
		*) \
			header="${GLYPH_MK} mk.interrupt ${sep}" \
			&& super=`CMK_INTERNAL=1 ${make} mk.supervisor.pid||true` \
			&& case "$${super:-}" in \
				"") $(call log.trace, ${red}Could not find supervisor!); ;; \
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
	@# Argument is always supervisors PPID.  Not to be confused with 
	@# the supervisors pid; See instead 'mk.supervisor.pid'
	@# 
	$(eval export MAKE_SUPER:=${*}) \
	$(call log.trace, ${GLYPH_MK} ${@} ${sep} ${red}started pid ${no_ansi}$${MAKE_SUPER})

mk.supervisor.exit/%:
	@# Unconditionally executed by the supervisor program after main pipeline, 
	@# regardless of whether that  pipeline was successful. Argument is always 
	@# the exit-status of the main pipeline.
	@#
	header="${GLYPH_MK} mk.supervisor.exit ${sep}" \
	&& $(call log.trace, $${header} ${red} status=${*} ${sep} ${bold}pid=$${MAKE_SUPER}) \
	&& $(call log.trace, $${header} ${red} calling exit handlers: ${CMK_AT_EXIT_TARGETS}) \
	&& CMK_DISABLE_HOOKS=1 CMK_INTERNAL=0 ${make} ${CMK_AT_EXIT_TARGETS} \
	&& if [ -f .tmp.mk.super.${MAKE_SUPER} ]; then \
		( $(call log.trace, ${GLYPH_MK} ${yellow}WARNING: ${no_ansi_dim}execution was yielded from ${no_ansi}${MAKE_SUPER}${no_ansi_dim} (pidfile=${no_ansi}.tmp.mk.super.${MAKE_SUPER}${no_ansi_dim})) \
			; trap "rm -f .tmp.mk.super.${MAKE_SUPER}" EXIT \
			; exit `cat .tmp.mk.super.${MAKE_SUPER}`) \
	else exit ${*}; \
	fi
	
mk.supervisor.trap/%:
	@# Executed by the supervisor program when the given signal is trapped.
	@#
	header="${GLYPH_MK} mk.supervisor.trap ${sep}" \
	&& $(call log.trace, $${header} ${red}${*} ${sep} ${dim}Supervisor trapped signal)

mk.targets.simple/%:; ${make} mk.targets/${*} | grep -v '%$$'
	@# Returns only local targets from the given file, 
	@# excluding parametric targets, and ignoring included targets.

mk.targets.parametric:
	@# This finds only the parametric targets in the current namespace.
	@#
	@# Note that targets like 'foo/%:' are automatically converted to simply 'foo', 
	@# which makes this friendly for use with stuff like `flux.starmap`, etc.
	@#
	${make} mk.parse.local | grep '%' | sed 's/\/%//g'

mk.targets.filter.parametric/%:
	@# Filters all parametric targets by the given pattern.
	pattern="`printf ${*}|sed 's/\./[.]/g'`" \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.part1, ${GLYPH_IO} mk.targets.filter.parametric ${sep} matching \'$${pattern}\') || true) \
	&& targets="`${make} mk.targets.parametric | grep "^$${pattern}" || true`" \
	&& count=`printf "$${targets}"|${stream.count.lines}` \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.part2, ${yellow}$${count}${no_ansi_dim} total) || true ) \
	&& printf "$${targets}"
mk.reconn/%:; make --reconn -f ${*}
	@# Runs makefile in dry-run / reconn mode 

mk.validate: mk.validate//dev/stdin
	@# Validates whether the input stream is legal Makefile
mk.validate/%:
	@# Validate the given Makefile (using `make -n`)
	hdr="mk.validate ${sep} ${dim}$${label:-} ${dim_ital}${*}" \
	&& $(call log.compiler.part1, mk.validate) \
	&& err=`make -n -f ${*} 2>&1 1>/dev/null` \
	; case $$? in \
		0) $(call log.compiler.part2, ${*} ${GLYPH_CHECK});; \
		*) ( $(call log.part1,$${hdr}) \
			&& $(call log.part2, ${red}failed) \
			&& printf "$${err}" | ${stream.as.log}; exit 39);; \
	esac

mk.vars=echo "${.VARIABLES}\n" | sed 's/ /\n/g' | sort
mk.vars:; ${mk.vars}
	@# Lists all the variables known to Make, including local or 
	@# inherited env-vars, make-vars, make-defines etc. 
	@# This target is also available as a macro.

mk.vars.filter/%:; (${mk.vars} | grep ${*}) || true
	@# Filter output of `mk.vars` with the given pattern.
	@# Non-strict; no error in case of no-match.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# USAGE: $(call mk.unpack.arg, <index>, <optional_default> )
mk.unpack.arg=$(shell result=$$(printf "${*}" | cut -s -d, -f$(strip ${1})); [ -n "$$result" ] && echo "$$result" || echo "$(strip $(if $(filter undefined,$(origin 2)),,$(2)))")

# USAGE: $(call mk.unpack.args, <name1> <name2> ..)
_counter = 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
_get_word_index=$(strip \
	$(foreach n,$(_counter),$(if $(filter $(1),$(word $(n),$(2))),$(n))))
mk.unpack.args=$(foreach \
	word,$(strip $(1)),$(word)=`echo ${*}|cut -d, -f$(call _get_word_index,$(word),$(1))`)

# USAGE: $(call mk.unpack.kwargs, ${1}, name, default)
define mk.unpack.kwargs
$(eval _kwargs_value:=$$(shell \
	printf "${1}" \
	| sed -n 's/.*\b$(strip ${2})="\([^"]*\)".*/\1/p; s/.*\b$(strip ${2})='"'"'\([^'"'"']*\)'"'"'.*/\1/p; s/.*\b$(strip ${2})=\([^"'"'"' ]*\).*/\1/p' \
	| grep . || echo "$(strip $(if $(filter undefined,$(origin 3)),,${3}))"))
$(eval $(if ! $(or $(strip $(_kwargs_value)),$(filter undefined,$(origin 3)),,${3}),\
	export kwargs_$(strip ${2})=$(_kwargs_value),
	$(error `mk.unpack.kwargs` expected parameter '$(strip ${2})', extracted `$(_kwargs_value)` and no default value was provided.  Input: `$(strip ${1})`)))
endef

define _mk.unpack.kwargs
export _kwargs_value="$(shell \
	printf "${1}" \
	| sed -n 's/.*\b$(strip ${2})="\([^"]*\)".*/\1/p; s/.*\b$(strip ${2})='"'"'\([^'"'"']*\)'"'"'.*/\1/p; s/.*\b$(strip ${2})=\([^"'"'"' ]*\).*/\1/p' \
	| grep . || echo "$(strip $(if $(filter undefined,$(origin 3)),,${3}))")" \
&& $(if ! $(or $(strip $${_kwargs_value}),$(filter undefined,$(origin 3)),,${3}),\
	export $(strip ${2})="$${_kwargs_value}",false)
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define mk.yield
	header="${GLYPH_MK} mk.yield ${sep}${dim}" \
	&& yield_to="$(if $(filter undefined,$(origin 1)),true,$(1))" \
	&& $(call log.trace, $${header} Yielding to:${dim_cyan} $(call strip, $${yield_to})) \
	&& eval $${yield_to} \
	; echo $$? > .tmp.mk.super.$${MAKE_SUPER} \
	; ${mk.interrupt}
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: flux.* targets
##
## The flux.* targets describe a miniature workflow library. Combining flux with 
## container dispatch is similar in spirit to things like declarative pipelines 
## in Jenkins, but simpler, more portable, and significantly easier to use.  
##
## ----------------------------------------------------------------------------
##
## What's a workflow in this context? Shell by itself is fine for what you might
## call "process algebra", and using operators like `&&`, `||`, `|` in the grand 
## unix tradition goes a long way. And adding `make` to the mix already provides 
## DAGs.
##
## What `flux.*` targets add is *flow-control constructs* and *higher-level 
## join/loop/map* instructions over other make targets, taking inspiration from 
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
## * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-flux)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


FLUX_POLL_DELTA?=5
FLUX_STAGES=
export FLUX_STAGE?=
flux.stage.file=.flux.stage.${*}

define _flux.always
	@# NB: Used in 'flux.always' and 'flux.finally'.  For reasons related to ONESHELL,
	@# this code cannot be target-chained and to make it reusable, it needs to be embedded.
	@#
	printf "${GLYPH_FLUX} flux.always${no_ansi_dim} ${sep} registering target: ${green}${*}${no_ansi}\n" >${stderr}
	target="${*}" pid="$${PPID}" ${make} .flux.always.bg &
endef

# A constructor for (binary) partials.
# See demos/partial.mk for example usage.
__flux.partial__=$(eval $(strip ${1})/%:; ${make} $(strip ${2})/$(strip ${3}),$${*})

flux.echo/%:
	@# Simply echoes the given argument.
	@# Mostly used in testing, but also provided for completeness.. 
	@# you can think of this as the "identity function" for flux algebra.
	echo "${*}"

flux.wrap/%:
	@# Same as `flux.and` except that it accepts commas or colon-delimited args.
	@# You can use this to disambiguate targets that need to have "," reserved.
	@#
	@# This performs an 'and' operation with the named targets, equivalent to the
	@# default behaviour of `make t1 t2 .. tN`.  Mostly used as a wrapper in case
	@# targets are unary
	@#
	${make}	flux.and/`echo ${*} | sed 's/:/,/g'`

# WARNING: refactoring for xargs/flux.each here introduces 
#          subtle errors w.r.t "docker run -it".
flux.all/% flux.and/%:
	@# Performs an 'and' operation with the named comma-delimited targets.
	@# This is equivalent to the default behaviour of `make t1 t2 .. tN`.
	@# This is mostly used as a wrapper in case arguments are unary, but 
	@# also has different semantics than default `make`, which ignores 
	@# duplicate targets as already satisfied.
	@#
	@# USAGE:
	@#   ./compose.mk flux.and/<t1>,<t2>
	@#
	@# See also 'flux.or'.
	@#
	$(call io.mktemp) \
	&& echo "${*}" \
	| ${stream.comma.to.nl} \
	| xargs -I% echo "${make} %" > $${tmpf} \
	&& bash ${dash_x_maybe} $${tmpf}

flux.apply/%:
	@# Applies the given target to the given argument, comma-delimited.
	@# In case no argument is given, we assume target is nullary.
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk flux.apply/<target>,<arg>
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk flux.apply/<target>
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk make flux.apply/flux.echo,THUNK
	@#
	${trace_maybe} \
	&& export target="`printf ${*}|cut -d, -f1`" \
	&& export arg="`printf ${*}|cut -s -d, -f2-`" \
	&& case $${arg} in \
		"") ${make} $${target}; ;; \
		*) ${make} $${target}/$${arg} ; ;; \
	esac

flux.apply.later/% flux.delay/%:
	@# Applies the given (unary) target at some point in the future.  This is non-blocking.
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
	@# Not pipe-safe since targets run in the background, this can garble your display!
	@#
	@# USAGE:
	@#   cmd="..." ./compose.mk flux.apply.later.sh/<seconds>
	@#
	header="${@} ${sep} ${dim_green}$${target} ${sep}" \
	&& time=`printf ${*}| cut -d/ -f1` \
	&& ([ -z "$${quiet:-}" ] && true || $(call log.flux, ${@} ${sep} after ${yellow}$${time}s)) \
	&& ( \
		$(call log.flux, $${header} ${dim_cyan}callback scheduled for ${yellow}$${time}s) \
		&& ${make} io.wait/$${time} \
		&& $(call log.flux, $${header} ${dim}callback triggered after ${yellow}$${time}s) && $${cmd:-true} \
	)&

flux.column/%:; delim=':' ${make} flux.pipeline/${*}
	@# Exactly flux.pipeline, but splits targets on colons.

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
	&& _then="`printf "${*}" | cut -s -d, -f1`" \
	&& _if="`printf "${*}" | cut -s -d, -f2-`" \
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

flux.pipe.fork=${make} flux.pipe.fork
flux.pipe.fork flux.split:
	@# Demultiplex / fan-out operator that sends stdin to each of the named targets in parallel.
	@# This is like `flux.sh.tee` but works with make-target names instead of shell commands.
	@# Also available as a macro.
	@#
	@# USAGE: (pipes the same input to target1 and target2)
	@#   echo {} | targets="jq,jq" ./compose.mk flux.pipe.fork 
	@#
	cmds="`printf $${targets} \
		| ${stream.comma.to.nl} \
		| xargs -I% echo ${make} % \
		| ${stream.nl.to.comma}`" \
	${make} flux.sh.tee

flux.pipe.fork/%:; ${stream.stdin} | targets="${*}" ${make} flux.pipe.fork
	@# Same as flux.pipe.fork, but accepts arguments directly (no variable)
	@# Stream-usage is required (this blocks waiting on stdin).
	@#
	@# USAGE: ( pipes the same input to yq and jq )
	@#   echo hello-world | ./compose.mk flux.pipe.fork/stream.echo,stream.echo

flux.each/%:
	@# Similar to `flux.for.each`, but accepts input on a pipe. 
	@# This maps the newline/space separated input on to the named (unary) target.
	@# This works via xargs, runs sequentially, and fails fast.  Also 
	@# available as a macro.  The named target MUST be parametric so it
	@# can accept the argument that is passed through!
	@#
	@# USAGE:
	@#
	@#  printf 'one\ntwo' | ./compose.mk flux.each/flux.echo
	@#
	${stream.stdin} | ${stream.space.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "${make} ${*}/% || exit 255"
flux.each=${make} flux.each

flux.fail:
	@# Alias for 'exit 1', which is POSIX failure.
	@# This is mostly for used for testing other pipelines.
	@#
	@# See also the `flux.ok` target.
	@#
	$(call log.flux, flux.fail ${sep} ${red}failing${no_ansi} as requested!)  \
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
	( \
		while kill -0 $${pid} 2> ${devnull}; do sleep 1; done \
		&& 	$(call log.flux, flux.always${no_ansi_dim} ${sep} main process finished. dispatching ${green}$${target}) \
		&& ${make} $${target} \
	) &

flux.help:; ${make} mk.namespace.filter/flux.
	@# Lists only the targets available under the 'flux' namespace.

flux.if.then/%:
	@# Runs the 2nd given target iff the 1st one is successful.
	@#
	@# Failure (non-zero exit) for the "if" check is not distinguished
	@# from a crash, & it will not propagate.  Only the 2nd argument may contain 
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
	&& $(call log.part1, ${GLYPH_FLUX} flux.${bold.underline}if${no_ansi}${dim_green}.then ${sep}${dim} ${ital}$${_if}${no_ansi} ) \
	&& case $${quiet:-1} in \
		1) ${make} $${_if} 2>/dev/null; st=$$?; ;; \
		*) ${make} $${_if}; st=$$?; ;; \
	esac \
	&& case $${st} in \
		0) ($(call log.part2, ${dim_green}true${no_ansi_dim}) \
			; $(call log, ${GLYPH_FLUX} flux.if.${bold.underline}then${no_ansi} ${sep} ${dim_ital}$${_then} ${cyan_flow_right}); ${make} $${_then}); ;; \
		*) $(call log.part2, ${yellow}false${no_ansi_dim}); ;; \
	esac

flux.stream.obliviate/%:; $(call _sh, ${make} ${*})
	@# Runs the given target, consigning all output to oblivion
_sh.obliviate=${1} 2>/dev/null > /dev/null
flux.if.then.else/%:
	@# Standard if/then/else control flow, for make targets.
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk flux.if.then.else/<test_target>,<then_target>,<else_target>
	@#
	_if=`printf "${*}"|cut -s -d, -f1` \
	&& _then=`printf "${*}"|cut -s -d, -f2` \
	&& _else=`printf "${*}"|cut -s -d, -f3-` \
	&& header="${GLYPH_FLUX} flux.if.then.else ${sep}${dim} testing ${dim_ital}$${_if} " \
	&& $(call log.part1, $${header}) \
	&& ${make} $${_if} 2>&1 > /dev/null \
	; case $${?} in \
		0) $(call log.part2, ${dim_green}true${no_ansi_dim} - dispatching ${dim_cyan}$${_then}) ; ${make} $${_then};; \
		*) $(call log.part2, ${yellow}false${no_ansi_dim} - dispatching ${dim_cyan}$${_else}); ${make} $${_else};; \
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
	$(call log.flux,  flux.loop${no_ansi_dim} ${sep} ${green}$${target}${no_ansi} ($${times}x))
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
	header="flux.loopf${no_ansi_dim}" \
	&& header+=" ${sep} ${green}${*}${no_ansi}" \
	&& interval=$${interval:-1} \
	&& ([ -z "$${quiet:-}" ] \
		&& tmp="`\
			[ -z "$${clear:-}" ] \
			&& true \
			|| echo ", clearing screen between runs" \
		   `" \
		&& $(call log.flux, $${header} ${dim}( looping forever at ${yellow}$${interval}s${no_ansi_dim} interval$${tmp})) || true ) \
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
	&& start_time=$$(date +%s%N) \
	&& $(call log, $${header} (until success)) \
	&& ${make} ${*} 2>/dev/null || (sleep $${interval:-1}; ${make} flux.loop.until/${*}) \
	&& end_time=$$(date +%s%N) \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& delta=$$(awk -v ns="$$time_diff_ns" 'BEGIN {printf "%.9f", ns / 1000000000}') \
	&& $(call log, $${header} ${no_ansi_dim}(succeeded after ${no_ansi}${yellow}$${delta}s${no_ansi_dim}))

flux.loop.watch/%:
	@# Loops the given target forever, using `watch` instead of the while-loop default.
	@# This requires `watch` is actually available.
	watch --interval $${interval:-2} --color ${make} ${*}

flux.map/% flux.for.each/%:
	@# Like `flux.each`, but accepts input as an argument.
	@#
	@# USAGE:
	@#   flux.for.each/flux.echo,hello,world 
	@#   flux.map/flux.echo,hello,world 
	@#
	${io.mktemp} \
	&& printf "${*}" | cut -d, -f2- \
	| ${stream.comma.to.nl} \
	| xargs -I% echo "${make} `printf "${*}" | cut -d, -f1`/%" \
	> $${tmpf} \
	&& bash ${dash_x_maybe} $${tmpf}
	
flux.or/% flux.any/%:
	@# Performs an 'or' operation with the named comma-delimited targets.
	@# This is equivalent to 'make target1 || .. || make targetN'.  See also 'flux.and'.
	@#
	@# USAGE: (generic)
	@#   ./compose.mk flux.or/<t1>,<t2>,..
	@#
	@# USAGE: (example)
	@#   ./compose.mk flux.or/flux.fail,flux.ok
	@#
	echo "${*}" | sed 's/,/\n/g' \
	| xargs -I% echo "|| ${make} %" | xargs | sed 's/^||//' \
	| bash ${dash_x_maybe}

flux.parallel/%:
	@# Runs the named targets in parallel, using  builtin support for concurrency.
	@#
	@# Similar to `flux.join` but using `make --jobs`, this is fundamentally much more
	@# tricky to handle than `flux.join`, but also in some ways will allow for 
	@# finer-grained control.  It probably does not work the way you think, because
	@# concurrency may affect *more* than the top level targets that are named as 
	@# arguments.  See [1] for more documentation about that.
	@#
	@# See the `flux.join` docs for some hints about running concurrently but safely 
	@# producing structured output.  Major caveat: input streams [2] probably cannot be 
	@# easily or safely used with `flux.parallel`. 
	@#
	@# REFS: 
	@#  [1] https://www.gnu.org/software/make/manual/html_node/Parallel-Disable.html
	@#  [2] https://www.gnu.org/software/make/manual/html_node/Parallel-Input.html
	@#
	targets="`echo ${*} | ${stream.comma.to.space}`" \
	&& $(call log.flux, flux.parallel ${sep} ${cyan} $${targets}) \
	&& ${trace_maybe} \
	&& ${make} --jobs $${jobs:-2} $${targets} \
		2> >(grep -v "resetting jobserver mode" \
			|grep -v "warning: jobserver unavailable")

flux.pipeline/: flux.noop
	@# No-op.  This just bottoms out the recursion on `flux.pipeline`.
flux.pipeline/%:
	@# Runs the given comma-delimited targets in a bash-style command pipeline.
	@# Besides working with targets and allowing for DAG composition, this has 
	@# the advantage of giving visibility to the intermediate results.
	@#
	@# There are several caveats though: all targets *must* be pipe safe on stdout, 
	@# and downstream targets must consume stdin.  Note also that this does not use
	@# pure streams, and tmp files are created as part of an attempt to debuffer and 
	@# avoid reordering stderr output.  Error handling is also probably not great!
	@#
	@# USAGE: (example)
	@#   ./compose.mk flux.pipeline/extract,transform,load
	@#    => roughly equivalent to `make extract | make transform | make load`
	$(trace_maybe) \
	&& $(call io.mktemp) && outputf=$${tmpf}\
	&& quiet=$${quiet:-1} && delim=$${delim:-,} \
	&& targets="${*}" \
	&& export opipe="$${opipe:-${*}}" \
	&& hdr="flux.pipeline ${sep} " \
	&& hdr2="$${hdr}${dim}$${opipe} ${sep}" \
	&& hlabel="${bold_green}$${first} ${no_ansi_dim}stage" \
	&& first=`echo "$${targets}" | cut -d$${delim} -f1` \
	&& rest=`echo "$${targets}" | cut -s -d$${delim} -f2-`  \
	&& case $${quiet} in \
		0) $(call log.flux, $${hdr2} ${bold_green}$${first} ${no_ansi_dim}stage);; \
	esac \
	&& ${make} $${first} >> $${outputf} 2> >(tee /dev/null >&2) \
	&& if [ -z "$${rest:-}" ]; \
		then ( \
			case $${quiet:-} in \
				1) cat $${outputf};; \
				*) ${.flux.pipeline.preview};; \
			esac ); \
		else ( \
			case $${quiet:-} in \
				1) true;; \
				*) ${.flux.pipeline.preview};; \
			esac \
			; cat $${outputf} | ${make} flux.pipeline/$${rest}); fi
.flux.pipeline.preview=(\
	$(call log.flux, $${hdr} ${bold_green}$${first} ${no_ansi_dim}stage ${sep} ${underline}result preview${no_ansi}) \
				; cat $${outputf} | CMK_INTERNAL=1 quiet=1 ${make} stream.pygmentize \
				; printf '\n'>/dev/stderr)

flux.pipeline.quiet/%:; quiet=1 ${make} flux.pipeline/${*}
flux.pipeline.verbose/%:; quiet=0 verbose=1 ${make} flux.pipeline/${*}

flux.mux flux.join:
	@# Similar to `flux.parallel`, but actually uses processes directly.  
	@# See instead that implementation for finer-grained control.
	@#
	@# Runs the given comma-delimited targets in parallel, then waits for all of them to finish.
	@# For stdout and stderr, this is a many-to-one mashup of whatever writes first, and nothing
	@# about output ordering is guaranteed.  This works by creating a small script, displaying it,
	@# and then running it.  It is not very sophisticated!  The script just tracks pids of
	@# launched processes, then waits on all pids.
	@#
	@# If the named targets are all well-behaved, this *might* be pipe-safe, but in
	@# general it is possible for the subprocess output to be out of order.  If you do
	@# want *legible, structured output* that *prints* in ways that are concurrency-safe,
	@# here is a hint: emit nothing, or emit minified JSON output with printf and 'jq -c',
	@# and there is a good chance you can consume it.  Printf should be atomic on most
	@# platforms with JSON of practical size? And crucially, 'jq .' handles object input,
	@# empty input, and streamed objects with no wrapper (i.e. '{}<newline>{}').
	@#
	@# EXAMPLE: (runs 2 commands in parallel)
	@#   targets="io.time.wait/1,io.time.wait/3" ./compose.mk flux.mux | jq .
	@#
	$(call log.flux, ${@} ${sep} ${dim}$(shell echo $${targets//,/ ; }))
	$(call io.mktemp) && \
	mcmds=`printf $${targets} \
	| ${stream.comma.to.nl} \
	| xargs -I% printf '${make} % & pids+=\"$$! \"\n' \
	` \
	&& (printf 'pids=""\n' \
		&& printf "$${mcmds}\n" \
		&& printf 'wait $${pids}\n') > $${tmpf} \
	&& $(call log.flux, ${@} ${sep} script ${cyan_flow_right} ) \
	&& cat $${tmpf} | ${stream.as.log} \
	&& bash ${dash_x_maybe} $${tmpf}

flux.mux/% flux.join%:; targets="${*}" ${make} flux.mux
	@# Like `flux.join` but accepts arguments directly.

flux.negate/%:; ! ${make} ${*}
	@# Negates the status for the given target.
	@#
	@# USAGE: 
	@#   `./compose.mk flux.negate/flux.fail`

flux.noop:; exit 0
	@# NO-OP mostly used for testing.  
	@# Similar to 'flux.ok', but this does not include logging.
	@#
	@# USAGE:	
	@#  ./compose.mk flux.noop

flux.ok:
	@# Alias for 'exit 0', which is success.
	@# This is mostly for used for testing other pipelines.  
	@#
	@# See also `flux.fail`
	@#
	$(call log.flux, ${@} ${sep} ${no_ansi}succeeding as requested!) \
	&& exit 0

flux.split/%:
	@# Alias for flux.split, but accepts arguments directly
	export targets="${*}" && make flux.split

flux.sh.tee:
	@# Helper for constructing a parallel process pipeline with `tee` and command substitution.
	@# Pipe-friendly, this works directly with stdin.  This exists mostly to enable `flux.pipe.fork`
	@# but it can be used directly.
	@#
	@# Using this is easier than the alternative pure-shell version for simple commands, but it is
	@# also pretty naive, and splits commands on commas; probably better to avoid loading other
	@# pipelines as individual commands with this approach.
	@#
	@# USAGE: ( pipes the same input to 'jq' and 'yq' commands )
	@#   echo {} | cmds="jq,yq" ./compose.mk flux.sh.tee 
	@#
	src="`\
		echo $${cmds} \
		| tr ',' '\n' \
		| xargs -I% \
			printf  ">($${tee_pre:-}%$${tee_post:-}) "`" \
	&& cmd="${stream.stdin} | tee $${src} " \
	&& count=$(shell echo $${cmds} | ${stream.comma.to.nl} | ${stream.count.lines}) \
	&& $(call log.flux, ${@} ${sep}${dim} starting pipe (${no_ansi}${bold}$${count}${no_ansi_dim} components)) \
	&& $(call log.flux, ${no_ansi_dim}flux.sh.tee${no_ansi} ${sep} ${no_ansi_dim}$${cmd}) \
	&& eval $${cmd}

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
	&& header="flux.retry ${sep} ${dim_cyan}${underline}$${target}${no_ansi} (${yellow}$${times}x${no_ansi}) ${sep}" \
	&& $(call log.flux, $${header}  ${dim_green}starting..) \
	&& ( r=$${times};\
		 while ! (\
			${make} $${target} \
			|| ( $(call log.flux, $${header} (${no_ansi}${yellow}failed.${no_ansi_dim} waiting ${dim_green}${FLUX_POLL_DELTA}s${no_ansi_dim})) \
				; exit 1) \
		); do ((--r)) || exit; sleep $${interval:-${FLUX_POLL_DELTA}}; done)

.flux.eval.symbol/%:
	@# This is a very dirty trick and mainly for internal use.
	@# This accepts a symbol to expand, then runs the expansion
	@# as a script. You can also provide an optional post-execution 
	@# script, which will run inside the same context.  This exists 
	@# because in some rare cases that are related to subshells and ttys,
	@# normal target-composition will not work.  See `flux.select.*` targets.
	@#
	@# USAGE: (Runs the file-chooser widget)
	@#   dir=. ./compose.mk .flux.eval.symbol/io.file.select
	@#
	$(call log.trace, ${@})
	${trace_maybe} && eval "`${make} mk.get/${*}` && $${script:-true}"
	
flux.select.file/%:
	@# Opens an interactive file-selector using the given dir, 
	@# then treats user-choice as a parameter to be passed into
	@# the given target.  
	@#
	@# You can use this to build layered interactions, getting new 
	@# input at each stage.  See example usage below which first
	@# chooses a file from `demos/` folder, then uses `mk.select` 
	@# to choose a target
	@#
	@# USAGE: 
	@#   pattern='*.mk' dir=demos/ ./compose.mk flux.select.file/mk.select
	@#
	${trace_maybe} \
	&& $(call log.io, ${GLYPH_IO} ${@}) \
	&& export selector=io.file.select \
	&& export dir="$${dir:-.}" && export target="${*}" \
	&& $(call log.trace, choice from ${dim_ital}$${dir} ${yellow}->${no_ansi_dim} target=${dim_cyan}$${target}) \
	&& ${make} flux.select.and.dispatch

flux.select.and.dispatch:
	@#
	@# USAGE: 
	@#   pattern='*.mk' dir=demos/ ./compose.mk flux.select.and.dispatch
	@#
	$(call log.flux, $${selector} ${sep} $${target}) \
	&& script="${make} $${target}/\$${chosen}" \
	${make} .flux.eval.symbol/$${selector}

flux.stage: mk.get/FLUX_STAGE
	@# Returns the name of the current stage. No Arguments.

flux.stage.clean/%:
	@# Cleans only stage files that belong to the given stage.
	@#
	@# USAGE: 
	@#   ./compose.mk flux.stage.clean/<stage_name>
	@#
	header="flux.stage.clean ${sep} ${bold}${underline}${*}${no_ansi} ${sep}" \
	&& $(call log.flux, $${header} ${dim}removing stack file @ ${dim_cyan}${flux.stage.file}) \
	&& rm -f ${flux.stage.file} 2>/dev/null || $(call log, $${header} ${yellow} could not remove stack file!)

flux.stage.enter/% flux.stage/% stage/%:
	@# Declares entry for the given stage.
	@# Stage names are generally target names or similar, no spaces allowed.
	@#
	@# Calling this target prints a pretty divider that makes output easier 
	@# to parse, but stages also add an idea of persistence to our otherwise 
	@# pretty stateless workflows, via a file-backed JSON stack object that 
	@# cooperating tasks can *push/pop* from.
	@#
	@# By default we draw a banner with `io.draw.banner`, but you can override 
	@# with e.g. `target_banner=io.figlet`, etc.
	@#
	@# USAGE:
	@#  ./compose.mk flux.stage.enter/<stage_name>
	@# 
	stagef="${flux.stage.file}" \
	&& header="flux.stage ${sep} ${bold}${underline}${*}${no_ansi} ${sep}" \
	&& (label="${*}" CMK_INTERNAL=1 ${make} $${banner_target:-io.draw.banner}) \
	&& true $(eval export FLUX_STAGE=${*}) $(eval export FLUX_STAGES+=${*}) \
	&& $(call log.flux, $${header}${dim} stack file @ ${dim_ital}$${stagef}) \
	&& ${jb} stage.entered="`date`" | ${make} flux.stage.push/${*}

flux.stage.exit/%:; ${make} flux.stage.stack/${*} flux.stage.clean/${*}
	@# Declares exit for the given stage.
	@# Calling this is optional but if you do not, stack-files will not be deleted!
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.exit/<stage_name>

flux.stage.file/%:; echo "${flux.stage.file}"
	@# Returns the name of the current stage file.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.file/<stage_name>

flux.stage.clean:; rm -f .flux.stage.*
	@# Cleans all stage-files from all runs, including ones that do not belong to this pid!
	@# No arguments.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage./

flux.stage.stack/%:; ${make} io.stack/${flux.stage.file}
	@# Returns the entire stack given a stack name
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage./

flux.stage.push/%: 
	@# Push the JSON data on stdin into the stack for the named stage.
	@#
	@# USAGE:
	@#   echo '<json_data>' | ./compose.mk flux.stage.push/<stage_name>
	@#
	header="flux.stage.push ${sep} ${bold}${underline}${*}${no_ansi}" \
	&& test -p ${stdin}; st=$$?; case $${st} in \
		0) ${stream.stdin} | ${make} io.stack.push/${flux.stage.file}; ;; \
		*) $(call log.flux, $${header} ${sep} ${red}Failed pushing data${no_ansi} because no data is present on stdin); ;; \
	esac

flux.stage.push:
	@# Push the JSON data on stdin into the stack for the implied stage 
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.push
	@#
	${stream.stdin} | ${make} flux.stage.push/${FLUX_STAGE}

flux.stage.pop/%:
	@# Pops the stack for the named stage.  
	@# Caller should handle empty value, this will not throw an error.
	@#
	@# USAGE:
	@#   ./compose.mk flux.stage.pop/<stage_name>
	@#   {"key":"val"}
	@#
	$(call log.flux,  flux.stage.pop ${sep} ${*}) 
	${make} io.stack.pop/${flux.stage.file}

flux.stage.stack:
	@# Dumps JSON for all the data on the current stack-file.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.stack/
	@#
	$(call log.flux,  flux.stage.stack ${sep} ) 
	$(call io.stack, ${flux.stage.file})
flux.stage.stack=$(call io.stack, ${flux.stage.file})

flux.stage.wrap:
	@# Like `flux.stage.wrap/<stage>/<target>`, but taking args from env
	@#
	${make} \
		flux.stage.enter/$${stage} \
		$${target} flux.stage.exit/$${stage} 

flux.stage.wrap/%:
	@# Context-manager that wraps the given target with stage-enter 
	@# and stage-exit.  It only accepts one stage at a time, but can
	@# easily be combined with `flux.wrap` for multiplem targets.
	@# 
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.wrap/<stage>/<target>
	@#
	@# USAGE: ( concrete )
	@#  ./compose.mk flux.stage.wrap/MAIN/flux.ok
	@#
	export stage="`echo "${*}"| cut -d/ -f1`" \
	&& header="flux.stage.wrap ${sep}${dim_cyan} $${stage} ${sep}" \
	&& export target="`echo "${*}"| cut -d/ -f2-`" \
	&& $(call log.trace, $${header} ${dim_ital}$${target}) \
	&& (printf "$${target}" | grep "," > /dev/null) \
		&& ( \
			export target="flux.and/$${target}" && ${make} flux.stage.wrap  ) \
		|| (${make} flux.stage.wrap ) 

flux.star/% flux.match/%:
	@# Runs all targets in the local namespace matching given pattern
	@# 
	@# USAGE: (run all the test targets)
	@#   make -f project.mk flux.star/test.
	@# 
	matches="`${make} mk.namespace.filter/${*}|${stream.nl.to.space}`" \
	&& count=`printf "$${matches}"|${stream.count.words}` \
	&& $(call log.target, ${bold}$${count}${no_ansi_dim} matches for pattern ${dim_cyan}${*}) \
	&& printf "$${matches}" | ${stream.fold} | sed 's/ /, /g' | ${stream.as.log} \
	&& printf "$${matches}" | ${make} flux.each/flux.apply

flux.starmap/%:
	@# Based on itertools.starmap from python, 
	@# this accepts 2 targets called the "function" and the "iterable".
	@# The iterable is nullary, and the function is unary.  The "function"
	@# target will be called once for each result of the "iterable" target.
	@# Iterable *must* return newline-separated data, usually one word per line!
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.starmap/<fn>,<iterable>
	@#
	target="`printf ${*}|cut -d, -f1`" \
	&& iterable="`printf ${*}|cut -d, -f2-`" \
	&& ${make} $${iterable} | ${make} flux.each/$${target}

flux.timer/%:
	@# Emits run time for the given make-target in seconds.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timer/<target_to_run>
	@#
	${trace_maybe} && start_time=$$(date +%s) \
	&& ${make} ${*} \
	&& end_time=$$(date +%s) \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& delta=$$(awk -v ns="$$time_diff_ns" 'BEGIN {printf "%.9f", ns }') \
	&& $(call log.flux, flux.timer ${sep} `echo ${*}|cut -d/ -f2-` ${sep} ${dim}$${label:-done in} ${yellow}$${delta}s)

flux.timeout/%:
	@# Runs the given target for the given number of seconds, then stops it with TERM.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timeout/<seconds>/<target>
	@#
	timeout=`printf ${*} | cut -d/ -f1` \
	&& target=`printf ${*} | cut -d/ -f2-` \
	timeout=$${timeout} cmd="${make} $${target}" ${make} flux.timeout.sh

flux.timeout.sh:
	@# Runs the given command for the given amount of seconds, then stops it with TERM.
	@# Exit status is ignored
	@#
	@# USAGE: (tails docker logs for up to 10s, then stops)
	@#   ./compose.mk flux.timeout.sh cmd='docker logs -f xxxx' timeout=10
	@#
	@# FIXME: use timeout(1) ?
	timeout=$${timeout:-5} \
	&& $(call log.io, flux.timeout.sh${no_ansi_dim} (${yellow}$${timeout}s${no_ansi_dim}) ${sep} ${no_ansi_dim}$${cmd}) \
	&& $(trace_maybe) \
	&& trap "set -x && echo bye" EXIT INT TERM \
	&& signal=$${signal:-TERM} \
	&& eval "$${cmd}" 2> >(grep -v Terminated$$ > /dev/stderr) \
	&& export command_pid=$$! \
	&& sleep $${timeout} \
	&& $(call log.flux, flux.timeout.sh${no_ansi_dim} (${yellow}$${timeout}s${no_ansi_dim}) ${sep} ${no_ansi}${yellow}finished) \
	&& trap '' EXIT INT TERM \
	&& kill -$${signal} `ps -o pid --no-headers --ppid $${command_pid}` 2>/dev/null || true

flux.with.ctx/% flux.context_manager/%:
	@# Runs the given target, using the given namespace as a context-manager
	@#
	@# USAGE: 
	@#  ./compose.mk flux.ctx/<target>,<ctx_name>
	@#
	@# Roughly equivalent to `compose.mk <ctx_name>.enter <target> <ctx_name>.exit`
	@#
	target=$(call mk.unpack.arg,1) \
	&& manager=$(call mk.unpack.arg,2) \
	&& man_args=$(call mk.unpack.arg,3) \
	&& enter=$${manager}.enter \
	&& exit=$${manager}.exit \
	&& case $${man_args} in \
		"") true;; \
		*) enter+="/$${man_args}"; exit+="/$${man_args}";; \
	esac \
	&& $(call log.trace, flux.context_manager ${sep} enter=${dim}$${enter} ${sep} exit=${dim}$${exit} ${sep} target=${dim}$${target}) \
	&& ${trace_maybe} \
	&& ${make} $${enter} flux.try.finally/$${target},$${exit}

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
	&& header="flux.try.except.finally ${sep}" \
	&& $(call log.flux, $${header} ${underline}${cyan}try${no_ansi_dim} ${sep} $${try}) \
	&& ${make} $${try} && exit_status=0 || exit_status=1 \
	&& case $${exit_status} in \
		0) true; ;; \
		1) $(call log.flux, $${header} ${underline}${cyan}except${no_ansi_dim} ${sep} $${except}) && ${make} $${except} && exit_status=0 || (echo 'keeping 1'; exit_status=1); ;; \
	esac \
	&& $(call log.flux, $${header} ${underline}${cyan}finally${no_ansi_dim} ${sep} $${finally}) && ${make} $${finally} \
	&& exit $${exit_status}
flux.try.except/%:
	@# Performs a try/except operation with the named targets.
	@# This is just `flux.try.except.finally` where `finally` is `flux.noop`.
	@#
	@# USAGE: (generic)
	@#  ./compose.mk flux.try.except/<try_target>,<except_target>
	@#
	$(call mk.unpack.args, _try _except) \
	&& ${make} flux.try.except.finally/$${_try},$${_except},flux.noop
flux.try.finally/%:
	@# Performs a try/finally operation with the named targets.
	@# This is just `flux.try.except.finally` where `except` is `flux.noop`.
	@#
	@# USAGE: (generic)
	@#  ./compose.mk flux.try.finally/<try_target>,<finally_target>
	@#
	${make} flux.try.except.finally/$(call mk.unpack.arg,1),flux.noop,$(call mk.unpack.arg,2)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: flux.* targets
## BEGIN: stream.* targets
##
## The `stream.*` targets support IO streams, including basic stuff with JSON,
## newline-delimited, and space-delimited formats.
##
## **General purpose tools:**
##
## * For conversion, see `stream.nl.to.comma`, `stream.comma.to.nl`, etc.
## * For JSON ops, see `stream.jb`[2] and `stream.json.append.*`, etc
## * For formatting and printing, see `stream.dim.*`, etc.
##
## ----------------------------------------------------------------------------
##
## **Macro Equivalents:**
##
## Most targets here are also available as macros, which can be used 
#  as an optimization since it saves a process.  
## 
## ```bash 
##   # For example, from a makefile, these are equivalent commands:
##   echo "one,two,three" | ${stream.comma.to.nl}
##   echo "one,two,three" | make stream.comma.to.nl
## ```
## ----------------------------------------------------------------------------
## DOCS:
##   * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/docs/api#api-stream)
##   * `[2]:` [Docs for jb](https://github.com/h4l/json.bash)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

stream.as.grepE = ${stream.nl.to.space} | sed 's/ /|/g'

# WARNING: without the tr, osx `wc -w` injects tabbed junk at the beginning of the result!
stream.count.words=wc -w | tr -d '[:space:]'
stream.count.lines=wc -l | tr -d '[:space:]'

stream.stderr.iff.failed=2> >(stderr=$$(cat); exit_code=$$?; if [ $$exit_code -ne 0 ]; then echo "$$stderr" >&2; fi; exit $$exit_code)
stream.as.log=( ${stream.dim.indent} > ${stderr}; printf "\n" >/dev/stderr)

stream.stdin=cat /dev/stdin
stream.obliviate=${all_devnull}
stream.trim=awk 'NF {if (first) print ""; first=0; print} END {if (first) print ""}'| awk '{if (NR > 1) printf "%s\n", p; p = $$0} END {printf "%s", p}'

stream.as.log:; ${stream.as.log}
	@# A dimmed, indented version of the input stream sent to stderr.
	@# See `stream.indent` for a version that works with stdout.
	@# Note that this consumes the input stream.. see instead 
	@# `stream.peek` for a version with pass-through.
	
stream.fold:; ${stream.fold}
	@# Uses fold(1) to wrap the input stream to the given width, 
	@# defaulting to current terminal width if nothing is provided.
	@# Also available as a macro.
stream.fold=${stream.nl.to.space} | fold -s -w $${width:-${io.term.width}}

stream.code: io.preview.file//dev/stdin
	@# A version of `io.preview.file` that works with streaming input.
	@# Uses pygments on the backend; pass style=.. lexer=.. to override.

stream.jb= ( ${jb.docker} `${stream.stdin}` )
stream.jb:; ${stream.jb}
	@# Interface to jb[1].  You can use this to build JSON on the fly.
	@# Also available as macro.
	@#
	@# USAGE:
	@#   $ echo foo=bar | ./compose.mk stream.jb
	@#   {"foo":"bar"}
	@#
	@# REFS:
	@#   `[1]:` https://github.com/h4l/json.bash
	
stream.glow:=${glow.run}
stream.markdown:=${glow.run} 
stream.glow stream.markdown:; ${stream.glow} 
	@# Renders markdown from stdin to stdout.

stream.to.docker=${make} stream.to.docker
stream.to.docker/%:
	@# This is a work-around because some interpreters require files and can not work with streams.
	@#
	@# USAGE: ( generic )
	@#   echo ..code.. | ./compose.mk stream.to.docker/<img>,<optional_entrypoint>
	@#
	@# USAGE: ( generic, as macro )
	@#   ${mk.def.read}/<def_name> | ${stream.to.docker}/<img>,<optional_entrypoint>
	@#
	$(call io.mktemp) && ${stream.stdin} > $${tmpf} \
		&& cmd="$${cmd:-} $${tmpf}" ${make} docker.image.run/${*}

stream.lstrip=( ${stream.stdin} | sed 's/^[ \t]*//' )
stream.lstrip:; ${stream.lstrip}
	@# Left-strips the input stream.  Also available as a macro.
	
stream.strip:
	@# Pipe-friendly helper for stripping whitespace.
	@#
	${stream.stdin} | awk '{gsub(/[\t\n]/, ""); gsub(/ +/, " "); print}' ORS=''

stream.ini.pygmentize:; ${stream.stdin} | CMK_INTERNAL=1 lexer=ini ${make} stream.pygmentize
	@# Highlights input stream using the 'ini' lexer.

stream.csv.pygmentize=${make} stream.csv.pygmentize
stream.csv.pygmentize:
	@# Highlights the input stream as if it were a CSV.  Pygments actually
	@# does not have a CSV lexer, so we have to fake it with an awk script.  
	@#
	@# USAGE: ( concrete )
	@#   echo one,two | ./compose.mk stream.csv.pygmentize
	@#
	${stream.stdin} | awk 'BEGIN{FS=",";H="\033[1;36m";E="\033[0;32m";O="\033[0;33m";N="\033[0;35m";S="\033[2;37m";R="\033[0m";r=0}{r++;l="";c=(r==1)?H:(r%2==0)?E:O;for(i=1;i<=NF;i++){gsub(/^[ \t]+|[ \t]+$$/,"",$$i);f=($$i~/^[0-9]+(\.[0-9]+)?$$/)?N:S;l=l c f $$i R;if(i<NF)l=l c "," R}print l}'

stream.dim.indent=( ${stream.stdin} | ${stream.dim} | ${stream.indent} )
stream.dim.indent:; ${stream.dim.indent}
	@# Like 'io.print.indent' except it also dims the text.

stream.help: mk.namespace.filter/stream.
	@# Lists only the targets available under the 'stream' namespace.
stream.nl.to.space=xargs
stream.nl.to.space:; ${stream.nl.to.space}
	@# Converts newline-delimited input stream to space-delimited output.
	@# Also available as a macro.
	@#
	@# USAGE: 
	@#   $ echo '\nfoo\nbar' | ./compose.mk stream.nl.to.space
	@#   > foo bar

stream.comma.to.nl=( ${stream.stdin} | sed 's/,/\n/g')
stream.comma.to.nl:; ${stream.comma.to.nl}
	@# Converts comma-delimited input stream to newline-delimited output.
	@# Also available as a macro.
	@#
	@# USAGE: 
	@#   > echo 'foo,bar' | ./compose.mk stream.comma.to.nl
	@#   foo
	@#   bar

stream.comma.to.space=( ${stream.stdin} | sed 's/,/ /g')
stream.comma.to.space:; ${stream.comma.to.space}
	@# Converts comma-delimited input stream to space-delimited output

stream.comma.to.json:
	@# Converts comma-delimited input into minimized JSON array
	@#
	@# USAGE:
	@#   > echo 1,2,3 | ./compose.mk stream.comma.to.json
	@#   ["1","2","3"]
	@#
	${stream.stdin} | ${stream.comma.to.nl} | ${make} stream.nl.to.json.array

stream.dim=printf "${dim}`${stream.stdin}`${no_ansi}"
stream.dim:; ${stream.dim}
	@# Pipe-friendly helper for dimming the input text.  
	@#
	@# USAGE:
	@#   $ echo "logging info" | ./compose.mk stream.dim

stream.echo:; ${stream.stdin}
	@# Just echoes the input stream.  Mostly used for testing.  See also `flux.echo`.
	@# 
	@# EXAMPLE:
	@#   echo hello-world | ./compose.mk stream.echo

# Extremely secure, for keeping hunter2 out of the public eye
stream.grep.safe=grep -iv password | grep -iv passwd

# Run image previews differently for best results in github actions. 
# See also: https://github.com/hpjansson/chafa/issues/260
stream.img=${stream.stdin} \
	| docker run -i --entrypoint chafa compose.mk:tux `[ "$${GITHUB_ACTIONS:-false}" = "true" ] \
	&& echo "--size 100x -c full --fg-only --invert --symbols dot,quad,braille,diagonal" \
	|| echo "--center on"` /dev/stdin

# Converts multiple sequential newlines to just one.
stream.nl.compress=awk -v RS='\0' '{ gsub(/\n{2,}/, "\n"); printf "%s", $$0 RS }'

stream.chafa=${stream.img}
stream.img stream.chafa stream.img.preview: tux.require
	@# Given an image file on stdin, this shows a preview on the console. 
	@# Under the hood, this works using a dockerized version of `chafa`.
	@#
	@# USAGE: ( generic )
	@#   > cat docs/img/docker.png | ./compose.mk stream.img.preview
	@#
	${stream.img}

stream.indent=( ${stream.stdin} | sed 's/^/  /' )
stream.indent:; ${stream.indent}
	@# Indents the input stream to stdout.  Also available as a macro.
	@# For a version that works with stderr, see `stream.as.log`

stream.json.array.append:; ${stream.stdin} | ${jq} "[.[],\"$${val}\"]"
	@# Appends <val> to input array
	@#
	@# USAGE:
	@#   > echo "[]" | val=1 ./compose.mk stream.json.array.append | val=2 make stream.json.array.append
	@#   [1,2]

stream.json.object.append stream.json.append:
	@# Appends the given key/val to the input object.
	@# This is usually used to build JSON objects from scratch.
	@#
	@# USAGE:
	@#	 > echo {} | key=foo val=bar ./compose.mk stream.json.object.append
	@#   {"foo":"bar"}
	@#
	${stream.stdin} | ${jq} ". + {\"$${key}\": \"$${val}\"}"

define Dockerfile.stream.pygmentize
FROM ${IMG_ALPINE_BASE:-alpine:3.21.2}
RUN apk add -q --update py3-pygments
endef
stream.pygmentize=CMK_INTERNAL=1 ${make} stream.pygmentize 
stream.pygmentize: Dockerfile.build/stream.pygmentize
	@# Syntax highlighting for the input stream.
	@# Lexer will be autodetected unless override is provided.
	@# Style defaults to 'monokai', which works best with dark backgrounds.
	@# Also available as a macro.
	@#
	@# USAGE: (using JSON lexer)
	@#   > echo {} | lexer=json ./compose.mk stream.pygmentize
	@#
	@# REFS:
	@# [1]: https://pygments.org/
	@# [2]: https://pygments.org/styles/
	@#
	lexer=`[ -z $${lexer:-} ] && echo '-g' || echo -l $${lexer}` \
	&& style="-Ostyle=$${style:-monokai}" \
	&& src="entrypoint=pygmentize" \
	&& src="$${src} cmd=\"$${style} $${lexer} -f terminal256 $${fname:-}\"" \
	&& CMK_INTERNAL=1 src="$${src} img=${@} ${make} mk.docker.run.sh" \
	&& ([ -p ${stdin} ] && ${stream.stdin} | eval $${src} || eval $${src}) >/dev/stderr

stream.json.pygmentize:; lexer=json ${make} stream.pygmentize
	@# Syntax highlighting for the JSON on stdin.

stream.indent.to.stderr=( ${stream.stdin} | ${stream.indent} | ${stream.to.stderr} )
stream.indent.to.stderr:; ${stream.indent.to.stderr}
	@# Shortcut for ' .. | stream.indent | stream.to.stderr'

stream.peek=( \
	( $(call io.mktemp) && ${stream.stdin} > $${tmpf} \
		&& cat $${tmpf} | ${stream.as.log} \
		| ${stream.trim} && cat $${tmpf}); )
stream.peek:; ${stream.peek}
	@# Prints the entire input stream as indented/dimmed text on stderr,
	@# Then passes-through the entire stream to stdout.  Note that this uses
	@# a tmpfile because proc-substition seems to disorder output.
	@#
	@# USAGE:
	@#   echo hello-world | ./compose.mk stream.peek | cat
	@#
stream.peek.maybe=( [ "${TRACE}" == "0" ] && ${stream.stdin} || ${stream.peek} )
stream.peek.40=( $(call io.mktemp) && ${stream.stdin} > $${tmpf} && cat $${tmpf} | fmt -w 35 | ${stream.as.log} && cat $${tmpf} )

# WARNING: long options will not work with OSX
stream.nl.enum=( ${stream.stdin} | nl -v0 -n ln )
stream.nl.enum:; ${stream.nl.enum}
	@# Enumerates the newline-delimited input stream, zipping index with values
	@#
	@# USAGE:
	@#   > printf "one\ntwo" | ./compose.mk stream.nl.enum
	@# 		0	one
	@# 		1	two

stream.nl.to.comma=( ${stream.stdin} | awk 'BEGIN{ORS=","} {print}' | sed 's/,$$//' )
stream.nl.to.comma:; ${stream.nl.to.comma}

stream.nl.to.json.array:; ${stream.stdin} | ${jq} -s '.'
	@#  Converts newline-delimited input stream into a JSON array
	
stream.space.enum:; ${stream.stdin} | ${stream.space.to.nl} | ${stream.nl.enum}
	@# Enumerates the space-delimited input list, 
	@# zipping indexes with values in newline delimited output.
	@#
	@# USAGE: 
	@#   printf one two | ./compose.mk stream.space.enum
	@#      0	one
	@#      1	two
	
stream.space.to.comma=(${stream.stdin} | sed 's/ /,/g')

stream.space.to.nl=xargs -n1 echo
stream.space.to.nl:; ${stream.space.to.nl}
	@# Converts a space-separated stream to a newline-separated one

stream.to.stderr=( ${stream.stdin} > ${stderr} )
stream.to.stderr stream.preview:; ${stream.to.stderr}
	@# Sends input stream to stderr.
	@# Unlike 'stream.peek', this does not pass on the input stream.

stream.yaml.pygmentize=lexer=yaml ${make} stream.pygmentize
stream.yaml.to.json=${yq} -o json
stream.yaml.to.json:; ${stream.yaml.to.json}
	@# Converts yaml to JSON
stream.makefile.pygmentize=lexer=makefile ${make} stream.pygmentize

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: tux.* targets
##
## The *`tux.*`* targets allow for creation, configuration and automation of an embedded TUI interface.  This works by sending commands to a (dockerized) version of tmux.  See also the public/private sections of the tux API[1], the general docs for the TUI[2], or the spec for the 'compose.mk:tux' container for more details.
## 
## ----------------------------------------------------------------------------
##
## DOCS:
##   * `[1]`: [API](https://github.com/robot-wranglers/compose.mk/api#api-tux)
##   * `[2]`: [Embedded TUI](https://github.com/robot-wranglers/compose.mk/embedded-tui)
##
## ----------------------------------------------------------------------------
##
## BEGIN: TUI Environment Variables
## ```
## | Variable Name        | Description                                                                  |
## | -------------------- | ---------------------------------------------------------------------------- |
## | TUI_BOOTSTRAP        | *Target-name that is used to bootstrap the TUI.  *                           |
## | TUX_BOOTSTRAPPED     | *Contexts for which the TUI has already been bootstrapped.*                  |
## | TUI_SVC_NAME         | *The name of the primary TUI svc.*                                           |
## | TUI_THEME_NAME       | *The name of the theme.*                                                     |
## | TUI_TMUX_SOCKET      | *The path to the tmux socket.*                                               |
## | TUI_THEME_HOOK_PRE   | *Target called when init is in progress but the core layout is finished*     |
## | TUI_THEME_HOOK_POST  | *Name of the post-theme hook to call.  This is required for buttons.*        |
## ```
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

# WARNING: MacOS docker requires volume-from-config here, 
# but this breaks linux.  might be different for rancher desktop, etc
ifeq (${OS_NAME},Darwin)
export TUI_TMUX_SOCKET?=/socket/dir/tmux.sock
else 
export TUI_TMUX_SOCKET?=tmux.sock
endif

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

tux.browser: .tux.browser.require
	@# Launches carbonyl browser in a docker container.
	@# See also: https://github.com/fathyb/carbonyl/blob/main/Dockerfile
	@#
	${trace_maybe} && tty=1 entrypoint=/carbonyl/carbonyl \
	cmd="--no-sandbox --disable-dev-shm-usage --user-data-dir=/carbonyl/data $${url}" \
	net=$${net:-host} ${make} docker.image.run/${IMG_CARBONYL}
.tux.browser.require:; docker pull ${IMG_CARBONYL} >/dev/null

tui.demo tux.demo:
	@# Demonstrates the TUI.  This opens a 4-pane layout and blasts them with tte[1].
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/ChrisBuilds/terminaltexteffects
	@#
	$(call log.tux, tui.demo ${sep} ${dim}Starting demo) \
	&& layout=spiral ${make} tux.open/.tte/${CMK_SRC},.tte/${CMK_SRC},.tte/${CMK_SRC},.tte/${CMK_SRC}

tux.pane/%:
	@# Sends the given make-target into the given pane.
	@# This is a public interface & safe to call from the docker-host.
	@#
	@# USAGE:
	@#   ./compose.mk tux.pane/<int>/<target>
	@#
	pane_id=`printf "${*}"|cut -d/ -f1` \
	&& target=`printf "${*}"|cut -d/ -f2-` \
	&& ${make} tux.dispatch/tui/.tux.pane/${*}

# Possible optimization: this command is *usually* but not 
# always called from  `MAKELEVEL<3` and above that it is 
# probably cached already?
tux.require: ${CMK_COMPOSE_FILE} compose.validate.quiet/${CMK_COMPOSE_FILE}
	@# Require the embedded-TUI stack to finish bootstrap.  This is time-consuming, 
	@# so it should be called strategically and only when needed.  Note that this might 
	@# be required for things like 'gum' and for anything that depends on 'dind_base', 
	@# so strictly speaking it is not just for TUIs.  
	@#
	@# This tries to take advantage of caching, but each service 
	@# in `TUI_SVC_BUILD_ORDER` needs to be visited, and even that is slow.
	@# 
	case $${force:-0} in \
		1) ${make} tux.purge;; \
	esac \
	&& header="${GLYPH_TUI} tux.require ${sep}" \
 	&& $(call log.trace, $${header} ${dim}Ensuring TUI containers are ready: "${TUI_SVC_BUILD_ORDER}") \
	&& (true \
		&& ([ -z "$${TUX_BOOTSTRAPPED:-}" ] || $(call log, $${header}${red}bootstrapped already); exit 0) \
		&& (local_images=`${docker.images} | xargs` \
			&& $(call log.trace.fmt, $${header} ${dim}local-images ${sep}, ${dim}$${local_images}) \
			&& items=`printf "${TUI_SVC_BUILD_ORDER}" | ${stream.comma.to.space}` \
			&& count=`printf "$${items}"|${stream.count.words}` \
			&& $(call log.trace.loop.top, $${header} ${yellow}$${count}${no_ansi_dim} items) \
			&& for item in $${items}; do \
				($(call log.trace.loop.item, ${dim}$${item}) \
				&& printf "$${local_images}" | grep -w $${item} > /dev/null \
					|| ( \
						$(call log.tux, ${@} ${no_ansi_dim}Container ${no_ansi}${bold}$${item}${no_ansi}${no_ansi_dim} not cached yet.${no_ansi}${bold} Building..) \
						&& quiet=$${quiet:-1} svc=$${item} ${make} compose.build/${TUI_COMPOSE_FILE}) \
			); done \
			&& exit 0 ) \
		)

tux.purge:
	@# Force removal of the base containers for the TUI.
	$(call log.flux, ${@} ${sep}${no_ansi_dim} Purging the TUI base images..)
	printf ${TUI_SVC_BUILD_ORDER} | ${stream.comma.to.nl} | xargs -I% docker rmi -f compose.mk:%
	# docker rmi -f compose.mk:tux && docker rmi -f compose.mk:dind_base

tux.open/%: tux.require
	@# Opens the given comma-separated targets in tmux panes.
	@# This requires at least two targets, and defaults to a spiral layout.
	@#
	@# USAGE:
	@#   layout=horizontal ./compose.mk tux.open/flux.ok,flux.ok
	@#
	orient=$${layout:-spiral} \
	&& targets="${*}" \
	&& count="`printf "$${targets},"|${stream.comma.to.space}|${stream.count.words}`" \
	&& $(call log.tux, tux.open ${sep} ${dim}layout=${bold}$${orient}${no_ansi_dim} pane_count=${bold}$${count}) \
	&& $(call log.tux, tux.open ${sep} ${dim}targets=$${targets}) \
	&& TUX_LAYOUT_CALLBACK=tux.layout.$${orient}/$${targets} ${make} tux.mux.count/$${count}

tux.open.service_shells/%:
	@# Treats the comma-separated input arguments as if they are service-names, 
	@# then opens shells for each of those services in individual TUI panes.
	@# 
	@# This assumes the compose-file has already been imported, either by 
	@# use of `compose.import` or by use of `loadf`.  It also assumes the 
	@# `<svc>.shell` target actually works, and this might not be true if 
	@# the container does not ship with bash!
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk tux.open.service_shells/alpine,debian,ubuntu
	@#
	targets=`echo "${*}"|${stream.comma.to.nl}|xargs -I% echo %.shell | ${stream.nl.to.comma}` \
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
	&& pane_targets=".tux.layout.$${layout} .tux.geo.set $${pane_targets}" \
	&& layout="flux.and/$${pane_targets}" \
	&& layout=`echo $$layout|${stream.space.to.comma}` \
	&& $(call log.trace, tux.callback ${sep} ${no_ansi_dim}Generated layout callback:\n  $${layout}) \
	&& ${make} $${layout}

tux.layout.horizontal/%:; layout=horizontal ${make} tux.callback/${*}
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>

tux.layout.spiral/%:; layout=spiral ${make} tux.callback/${*}
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>

tux.layout.vertical/%:; layout=vertical ${make} tux.callback/${*}
	@# Runs a spiral-layout callback for the given targets, automatically assigning them to panes
	@#
	@# USAGE: 
	@#   tux.spiral/<callback>

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
	
tux.help:; ${make} mk.namespace.filter/tux.
	@# Lists only the targets available under the 'tux' namespace.

tux.mux/%:
	@# Maps execution for each of the comma-delimited targets
	@# into separate panes of a tmux (actually 'tmuxp') session.
	@#
	@# USAGE:
	@#   ./compose.mk tux.mux/<target1>,<target2>
	@#
	$(call log.tux, tux.mux ${sep} ${bold}${*})
	targets=$(shell printf ${*}| sed 's/,$$//') \
	&& export reattach=".tux.attach" \
	&& $(trace_maybe) && ${make} tux.mux.detach/$${targets}

.tux.attach:;  
	@# Thin wrapper on `tmux attach`.
	@#
	label='Reattaching TUI' ${make} io.print.banner
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
	&& header="tux.mux.detach ${sep}${no_ansi_dim}" \
	&& $(call log.tux, $${header} ${bold}${*}) \
	&& $(call log.tux, $${header} reattach=${dim_red}$${reattach}) \
	&& $(call log.tux, $${header} TUI_SVC_NAME=${dim_green}$${TUI_SVC_NAME}) \
	&& $(call log.tux, $${header} TUI_INIT_CALLBACK=${dim_green}$${TUI_INIT_CALLBACK}) \
	&& $(call log.tux, $${header} TUX_LAYOUT_CALLBACK=${dim_green}$${TUX_LAYOUT_CALLBACK}) \
	&& $(call log.part1, ${GLYPH_TUI} $${header} Generating pane-data) \
	&& export panes=$(strip $(shell ${make} .tux.panes/${*})) \
	&& $(call log.part2, ${dim_green}ok) \
	&& $(call log.part1, ${GLYPH_TUI} $${header} Generating tmuxp profile) \
	&& eval "$${_TUI_TMUXP_PROFILE_DATA_}" > $${TMUXP}  \
	&& $(call log.part2, ${dim_green}ok) \
	&& cmd="${trace_maybe}" \
	&& cmd="$${cmd} && tmuxp load -d -S ${TUI_TMUX_SOCKET} $${TMUXP}" \
	&& cmd="$${cmd} && TMUX=${TMUX} tmux list-sessions" \
	&& cmd="$${cmd} && label='TUI Init' ${make} io.print.banner $${TUI_INIT_CALLBACK}" \
	&& cmd="$${cmd} && label='TUI Layout' ${make} io.print.banner $${TUX_LAYOUT_CALLBACK}" \
	&& cmd="$${cmd} && ${make} $${reattach}" \
	&& trap "${docker.compose} -f ${TUI_COMPOSE_FILE} stop -t 1" exit \
	&& $(call log.tux, $${header} Enter main loop for TUI) \
	&& ${docker.compose} -f ${TUI_COMPOSE_FILE} \
		$${COMPOSE_EXTRA_ARGS} run --rm --remove-orphans \
		${docker.env.standard} \
		-e TUI_TMUX_SOCKET="${TUI_TMUX_SOCKET}" \
		-e TUI_TMUX_SESSION_NAME="${TUI_TMUX_SESSION_NAME}" \
		-e TUI_INIT_CALLBACK="$${TUI_INIT_CALLBACK}" \
		-e TUX_LAYOUT_CALLBACK="$${TUX_LAYOUT_CALLBACK}" \
		-e TUI_SVC_STARTED=1 \
		-e geometry=$${geometry:-} \
		-e reattach="$${reattach}" \
		-e k8s_commander_targets="$${k8s_commander_targets:-}" \
		-e tux_commander_targets="$${tux_commander_targets:-}" \
		--entrypoint bash $${TUI_SVC_NAME} ${dash_x_maybe} -c "$${cmd}" $(_compose_quiet) \
	; st=$$? \
	&& case $${st} in \
		0) $(call log.tux, ${dim_cyan}exiting TUI); ;; \
		*) $(call log.tux, ${red}TUI failed with code $${st} ); ;; \
	esac

tux.mux.svc/% tux.mux.count/%:
	@# Starts N panes inside a tmux (actually 'tmuxp') session.
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
	$(call log.tux, tux.mux.count ${sep}${dim} Starting ${bold}${*}${no_ansi_dim} panes..)
	case ${*} in \
		''|*[!0-9]*) \
			targets=`echo $(strip $(shell printf ${*}|sed 's/,/\n/g' | xargs -I% printf '%.shell,'))| sed 's/,$$//'` \
			; ;; \
		*) \
			targets=`seq ${*} | xargs -I% printf "io.shell,"` \
			; ;; \
	esac \
	&& ${trace_maybe} \
	&& ${make} tux.mux/$(strip $${targets})
	
tux.pane/%:; ${make} tux.dispatch/.tux.pane/${*}
	@# Remote control for the TUI, from the host, running the given target.
	@#
	@# USAGE:
	@#   ./compose.mk tux.pane/1/<target_name>

tux.panic:
	@# Non-graceful stops for the TUI plus any affiliated containers.
	@#
	@# USAGE:
	@#  ./compose.mk tui.panic
	$(call log.tux, tux.panic ${sep}${dim} Stopping all TUI sessions)
	${make} tux.ps | xargs -I% bash -x "id=% ${make} docker.stop" | ${stream.dim.indent}

tux.ps:
	@# Lists ID's for containers related to the TUI.
	@#
	@# USAGE:
	@#  ./compose.mk tux.ps
	$(call log.tux, tux.ps ${sep} $${TUI_CONTAINER_IMAGE} ${sep} ${dim} Looking for TUI containers)
	docker ps | grep compose.mk:tux | awk '{print $$1}'

tux.shell: tux.require
	@# Opens an interactive shell for the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.shell
	${trace_maybe} \
	&& ${docker.compose} -f ${TUI_COMPOSE_FILE} \
		$${COMPOSE_EXTRA_ARGS} run --rm --remove-orphans \
		--entrypoint bash $${TUI_SVC_NAME} ${dash_x_maybe} -i $(_compose_quiet)

tux.shell.pipe: tux.require
	@# A pipe into the shell for the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.shell
	${trace_maybe} \
	&& ${docker.compose} -f ${TUI_COMPOSE_FILE} \
		$${COMPOSE_EXTRA_ARGS} run -T --rm --remove-orphans \
		--entrypoint bash $${TUI_SVC_NAME} ${dash_x_maybe} -c "`${stream.stdin}`" $(_compose_quiet)

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
	$(call log.tux, ${@} ${sep} ${dim}Initializing TUI)
	$(trace_maybe) \
	&& ${make} .tux.init.panes .tux.init.bind_keys .tux.theme || exit 16
	$(call log.tux, ${@} ${sep} ${dim}Setting pane labels ${TMUX})
	tmux set -g pane-border-style fg=green \
	&& tmux set -g pane-active-border-style "bg=black fg=lightgreen" \
	&& index=0 \
	&& cat .tmp.tmuxp.yml | yq -r .windows[].panes[].name | ${stream.peek} \
	| while read item; do \
		$(call log.tux, ${@} ${sep} ${dim}Setting pane labels ${TMUX} $${item})\
		; tmux select-pane -t $${index} -T " ┅ $${item} " \
		; ((index++)); \
	done || $(call log.tux, ${@} ${sep} ${red}failed setting pane labels)
	tmux set -g pane-border-format "#{pane_index} #{pane_title}" || $(call log.tux, ${@} ${sep} ${red}failed setting pane labels)
	$(call log.tux, ${@} ${sep} ${dim}Done initializing TUI)
.tux.init.bind_keys:
	@# Private helper for .tux.init.
	@# This binds default keys for pane resizing, etc.
	@# See also: xmonad defaults[1] 
	@#
	@# [1]: https://gist.github.com/c33k/1ecde9be24959f1c738d
	@#
	@#
	$(call log.tux, ${@} ${sep} ${dim}Binding keys)
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
# 	$(call log.tux, ${@} ${sep}${dim} Initializing Panes) \
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
	$(call log.tux, ${@} ${sep}${dim} Initializing Panes) \
	&& ${trace_maybe} && tmux set -g base-index 0 \
	&& tmux setw -g pane-base-index 0 \
	&& tmux set -g pane-border-status top \
	&& ${make} .tux.pane.focus/0 || $(call log.tux, ${@} ${sep}${dim} ${red}Failed initializing panes)

.tux.init.buttons:
	@# Generates tmux-script that configures the buttons for "New Pane" and "Exit".
	@# This is not called directly, but is generally used as the post-theme setup hook.
	@# See also 'TUI_THEME_HOOK_POST'
	@#
	wscf=`${mk.def.read}/_tux.theme.buttons | xargs -I% printf "$(strip %)"` \
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
	$(call log.tux, ${@} ${sep} ${dim}Initializing status-bar)
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
	$(call log.tux, ${@} ${sep} ${dim}Initializing theme)
	setter="tmux set -goq" \
	&& ($${setter} @powerline-color-main-1 colour2 \
		&& $${setter} @powerline-color-main-2 colour2 \
		&& $${setter} @powerline-color-main-3 colour65 \
		&& $${setter} @powerline-color-black-1 colour233 \
		&& $${setter} @powerline-color-grey-1 colour233 \
		&& $${setter} @powerline-color-grey-2 colour235 \
		&& $${setter} @powerline-color-grey-3 colour238 \
		&& $${setter} @powerline-color-grey-4 colour240 \
		&& $${setter} @powerline-color-grey-5 colour243 \
		&& $${setter} @powerline-color-grey-6 colour245 \
		&& $(call log.tux, ${green} theme ok)) \
	|| $(call log.tux, ${red} theme failed)

.tux.layout.vertical:; tmux select-layout even-horizontal
	@# Alias for the vertical layout.
	@# See '.tux.dwindle' docs for more info
	
.tux.layout.horizontal .tux.layout.h:; tmux select-layout even-vertical
	@# Alias for the horizontal layout.
	
.tux.layout.spiral: .tux.dwindle/s
	@# Alias for the dwindle spiral layout.
	@# See '.tux.dwindle' docs for more info

.tux.layout/% .tux.layout.dwindle/% .tux.dwindle/%:; tmux-layout-dwindle ${*}
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
	
.tux.layout.shuffle:
	@# Shuffles the pane layout randomly
	@#
	$(call log.tux, ${@} ${sep} shuffling layout )
	tmp=`printf "h tlvc v h trvc h blvc brvc tlvs trvs brvs v blvs h tlhc v trhc blhc brhc tlhs trhs blhs brhs" | tr ' ' '\n' | shuf -n 1` \
	&& $(call log.tux, tux.layout.shuffle ${sep} shuffling to new layout: $${tmp}) \
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
	case "$${geometry:-}" in \
		"") $(call log.trace,${GLYPH_TUI} ${@} ${sep} ${dim}No geometry provided) ;; \
		*) ( \
			$(call log.part1, ${GLYPH_TUI} ${@} ${sep} ${dim}Setting geometry) \
			&& tmux select-layout "$${geometry}" \
			; case $$? in \
				0) $(call log.part2, ${dim}ok); ;; \
				*) $(call log.part2, ${red}error setting geometry); ;; \
			esac );; \
	esac 

.tux.msg:; tmux display-message "$${msg:-?}"
	@# Flashes a message on the tmux UI.

.tux.pane.focus/%:
	@# Focuses the given pane.  This always assumes we're using the first tmux window.
	@#
	@# USAGE: (focuses pane #1)
	@#  ./compose.mk .tux.pane.focus/1
	@#
	$(call log.tux, ${@} ${sep} ${dim}Focusing pane ${*})
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
	) | ${jq} -s -c | echo \'$$(${stream.stdin})\' | ${stream.peek.maybe}

.tux.quit .tux.panic:
	@# Closes the entire session, from inside the session.  No arguments.
	@# This is used by the 'Exit' button in the main status-bar.
	@# See also 'tux.panic', which can be used from the docker host, and which stops *all* sessions.
	@#
	$(call log.tux, ${@} ${sep} killing session)
	tmux kill-session

.tux.theme:
	@# Setup for the TUI's tmux theme.
	@#
	@# This does nothing directly, and just honors the environment settings
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
	@# in case the full text will not fit in the space available. Like most TUI widgets,
	@# this loops forever, but unlike most it is pure bash, no ncurses/tmux reqs.
	@#
	@# USAGE:
	@#   text=mytext ./compose.mk tux.widget.ticker
	@#
	label="$${label:-no ticker text}" \
	&& while true; do \
		for (( i=0; i<$${#label}; i++ )); do \
			echo -ne "\r$${label:i}$${label:0:i}" \
			&& sleep $${delta:-0.2}; \
		done; \
	done

.tux.widget.img.rotate/%:; url=${*} ${make} .tux.widget.img.rotate
	@# Like `.tux.widget.img.rotate`, but using parameters, not environment
.tux.widget.img.rotate:
	@# Like `.tux.widget.img`, but sets up a rotating version of the image.
	display_target=.tux.img.rotate ${make} .tux.widget.img

.tux.widget.img/%:; url="${*}" ${make} .tux.widget.img
	@# Like `.tux.widget.img`, but using parameters, not environment
.tux.widget.img:
	@# Displays the given image URL or file-path forever, as a TUI widget.
	@# This functionality requires a loop, otherwise chafa will not notice or adapt
	@# to any screen or pane resizing.  In case of a URL, it is downloaded
	@# only once at startup.
	@#
	@# USAGE:
	@#   url=... ./compose.mk .tux.widget.img
	@#   path=... ./compose.mk .tux.widget.img
	@#
	@# Besides supporting proper URLs, this works with file-paths.
	@# The path of course needs to exist and should actually point at an image.
	@#
	url="$${path:-$${url:-${ICON_DOCKER}}}" \
	&& case $${url} in \
		http*) \
			export suffix=.png \
			&&  $(call io.get.url,$${url:-"${ICON_DOCKER}"}) \
			&& fname=$${tmpf}; ;; \
		*) fname=$${url}; ;; \
	esac \
	&& interval=$${interval:-10} ${make} flux.loopf/$${display_target:-.tux.img.display}/$${fname}

.tux.img.rotate/%:
	$(call log, ${@})
	cmd="${*} --range 360 --center --display" \
	${make} docker.image.run/${IMG_IMGROT}

.tux.img.display/%:; chafa --clear --center on ${*}
	@# Displays the named file using chafa, and centering it in the available terminal width.
	@#
	@# USAGE: .tux.img.display/<fname>

.tux.widget.ctop:; img="${IMG_MONCHO_DRY}" ${make} io.wait/2 docker.start.tty
	@# A container monitoring tool.  
	@# https://github.com/moncho/dry https://hub.docker.com/r/moncho/dry
.tux.widget.lazydocker: .tux.widget.lazydocker/0
.tux.widget.lazydocker/%:
	@# Starts lazydocker in the TUI, then switches to the "statistics" tab.
	@#
	pane_id=`echo ${*}|cut -d/ -f1` \
	&& filter=`echo ${*}|cut -s -d/ -f2` \
	&& $(trace_maybe) \
	&& tmux send-keys -t 0.$${pane_id} "lazydocker" Enter "]" \
	&& cmd="tmux send-keys -t 0.$${pane_id} Down" ${make} flux.apply.later.sh/3 \
	&& case "$${filter:-}" in \
		"") true;; \
		*) (tmux send-keys -t 0.$${pane_id} "/$${filter}" C-m );; \
	esac

.tte/%:
	@# Interface to terminal-text-effects[1], just for fun.  Used as part of the main TUI demo.
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/ChrisBuilds/terminaltexteffects
	cat ${*} | head -`echo \`tput lines\`-1 | bc` \
	| tte matrix --rain-time 1 && ${make} io.shell

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Embedded files and data
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define FILE.TUX_COMPOSE
# ${TUI_COMPOSE_FILE}:
# This is an embedded/JIT compose-file, generated by compose.mk.
#
# Do not edit by hand and do not commit to version control.
# it is left just for reference & transparency, and is regenerated
# on demand, so you can also feel free to delete it.
#
# This describes a stand-alone config for a DIND / TUI base container.
# If you have a docker-compose file that you're using with 'compose.import',
# you can build on this container by using 'FROM compose.mk:tux'
# and then adding your own stuff.
#
volumes:
  socket_data:  # Define the named volume
services:
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
        RUN apt-get update -qq && apt-get install -qq -y curl uuid-runtime git bsdextrautils
        RUN yes|apt-get install -y sudo
        RUN curl -fsSL https://get.docker.com -o get-docker.sh && bash get-docker.sh
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
      - socket_data:/socket/dir  # This is a volume mount
      - "${KUBECONFIG:-~/.kube/config}:/home/${DOCKER_UGNAME:-root}/.kube/config"
    environment: &tux_environment
      DOCKER_UID: ${DOCKER_UID:-1000}
      DOCKER_GID: ${DOCKER_GID:-1000}
      DOCKER_UGNAME: ${DOCKER_UGNAME:-root}
      DOCKER_HOST_WORKSPACE: ${DOCKER_HOST_WORKSPACE:-${PWD}}
      TERM: ${TERM:-xterm-256color}
      CMK_DIND: "1"
      KUBECONFIG: /home/${DOCKER_UGNAME:-root}/.kube/config
      TMUX: "${TUI_TMUX_SOCKET:-/socket/dir/tmux.sock}"
    image: 'compose.mk:tux'
    build:
      tags: ['compose.mk:tux']
      context: .
      dockerfile_inline: |
        FROM ghcr.io/charmbracelet/gum AS gum
        FROM compose.mk:dind_base
        COPY --from=gum /usr/local/bin/gum /usr/bin
        USER root
        RUN apt-get update -qq && apt-get install -qq -y python3-pip wget tmux libevent-dev build-essential yacc ncurses-dev bsdextrautils jq yq bc ack-grep tree pv chafa figlet jp2a nano
        RUN wget https://github.com/tmux/tmux/releases/download/${TMUX_CLI_VERSION:-3.4}/tmux-${TMUX_CLI_VERSION:-3.4}.tar.gz
        RUN pip3 install tmuxp --break-system-packages
        RUN tar -zxvf tmux-${TMUX_CLI_VERSION:-3.4}.tar.gz
        RUN cd tmux-${TMUX_CLI_VERSION:-3.4} && ./configure && make && mv ./tmux `which tmux`
        RUN mkdir -p /home/${DOCKER_UGNAME:-root}
        RUN curl -sL https://raw.githubusercontent.com/sunaku/home/master/bin/tmux-layout-dwindle > /usr/bin/tmux-layout-dwindle
        RUN chmod ugo+x /usr/bin/tmux-layout-dwindle
        RUN cd /usr/share/figlet; wget https://raw.githubusercontent.com/xero/figlet-fonts/refs/heads/master/3d.flf
        RUN cd /usr/share/figlet; wget https://raw.githubusercontent.com/xero/figlet-fonts/refs/heads/master/Roman.flf
        RUN wget https://github.com/jesseduffield/lazydocker/releases/download/v${LAZY_DOCKER_VERSION:-0.23.1}/lazydocker_${LAZY_DOCKER_VERSION:-0.23.1}_Linux_x86_64.tar.gz
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
## BEGIN: Default TUI Shortcuts
##
## | Shortcut         | Purpose                                                |
## | ---------------- | ------------------------------------------------------ |
## | `Escape`           | *Exit TUI*                                           |
## | `Ctrl b |`         | *Split pane vertically*                              |
## | `Ctrl b -`         | *Split pane horizontally*                            |
## | `Alt t`            | *Shuffle pane layout*                                |
## | `Alt ^`            | *Grow pane up*                                       |
## | `Alt v`            | *Grow pane down*                                     |
## | `Alt <`            | *Grow pane left*                                     |
## | `Alt >`            | *Grow pane right*                                    |
## | `Alt <left>`       | *Grow pane left*                                     |
## | `Alt <right>`      | *Grow pane right*                                    |
## | `Alt <up>`         | *Grow pane up*                                       |
## | `Alt <down>`       | *Grow pane down*                                     |
## | `Alt-1`            | *Select pane 1*                                      |
## | `Alt-2`            | *Select pane 2*                                      |
## | ...                | *...*                                                |
## | `Alt-N`            | *Select pane N*                                      |
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define _TUI_TMUXP_PROFILE
cat <<EOF
# This tmuxp profile is generated by compose.mk.
# Do not edit by hand and do not commit to version control.
# it is left just for reference & transparency, and is regenerated
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

# Macro to yank all the compose-services out of YAML.  Important Note:
# This runs for each invocation of make, and unfortunately the command
# 'docker compose config' is actually pretty slow compared to parsing the
# yaml any other way! But we can not say for sure if 'yq' or python+pyyaml
# are available. Inside service-containers, docker compose is also likely
# unavailable.  To work around this, the CMK_INTERNAL env-var is checked,
# so that inside containers `compose.get_services` always returns nothing.
# As a side-effect, this prevents targets-in-containers from calling other
# targets-in-containers (which will not work anyway unless those containers
# also have docker).  This is probably a good thing!
#
# WARNING: tempting to add --no-env-resolution --no-path-resolution --no-consistency
# here, but note that these are not available for some versions of compose.
define compose.get_services
	$(shell if [ "${CMK_INTERNAL}" = "0" ]; then \
		(${trace_maybe} && ([ "$(strip ${1})" = "" ] && echo -n "" || ${docker.compose} -f ${1} config --services))  ; \
	else echo -n ""; fi)
endef

# Macro to create all the targets for a given compose-service.
# See docs @ https://robot-wranglers.github.io/compose.mk/bridge
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval import_to_root := $(strip $3))
$(eval compose_file := $(strip $4))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval compose_file_stem:=$(shell basename -s .yml $(compose_file)))

${compose_file_stem}.command/%:
	@# Passes the given command to the default entrypoint of the named service.
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.command/<svc>/<command>
	@#
	cmd="$${*}" ${make} $${compose_file_stem}/`printf $${*}|cut -d/ -f1`

${compose_file_stem}.dispatch/%:
	@# Dispatches the named target inside the named service.
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.dispatch/<svc>/<target>
	@#
	set -x && entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} `printf $${*}|cut -d/ -f2-`" \
	${make} ${compose_file_stem}/`printf $${*}|cut -d/ -f1`

${compose_file_stem}/$(compose_service_name).logs:
	@# Logs for this service.  NB: Uses "follow" mode by default, so this is blocking
	${make} docker.logs.follow/`${make} ${compose_file_stem}/$(compose_service_name).ps | ${jq} -r .ID` \
	|| $$(call log.docker, ${compose_file_stem}/$(compose_service_name).logs ${sep} ${red} failed${no_ansi} showing logs for ${bold}${compose_service_name}${no_ansi}.. could not find id?)

${compose_file_stem}.exec/%:
	@# Like ${compose_file_stem}.dispatch, but using exec instead of run
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.exec/<svc>/<target>
	@#
	@$$(eval detach:=$(shell if [ -z $${detach:-} ]; then echo "--detach"; else echo ""; fi)) 
	${trace_maybe} \
	&& docker compose -f ${compose_file} \
		exec `[ -z "$${detach}" ] && echo "" || echo "--detach"` \
		`printf $${*}|cut -d/ -f1` \
		${make} `printf $${*}|cut -d/ -f2-` 2> >(grep -v 'variable is not set' >&2)

${compose_file_stem}/$(compose_service_name).get_shell:
	@# Detects the best shell to use with the `$(compose_service_name)` container @ ${compose_file}
	$$(call compose.get_shell, $(compose_file), $(compose_service_name))

${compose_file_stem}/$(compose_service_name).get_config:
	@# Dumps JSON-formatted config for the `$(compose_service_name)` container @ ${compose_file}.
	@# This turns off most of the string-interpolation and path-resolution that happens by default.
	docker compose -f $(compose_file) config \
		--no-interpolate --no-path-resolution --format json \
	| ${jq} .services.${compose_service_name}

${compose_file_stem}/$(compose_service_name).get_config/%:
	@# Dumps JSON-formatted config for the `$(compose_service_name)` container @ ${compose_file}.
	@# This turns off most of the string-interpolation and path-resolution that happens by default.
	${make} ${compose_file_stem}/$(compose_service_name).get_config | ${jq} -er .$${*}

${compose_file_stem}/$(compose_service_name).shell:
	@# Starts a shell for the "$(compose_service_name)" container defined in the $(compose_file) file.
	@#
	$$(call compose.shell, $(compose_file), $(compose_service_name))

# NB: implementation must NOT use 'io.mktemp'!
${compose_file_stem}/$(compose_service_name).shell.pipe:
	@# Pipes data into the shell, using stdin directly.  This uses bash by default.
	@#
	@# USAGE:
	@#   echo <commands> | ./compose.mk ${compose_file_stem}/$(compose_service_name).shell.pipe
	@#
	@$$(eval export shellpipe_tempfile:=$$(shell mktemp))
	trap "rm -f $${shellpipe_tempfile}" EXIT \
	&& ${stream.stdin} > $${shellpipe_tempfile} \
	&& eval "cat $${shellpipe_tempfile} \
	| pipe=yes \
	  entrypoint="bash" \
	  ${make} ${compose_file_stem}/$(compose_service_name)"

${compose_file_stem}/$(compose_service_name).pipe:
	@# A pipe into the $(compose_service_name) container @ $(compose_file).
	@# Specify 'entrypoint=...' to override the default spec.
	@#
	@# EXAMPLE: 
	@#   echo echo hello-world | ./compose.mk  ${compose_file_stem}/$(compose_service_name).pipe
	@#
	${stream.stdin} | pipe=yes ${make} ${compose_file_stem}/$(compose_service_name)


$(compose_service_name).ps ${compose_file_stem}/$(compose_service_name).ps:
	@# Returns docker process-JSON for affiliated service.
	@# If strict=1, this fails when no process is found
	@$$(eval strict:=$(shell if [ -z $${strict:-} ]; then echo "0"; else echo "1"; fi)) 
	${trace_maybe} \
	&& ${docker.compose} -f ${compose_file} ps --format json ${compose_service_name} \
	| case $${strict} in \
		1) grep -q . ;; \
		*) cat ;; \
	esac

${compose_file_stem}/$(compose_service_name).stop:
	@# Stops the named service
	@#
	@# EXAMPLE: 
	@#   ./compose.mk ${compose_file_stem}/$(compose_service_name).stop
	@#
	$$(call log.docker, ${dim_green}${target_namespace} ${sep} ${no_ansi}${green}$(compose_service_name) ${sep} ${no_ansi_dim}stopping..)
	${docker.compose} -f ${compose_file} stop -t 1 ${compose_service_name} $${stream.stderr.iff.failed}

$(eval ifeq ($$(import_to_root), TRUE)
$(compose_service_name): $(target_namespace)/$(compose_service_name)
	@# Target wrapping the '$(compose_service_name)' container (via compose file @ ${compose_file})

$(compose_service_name).build: ${compose_file_stem}.build/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.build/$(compose_service_name)

$(compose_service_name).clean: ${compose_file_stem}.clean/$(compose_service_name)
	@# Cleans the given service, removing local image cache etc.
	@#
	@# Shorthand for ${compose_file_stem}.clean/$(compose_service_name)

# NB: optimization: NOT using chaining
$(compose_service_name).dispatch/%:
	@# Shorthand for ${compose_file_stem}.dispatch/$(compose_service_name)/<target_name>
	${trace_maybe} \
	&& entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} $${*}" \
	${make} ${compose_file_stem}/${compose_service_name}

$(compose_service_name).dispatch.quiet/%:; quiet=1 ${make} $(compose_service_name).dispatch/$${*}
$(compose_service_name).exec.detach/%:
	$$(call log.docker, ${dim_green}${target_namespace} ${sep} ${no_ansi}${green}$(compose_service_name) ${sep} ${dim_cyan}exec.detach ${sep} `printf $${*}|cut -d/ -f1-`)
	docker compose -f ${compose_file} \
		exec --detach $(compose_service_name) \
		${make} `printf $${*}|cut -d/ -f1-` 2> >(grep -v 'variable is not set' >&2)
$(compose_service_name).exec/%:
	@# Shorthand for ${compose_file_stem}.exec/$(compose_service_name)/<target_name>
	${make} ${compose_file_stem}.exec/$(compose_service_name)/$${*}

$(compose_service_name).exec.shell:
	@# Shorthand for ${compose_file_stem}.exec/$(compose_service_name)/<target_name>
	set -x && docker exec -it `${make} $(compose_service_name).ps |${jq} -e -r .ID` `${make} $(compose_service_name).get_shell`

$(compose_service_name).get_shell: ${compose_file_stem}/$(compose_service_name).get_shell
	@# Shorthand for ${compose_file_stem}/$(compose_service_name).get_shell
$(compose_service_name).get_config: ${compose_file_stem}/$(compose_service_name).get_config
	@# Shorthand for ${compose_file_stem}/$(compose_service_name).get_config
$(compose_service_name).get_config/%:; ${make} ${compose_file_stem}/$(compose_service_name).get_config/$${*}
$(compose_service_name).pipe:;  pipe=yes ${make} ${compose_file_stem}/$(compose_service_name)
	@# Pipe into the default shell for the '$(compose_service_name)' container (via compose file @ ${compose_file})

$(compose_service_name).shell: ${compose_file_stem}/$(compose_service_name).shell
	@# Shortcut for ${compose_file_stem}/$(compose_service_name).shell

$(compose_service_name).logs: ${compose_file_stem}/$(compose_service_name).logs
$(compose_service_name).logs/%:
	$$(call log.docker, ${dim_green}${target_namespace} ${sep} ${no_ansi}${green}$(compose_service_name) ${sep} ${dim_cyan}logs/ ${sep} `printf $${*}`)
	${trace_maybe} && docker compose -f ${compose_file} \
		logs -n $${*} $(compose_service_name)

$(compose_service_name).start $(compose_service_name).up: ${compose_file_stem}.up/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.up/$(compose_service_name)

$(compose_service_name).stop: ${compose_file_stem}/$(compose_service_name).stop
	@# Shorthand for ${compose_file_stem}.stop/$(compose_service_name)

$(compose_service_name).up.detach: ${compose_file_stem}.up.detach/$(compose_service_name)
	@# Shorthand for ${compose_file_stem}.up.detach/$(compose_service_name)

$(compose_service_name).shell.pipe: ${compose_file_stem}/$(compose_service_name).shell.pipe
	@# Shorthand for ${compose_file_stem}/$(compose_service_name).shell.pipe

endif)

${target_namespace}/$(compose_service_name).pipe:; pipe=yes ${make} ${target_namespace}/$(compose_service_name)
${target_namespace}/$(compose_service_name).command/%:; cmd="$${*}" ${make} ${compose_file_stem}/$(compose_service_name)
${target_namespace}/$(compose_service_name): 
	@# Target dispatch for $(compose_service_name)
	@#
	[ -z "${MAKE_CLI_EXTRA}" ] && true || verbose=0 \
	&& ${trace_maybe} && ${make} ${compose_file_stem}/${compose_service_name}
${target_namespace}/$(compose_service_name)/%:
	@# Dispatches the named target inside the $(compose_service_name) service, as defined in the ${compose_file} file.
	@#
	@# EXAMPLE: 
	@#  # mapping a public Makefile target to a private one that is executed in a container
	@#  my-public-target: ${target_namespace}/$(compose_service_name)/myprivate-target
	@#
	#
	@$$(eval export pipe:=$(shell \
		if [ -p ${stdin} ]; then echo "yes"; else echo ""; fi))
		pipe=$${pipe} entrypoint=make cmd="${MAKE_FLAGS} -f ${MAKEFILE} $${*}" \
		make -f ${MAKEFILE} ${compose_file_stem}/$(compose_service_name)
endef

define compose.get_shell
	${docker.compose} -f $(1) run --entrypoint bash $(2) -c "which bash"  \
	|| (${docker.compose} -f $(1) run --entrypoint sh $(2) -c "which sh" \
		|| $(call log.docker, ${red}No shell found for $(1) / $(2)); exit 35 )
endef

define compose.shell
	${trace_maybe} \
	&& entrypoint="`${compose.get_shell}`" \
	&& printf "${green}⇒${no_ansi}${dim} `basename -s.yaml \`basename -s.yml ${1}\``/$(strip $(2)).shell (${green}...${no_ansi_dim})${no_ansi}\n" \
	&& docker compose -f ${1} \
		run --rm --remove-orphans --quiet-pull \
		--env CMK_INTERNAL=1 -e TERM="$${TERM}" \
		-e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE} \
		--env verbose=$${verbose} \
		 --entrypoint $${entrypoint}\
		${2}
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: *.import.*
## Import-Statement Macros
##
## See the docs here: https://github.com/robot-wranglers/compose.mk/style#import-statements
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# loggers used at module level.
log.import=$$(shell $$(call \
	log.io, __import__ $${sep} $${dim_cyan}.. $${sep}$${dim} ${1}))
log.import.1=$$(shell $$(call \
	log.trace.part1, __import__ $${sep} $${dim_cyan}.. $${sep}$${dim} ${1}))
log.import.2=$$(shell $$(call log.trace.part2, ${1}))

# Reroutes call into container if necessary, or otherwise executes the target directly
#
# USAGE:
#   foo:; $(call in.container, container_name)
#   .foo:; echo hello-world
#
define in.container
case $${CMK_INTERNAL} in 0)  ${log.target.rerouting} ; quiet=1 ${make} $(strip ${1}).dispatch/.$(strip ${@});; *) ${make} .$(strip ${@}) ;; esac
endef

docker.import.script= $(eval $(call _docker.import.script,${1},${2},${3},${4}))
define _docker.import.script
$(strip $(if $(filter undefined,$(origin 4)),$(strip ${3}),$(4))):; $(call docker.bind.script,${1},${2},${3})
endef
compose.import.script=$(eval $(call _compose.import.script, ${1}))
define _compose.import.script
$(call mk.unpack.kwargs, ${1}, def)
$(strip ${kwargs_def}):; $${make} flux.timer/io.bash/${kwargs_def}
endef

compose.import.string=$(eval $(call _compose.import.string,${1}))
define _compose.import.string
ifeq (${CMK_INTERNAL},1)
else
$(call mk.unpack.kwargs, ${1}, def)
$(call mk.unpack.kwargs, ${1}, import_to_root, TRUE)
$(shell cat $(MAKEFILE_LIST) | awk '/^define ${kwargs_def}/{flag=1; next} /endef/{flag=0} flag' > .tmp.${kwargs_def}.yml)
$(call compose.import.generic, $(kwargs_def), $(kwargs_import_to_root), .tmp.${kwargs_def}.yml)
endif
endef

dockerfile.import.string=$(eval $(call _dockerfile.import.string, ${1}))
define _dockerfile.import.string
$(call mk.unpack.kwargs, ${1}, def, ${1})
$(eval img_name:=$(patsubst Dockerfile.%,%,${kwargs_def}))
${img_name}.img:=compose.mk:${img_name}
${img_name}.build: Dockerfile.build/${img_name}
${img_name}.shell:
	img=compose.mk:${img_name} hostname=${img_name} \
	entrypoint=$${entrypoint:-sh} ${make} docker.run.sh 
${img_name}.build.force:; force=1 ${make} ${img_name}.build 
${img_name}.dispatch/%:; hostname=${img_name} img=${img_name} ${make} mk.docker.dispatch/$${*}
${img_name}.run:; img=compose.mk:${img_name} ${make} docker.run.sh 
endef

# Scaffolds dispatch/shell/run targets for the given docker image
docker.import=$(eval $(call _docker.import,${1}))
docker.image.import=${docker.import}
define _docker.import
ifeq ($${CMK_INTERNAL},1)
else
$(call mk.unpack.kwargs, ${1}, img)
$(call mk.unpack.kwargs, ${1}, file, undefined)
$(call mk.unpack.kwargs, ${1}, namespace)
${kwargs_namespace}.img:=${kwargs_img}
${kwargs_namespace}.dispatch/%:; img=${kwargs_img} hostname=${kwargs_img} \
	${make} docker.dispatch/$${*}
${kwargs_namespace}.build:; tag=${kwargs_img} ${make} docker.build/$${kwargs_file}
${kwargs_namespace}.shell:; img=${kwargs_img} hostname=${kwargs_img} \
	entrypoint=$${entrypoint:-sh} ${make} docker.run.sh 
${kwargs_namespace}:; img=${kwargs_img} hostname=${kwargs_img} ${make} docker.run.sh 
endif
endef

MAKE_PID := $(shell echo $$PPID)
# MAKE_ID := $(shell echo $$PPID | { h=5381; read p; for((i=0;i<$${#p};i++)); do printf -v c "%d" "'$${p:i:1}"; h=$$((h*33+c)); done; echo $$((h & 0x7FFFFFFF)); })
# # Alternative using date for more uniqueness
# MAKE_ID_ALT := $(shell printf "%d%s" $$PPID $$(date +%N 2>/dev/null || echo $$RANDOM))
# _pid_info= $(call log.io, Make PID: ${MAKE_PID} -- ${MAKE_ID} -- ${MAKE_ID_ALT} -- $$$$)
# pid_info:; ${_pid_info}

# Helper macro, defaults to root-import with an optional dispatch-namespace.
#
# USAGE: 
#   $(call compose.import, file=docker-compose.yml)
#   $(call compose.import, file=docker-compose.yml namespace=▰)
#   $(call compose.import, file=docker-compose.yml namespace=▰ import_to_root=TRUE)
#
# If not provided, the default dispatch namespace is `services`.
compose.import=$(eval $(call _compose.import, ${1}))
compose.import.*=${compose.import}
define _compose.import
$(call mk.unpack.kwargs, ${1}, file)
$(call mk.unpack.kwargs, ${1}, import_to_root, TRUE)
$(call mk.unpack.kwargs, ${1}, namespace, services)
$(call compose.import.generic, ${kwargs_namespace}, ${kwargs_import_to_root}, ${kwargs_file})
endef
define compose.import.as
$(eval 
$(call mk.unpack.kwargs, ${1}, namespace)
$(call mk.unpack.kwargs, ${1}, file)
$(call compose.import.generic, ${kwargs_namespace}, FALSE, ${kwargs_file}))
endef

define compose.import.generic
$(eval target_namespace:=$(strip $(1)))
$(eval compose_file:=$(strip $(3)))
$(eval cached:=$(call io.string.hash,$(target_namespace)$(2)$(3)))
$(call log.import.1,${compose_file})
ifndef $${cached}
$$(eval ${cached} := 1)
$(call log.import.2,${bold}creating)

$(eval import_to_root := $(if $(2), $(strip $(2)), FALSE))
$(eval compose_file_stem:=$(shell basename -s.yaml `basename -s.yml $(strip ${3}`)))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

# Operations on the compose file itself
# WARNING: these can not use '/' naming conventions as that conflicts with '<stem>/<svc>' !
${compose_file_stem}.services $(target_namespace).services:
	@# Outputs newline-delimited list of services for the ${compose_file} file.
	@#
	@# NB: This must remain suitable for use with xargs, etc
	@#
	echo $(__services__) | sed -e 's/ /\n/g' | sort

${compose_file_stem}.images ${target_namespace}.images:; ${make} compose.images/${compose_file}
	@# Returns a nl-delimited list of images for this compose file

${compose_file_stem}.size ${target_namespace}.size:; ${make} compose.size/${compose_file}

${compose_file_stem}.build $(target_namespace).build:
	@# Noisy build for all services in the ${compose_file} file, or for the given services.
	@#
	@# USAGE: 
	@#   ./compose.mk  ${compose_file_stem}.build
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	$$(call log.docker, ${bold_green}${target_namespace} ${sep} ${bold_cyan}build ${sep} ${dim_ital}all services) \
	&&  $(trace_maybe) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build -q 

${compose_file_stem}.build.quiet $(target_namespace).build.quiet:
	@# Quiet build for all services in the given file.
	@#
	@# USAGE: ./compose.mk  <compose_stem>.build.quiet
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	@$$(eval export svc_disp:=$(shell echo echo $$$${svc:-all services}))
	$(call log.docker, ${bold_green}${target_namespace} ${sep} ${bold_cyan}build ${sep} ${dim_ital}$${svc_disp})
	$(trace_maybe) \
	&& quiet=1 label="build finished in" ${make} flux.timer/compose.build/${compose_file}

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
	$$(call log.docker, ${target_namespace} ${sep} ${green}$${*} ${sep} ${no_ansi_dim}building..) 
	echo $${*} | ${stream.comma.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build %"

${compose_file_stem}.up/%:
	@# Ups the given service(s) for the ${compose_file} file.
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.up/<svc_name>
	@#
	$$(call log.docker, ${target_namespace}.up ${sep} $${*}) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up $${*} 

${compose_file_stem}.up.detach/%:
	@# Ups the given service(s) for the ${compose_file} file, with implied --detach
	@#
	@# USAGE: 
	@#   ./compose.mk ${compose_file_stem}.up.detach/<svc_name>
	@#
	$(call log.docker, ${target_namespace} ${sep} ${dim_cyan}up.detach ${sep} ${dim_green}$${*})
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up -d $${*} $${stream.stderr.iff.failed}

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

${compose_file_stem}.stop $(target_namespace).stop:
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${bold_green}${target_namespace} ${sep} ${bold_cyan}stop ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} stop -t 1 2> >(grep -v '\] Stopping'|grep -v '^ Container ' >&2)

${compose_file_stem}.down $(target_namespace).down:
	@# Bring down all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${bold_green}${target_namespace} ${sep} ${bold_cyan}down ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} down -t 1 2> >(grep -v '^Network.*Removing'|grep -v '^Network.*Removed' >&2)

${compose_file_stem}.up:
	@# Brings up all services in the given compose file.
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose_file_stem}.up ${sep} ${dim_ital} $${svc:-all services})
	${docker.compose} -f $${compose_file} up $${svc:-}

${compose_file_stem}.clean:
	@# Runs 'compose.clean' for the given service(s), or for all services in the '${compose_file}' file if no specific service is provided.
	@#
	svc=$${svc:-} ${make} compose.clean/${compose_file}

# NB: implementation must NOT use 'io.mktemp'!
${compose_file_stem}/%:
	@# Generic dispatch for given service inside ${compose_file}
	@# WARNING: This uses noglob to let expansion happen in the container. 
	@#          This could be confusing but is usually correct.
	@#
	@$$(eval export tty:=$(shell [ "$${tty}" = "0" ] && echo "" || echo "-T"))
	@$$(eval export svc_name:=$$(shell echo $$@|awk -F/ '{print $$$$2}'))
	@$$(eval export cmd:=$(shell echo $${MAKE_CLI_EXTRA:-$${cmd:-}}))
	@$$(eval export quiet:=$(shell if [ -z "$${quiet:-}" ]; then echo "0"; else echo "$${quiet:-1}"; fi))
	@$$(eval export pipe:=$(shell \
		if [ -z "$${pipe:-}" ]; then echo ""; else echo "-iT"; fi))
	@$$(eval export nsdisp:=${log.prefix.makelevel} ${green}${bold}$${target_namespace}${no_ansi})
	@$$(eval export header:=$${nsdisp} ${sep} ${bold_green}${underline}$${svc_name}${no_ansi_dim} container ${sep} ${dim}@${ital}${compose_file_stem}${no_ansi}\n)
	@$$(eval export entrypoint:=$(shell \
		if [ -z "$${entrypoint:-}" ]; \
		then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi))
	@$$(eval export user:=$(shell \
		if [ -z "$${user:-}" ]; \
		then echo ""; else echo "--user $${user:-}"; fi))
	@$$(eval export extra_env=$(shell \
		if [ -z "$${env:-}" ]; then echo "-e _=_"; else \
		printf "$${env:-}" | sed 's/,/\n/g' | xargs -I% bash -c "[[ -v % ]] && printf '%\n' || true" | xargs -I% echo --env %='☂$$$${%}☂'; fi))
	@$$(eval export base:=docker compose -f $(compose_file) run $${tty} --rm --remove-orphans --quiet-pull \
		$$(subst ☂,\",$${extra_env}) \
		--env CMK_INTERNAL=1 \
		-e TERM="$${TERM}" -e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE} \
		--env verbose=$${verbose} \
		 $${pipe} $${user} $${entrypoint} $${svc_name} $${cmd})
	@$$(eval export stdin_tempf:=$$(shell mktemp))
	@$$(eval export entrypoint_display:=${cyan}[${no_ansi}${bold}$(shell \
			if [ -z "$${entrypoint:-}" ]; \
			then echo "default${no_ansi} entrypoint"; else echo "$${entrypoint:-}"; fi)${no_ansi_dim}${cyan}] ${no_ansi})
	@$$(eval export cmd_disp:=`[ -z "$${cmd}" ] && echo " " || echo " $${cmd}\n${log.prefix.makelevel}"`)
	@$$(eval export cmd_disp:=$$(shell echo "$${cmd}" | sed 's/-s -S --warn-undefined-variables --no-builtin-rules //g'))
	@$$(eval export cmd_disp:=${no_ansi_dim}${ital}$${cmd_disp}${no_ansi})
	@trap "rm -f $${stdin_tempf}" EXIT \
	&& set -o noglob \
	&& if [ -z "$${pipe}" ]; then \
		([ $${verbose} == 1 ] && printf "$${header}${log.prefix.makelevel} ${green_flow_right}  ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${cyan}<${no_ansi}${bold}..${no_ansi}${cyan}>${no_ansi}${dim_ital}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
		&& ($(call log.trace, ${dim}$${base}${no_ansi})) \
		&& eval $${base}  2\> \>\(\
                 grep -vE \'.\*Container.\*\(Running\|Recreate\|Created\|Starting\|Started\)\' \>\&2\ \
                 \| grep -vE \'.\*Network.\*\(Creating\|Created\)\' \>\&2\ \
                 \) ; \
	else \
		${stream.stdin} > $${stdin_tempf} \
		&& ([ $${verbose} == 1 ] && printf "$${header}${dim}$${nsdisp} ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${cyan_flow_left} ${dim_ital}`cat $${stdin_tempf} | sed 's/^[\\t[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
		&& cat "$${stdin_tempf}" | eval $${base} 2\> \>\(\
                 grep -vE \'.\*Container.\*\(Running\|Recreate\|Created\|Starting\|Started\)\' \>\&2\ \
                 \| grep -vE \'.\*Network.\*\(Creating\|Created\)\' \>\&2\ \
                 \)  \
	; fi \
	&& ([ -z "${MAKE_CLI_EXTRA}" ] && true || ${make} mk.interrupt)

$$(foreach \
 	compose_service_name, \
 	$(__services__), \
	$$(eval \
		$$(call compose.create_make_targets, \
			$${compose_service_name}, \
			${target_namespace}, ${import_to_root}, ${compose_file}, )))
else
$(call log.import.2,${GLYPH_CHECK} cached)
$(call log.import,double-import${no_ansi_dim}.. skipping)
endif
endef

polyglot.import.file=$(eval $(call _polyglot.import.file,${1}))
define _polyglot.import.file
$(call mk.unpack.kwargs, ${1}, namespace)
${kwargs_namespace}:; $$(call polyglot.bind.file, ${1})
endef
define polyglot.bind.file
$(call _mk.unpack.kwargs, ${1}, file) \
&& $(call _mk.unpack.kwargs, ${1}, entrypoint) \
&& $(call _mk.unpack.kwargs, ${1}, img) \
&& $(call _mk.unpack.kwargs, ${1}, cmd,) \
&& $(call _mk.unpack.kwargs, ${1}, env,) \
&& env="`printf "$${env}" | sed 's/ /,/g'`" \
	img=$${img} entrypoint=$${entrypoint} \
	cmd="$${cmd} $${file}" ${make} docker.run.sh
endef

# Main macros to import 1 or more code-blocks
polyglots.import=$(eval $(call _polyglots.import,${1}))
define _polyglots.import
$(call mk.unpack.kwargs, ${1}, pattern)
$(eval __code_blocks__:=$(shell echo "$(.VARIABLES)" | ${stream.space.to.nl} | grep '${kwargs_pattern}$$'))
$(foreach codeblock, ${__code_blocks__},\
	$(call _compose.import.code, def=${codeblock} ${1}))
endef

polyglot.import=$(eval $(call _polyglot.import,${1}))
define _polyglot.import
$(call mk.unpack.kwargs, ${1}, bind, None) 
ifneq (${kwargs_bind}, None)
$$(call compose.import.code, ${1})
else
$$(call polyglot.import_container,${1})
endif
endef

# USAGE: only from CMK-lang.  See demos/cmk/code-objects.cmk
polyglot.__import__.target=$(call polyglot.import, def=${1} bind=${2})
polyglot.__import__.container=$(call polyglot.import, \
	def=$(strip ${1}) img=$(strip ${2}) entrypoint=$(strip ${3}))

polyglot.import_container=$(eval $(call _polyglot.import_container,${1}))
define _polyglot.import_container
$(call mk.unpack.kwargs, ${1}, def)
$(call mk.unpack.kwargs, ${1}, namespace, $${kwargs_def})
$(call mk.unpack.kwargs, ${1}, local_img, Undefined)
$(call mk.unpack.kwargs, ${1}, env)
$(call mk.unpack.kwargs, ${1}, img, compose.mk:$${kwargs_local_img})
$(call mk.unpack.kwargs, ${1}, entrypoint)
${kwargs_namespace}.interpreter.base:
	case ${kwargs_local_img} in \
		Undefined) true;; \
		*) ${make} Dockerfile.build/$${kwargs_local_img};; \
	esac \
	&& img=${kwargs_img} entrypoint="${kwargs_entrypoint}" ${make} docker.run.sh
${kwargs_namespace}.interpreter/%:; cmd=$${*} ${make} ${kwargs_namespace}.interpreter.base
$(call compose.import.code, ${1} bind=${kwargs_namespace}.interpreter)
endef

compose.import.code=$(eval $(call _compose.import.code,$(1)))
define _compose.import.code
${nl}
ifeq ($${CMK_INTERNAL},1)
else 
$(call mk.unpack.kwargs, ${1}, def)
$(call mk.unpack.kwargs, ${1}, namespace, $${kwargs_def})
$(call mk.unpack.kwargs, ${1}, bind, None) 
$(call mk.unpack.kwargs, ${1}, env,) 
${kwargs_namespace}.with.file/%:; ${make} io.with.file/${kwargs_def}/$${*}
${kwargs_namespace}.to.file/%:; CMK_INTERNAL=1 ${make} mk.def.read/${kwargs_def} > $${*}
${kwargs_namespace}.to.file:
	@$$(eval export tmpf:=$$(shell TMPDIR=. mktemp))
	CMK_INTERNAL=1 ${make} mk.def.read/${kwargs_def} > $${tmpf} \
	&& echo $${tmpf}
${kwargs_namespace}.preview: ${kwargs_namespace}.with.file/io.preview.file
${kwargs_namespace}.run/%:; CMK_INTERNAL=1 ${make} mk.def.read/${kwargs_def}/$${*}
${kwargs_namespace}:
	@# ...
	export env="$(subst ${space},${comma},${kwargs_env})" \
	&& case "${kwargs_bind}" in \
		None) $$(call log.io, \
				${kwargs_namespace} ${sep}${no_ansi}${kwargs_def} unbound at import time) \
			; ${make} ${kwargs_namespace}.with.file/${kwargs_namespace}.interpreter \
				|| exit 41 ;; \
		*) $$(call log.io, \
				${kwargs_namespace} ${sep}${dim} bound to ${no_ansi}${underline}${kwargs_bind}${no_ansi}) \
			&& ${make} ${kwargs_namespace}.with.file/${kwargs_bind} ;; \
	esac
${kwargs_namespace}=${make} ${kwargs_namespace}
endif
endef

# Target decorator.  
# Runs the implied private-target inside the given container.
# USAGE:
#   my_target:; $(call containerized.target, debian)
#   .my_target:; echo hello container `hostname`
# (eval _prefix=$(strip $(if $(filter undefined,$(origin 2)),.,$(2))))
define containerized.target
$(eval _data=$(if $(filter undefined,$(origin 2)),,$(2))) true \
&& _hdr="${dim}${_GLYPH_IO}${dim} $(shell echo ${@}|sed 's/\/.*//') ${sep}${dim}" \
&& $(call _mk.unpack.kwargs,${_data},env,) \
&& $(call _mk.unpack.kwargs,${_data},quiet,$${quiet:-}) \
&& $(call _mk.unpack.kwargs,${_data},prefix,.) \
&& case $${CMK_INTERNAL} in \
	0)  ($(call log.target.rerouting, Invoked from top; rerouting to tool-container) \
		&& ${trace_maybe} \
		&& export env=`printf "$${env}"|sed 's/ /,/g'` \
		&& _disp=$(strip ${1}).dispatch \
		&& _priv=$${prefix}$(strip ${@}) \
		&& ([ -z "$${env}" ] \
			|| $(call log.trace, $${_hdr} ${bold}env ${sep} ${green_flow_left}$${env})) \
		&& $(call log, $${_hdr} ${cyan_flow_right}${ital}$${_disp}/$${_priv}) \
		&& quiet=$${quiet} ${make} $${_disp}/$${_priv});; \
	*) quiet=$${quiet} ${make} $${prefix}$(strip ${@}) ;; \
esac
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: bind.* targets 
## See the docs: /compose.mk/style/#bind-declarations
##
## `docker_context` is used in CMK-lang in support of ⨖/with/as.
## USAGE:
##   ⨖ my_dockerized_script
##   echo hello `hostname` at `uname -a`
##   ⨖ with debian/buildd:bookworm as docker_context
##
## `local_context` is used in CMK-lang in support of ⨖/with/as.
## USAGE:
##   ⨖ script.sh
##   echo hello `hostname` at `uname -a`
##   ⨖ with my_container as local_context
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

compose.bind.target=$(call containerized.target,${1},prefix=self. $(if $(filter undefined,$(origin 2)),,$(2)))
define compose.bind.script
$(call _mk.unpack.kwargs,${1},svc,${1}) \
&& $(call _mk.unpack.kwargs,${1},entrypoint,bash) \
&& $(call _mk.unpack.kwargs,${1},env,$${env:-}) \
&& $(call _mk.unpack.kwargs,${1},quiet,$${quiet:-0}) \
&& $(call _mk.unpack.kwargs,${1},output,cat) \
&& $(call log.io, compose.bind.script ${sep} ${dim_cyan}${@}) \
&& $(call log.io, ${green_flow_right} ${no_ansi_dim}svc=${no_ansi}$${svc} ${dim}entrypoint=${no_ansi}$${entrypoint}) \
&& ${log.target.rerouting} \
&& ( ${trace_maybe} \
	&& env="`printf "$${env}" | ${stream.space.to.comma}`" \
	&& ${io.mktemp} && ${mk.def.read}/${@} > $${tmpf} \
	&& case ${CMK_INTERNAL} in \
		1)  cat $${tmpf} | bash ${dash_x_maybe};; \
		*) ( true \
			&& case $${quiet:-1} in \
				0) cat $${tmpf} | ${stream.as.log};; \
			esac && ${trace_maybe} \
			&& entrypoint=$${entrypoint} cmd=$${tmpf} ${make} $${svc}) \
			| (case "$${output}" in \
				"stderr") ${stream.as.log};; \
				*) cat;; \
			esac);; \
	esac)
endef

bind.compose.bind.script=${compose.bind.script}
bind.compose.target=${compose.bind.target}

# Used in CMK-Lang
docker_context=$(call docker.bind.script, ${1})
local_context=$(call mk.docker.bind.script, ${1} build=Dockerfile.build)
compose_context=${compose.bind.script}
bind.compose.bind.target=${compose.bind.target}
bind.polyglot.bind.file=${polyglot.bind.file}

define docker.bind.script
$(call _mk.unpack.kwargs,${1},img,${1}) \
&& $(call _mk.unpack.kwargs,${1},def,${@}) \
&& $(call _mk.unpack.kwargs,${1},entrypoint,bash) \
&& $(call _mk.unpack.kwargs,${1},env,$${env:-}) \
&& $(call _mk.unpack.kwargs,${1},cmd,) \
&& $(call _mk.unpack.kwargs,${1},quiet,$${quiet:-0}) \
&& $(call _mk.unpack.kwargs,${1},build,) \
&& export env=`printf "$${env}"|sed 's/ /,/g'` \
&& ([ -z "$${env}" ] \
	|| $(call log.trace, $${_hdr} ${bold}env ${sep} ${green_flow_left}$${env})) \
&& case $(strip $${build:-}) in \
	"") true;; \
	*) $(call log.target, building with $${build}/$${img}); build=$${build}/$${img};; \
esac \
&& $(call log.trace, docker.bind.script ${sep} def=$${def} img=$${img} entrypoint=$${entrypoint}) \
&& ${io.mktemp} && ${mk.def.read}/$${def} | ${stream.peek} > $${tmpf} \
&& ${trace_maybe} && entrypoint=$${entrypoint} cmd="$${cmd} $${tmpf}" ${make} $${build} docker.run.sh
endef
mk.docker.bind.script=$(call _mk.docker.bind.script,${1} build=Dockerfile.build)
define _mk.docker.bind.script
$(call docker.bind.script, $(strip $(shell printf "$(if $(findstring img=,$(1)),$(1),img=$(strip $(1)))"| sed s'/img=/img=compose.mk:/')))
endef
polyglot.bind=${docker.bind.script}
bind.docker.bind.script=${docker.bind.script}

bind.args.from_params=$(call bind.posargs,${1})
bind.posargs=$(call _bind.posargs,$(strip $(or $(if $(filter undefined,$(origin 1)),,$(1)),${comma})))
define _bind.posargs
kwargs_delim=$(strip $(if $(filter undefined,$(origin 1)),${comma},$(1))) \
&& _1st="`echo ${*} | cut -d$${kwargs_delim} -f 1`" \
&& _2nd="`echo ${*} | cut -d$${kwargs_delim} -f 2`" \
&& _3rd="`echo ${*} | cut -d$${kwargs_delim} -f 3`" \
&& _4th="`echo ${*} | cut -d$${kwargs_delim} -f 4`" \
&& _5th="`echo ${*} | cut -d$${kwargs_delim} -f 4`" \
&& _head="`echo ${*} | cut -d$${kwargs_delim} -f 1`" \
&& _tail="`echo ${*} | cut -d$${kwargs_delim} -f2-`"
endef
define bind.args.from_json
${trace_maybe} && [ -p /dev/stdin ] && input=$$(cat) || input=""; for arg in ${1}; do [[ $$arg =~ ^([^=]+)(=(.*))?$$ ]] && { val=$$(echo "$$input" | sed -n "s/.*\"$${BASH_REMATCH[1]}\"[[:space:]]*:[[:space:]]*\"\?\([^,}\"]*\)\"\?.*/\1/p"); export "$${BASH_REMATCH[1]}=$${val:-$${BASH_REMATCH[3]}}"; }; done
endef
define bind.args.from_env
${trace_maybe} && for v in $1; do if [[ "$$v" =~ ^([^=]+)=(.+)$$ ]]; then n=$${BASH_REMATCH[1]}; [[ -z "$${!n}" ]] && export "$$n"="$${BASH_REMATCH[2]}" || true; else [[ -n "$${!v}" ]] || { echo "Error: $$v is not set or empty" >&2; exit 1; }; fi; done
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: help.* targets and macros
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Define 'help' target iff it is not already defined.  This should be inlined
# for all files that want to be simultaneously usable in stand-alone
# mode + library mode (with 'include')
# _help_id:=$(shell (uuidgen ${stderr_devnull} || cat /proc/sys/kernel/random/uuid 2>${devnull} || date +%s) | head -c 8 | tail -c 8)
define _help_gen
(LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : ${stderr_devnull} | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' | LC_ALL=C sort| uniq || true)
endef
help:
	@# Attempts to autodetect the targets defined in this Makefile context.
	@# Older versions of make dont have '--print-targets', so this uses the 'print database' feature.
	@# See also: https://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile
	@#
	export CMK_DISABLE_HOOKS=1 \
	&& $(call io.mktemp) \
	&& case $${search:-} in \
		"") export key=`echo "$${MAKE_CLI#* help}"|awk '{$$1=$$1;print}'` ;; \
		*) export key="$${search}" ;;\
	esac \
	&& count=`echo "$${key}" |${stream.count.words}` \
	&& case $${count} in \
		0) ( $(call _help_gen) > $${tmpf} \
			&& count=`cat $${tmpf}|${stream.count.lines}` && count="${yellow}$${count}${dim} items" \
			&& cat $${tmpf} \
			&& $(call log.docker, help ${sep} ${dim}Answered help for: ${no_ansi}${bold}top-level ${sep} $${count}) \
			&& $(call log.docker, help ${sep} ${dim}Use ${no_ansi}help <topic>${no_ansi_dim} for more specific target / module help.) \
			&& $(call log.docker, help ${sep} ${dim}Use ${no_ansi}help.local${no_ansi_dim} to get help for ${dim_ital}${MAKEFILE} without any included targets.) \
		); ;; \
		1) ( ( ${make} mk.help.module/$${key} \
				; ${make} mk.help.target/$${key} \
				; ${make} mk.help.search/$${key} \
			) \
			;  $(call mk.yield,true) \
		); ;; \
		*) ( $(call log.docker, help ${sep} ${red}Not sure how to help with $${key} ($${count}) ${no_ansi}$${key}) ; ); ;; \
	esac 

# Code-gen shim for `loadf`
define _loadf
cat <<EOF
#!/usr/bin/env -S make -sS --warn-undefined-variables -f
# Generated by compose.mk, for ${fname}.
#
# Do not edit by hand and do not commit to version control.
# it is left just for reference & transparency, and is regenerated
# on demand, so you can feel free to delete it.
#
SHELL:=/bin/bash
.SHELLFLAGS?=-euo pipefail -c
MAKEFLAGS=-s -S --warn-undefined-variables
include ${CMK_SRC}
\$(eval \$(call compose.import.generic, ▰, TRUE, ${fname}))
EOF
endef

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
	&& cmd=$${cmd:-$${after:-.}} && dcmd="${yq.run.pipe} $${cmd}" \
	&& ([ -p ${stdin} ] && dcmd="${stream.stdin} | $${dcmd}" || true) \
	&&  $(call mk.yield, $${dcmd})

jq:
	@# A wrapper for jq.  
	after=`echo -e "$${MAKE_CLI#*jq}"` \
	&& cmd=$${cmd:-$${after:-.}} && dcmd="${jq.run.pipe} $${cmd}" \
	&& ([ -p ${stdin} ] && dcmd="${stream.stdin} | $${dcmd}" || true) \
	&& $(call mk.yield, $${dcmd})

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
	@#   * `[2]`: https://robot-wranglers.github.io/compose.mk/signals
	@#
	case $$(test -p /dev/stdin && echo pipe) in \
		pipe) sh ${dash_x_maybe} -c "${jb.docker} `${stream.stdin}`"; ;; \
		*) sh ${dash_x_maybe} -c "${jb.docker} `echo "$${MAKE_CLI#*jb}"`"; ;; \
	esac

define .awk.main.preprocess
BEGIN {
    in_define_block = 0; header_printed = 0
    # Define the header to be printed at the beginning of the output
    header = ""
    # Define string substitution pairs (literal strings, not regex)
    # Format: from_string[i] = "original"; to_string[i] = "replacement"
    from_string[1] = "compose.import("; to_string[1] = "$(call compose.import,"
    from_string[2] = "compose.import.string("; to_string[2] = "$(call compose.import.string,"
    from_string[3] = "compose.import.script("; to_string[3] = "$(call compose.import.script,"
    from_string[4] = "compose.import.code("; to_string[4] = "$(call compose.import.code,"
    from_string[5] = "polyglot.import("; to_string[5] = "$(call polyglot.import,"
    from_string[6] = "polyglots.import("; to_string[6] = "$(call polyglots.import,"
    from_string[7] = "polyglot.import.file("; to_string[7] = "$(call polyglot.import.file,"
    num_substitutions = 7 }
# Function to ensure the header is printed once before any other output
function ensure_header() {if (!header_printed) { printf "%s", header; header_printed = 1 } }
# Track when we enter/exit define-endef blocks
/^define / { ensure_header(); in_define_block = 1; print; next }
/^endef/ { ensure_header(); in_define_block = 0; print; next }
# Function for literal string substitution (no regex)
function string_substitute(text,    i, result, from, to, index_pos, before, after) {
    result = text
    # Skip substitution if we're in a define block
    if (in_define_block) { return result }
    for (i = 1; i <= num_substitutions; i++) {
        from = from_string[i]; to = to_string[i]
        # Process all occurrences of the literal string
        temp = result; result = ""
        while (1) {
            # Find the next occurrence using index() which is literal, not regex
            index_pos = index(temp, from)
            # No more occurrences found, append remaining text
            if (index_pos == 0) { result = result temp; break }
            # Split text and insert replacement
            # Append before + replacement
            # Continue with remaining text
            before = substr(temp, 1, index_pos - 1)
            after = substr(temp, index_pos + length(from))
            result = result before to; temp = after
        }
    }
    return result }
function process_text(text, result, pos, method_start, method_name, args_start, args, processed_args, paren_count, c) {
    result = ""; pos = 1
    while (pos <= length(text)) {
        # Look for "cmk." pattern
        method_start = index(substr(text, pos), "cmk.")
        # No more "cmk." found, append remaining text
        if (method_start == 0) { result = result substr(text, pos); break }
        # Append text before "cmk.", then skip "cmk."
        result = result substr(text, pos, method_start - 1)
        pos = pos + method_start - 1; pos = pos + 4
        # Extract method name (until opening parenthesis)
        method_name = ""
        while (pos <= length(text) && substr(text, pos, 1) != "(") {
            method_name = method_name substr(text, pos, 1)
            pos++ }
        # No opening parenthesis found, append remaining text
        if (pos > length(text)) { result = result "cmk." method_name; break }
        # Skip opening parenthesis
        pos++
        # Extract arguments with balanced parentheses
        args_start = pos; paren_count = 1
        while (pos <= length(text) && paren_count > 0) {
            c = substr(text, pos, 1)
            if (c == "(") { paren_count++ } 
            else if (c == ")") { paren_count-- }
            pos++
        }
		# Unbalanced parentheses, append remaining text
        if (paren_count > 0) {
            result = result "cmk." method_name "(" substr(text, args_start)
            break }
        # Extract arguments (excluding closing parenthesis)
        # Process arguments recursively for nested calls
        # Build replacement using the current method name
        args = substr(text, args_start, pos - args_start - 1)
        processed_args = process_text(args)
        result = result "$(call " method_name "," processed_args ")"
    }
    return result }
# Ensure header is printed before any output
# Apply string substitutions (only outside define blocks)
# If we're in a define-endef block, print the line unchanged
# Otherwise, process the line for method call conversion
{ ensure_header(); line = string_substitute($0)
  if (in_define_block) {print $0} else {print process_text(line)} }
endef
define .awk.dispatch
{ while (match($$0, /([[:alnum:]_.]+)\.dispatch\(([^)]+)\)/, arr)) {
    before = substr($$0, 1, RSTART-1); after = substr($$0, RSTART+RLENGTH)
    $$0 = before arr[1] ".dispatch/" arr[2] after
    }
    print }
endef
define .awk.sugar
BEGIN {
 if (ARGC < 3) {
    print "Usage: script.awk open_pattern close_pattern post_process_template" > "/dev/stderr"
    exit 1 }
 open_pattern = ARGV[1]; close_pattern = ARGV[2]
 post_process_template = ARGV[3]
 delete ARGV[1]; delete ARGV[2]; delete ARGV[3]
}
# Look for opening block marker
$0 ~ open_pattern && block_mode == 0 {
 # Extract block name by removing the open pattern and leading/trailing whitespace
 block_name = $0
 sub(open_pattern, "", block_name)
 sub(/^[ \t]+/, "", block_name)
 sub(/[ \t]+$/, "", block_name)
 # Print define header, switch to block mode
 print "define " block_name
 block_mode = 1; next
}

# Look for closing block marker
$0 ~ close_pattern && block_mode == 1 {
 # Print define end, parse remainder of the line after close_pattern
 # Prepare template for substitution
 print "endef"
 remainder = $0; sub(close_pattern, "", remainder); sub(/^[ \t]+/, "", remainder)
 cur_template = post_process_template
 
 # Check for "with ... as ..." pattern, use original substitutions
 if (match(remainder, /^with (.+)\s+as\s+(.+)$/, matches)) {
     # matches[1] is always the with-clause
     # matches[3] is the as-clause (or empty if not present)
     with_clause = matches[1]
     as_clause = matches[2]
     
     # Replace @ with with-clause and _ with as-clause
     gsub(/__WITH__/, with_clause, cur_template)
     gsub(/__AS__/, as_clause, cur_template)
     gsub(/__NAME__/, block_name, cur_template) }
 else { gsub(/__NAME__/, block_name, cur_template); gsub(/__REST__/, remainder, cur_template) }
 
 print cur_template
 # Exit block mode
 block_mode = 0
 next
}
# In block mode, print lines as-is
# Print non-block lines normally when not in block mode
block_mode == 1 { print $0 }
block_mode == 0 { print $0 }
endef

flux.pre/%:
	@# Dispatch pre-hook if one is available
	export CMK_DISABLE_HOOKS=1 \
	&& ${make} -q ${*}.pre > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.mk, flux.pre ${sep} pre-hook found, dispatching ${*}) ; ${make} ${*}.pre ;; \
		1) $(call log.trace, flux.pre ${sep} pre-hook found, dispatching ${*}) ; ${make} ${*}.pre ;; \
		*) $(call log.trace, flux.pre ${sep} no such hook: ${*}.pre); exit 0;; \
	esac
flux.post/%:
	@# Dispatch post-hook if one is available
	export CMK_DISABLE_HOOKS=1 \
	&& ${make} -q ${*}.post > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.mk, flux.post ${sep} post-hook found, dispatching ${*}) ; ${make} ${*}.post;; \
		1) $(call log.trace, flux.post ${sep} post-hook found, dispatching ${*}) ; ${make} ${*}.post;; \
		*) $(call log.trace, flux.post ${sep} no such hook: ${*}.post ${MAKE_CLI}) && exit 0;; \
	esac

define .awk.rewrite.targets.maybe 
{ if ($0 ~ /help/ || $0 ~ /jb/ || $0 ~ /yq/ || $0 ~ /jq/ || $0 ~ /mk.include/ || $0 ~ /loadf/) {
    print $0; next }
  if ($0 ~ /mk.interpret/ ) { print $0; next }
  result = ""
  for (i=1; i<=NF; i++) {
    if ($i ~ /^\./ || $i ~ /\//) {result = result " " $i; continue}
    if (result != "") result = result " "
    result = result "flux.pre/" $i " " $i " flux.post/" $i
  }
  print result }
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## This section accomodates other files that can "cohosted" inside `compose.mk`.
## See the docs[1] for more details. 
## [1] https://robot-wranglers.github.io/compose.mk/demos/packaging#guests-and-payloads

mk.fork/%:
	@# USAGE: ./compose.mk mk.fork/<Makefile>,<composefile>
	@# Like `mk.fork.guest/1st` followed by `mk.fork.services/2nd`
	@#
	${io.mktemp} && outf=$${tmpf} \
	&& ${io.mktemp} && guest=`printf "${*}" | cut -d, -f1` \
	&& $(call log.mk,mk.fork ${sep}${dim} forking guest ${sep} $${guest}) \
	&& ${make} mk.fork.guest/$${guest} > $${tmpf} \
	&& chmod +x $${tmpf} && services=`printf "${*}" | cut -d, -f2-` \
	&& $(call log.mk,mk.fork ${sep}${dim} forking services ${sep} $${services}) \
	&& $${tmpf} mk.fork.services/$${services} > $${outf} \
	&& chmod +x $${outf} \
	&& bin=$${bin:-${CMK_BIN}.fork} \
	&& $(call log.mk,mk.fork ${sep}${dim} ${dim}saving to ${no_ansi}$${bin}) \
	&& mv $${outf} $${bin} 

mk.fork.services: mk.fork.services/-
	@# Like `mk.fork.services`, but with streaming input.
mk.fork.services/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the default services section.
	PREFIX="define SERVICES" POSTFIX="endef" \
	POSTHOOK='$$(call compose.import.string, def=SERVICES import_to_root=TRUE)' \
	CMK_INTERNAL=1 ${make} .mk.fork.section/SERVICES/${*} 

mk.fork.guest: mk.fork.guest/-
	@# Like `mk.fork.guest`, but with streaming input.
mk.fork.guest/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the current "guest" section.
	${io.mktemp} && cat ${*} > $${tmpf} \
	&& (\
		cat $${tmpf} | grep -v '^include compose.mk' \
		&& ( cat $${tmpf} \
			| grep '__main__:' >/dev/null 2>/dev/null \
			&& $(call log.mk,${GLYPH_CHECK} guest comes with __main__)\
			|| ( $(call log.mk,${yellow}__main__ missing in guest) \
				&& printf "__main__: help\n" ))) \
	| CMK_INTERNAL=1 ${make} .mk.fork.section/GUEST/-

mk.fork.payload: mk.fork.payload/-
	@# Like `mk.fork.payload`, but with streaming input.
mk.fork.payload/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the current "guest" section.
	PREFIX="define PAYLOAD" POSTFIX="endef" \
	CMK_INTERNAL=1 ${make} \
		.mk.fork.section/PAYLOAD/${*} 
.mk.fork.section/%:
	true \
	&& section=`printf "${*}" | cut -d/ -f1` \
	&& fname=`printf "${*}" | cut -d/ -f2-` \
	&& case $${fname} in \
		-) fname=/dev/stdin;; \
	esac \
	&& fdata=`cat $${fname}` \
	&& $(call log.mk, mk.fork.section ${sep} ${dim}section=${dim_cyan}$${section} ${sep} ${dim}loading ${bold}$${fname}) \
	&& [ -z "$${shebang:-}" ] \
		&& true || printf "$${shebang}\n" \
	&& cat ${CMK_BIN} \
		| TARGET_SECTION=$${section} \
		PREFIX='$(shell echo "$${PREFIX:-}")' \
		POSTFIX="$${POSTFIX:-}" POSTHOOK=$${POSTHOOK:-} \
		GUEST_DATA="$${fdata}" \
			CMK_INTERNAL=1 ${make} io.awk/.awk.fork.section
define .awk.fork.section
BEGIN { 
    in_target_section = 0
    begin_marker = "# 𒄡 BEGIN " ENVIRON["TARGET_SECTION"]
    end_marker = "# 𒄡 END " ENVIRON["TARGET_SECTION"] }
$0 == begin_marker {
    print $0; print ENVIRON["PREFIX"];print ENVIRON["GUEST_DATA"]
    print ENVIRON["POSTFIX"] "\n"; print ENVIRON["POSTHOOK"] "\n"
    in_target_section = 1; next }
$0 == end_marker {print $0; in_target_section = 0; next }
!in_target_section { print $0 }
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# 𒄡 BEGIN GUEST
# 𒄡 END GUEST
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# 𒄡 BEGIN SERVICES
define SERVICES
endef
# 𒄡 END SERVICES
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# 𒄡 BEGIN PAYLOAD
define PAYLOAD
endef
# 𒄡 END PAYLOAD
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#*/