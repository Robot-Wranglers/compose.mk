#!/usr/bin/env -S bash
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# compose.mk: 
#
# A tool / library / framework for Makefile-based automation, scripting, 
# and lightweight orchestration. Support for docker, docker-compose, workflow
# primitives, TUI elements, and more, all provided by a single file with no 
# dependencies beyond what's already in your development environment.
#
# DOCS: https://github.com/robot-wranglers/compose.mk
# LATEST: https://github.com/robot-wranglers/compose.mk/tree/main/compose.mk
#
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#
# Let's get into the horror and the delight right away with shebang hacks. 
# The block below these comments *looks* like a comment, but it is not. That 
# line and a matching one at EOF makes this file a polyglot, so that it is 
# executable as both a bash script and a Makefile.  This allows for improvement
# around the poor signal-handling that Make supports by default, and several 
# other advanced features like such as short-circuiting `make` from attempting
# to parse the full CLI, and "pre" / "post" targets.  See documentation & usage 
# info here https://github.com/robot-wranglers/compose.mk/signals/, especially 
# re: `mk.interrupt` and `mk.yield`.
#
#/* \
_make_="make -sS --warn-undefined-variables -f ${0}"; export MAKEFLAGS="${MAKEFLAGS:+${MAKEFLAGS} }--no-print-directory"; trace="${TRACE:-${trace:-0}}"; \
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
			0) [ $# -eq 0 ] \
				&& _targets="mk.__main__" \
				|| _targets="$(echo ${@} | awk -f <(sed -n '/^define .awk.rewrite.targets.maybe/,/^endef/{/^define/d;/^endef/d;p}' ${0}))";; \
			1) _targets="${@:-mk.__main__}";; \
		esac; \
		if [ -n "${CMK_BOOTLOADER_DISABLED}" ]; then printf "ᐂ ${sep} \033[93mbootloader disabled (CMK_BOOTLOADER_DISABLED) -- running targets directly\n${no_ansi}" >/dev/stderr; ${_make_} ${_targets}; st=$?; else source <(sed -n '/^define _mk.supervisor.bootloader/,/^endef/{/^define/d;/^endef/d;p}' ${0}); fi; ;; \
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
# --no-print-directory neutralizes an inherited `-w`/print-directory (from the env or an outer
# make): those `Entering/Leaving directory` lines are noise AND corrupt the `awk -f <(${mk.def.read}
# /..)` process-subs (io.awk) by prepending to the awk program.  We keep it in MAKEFLAGS (which
# make auto-exports, so sub-makes inherit the suppression) but STRIP it from MAKE_FLAGS below, so
# it never lands on a recursive `make` command line -- MAKE_CLI is captured from the cmdline and
# the subcommands parser reads it, so an extra flag there would corrupt subcommand resolution.
# The bash-trampoline (top of file) appends it to the ENV MAKEFLAGS for the same reason: it
# suppresses the shebang-launched top make (and an inherited MAKELEVEL>0) without touching cmdline.
MAKEFLAGS:=-s -S --warn-undefined-variables --no-builtin-rules --no-print-directory
.SUFFIXES:
.INTERMEDIATE: .tmp.* .flux.*
export TERM?=xterm-256color
# Host-invariant within a run. Probe ONCE but honor any value already set in the
# environment / on the CLI, via simply-expanded `:=` + `$(or $(value VAR),...)`.
# NB: do NOT write `export VAR ?= $(shell ...)` (recursive) here, because GNU make 4.4+
# passes exported variables into every `$(shell ...)` subshell, so a recursive
# exported probe is re-run for each of compose.mk's hundreds of parse-time $(shell)
# calls (~40x slowdown; detect via the `shell-export` value in $(.FEATURES)). `:=`
# makes the exported value a literal once assigned, so there is nothing to re-run;
# `$(value VAR)` (not `$(VAR)`) reads any preset value WITHOUT tripping
# `--warn-undefined-variables` when it is unset.
export OS_NAME := $(or $(value OS_NAME),$(shell uname -s))
# XDG cache dir for compose.mk's OWN host artifacts (e.g. built helper binaries).  Same `:=` +
# `$(value)` idiom as OS_NAME so the probe runs once.  Honors XDG_CACHE_HOME; override CMK_XDG_CACHE
# to relocate.
export CMK_XDG_CACHE := $(or $(value CMK_XDG_CACHE),$(shell echo "$${XDG_CACHE_HOME:-$${HOME}/.cache}")/compose.mk)

# Pre-declared (?= empty) so native `$(VAR)` reads are safe under
# --warn-undefined-variables, which lets us replace per-parse
# `$(shell echo $${VAR:-default})` subshell forks with native `$(or $(VAR),default)`.
quiet ?=
trace ?=
NO_COLOR ?=
# NB: CMK_DIND is declared+exported later (`export CMK_DIND?=0`); do NOT
# pre-declare it here, since that would make the later `?=` skip and leave CMK_DIND
# empty+unexported, breaking docker-in-docker propagation.

# Color constants and other stuff for formatting user-messages
ifeq ($(NO_COLOR),1) # https://no-color.org/
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
GLYPH_IO=${green}${_GLYPH_IO}${dim_green}
_GLYPH_TUI=${bold}⏣${no_ansi}
GLYPH_TUI=${green}${_GLYPH_TUI}${dim_green}
_GLYPH_FLUX=${bold}Φ${no_ansi}
GLYPH_FLUX=${green}${_GLYPH_FLUX}${dim_green}
GLYPH_DEBUG=${dim}(debug=${no_ansi}${verbose}${dim})${no_ansi}${dim}(quiet=${no_ansi}$(quiet)${dim})${no_ansi}${dim}(trace=${no_ansi}$(trace)${dim})
GLYPH_SPARKLE=✨
GLYPH_CHECK=✔
GLYPH_XXX=${red}✗
GLYPH_SUPER=${green}ᐂ${dim_green}
GLYPH_NUMS=① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩
# NB: native `${1}+1` without a subshell.  `$(words $(wordlist 1,N,LIST) +)` counts
# the first N words plus one extra token, i.e. N+1 (and N=0 -> empty wordlist -> 1).
# Reusing the glyph list as the counting source matches the old subshell arithmetic
# byte-for-byte, including out-of-range (-> empty `$(word)`). Hot path: every log line.
GLYPH.NUM=${dim_green}$(word $(words $(wordlist 1,${1},${GLYPH_NUMS}) +),${GLYPH_NUMS})${no_ansi}
# GLYPH_ARRS=🡨 🡩 🡪 🡫 🡬 🡭 🡮 🡯 🡒 🡑
GLYPH_ARRS=▋ ▊ ▉ █ █ █ █ █ ▏ ▎ ▍
GLYPH.ARRS=${dim_green}$(word $(words $(wordlist 1,${1},${GLYPH_ARRS}) +),${GLYPH_ARRS})${no_ansi}
GLYPH.tree_item:=├┈
GLYPH.tree_last:=╰┈

# FIXME: docs 
# NB: keep this RECURSIVE (`?=`), unlike the OS_NAME/DOCKER_UID/DOCKER_GID probes:
# it is load-bearing for DIND / container-dispatch path resolution, and freezing it to
# the parse-time pwd (`:=`) mangles the in-container `-f`. It also does NOT hit the
# make-4.4 $(shell) blowup in practice (set/inherited before the parse-time storm).
export DOCKER_HOST_WORKSPACE?=$(shell pwd)

ifeq (${OS_NAME},Darwin)
export DOCKER_UID:=0
export DOCKER_GID:=0
export DOCKER_UGNAME:=root
export MAKE_CLI:=$(shell echo `which make` `ps -o args -p $${PPID} | tail -1 | cut -d' ' -f2-`)
else
export DOCKER_UID := $(or $(value DOCKER_UID),$(shell id -u))  # := $(or $(value)): see OS_NAME note (make 4.4 shell-export)
export DOCKER_GID := $(or $(value DOCKER_GID),$(shell getent group docker 2> /dev/null | cut -d: -f3 || id -g))
export DOCKER_UGNAME:=user
export MAKE_CLI:=$(shell \
	( cat /proc/$${PPID}/cmdline 2>/dev/null \
		| tr '\0' ' ' ) ||echo '?')
endif

export MAKE_CLI_EXTRA:=$(shell printf "${MAKE_CLI}"|awk -F' -- ' '{print $$2}')
export MAKEFILE_LIST:=$(call strip,${MAKEFILE_LIST})
# MAKE_FLAGS feeds recursive `make` command lines (and thus MAKE_CLI), so strip the
# env-only `--no-print-directory` here -- it stays in MAKEFLAGS (inherited) for suppression.
export MAKE_FLAGS:=$(shell ( [ `echo ${MAKEFLAGS} | cut -c1` = - ] && echo "${MAKEFLAGS}" || echo "-${MAKEFLAGS}" ) | sed 's/--no-print-directory//g; s/  */ /g; s/ *$$//')
export MAKEFILE?=$(firstword $(MAKEFILE_LIST))
export TRACE?=$(or $(trace),0)
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

## ----------------------------------------------------------------------------
##
## BEGIN: SelfPath
## "Where is compose.mk?" -- several vars answer this, each for a DIFFERENT
## context (they are NOT redundant).  The last few bridge the host<->dispatch-
## container boundary, where a host path is meaningless inside the container.
##
## | name            | what it answers                   |
## |-----------------|-----------------------------------|
## | cmk.self        | host abspath; the source of truth |
## | CMK_SRC         | source to read/include, this proc |
## | CMK_BIN         | invocation path ($0)              |
## | CMK_DOCKER_PATH | where it's mounted in-container   |
## | CMK_DIND_SRC    | include path: host AND container  |
##
## Derived host<->container helpers (detailed below): docker.cmk.mount (the `-v`
## bind), makefile_list.dind / make.dind (the host `-f` rewritten to the mount).
## END: SelfPath
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Implementation notes for each member of the family follow.
# (We use DERIVED vars rather than env-reassigning CMK_* at dispatch because a
# `-f` path is a make CLI arg an env var can't redirect, and CMK_SRC is `=`/not `?=`.)
#
# compose.mk's own absolute path. Resolved by NAME from MAKEFILE_LIST (robust to
# position/order across multiple `-f`/includes; not the naive positional
# `lastword`). Used only to make compose.mk reachable inside dispatch containers
# when it lives OUTSIDE the mounted workspace (i.e. a global / on-PATH install).
cmk.self := $(abspath $(firstword $(filter %compose.mk,$(MAKEFILE_LIST))))
# Canonical location compose.mk is mounted at INSIDE a dispatch container (and is
# on PATH there). Shared by `docker.cmk.mount` (the mount), `makefile_list.dind`
# (the matching `-f` rewrite), and `CMK_DIND_SRC` so they never drift.
CMK_DOCKER_PATH:=/usr/local/bin/compose.mk
# Shared probe for the host<->container path vars below: sets `s` (compose.mk
# abspath), `ws` (the bind-mounted workspace), and `rel` (s relative to ws, == s
# when s is OUTSIDE ws, i.e. a global/on-PATH install). Recursive (=) so `$$`/`${}`
# resolve identically at each use. One definition so the membership test can't drift.
# (The `\#` escapes the shell prefix-strip's `#`; a bare `#` in a make assignment
# would start a comment and truncate the value; inside the old inline `$(shell ..)`
# it didn't need escaping.)
_cmk.ws.probe=s='${cmk.self}'; ws="$${DOCKER_HOST_WORKSPACE:-$$PWD}"; rel="$${s\#$$ws/}"
# Additive dispatch mount: bind the host compose.mk at a canonical on-PATH
# location inside the container, so a project's `include $(shell which
# compose.mk)` resolves there to the identical file/version. Emitted ONLY when
# compose.mk is OUTSIDE ${DOCKER_HOST_WORKSPACE:-${PWD}} (i.e. not already inside
# the workspace mount), so vendored/drop-in dispatch is byte-for-byte
# unchanged (the var expands to empty). Recursive (=) so it honors the
# workspace at dispatch time.
docker.cmk.mount=$(shell ${_cmk.ws.probe}; [ -n "$$s" ] && [ "$$rel" = "$$s" ] && echo "-v $$s:${CMK_DOCKER_PATH}:ro" || true)
# `makefile_list` / `${make}` as they should be invoked INSIDE a dispatch
# container. When compose.mk lives OUTSIDE the workspace (so `docker.cmk.mount` is
# engaged and binds it to ${CMK_DOCKER_PATH}), its host `-f` entry is rewritten to
# that mount path; otherwise the list is unchanged, since a vendored copy resolves via
# the /workspace mount, and a library-mode project Makefile is already inside the
# workspace (and `include $(shell which compose.mk)` finds the mount on PATH).
# This is what lets standalone tools (esp. tux, which dispatches compose.mk's OWN
# targets) work under a global install. (Limit: a global install invoked by a
# *relative* `-f` path won't match `cmk.self` and so won't be rewritten.)
makefile_list.dind=$(if $(strip ${docker.cmk.mount}),$(patsubst -f${cmk.self},-f${CMK_DOCKER_PATH},${makefile_list}),${makefile_list})
make.dind=make ${MAKE_FLAGS} ${makefile_list.dind}
# Path to compose.mk for a generated makefile that is consumed BOTH on the host
# (cwd = workspace) AND inside a dispatch container (cwd = /workspace), e.g. the
# `loadf` makefile, whose panes re-`make` it in the tux container. A vendored copy
# is reachable by its workspace-relative path in both places (same content under
# the host cwd and the /workspace mount); a global/out-of-workspace copy is
# reachable at the ${CMK_DOCKER_PATH} mount inside the container. (NOT `${CMK_SRC}`,
# which is an absolute HOST path that does not exist inside the container.) The name
# matches the other `*.dind` host<->container bridges (it is NOT workspace-relative
# in global mode; it's the mount path). Exported (shell-valid name) so it expands
# in the `loadf` heredoc, where the include is resolved by the shell, like CMK_SRC.
export CMK_DIND_SRC=$(shell ${_cmk.ws.probe}; if [ "$$rel" = "$$s" ]; then echo "${CMK_DOCKER_PATH}"; else echo "$$rel"; fi)

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

# mk.var.*: parse-time predicates over a NAMED variable's $(origin).  Distinct from the shell-level
# mk.ifdef/mk.ifndef (which grep .VARIABLES at recipe time); these expand during make parsing.
# $(strip) absorbs the leading space $(call) leaves on args.
# CAVEAT: mk.var.or / mk.var.opt EAGERLY expand their default (a $(call) arg), so use them only when
# the default is side-effect-free.  When the default holds $(shell)/$(error), keep an explicit $(if)
# and use the mk.var.defined / mk.var.undefined PREDICATES inside it (lazy -- the default is not
# expanded unless taken).
mk.var.defined=$(filter-out undefined,$(origin $(strip ${1})))
mk.var.undefined=$(filter undefined,$(origin $(strip ${1})))
mk.var.or=$(if $(call mk.var.defined,${1}),$($(strip ${1})),${2})
mk.var.opt=$(call mk.var.or,${1},)
mk.var.from.invoker=$(or $(findstring environment,$(origin $(strip ${1}))),$(findstring command,$(origin $(strip ${1}))))

# Returns "-x" iff trace is enabled.  (This is used with calls to bash/sh to show the command)
dash_x_maybe:=`[ $${TRACE} == 1 ] && echo -x || true`
export HOSTNAME?=$(shell hostname)
GLYPH_HOSTNAME= ${bold}[${no_ansi_dim}${ital}$${HOSTNAME}${no_ansi}${bold}]${no_ansi}
trace_maybe=[ "${TRACE}" == 1 ] && set -x || true 
log.prefix.makelevel.glyph=${dim}$(call GLYPH.NUM, ${MAKELEVEL})${no_ansi}
log.prefix.makelevel.glyph=${dim}$(call GLYPH.NUM, ${MAKELEVEL})
log.prefix.makelevel.indent=
log.prefix.makelevel=${log.prefix.makelevel.glyph} ${log.prefix.makelevel.indent}
log.prefix.loop.inner=${log.prefix.makelevel}${bold}${dim_green}${GLYPH.tree_item}${no_ansi}
log.prefix.loop.last=${log.prefix.makelevel}${bold}${dim_green}${GLYPH.tree_last}${no_ansi}
log.stdout=printf "${log.prefix.makelevel} $(strip $(if $(filter undefined,$(origin 1)),...,$(1))) ${no_ansi}\n"
log=([ "$(or $(quiet),0)" == "1" ] || ( ${log.stdout} >${stderr} ))
log.json=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.docker} ${1} | ${jq.run} . | ${stream.as.log}
log.json.min=$(call log, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.docker} ${1} | ${jq.run} -c . | ${stream.as.log}
log.target=$(call log.io, ${dim_green}$(strip $(shell printf "${@}" | cut -d/ -f1)) ${sep}${dim_ital} $(strip $(or $(strip $(if $(filter undefined,$(origin 1)),,$(1))),$(shell printf "${@}" | cut -d/ -f2-))))
log.target.pad_top=printf '\n' >> /dev/stderr; ${log.target}
log.target.pad_bottom=${log.target}; printf '\n'>>/dev/stderr
log.target.part1=([ -z "$${quiet:-}" ] && (printf "${log.prefix.makelevel}${GLYPH_IO}${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep}${dim_ital} `echo "$(strip $(or $(1),))"| ${stream.lstrip}`${no_ansi_dim}..${no_ansi}") || true )>${stderr}
log.target.part2=([ -z "$${quiet:-}" ] && $(call log.part2, ${1}))
log.test_case=$(call log.io, ${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep} ${dim}..\n  ${cyan_flow_right}${dim_ital_cyan}$(or $(1),$(shell printf "${@}" | cut -d/ -f2-)))
log.test=${log.test_case}
log.trace=[ "${TRACE}" == "0" ] && true || (printf "${log.prefix.makelevel}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr} )
log.trace.fmt=( ${log.trace} && [ "${TRACE}" == "0" ] && true || (printf "${2}" | fmt -w 70 | ${stream.indent.to.stderr} ) )
log.trace.part1=[ "${TRACE}" == "0" ] && true || $(call log.part1, ${1})
log.trace.part2=[ "${TRACE}" == "0" ] && true || $(call log.part2, ${1})
log.target.rerouting=$(call log, ${dim}${_GLYPH_IO}${dim} $(shell echo ${@} | sed 's/\/.*//') ${sep}${dim} Invoked from top; rerouting to tool-container)
log.file.contents=$(call log.target, file=$(strip ${1})) && cat ${1} | ${stream.as.log}
log.preview.file=$(call log.target, ${cyan}$(strip ${1})) ; $(call io.preview.file, ${1})
log.compiler=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log, ${GLYPH_MK} ${1}))
# Conditional compiler log: emit ${2} only when ${1} (a shell string) has non-whitespace
# content -- i.e. "log this value only when it was actually set".  Both gates apply (silent
# if CMK_COMPILER_VERBOSE=0 OR ${1} is empty/blank).  The case-glob tests the RUNTIME value,
# so it tolerates the leading space `$(call ..)` leaves on the argument.  Always succeeds.
log.compiler.maybe=( case "${1}" in *[![:space:]]*) $(call log.compiler, ${2}) ;; esac )
# Compiler log with a folded+indented body: header ${1} on its own line, then ${2}
# word-wrapped and indented beneath it (cf. log.trace.fmt).  Verbose-gated; ${2} must
# be comma-free (it is the $(call) 2nd arg).
log.compiler.fmt=( $(call log.compiler, ${1}) && ( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || ( printf '%b\n' "${2}" | fmt -w 64 | sed 's/^/    /' | ${stream.indent.to.stderr} ) ) )
log.docker=$(call log, ${GLYPH.DOCKER} ${1})
log.flux=$(call log, ${GLYPH_FLUX} ${1})
log.io=$(call log,${GLYPH_IO} $(1))
log.mk=$(call log, ${GLYPH_MK} ${1})
log.tux=$(call log,${GLYPH_TUI} $(1))

# Loggers used at module level.
export CMK_LOG_IMPORTS?=0
log.import=$$(shell [ $${CMK_LOG_IMPORTS} == 0 ] || $$(call \
	log.mk, ${GLYPH_MK} ${dim}__import__ $${sep}$${dim} ${1}))
log.import.part1=$$(shell [ $${CMK_LOG_IMPORTS} == 0 ] || $$(call \
	log.part1, ${GLYPH_MK} ${dim}__import__  $${sep}$${dim} ${1}))
log.import.part2=$$(shell [ $${CMK_LOG_IMPORTS} == 0 ] || $$(call log.part2, ${1}))
log.import.error=$$(shell $$(call \
	log.mk, ${red}${GLYPH_MK} ${dim}__import__ $${sep}$${dim} ${1}))
# log.import.deprecated(<old>[,<new>]) -- yellow parse-time DEPRECATION notice.
# Unlike the gated loggers above it ALWAYS shows (a deprecation must be seen), and
# uses SINGLE `$(shell)` -- callers expand it DIRECTLY (in a recursive macro body),
# not via `$(eval)`.  <new> names the replacement to steer users toward.
log.import.deprecated=$(shell $(call log.mk, ${yellow}${1}${no_ansi}${dim_ital} is deprecated$(if $(strip ${2}), ${sep}${dim_ital} use ${no_ansi}${2}${dim_ital} instead)${no_ansi}))

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
define log.loop.item.last # Call this for the FINAL item (terminator glyph)
 ( printf "${log.prefix.loop.last}`echo "$(or $(1),)" | sed 's/^ //'`${no_ansi}\n" > ${stderr} )
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
log.compiler.part1=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.part1, ${GLYPH_MK} ${1}))
log.compiler.part2=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.part2, ${1}))

# Completely silent output iff quiet is set and quiet!=0
quiet.maybe=$(shell [ "$${quiet:-0}" == "0" ] && echo '' || echo '> /dev/null 2>/dev/null' )

define _compose_quiet
2> >( grep -vE \
		'.*Container.*(Running|Recreate|Created|Starting|Started)' >&2 \
	  | grep -vE '.*Network.*(Creating|Created)' >&2 )
endef
docker.run.base:=docker run --rm -i -v $${DOCKER_HOST_WORKSPACE:-$${PWD}}:/workspace -w/workspace

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Environment Variables
##
## Variables used internally:
##
## | Variable               | Meaning                                                               |
## | ---------------------- | ----------------------------------------------------------------------|
## | CMK_COMPOSE_FILE       | *Temporary file used for the embedded-TUI*                            |
## | CMK_LOG_IMPORTS        | Defaults is 0.  Controls module-level logging                         |
## | CMK_PLUGINS_DIR        | ':'-separated plugin search PATH for `include.plugin`; default ".cmk"|
## | CMK_MODULES_DIR        | Single writable staging dir (1st CMK_PLUGINS_DIR element by default)|
## | CMK_XDG_CACHE          | XDG cache dir for compose.mk host artifacts (built binaries, etc)      |
## | CMK_COMPILER_VERBOSE   | 1 if debugging-messages from compilation are allowed                  |
## | CMK_DIND               | *Determines whether docker-in-docker is allowed*                      |
## | CMK_SRC:               | path to compose.mk source to READ/include (standalone==cmk.self)      |
## | cmk.self               | compose.mk's host ABSPATH (single source of truth for the above)      |
## | CMK_BIN                | compose.mk's INVOCATION/exe path ($0); backs __interpreter__ + fork   |
## | CMK_DOCKER_PATH        | where compose.mk is mounted INSIDE a dispatch container (on PATH)     |
## | CMK_DIND_SRC           | compose.mk include-path for a makefile run on host AND in-container   |
## | CMK_SUPERVISOR         | *1 if supervisor/signals is enabled, otherwise 0*                     |
## | DOCKER_HOST_WORKSPACE  | *Needs override for correctly working with DIND volumes*              |
## | TRACE                  | 1 if increase in verbosity desired (more detailed than verbose)       |
## | trace                  | alias for setting TRACE. very noisy! this appends '-x' to most shell invocations ) |
## | verbose                | 1 if debugging output should be shown, otherwise 0 (affects CMK internal logging ) |
## | quiet                  | 0 if debugging output should be shown, otherwise 1 (affects docker build output) |
## | force                  | 0 if operation should not be forced, otherwise 1 (affects docker pulls, etc) |
## | __file__               | val of CMK_SRC if stand-alone mode, invoked file if in library mode   |
## | __interpreter__        | invocation path; defaults to ${CMK_BIN} unless overridden             |
## | __interpreting__       | CMK_SRC unless overridden; sometimes useful for extensions            |
##
## **`CMK_INTERNAL`** -- 1 if the runtime is dispatched inside a container,
## otherwise 0.  Setting it explicitly (rather than auto-detecting) controls
## whether DIND is enabled and no-ops all `compose.import`s -- an optimization.
##
## **Other Variables:**
##
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
_docker_quiet_flag=-q
ifeq ($(quiet), 0)
_docker_quiet_flag=
endif

export CMK_INTERNAL?=0
#export CMK_SRC:=$(filter %compose.mk,${MAKEFILE_LIST})
export CMK_SRC:=$(or $(filter %compose.mk,${MAKEFILE_LIST}),${MAKEFILE})
export CMK_BIN?=${CMK_SRC}
# `__interpreter__` is the invocation path (== CMK_BIN == ${0}); the old shell form
# rebuilt it as dirname/basename of CMK_SRC (relative in the top parse) and then
# rode the env-override through sub-makes. `?= ${CMK_BIN}` yields the identical
# value with no sh/dirname/basename fork per re-parse, and still honors a
# caller-supplied __interpreter__ (env wins) + inherits into sub-makes.
export __interpreter__ ?= ${CMK_BIN}
export CMK_SUPERVISOR?=1
export CMK_EXTRA_REPO?=.
export GITHUB_ACTIONS?=false
export __interpreting__?=

# _mk.run.id: the per-run suffix shared by `.tmp.*` scratch names -- the supervisor pid
# (MAKE_SUPER) when supervised (chosen natively, no fork), else a fresh uuid/timestamp.  The
# $(if) is deliberately kept (not mk.var.or) so the fallback `$(shell)` is expanded ONLY when
# MAKE_SUPER is unset -- under a supervisor it never forks.
_mk.run.id=$(if $(call mk.var.defined,MAKE_SUPER),${MAKE_SUPER},$(shell uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N))

# The default backing-file for the argless `io.stack`/`io.stack.push`/
# `io.stack.pop`. Suffixed so one invocation's whole process tree shares a stack
# while separate invocations stay isolated. The suffix is the supervisor pid
# (MAKE_SUPER) when there is one (chosen natively via `$(origin)`, no fork),
# else a uuid, else a timestamp. We only compute it (and `export`) when nothing
# upstream already set it: a recursive sub-make inherits the parent's value from
# the environment (origin != undefined -> the `ifeq` is skipped, no recompute),
# and a command-line override is respected the same way. `:=` (not `?=`) is
# deliberate: it freezes the value once per top-level process, so the fallback
# `$(shell)` runs at most once and every expansion is byte-stable (a recursive
# `?=` would re-fork the uuid on every reference).
#
# Container dispatch forwards this var by default (see `docker.env.standard` and
# `docker.compose.run`): since the workspace is bind-mounted at the same relative
# path, an in-container `make` inherits the host's name (origin=environment ->
# honored, not recomputed) and reads/writes the SAME stack file as the host.
ifeq ($(origin CMK_IO_STACK),undefined)
export CMK_IO_STACK := .tmp.cmk.stack.${_mk.run.id}
endif

# Run-id-keyed prefix for `⬥` file-blockref tmpfiles (see `_mk.def.tmpfile`).  Mirrors
# CMK_IO_STACK: local `.tmp.*` name, exported so container dispatch forwards it (the
# workspace is bind-mounted at the same relative path, so the host can sweep files an
# in-container submake wrote).  Swept at end-of-run by the supervisor teardown (top of
# file); `mk.clean` and `.INTERMEDIATE: .tmp.*` are backstops.
ifeq ($(origin CMK_BRF_PREFIX),undefined)
export CMK_BRF_PREFIX := .tmp.cmk.brf.${_mk.run.id}
endif

##
export __script__?=None
# Common default so `__file__` is ALWAYS defined -- the CMK_STANDALONE branch
# (e.g. the `make -f compose.mk … mk.compile` sub-make used to stage a module)
# otherwise leaves it unset, which trips `--warn-undefined-variables` and feeds
# an empty value to the `jb` context-block builder in `mk.src`.  The CMK_LIB
# branch still overrides it to `${__interpreting__}` when interpreting.
export __file__?=$(word 1, $(MAKEFILE_LIST))
.DEFAULT_GOAL:=__main__

ifneq ($(findstring compose.mk, ${MAKE_CLI}),)
export CMK_LIB=0
export CMK_STANDALONE=1
# Resolve to the REAL invoked path (absolute), not the bare `findstring` which
# loses it, so mk.interpret's `cat ${CMK_SRC}` works under a global/on-PATH
# install (run from a dir with no local copy). cmk.self is the name-resolved
# abspath; fall back to the old findstring if it's somehow empty.
export CMK_SRC=$(or ${cmk.self},$(findstring compose.mk, ${MAKE_CLI}))

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
IMG_NUSHELL?=ghcr.io/nushell/nushell:latest-alpine
IMG_IMGROT?=robotwranglers/imgrot:07abe6a
IMG_MONCHO_DRY=moncho/dry@sha256:6fb450454318e9cdc227e2709ee3458c252d5bd3072af226a6a7f707579b2ddd

# Used internally.  If this is container-dispatch and DIND,
# then DOCKER_HOST_WORKSPACE should be treated carefully
ifeq ($(or $(CMK_DIND),0), 1)
export workspace?=$(shell echo ${DOCKER_HOST_WORKSPACE})
export CMK_INTERNAL=0
endif

docker.env.standard=-e DOCKER_HOST_WORKSPACE=$${DOCKER_HOST_WORKSPACE:-$${PWD}} -e TERM=$${TERM:-xterm} -e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE} -e CMK_IO_STACK=$${CMK_IO_STACK}

ifeq (${TRACE},1)
$(shell printf "trace=$${TRACE} quiet=$${quiet} verbose=$${verbose:-} ${yellow}CMK_INTERNAL=$${CMK_INTERNAL} CMK_DIND=$${CMK_DIND} ${MAKE_CLI}${no_ansi}\n" > /dev/stderr)
endif 

# External tool used for parsing Makefile metadata
MKPARSE_IMG?=ghcr.io/mattvonrocketstein/mk.parse:latest
mkparse=$(trace_maybe) && ${docker.run.base} ${MKPARSE_IMG} $${subcommand:-targets} $${mkparse_args:-}

# Macros for use with jq/yq/jb, using local tools if available and falling back to dockerized versions
jq.docker=${docker.run.base} -e key=$${key:-} ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}
yq.docker=${docker.run.base} -e key=$${key:-} mikefarah/yq:$${YQ_VERSION:-4.43.1}
# Memoized-lazy (was `:=`, which ran `which jq` + `which yq` on EVERY parse: 4
# probes per parse, paid by all ~20 compile re-parses that never use jq/yq). Each
# resolves at most once per process, only when actually expanded. On any host with
# jq/yq on PATH (all CI/test envs) the cached value is byte-identical to the old
# `:=` result; the only difference is on docker-fallback hosts, where the fallback
# string's `$${key:-}`/version interpolate at first-use rather than parse (key was
# already baked empty at parse, and is never set before a jq/yq use in-tree).
_yq.run.detect=$(shell which yq 2>/dev/null || echo "${yq.docker}")
_jq.run.detect=$(shell which jq 2>/dev/null || echo "${jq.docker}")
_jq.run.pipe.detect=$(shell which jq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} ghcr.io/jqlang/jq:$${JQ_VERSION:-1.7.1}")
_yq.run.pipe.detect=$(shell which yq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} mikefarah/yq:$${YQ_VERSION:-4.43.1}")
_yq.run.cached:=
_jq.run.cached:=
_jq.run.pipe.cached:=
_yq.run.pipe.cached:=
yq.run=$(or ${_yq.run.cached},$(eval _yq.run.cached:=${_yq.run.detect})${_yq.run.cached})
jq.run=$(or ${_jq.run.cached},$(eval _jq.run.cached:=${_jq.run.detect})${_jq.run.cached})
jq.run.pipe=$(or ${_jq.run.pipe.cached},$(eval _jq.run.pipe.cached:=${_jq.run.pipe.detect})${_jq.run.pipe.cached})
yq.run.pipe=$(or ${_yq.run.pipe.cached},$(eval _yq.run.pipe.cached:=${_yq.run.pipe.detect})${_yq.run.pipe.cached})
jb.docker:=docker container run $${docker_extra:-} --rm  ghcr.io/h4l/json.bash/jb:$${JB_CLI_VERSION:-0.2.2}
jb.array=docker_extra="$${docker_extra:-} --entrypoint jb-array"; ${jb.docker} 
jb=${jb.docker}
json.from=${jb}
jq=${jq.run}
jq.slurp.nonempty=${jq} -s '[.[] | select(length > 0)]'
yq=${yq.run}

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
	@# Generate (and validate, once) the embedded-TUI compose file. It's cached:
	@# the recipe is a no-op when the file already exists, so validation runs only
	@# at generation time, not on every `tux.require`/`tux.open`/`loadf` bootstrap.
	ls ${CMK_COMPOSE_FILE} 2>/dev/null >/dev/null \
	|| ( verbose=0 ${mk.def.to.file}/FILE.TUX_COMPOSE,${CMK_COMPOSE_FILE} \
		&& ${make} compose.validate.quiet/${CMK_COMPOSE_FILE} )

compose.build/%:
	@# Builds all services for the given compose file.
	@# This optionally runs for just the given service, otherwise on all services.
	@#
	@# USAGE:
	@#   ./compose.mk compose.build/<compose_file>
	@#   svc=<svc_name> ./compose.mk compose.build/<compose_file>
	@#
	$(call log.docker, \
		${compose.ctx.display_profile} ${bold_cyan}build ${sep} ${dim_ital}$${svc:-all services})
	label='build finished.' ${make} flux.timer/.compose.build/${*}
.compose.build/%:
	case $${force:-0} in \
		""|0) force='';; \
		*) force='--no-cache' ;; \
	esac \
	&& case $${quiet:-0} in \
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
		${compose.ctx.display} ${bold_cyan}compose.clean ${dim} ${sep} ${dim_ital}$${svc:-all services}) \
	&& ${docker.compose} -f ${*} \
		--progress quiet down -t 1 --remove-orphans --rmi local $${svc:-}

# Single chokepoint for "run a one-off command in a compose service". Applies
# --rm/--remove-orphans + the global-install compose.mk mount (docker.cmk.mount)
# in exactly ONE place, so every caller (compose.dispatch.sh and all the tux.*
# container runs) stays consistent instead of hand-rolling its own `docker
# compose run`. Inputs (shell env): compose_file, svc, entrypoint (=bash),
# compose_env (extra `-e ..` flags), compose_run_flags (e.g. `-T`). Callers append
# their own tail (`-c "$cmd"` / `-i`) plus ${dash_x_maybe} and $(_compose_quiet).
docker.compose.run=${docker.compose} $${COMPOSE_EXTRA_ARGS} -f $${compose_file} run $${compose_run_flags:-} --rm --remove-orphans ${docker.cmk.mount} -e CMK_IO_STACK=$${CMK_IO_STACK} $${compose_env:-} --entrypoint $${entrypoint:-bash} $${svc}
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
	&& compose_file="${*}" \
	&& ${docker.compose.run} ${dash_x_maybe} \
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
	&& $(call io.mktemp) \
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

compose.require:; docker info --format json | ${jq} -e '.ClientInfo.Plugins[]|select(.Name=="compose")'
	@# Asserts that docker compose is available.

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

# Memoized-lazy: the `docker compose` availability probe runs at most once per
# process, and only when `${docker.compose}` is actually expanded (a docker /
# compose / TUI target), never on the compile/interpret/flux hot path, which
# re-parses this file ~20x and used to pay this probe on every parse. The cached
# value is byte-identical to the old `:=` result (availability is process-stable).
_docker.compose.detect=$(shell docker compose >/dev/null 2>/dev/null && echo docker compose || echo echo DOCKER-COMPOSE-MISSING)
# Pre-declared empty so the first `$(or ...)` read is of a *defined* var (keeps
# `--warn-undefined-variables` quiet); the eval below rewrites it on first use.
_docker.compose.cached:=
docker.compose=$(or ${_docker.compose.cached},$(eval _docker.compose.cached:=${_docker.compose.detect})${_docker.compose.cached})

docker.containers.all:=docker ps --format json

mk.docker.clean:
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
	$(call assert.env, img)
	docker inspect $${img} --format='{{.Config.Entrypoint}}'

docker.image.sizes:; ${make} docker.size.summary | ${jq.column.zipper}
	@# Shows disk-size summaries for all images. 
	@# Returns JSON like `{ "repo:tag" : "human friendly size" }`
	@# See `docker.size.summary` for similar column-oriented output
	
# docker.image.stop/%:; img=${*} ${make} docker.image.stop
docker.image.stop:
	@# Stops one or more running instances launched from given image.
	$(call assert.env, img)
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
	$(call assert.env, tag)
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
			|  ${jq.run} ".[]|select(.Name==\"$${ctx}\")" -r; ;; \
		*) \
			${make} docker.context \
			| ${jq.run} ".[]|select(.Name==\"${*}\")" -r; ;; \
	esac

# Content hash (md5) of a Dockerfile define-block's rendered text.  Used to bust
# the build cache when a def changes but its tag/name does not.  Arg 1 is the bare
# name (the `Dockerfile.` prefix is added), matching `Dockerfile.build/<name>`.
docker.def.sha=${mk.def.read}/Dockerfile.$(strip ${1}) | md5sum | cut -d' ' -f1

docker.def.is.cached/%:
	@# Answers whether the named define has an up-to-date cached docker image.
	@#
	@# "Up-to-date" means an image exists *and* its recorded def-content hash
	@# (the `compose.mk.def.sha` label, stamped by `Dockerfile.build`) matches the
	@# current text of `Dockerfile.<name>`, so editing the def busts the cache
	@# even though the tag is unchanged, and a stale same-named tag from an
	@# unrelated build never counts as cached.
	@#
	@# This never fails; it echoes "yes" or "no".  It honors 'force=1' (always
	@# "no").  The image tag inspected is `$${tag}` if set, else `compose.mk:<name>`;
	@# the wanted hash is `$${want}` if set, else computed from the def.
	@#
	header="${GLYPH.DOCKER} ${no_ansi_dim} Checking if ${dim_cyan}${ital}${*}${no_ansi_dim} is cached" \
	&& $(call log.trace.part1, $${header} ) \
	&& img_tag="$${tag:-compose.mk:${*}}" \
	&& if [ -z "$${want:-}" ]; then want=`$(call docker.def.sha,${*})`; fi \
	&& have=`docker image inspect "$${img_tag}" --format '{{ index .Config.Labels "compose.mk.def.sha" }}' 2>/dev/null || true` \
	&& case $${force:-0} in \
		1) $(call log.trace.part2, ${yellow}no${no_ansi_dim} (force is set)) && echo no && exit 0;; \
	esac \
	&& if [ -n "$${want}" ] && [ "$${have}" = "$${want}" ]; then \
		$(call log.trace.part2, ${dim_green}yes) && echo yes; \
	else \
		$(call log.trace.part2, ${yellow}no${no_ansi_dim} (def changed or missing)) && echo no; \
	fi
docker.def.run/%:; ${make} docker.from.def/${*} docker.dispatch/${*}
	@# Builds, then runs the docker-container for the given define-block
	@#
docker.def.start/% docker.start.def/%:; ${make} docker.from.def/${*} docker.start/compose.mk:${*}
	@# Starts a container represented by named define-block.
	@# (This is like docker.run.def but assumes default entrypoint)
	@#

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
		cmd="${MAKE_FLAGS} ${makefile_list.dind} ${*}" \
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

docker.image.run=${make} docker.image.run
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
	compose_version="`${docker.compose} version`" \
	; $(call log.docker, ${@} ${sep} ${no_ansi_dim} version ${sep} ${ital}$${compose_version}${no_ansi})

docker.lambda/%:
	@# Similar to `docker.def.run`, but eschews usage of tags 
	@# and rebuilds implicitly on every single invocation. 
	@#
	@# Note that technically, this is still caching and 
	@# still actually  involves tags, but the tags are naked SHAs.
	@#
	entrypoint=`if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi` \
	&& cmd=`if [ -z "$${cmd:-}" ]; then echo ""; else echo "$${cmd:-true}"; fi` \
	&& sha=`docker build -q $${docker_args:-} - <<< $$(${make} mk.def.read/Dockerfile.${*})` \
	&& docker run -i $${entrypoint} \
		${docker.env.standard} \
		-v $${workspace:-$${PWD}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		-w /workspace --rm $${docker_args:-} $${sha} $${cmd}

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
docker.logs.follow/:; $(call log.docker, docker.logs.follow ${sep} ${yellow}No container ID to get logs from.)
	@# Error handler, only called when `docker.ps` output was null
docker.logs.timeout/%:
	@# Like docker.logs.follow, but times out after the given number of seconds.
	@# USAGE: `docker.logs.timeout/<timeout_in_seconds>,<id>`
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
	&& sha=`$(call docker.def.sha,$${inp})` \
	&& header="${GLYPH.DOCKER} Dockerfile.build ${sep} ${dim_cyan}${ital}$${def_name}${no_ansi_dim}" \
	&& $(call log.trace, $${header} ) \
	&& $(trace_maybe) \
	&& case `tag=$${tag} want=$${sha} ${make} docker.def.is.cached/$${inp}` in \
		yes) true;; \
		no) ( $(call io.mktemp) && ${mk.def.to.file}/$${def_name},$${tmpf} \
			  && $(call log.docker, $(shell echo ${@}|cut -d/ -f1) \
					${sep} ${ital}${dim_cyan}$(shell echo ${@}|cut -d/ -f2) ${sep} ${dim}tag=${no_ansi}$${tag}${no_ansi_dim}) \
				&& cat $${tmpf} | ${stream.as.log} \
				&& $(call log, ${cyan_flow_right} ${bold}Building..) \
				&& docker_args="--label compose.mk.def.sha=$${sha} $${docker_args:-}" tag=$${tag} ${make} docker.build/$${tmpf} ); ;; \
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
	&& ( $(call log.target.part2, already cached) &&  exit 0 )\
	|| ( $(call log.target.part2, ${yellow}not cached) \
		&& $(call log.target.part1, building) \
		&& $(call log.target.part2,\n${cyan_flow_right} ${dim_ital}$${url}) \
		&& ${trace_maybe} \
		&& docker build ${_docker_quiet_flag} -t compose.mk:$${tag} $${url})

docker.help: mk.namespace.filter/docker.
	@# Lists only the targets available under the 'docker' namespace.

docker.network.panic:; docker network prune -f
	@# Runs 'docker network prune' for the entire system.
docker.network.connect/%:; $(call bind.posargs) && ${trace_maybe} && docker network connect $${_1st} $${_2nd}
	@# USAGE: ./compose.mk docker.network.connect/net1,net2

docker.panic: docker.stop.all docker.network.panic docker.volume.prune docker.system.prune; set -x && docker rm -f $$(docker ps -qa | tr '\n' ' ') 2>/dev/null || true
	@# Debugging only!  This is good for ensuring a clean environment,
	@# but running this from automation will nix your cache of downloaded
	@# images, and then you will probably quickly hit rate-limiting at dockerhub.
	@# It tears down volumes and networks also, so you do not want to run this in prod.
	@#

docker.prune docker.system.prune:; $(call log.target) && set -x && docker system prune --all --force
	@# Debugging only! Runs 'docker system prune' for the entire system.
	@# 

docker.prune.old: flux.timer/.docker.prune.old
	@# Debugging only! Runs 'docker system prune --all --force --filter "until="'
.docker.prune.old:; docker system prune --all --force --filter "until=$${docker_max_age:-168h}"

docker.ps:; docker ps --format json | ${jq} .
	@# Like 'docker ps', but always returns JSON.

docker.rmi:
	@# Removes images with `docker rmi`.  Must provide `img` in environment.
	force=`case $${force:-} in 1) echo '--force';; *) echo ;; esac` \
	&& set -x && docker rmi $${force} $${img} 2>/dev/null|| true

docker.rmi/%:; img=${*} ${make} docker.rmi
	@# USAGE: Shortcut for `docker rmi ..` 
	
docker.run.def:
	@# Treats the named define-block as a script, then runs it inside the given container.
	@#
	@# USAGE:
	@#  entrypoint=<entry> def=<def_name> img=<image> ./compose.mk docker.run.def
	@#
	true \
	&& $(call log.docker, docker.run.def ${no_ansi}${sep} ${dim_cyan}${ital}$${def}${no_ansi} ${sep} ${bold}${underline}$${img}) \
	&& case $${docker_args:-} in \
		"") true;; \
		*) quiet=$${quiet:-0};; \
	esac \
	&& $(call io.mktemp) \
	&& ${make} mk.def.to.file/$${def},$${tmpf} \
	&& (script_pre="$${cmd:-}" \
		&& unset cmd \
		&& script="$${script_pre} $${tmpf}" \
			img=$${img} ${make} docker.run.sh) \
	${stderr_stdout_indent}

docker.run.sh:
	@# Runs the given command inside the named container.  Also available as a macro.
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
	&& tty=`[ -z $${tty:-} ] && echo \`${io.tty.stdin} && echo "-t"|| true\` || echo "-t"` \
	&& cmd_args="\
		--rm -i $${tty} $${extra_env} \
		$${hostname} \
		-e CMK_INTERNAL=1 \
		${docker.env.standard} \
		-v $${workspace:-$${PWD}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		${docker.cmk.mount} \
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


docker.run/% docker.start/%:; img="${*}" entrypoint=none ${make} docker.run.sh
	@# Starts the named docker image with the default entrypoint
	@# USAGE: 
	@#   ./compose.mk docker.start/<img>

docker.start:; ${make} docker.start/$${img}
	@# Like 'docker.run', but uses the default entrypoint.
	@# USAGE: 
	@#   img=.. ./compose.mk docker.start
docker.start.tty:; tty=1 ${make} docker.start
	@# Like `docker.start`, but sets tty=1
docker.start.tty/%:; tty=1 ${make} docker.start/${*}
	@# Like `docker.start/..`, but sets tty=1

docker.socket:; ${make} docker.context/current | ${jq.run} -r .Endpoints.docker.Host
	@# Returns the docker socket in use for the current docker context.
	@# No arguments & pipe-friendly.

docker.stat: 
	@# Show information about docker-status,
	@# Includes version details for docker, docker-compose, container-count, 
	@# docker socket, docker-related environment variables.
	@# No arguments. Pipe-friendly.
	@#
	which docker >/dev/null 2>/dev/null \
		&& CMK_INTERNAL=1 ${make} .docker.stat \
		|| ($(call log.target, ${red}WARNING: Docker is missing!); printf "{}\n")
.docker.stat:
	$(call io.mktemp) \
	&& ${make} docker.context/current > $${tmpf} \
	&& $(call log.docker, ${@}) \
	&& export env="`${make} io.env.json/DOCKER`" \
	&& export docker_extra="-e env " \
	&& ${jb} \
		docker_bin=`which docker` \
		docker_version="`\
			docker --version | sed 's/Docker " //' | cut -d, -f1|cut -d' ' -f3`" \
		compose_version="`${docker.compose} version \
			|sed 's/Docker Compose version v//'||echo '?'`" \
		container_count="`\
			docker ps --format json \
				| ${jq.run} '.Names' | ${stream.count.lines}`" \
		socket="`cat $${tmpf} | ${jq.run} -r .Endpoints.docker.Host`" \
		context_name="`cat $${tmpf} | ${jq.run} -r .Name`" \
		@env:raw \
	| ${jq} .

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
	&& $(call log.target.part1, ) && $(call log.target.part2, ${yellow}$${count}${no_ansi_dim} containers total) \
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
io.mktempd=export tmpd=$$(mktemp -u ./.tmp.XXXXXXXXX$${suffix:-}) && trap 'rm -rf -- "$$tmpd"' EXIT
else
col_b=col
io.mktemp=export tmpf=$$(TMPDIR=`pwd` mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
# Similar to io.mktemp, but returns a directory.
io.mktempd=export tmpd=$$(TMPDIR=`pwd` mktemp -d ./.tmp.XXXXXXXXX$${suffix:-}) && trap 'rm -rf -- "$$tmpd"' EXIT
endif

# io.safe_rm(<path>) -- `rm -f` ONE path safely:
#   - `--` ends options, so a leading `-` can't become a flag,
#   - the double-quotes stop word-splitting and globbing,
#   - `-f` makes a missing path a no-op (so it is set-e safe).
# NB: for an UNTRUSTED path, pass a SHELL var -- `$(call
# io.safe_rm,$$f)` expands to `rm -f -- "$f"`, so the shell reads
# the value literally (no re-parse of an embedded `$(...)`/`;`).
# A make-interpolated value is only quote-safe (a literal
# `$(...)` inside it would still expand within the quotes).
# WARNING: NOT for globs -- the quotes make the pattern literal.
io.safe_rm=rm -f -- "$(1)"
define _io.mktemp
$(call mk.unpack.kwargs, $(strip $(if $(filter undefined,$(origin 1)),,$(1))), var, tmpf) 
${io.mktemp} && ${kwargs_var}=$${tmpf}
endef

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
io.bash:; bash
	@# Starts an interactive shell with the same environment as this Makefile
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
	bash -i </dev/tty >/dev/tty 2>&1

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
io.browser/%:; url="`CMK_INTERNAL=1 ${make} mk.get/${*}`" ${make} io.browser
	@# Like `io.browser`, but accepts a variable-name as an argument.
	@# Variable will be dereferenced and stored as 'url' before chaining.
	@# NB: This requires python on the host and can not run from docker.

IMG_CURL=curlimages/curl:8.13.0
IO_ENV_LOG?=DOCKER,MK,MAKE
io.curl=$(shell which curl 2>/dev/null || echo docker run --rm ${IMG_CURL}) $(if $(filter undefined,$(origin 1)),,$(1))
_io.curl=${io.curl} ${1}
io.curl.stat=bash ${dash_x_maybe} -c '${io.curl} -s -o /dev/null $(if $(filter undefined,$(origin 1)),$${1},$(1)) > /dev/null' -- 
io.curl.quiet=$(call io.curl, -s $(if $(filter undefined,$(origin 1)),,$(1)))
io.log.curl=$(call io.curl.quiet, nginx-tcp:8080) | ${stream.as.log}

io.echo:; ${stream.stdin}
	@# Echos data from input stream. Alias for the `stream.stdin` macro.

io.env:; CMK_INTERNAL=1 ${make} io.env.filter.prefix/PWD,CMK,KUBE,K8S,MAKE,TUI,DOCKER,__
	@# Dumps a relevant subset of environment variables for the current context.
	@# No arguments.  Pipe-safe since this is just filtered output from 'env'.
	@#
	@# USAGE: ./compose.mk io.env
io.env/% io.env.filter.prefix/%:; echo ${*} | ${_io.env} | ${stream.grep.safe} | grep -v ___ | sort
	@# Filters environment variables by the given prefix or (comma-delimited) prefixes.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk io.env/<prefix1>,<prefix2>
_io.env=sed 's/,/\n/g' | xargs -I% sh -c "env | ${stream.grep.safe} | grep \"^%.*=\" || true" 
io.env=bash -c 'echo $${1\#/} | ${_io.env}' -- 
io.env.filter.prefix=${io.env}
io.env.log: io.env.log/${IO_ENV_LOG}
	@# Filters environment variables starting with DOCKER, MAKE, MK, etc.
	@# Human-readable output sent to stderr.  Also available as a macro
io.env.log=${make} io.env.log

io.env.log/%:; $(call io.env.log,${*})
	@# Human-readable description of the given subset of env-vars.
	@# Multiple inputs should be comma-separated.  Also available as a macro
define io.env.log
	$(call log.target, prefixes ${sep} ${1}); 
	echo '${1}' | ${stream.comma.to.space} | ${stream.space.to.nl} | ${flux.each}/io.env | ${stream.as.log}
endef

io.env.json/%:
	@# Like `io.env/<prefix>` but returns JSON data.
	env="`${make} io.env/${*} | ${stream.nl.to.space}`" \
	&& ${jb} $${env}

io.envp=CMK_INTERNAL=1 ${make} io.envp
io.envp io.env.pretty: flux.pipeline/io.env,stream.ini.pygmentize; 
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
	
io.figlet=printf "figlet -f$${font:-3d} $${label}" | ${make} tux.shell.pipe >/dev/stderr
io.figlet:; ${io.figlet} 
	@# Pulls `label` from the environment and renders it with `figlet`. 
	@# Also available as a macro. NB: This requires the embedded tui is built.
io.figlet/%:; label="${*}"; ${io.figlet}
	@# Treats the argument as a label, and renders it with `figlet`. 
	@# NB: This requires the embedded tui is built.  

io.file.select=header="Choose a file: (dir=$${dir:-.})"; \
	choices="`ls $${dir:-.}/$${pattern:-} | ${stream.nl.to.space}`" \
	&& $(call log.io,io.file.select ${sep} $${dir:-.} ${sep} $${choices}) \
	&& ${io.get.choice} 
# Creates file w/ the 2nd argument as a command, iff the file given by the 1st arg is older than
io.file.gen.maybe=[ -n "$$(find "${1}" -mmin +1 2>/dev/null)" ] \
	&& ($(call log,${dim} cached @ ${1} is old and will be recomputed fresh); eval "${2} > ${1}") \
	|| (true)

io.force/%:; force=1 ${make} ${*}
	@# Context-manager.  Sets `force=1` and then runs the given target.

io.get.url=$(call io.mktemp) && curl -sL $${url} > $${tmpf}

io.gum.docker=${trace_maybe} && docker run $$(if ${io.tty.stdin}; then echo "-it"; else echo "-i"; fi) -e TERM=$${TERM:-xterm} --entrypoint /usr/local/bin/gum --rm `docker build -q - <<< $$(printf "FROM alpine:${ALPINE_VERSION}\nCOPY --from=charmcli/gum:${IMG_GUM} /usr/local/bin/gum /usr/local/bin/gum\nRUN apk add --update --no-cache bash\n")`

# USAGE: see docs.mk :// css.min 
#   $(call io.factory.file_handler, ns=css.pretty handler=css.prettify prereqs='Dockerfile.build/css.pretty' root=$${docs.root} name='*.css')
io.factory.file_handler=$(eval $(call io.factory.file_handler.src, ${1}))
define io.factory.file_handler.src
$(call mk.unpack.kwargs, ${1}, ns)
$(call mk.unpack.kwargs, ${1}, handler, $${kwargs_ns}.handler)
$(call mk.unpack.kwargs, ${1}, root, .)
$(call mk.unpack.kwargs, ${1}, prereqs,${space})
$(call mk.unpack.kwargs, ${1}, name, default)
${kwargs_ns}/%:
	@# Generic handler for dirs or files
	$${trace_maybe} \
	&& if [ -d "$${*}" ]; then ( \
		$$(call log.target, dispatching ${dim_cyan}${kwargs_handler} ${sep} path=${dim_ital}$${*}) \
		&& find $${*} -name $${kwargs_name} \
		| $${stream.peek} | $${flux.each}/${kwargs_handler} \
	); else ( \
		$$(call log.target,$${*}) && ${make} ${kwargs_handler}/$${*} \
	); fi
${kwargs_ns}: ${kwargs_prereqs}
	@# Runs on given root or working directory
	$$(call log.target, handler=${bold_green}${kwargs_handler} ${sep} name=${dim_cyan}${kwargs_name}  ${sep} root=${dim_cyan}${kwargs_root})
	$${trace_maybe} && ${make} ${kwargs_ns}/${kwargs_root}
endef


# gum-presence probe, memoized to once-per-process (replaces a parse-time
# `ifeq ($(shell which gum ...))` that forked a `which` on EVERY re-parse).
# `io.gum.run`/`io.get.choice` then branch at call-time via `.$(_gum.present)`
# indirection ("1" -> on PATH, "0" -> dockerized), byte-identical to the old
# ifeq selection (verified against both branches), but no probe unless used.
_gum.present.cached :=
_gum.present = $(or ${_gum.present.cached},$(eval _gum.present.cached := $(shell which gum >/dev/null 2>/dev/null && echo 1 || echo 0))${_gum.present.cached})
io.gum.run=${io.gum.run.$(_gum.present)}
io.gum.run.1=`which gum`
io.gum.run.0=${io.gum.docker}
io.get.choice=${io.get.choice.$(_gum.present)}
io.get.choice.1=chosen=$$(${io.gum.run} choose --header="$${header:-Choose:}" $${choices})
io.get.choice.0=$(call io.script.tmpf, ${io.gum.run} choose --header=\"$${header:-Choose:}\" _ $${choices}) \
	&& filter="`echo $${choices}|sed 's/ /|/g'`" \
	&& cat $${tmpf} | ${col_b} | grep -E "$${filter}" | tail -n-3 | tail -n-1 | awk -F"006l" '{print $$2}' | head -1 > $${tmpf}.selected \
	&& mv $${tmpf}.selected $${tmpf} && chosen="`cat $${tmpf}`"
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


io.gum.div=label=${@} ${make} io.gum.div
io.gum.div:; label=$${label:-${io.timestamp}} ${io.draw.banner}
	@# Draw a horizontal divider with gum.
	@# If `label` is not provided, this defaults to using a timestamp.
	@#
	@# USAGE:
	@#  label=".." ./compose.mk io.gum.div 
io.gum.style/% io.draw.banner/%:; label="${*}"; ${io.draw.banner}
	@# Prints a divider with the given label. 
	@# Invocation must be a legal target (Do not use spaces, etc!)
	@# See also `io.draw.banner` and `io.print.banner` for something simpler.
	@#
	@# USAGE: ./compose.mk io.draw.banner/<label>

io.help: mk.namespace.filter/io.
	@# Lists only the targets available under the 'io' namespace.

io.inotify: assert.tool.required/inotifywait
	@# Runs given command once, and again in a loop whenever the given path changes
	@#
	@# USAGE: path='..' cmd='..' make io.inotify
	@#
	$(call log.target, ${dim}path=${no_ansi}$${path}) \
	&& export events="$${events:-modify,create,delete}" \
	&& $(call log.target, ${dim}events=${no_ansi}$${events}) \
	&& $(call log.target, ${cyan_flow_right} ${dim} $${cmd}) \
	&& bash -x -c 'set -e; $${cmd} & pid=$$!; trap "exit 0" SIGTERM SIGINT; \
	while inotifywait -q -r -e $${events} $${path}; do \
	    kill -KILL $${pid} 2>/dev/null || true; \
	    $${cmd} & \
	done'
io.inotify/%:; path="${*}" ${make} io.inotify
	@# Like `io.inotify`, but accepts path as argument 
	@#
	@# USAGE: cmd='..' ${make} io.inotify/<path>

io.mkdir/% mk.require.dir/%:
	@# Runs `mkdir -p` for the named directory.
	@# Set `force=1` to use sudo.
	([ -z "$${force:-}" ] && sudo="" || sudo=sudo ) \
	&& $(call log.target.part1, ${*} ) \
	&& $${sudo} mkdir -p ${*} \
	&& $(call log.target.part2,${green}${GLYPH_CHECK})
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
		&& printf "${dim}%*s" "$${side_length}" | sed "s/ /$${filler}/g" > /dev/stderr \
		&& printf "${no_ansi_dim}${bold}$${label_color:-${green}}$${label}${no_ansi_dim}" > /dev/stderr \
		&& printf "%*s${no_ansi}\n" "$${side_length}" | sed "s/ /$${filler}/g" > /dev/stderr \
	; fi
endef
io.print.banner/%:; label="${*}"; ${io.print.banner}
	@# Like `io.print.banner` but accepts a label directly.
io.log=$(call log.io,${1})
io.log.part1=$(call log.part1,${GLYPH_IO} $(strip ${1}))
io.log.part2=$(call log.part2, $(strip ${1}))

io.quiet.stderr/%:; cmd="${make} ${*}" ${make} io.quiet.stderr.sh
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

io.selector/%:; $(call io.selector, $(shell echo ${*}|cut -d, -f1),$(shell echo ${*} | cut -d, -f2-))
	@# Uses the given targets to generate and then handle choices.
	@# The 1st argument should be a nullary target; the 2nd must be unary.
	@#
	@# USAGE: 
	@#   ./compose.mk io.selector/<choice_generator>,<choice_handler>
io.selector=choices=`${make} ${1} | ${stream.nl.to.space}` && ${io.get.choice} && ${make} ${2}/$${chosen}

io.shell.isolated=env -i TERM=$${TERM} COLORTERM=$${COLORTERM} PATH=$${PATH} HOME=$${HOME}
io.shell.iso=${io.shell.isolated}

# Every io.stack.* macro resolves its stack-file the same way: the ${1} argument
# when one is given AND non-empty, else the default ${CMK_IO_STACK}. The $(origin)
# guard keeps this warning-clean (the ${1} reference is absent) when called with
# no args at all, so `$(call io.stack.pop)` works inline with no `${make}`
# sub-make; the inner $(or ..) additionally falls back when ${1} is present but
# EMPTY, which is what the CMK `cmk.io.stack.pop()` sugar emits (it lowers to a
# trailing-comma `$(call io.stack.pop,)`). The argless *targets* below are thin
# wrappers over the same macros.
io.stack.cur = $(if $(filter-out undefined,$(origin 1)),$(or ${1},${CMK_IO_STACK}),${CMK_IO_STACK})

# declare.stack / _declare.stack: code-gen an exported, per-run-unique,
# origin-guarded stack-name variable -- for a private stack file, separate from the
# default ${CMK_IO_STACK}.  `_declare.stack` (private) is the template body: it
# yields a makefile `export <VAR> := .tmp.<VAR>.<run-id>` line.  `declare.stack`
# wraps it in $(eval) to bind it, so callers just write the call -- no outer eval.
# USAGE: $(call declare.stack,MY_STACK).  The name is frozen on first definition
# (the origin-guard), so every sub-make in the run shares one file and an inherited
# environment value is reused as-is.  <run-id> is the supervisor id (MAKE_SUPER) when
# supervised, else this process's PPID.
define _declare.stack
export $(1) := $(if $(call mk.var.undefined,$(1)),.tmp.$(1).$(if $(call mk.var.defined,MAKE_SUPER),${MAKE_SUPER},$(shell echo $$PPID)),$($(1)))
endef
declare.stack=$(eval $(call _declare.stack,$(1)))

io.stack/%:; $(call io.stack, ${*})
	@# Returns all the data in the named stack-file
	@#
	@# USAGE:
	@#  ./compose.mk io.stack/<fname>
	@#  [ {.. data ..}, .. ]
io.stack=(${io.stack.require} && cat ${io.stack.cur} | ${jq.run} .)

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
# discard = pop without returning the value (it just trims the top off the
# file); pop is defined as "show the top, then discard it" so the trim lives in
# one place.
io.stack.discard=(${io.stack} | ${jq.run} '.[:-1]' > ${io.stack.cur}.tmp && mv ${io.stack.cur}.tmp ${io.stack.cur})
io.stack.pop=(${io.stack} | ${jq.run} '.[-1]'; ${io.stack.discard})
# pop_word = pop, but emits the value RAW (jq -r): an unquoted string instead of
# JSON.  Saves callers a trailing `| jq -r .`.  (`word` as in a bare scalar.)
io.stack.pop_word=(${io.stack} | ${jq.run} -r '.[-1]'; ${io.stack.discard})

io.stack.require=( ls ${io.stack.cur} >/dev/null 2>/dev/null || echo '[]' > ${io.stack.cur})
io.stack.push=(${io.stack.require} && obj=`${stream.stdin} | ${jq.run} -c .` && ${jq} --argjson obj "$${obj}" '. + [$$obj]' ${io.stack.cur} > ${io.stack.cur}.tmp && mv ${io.stack.cur}.tmp ${io.stack.cur})
io.stack.reset=echo '[]' > ${io.stack.cur}
io.stack.push/%:
	@# Pushes new JSON data onto the named stack-file
	@#
	@# USAGE:
	@#   echo '<json>' | ./compose.mk io.stack.push/<fname>
	@#
	${trace_maybe} \
	&& ([ "$${quiet:-0}" == "1" ] || $(call log.io,  io.stack.push ${sep} ${dim}stack@${no_ansi}${*} ${cyan_flow_left})) \
	&& ${stream.peek} | $(call io.stack.push, ${*})
io.stack.reset/%:; @$(call io.stack.reset, ${*})
	@# (Re)initialize the named stack-file to empty.
io.stack.discard/%:
	@# Discards the top item of the given stack-file: like `io.stack.pop`, but
	@# removes the top WITHOUT emitting it.  Not strict (empty stack is allowed).
	@# Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.discard/<fname>
	@#
	$(call log.io,  io.stack.discard ${sep} ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.discard, ${*})
io.stack.pop_word/%:
	@# Like `io.stack.pop`, but returns the top as a RAW value (jq -r): an
	@# unquoted string instead of JSON.  Removes the top.  Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.pop_word/<fname>
	@#
	$(call log.io,  io.stack.pop_word ${sep} ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.pop_word, ${*})

# io.stack.push_word: push a RAW word read from stdin onto the default stack.  This is
# the stdin-input counterpart of `io.stack.pop_word` (which emits a raw word).  `jq -Rs .`
# slurps stdin into one JSON string, which `io.stack.push` then appends.
io.stack.push_word=${jq} -Rs . | ${io.stack.push}
io.stack.push_word/%:; printf '%s' "${*}" | ${io.stack.push_word}
	@# Push the (raw, literal) stem as a word onto the default stack.  NB: `%` is the
	@# WORD to push here (unlike `io.stack.push/<file>`, where it names a stack-file).
	@# Also a macro (`echo word | ${io.stack.push_word}`) for piping a value in.
	@#
	@# USAGE: ./compose.mk io.stack.push_word/<word>
	@#
io.stack.push_word/:; printf '' | ${io.stack.push_word}

# Argless aliases over the default stack (${CMK_IO_STACK}), so you can use a
# stack without naming a file. The whole invocation's process tree shares it.
# Each is the no-arg form of the like-named macro (no `${make}` sub-make).
io.stack:;       @$(call io.stack)
	@# Show the default stack (${CMK_IO_STACK}).  See also io.stack/<fname>.
io.stack.push:;  @${stream.peek} | $(call io.stack.push)
	@# Push stdin JSON onto the default stack.  See also io.stack.push/<fname>.
io.stack.pop:;   @$(call io.stack.pop)
	@# Pop the default stack.  See also io.stack.pop/<fname>.
io.stack.pop_word:; @$(call io.stack.pop_word)
	@# Pop the default stack as a raw value (jq -r).  See also io.stack.pop_word/<fname>.
io.stack.push_word:; @${io.stack.push_word}
	@# Push a raw word read from stdin onto the default stack.  See also io.stack.push_word/<word>.
io.stack.discard:; @$(call io.stack.discard)
	@# Discard the top of the default stack (no value returned).  See also io.stack.discard/<fname>.
io.stack.reset:; @$(call io.stack.reset)
	@# (Re)initialize the default stack (${CMK_IO_STACK}) to empty.
## ----------------------------------------------------------------------------
##
## BEGIN: Events
## A CHANNEL is a named event-stack (built on `io.stack.*`); an EVENT is a JSON
## object `{type, ...meta}`.  `$(call declare.channel, namespace=<n>)` constructs
## channel <n> plus the operators below, each prefixed with the channel name.
##
## | Operator on channel `<n>`         | Action                               |
## |-----------------------------------|--------------------------------------|
## | `<n>.emit`                        | push an event (macro; kwargs/stdin)  |
## | `<n>.emit.type/<type>`            | push; type from stem, meta on stdin  |
## | `<n>.push` / `<n>.pop`            | raw stack ops (one JSON obj in/out)  |
## | `<n>.filter.field_equal/F/V`      | every event whose `.F` == `V`        |
## | `<n>.first.match.field_equal/F/V` | the first such event, else nothing   |
## | `<n>.dispatch.drain/<field>`      | drain, routing each by `.<field>`    |
## | `<n>.dispatch.by_type`            | == `dispatch.drain/type`             |
## | `<n>.purge`                       | drop the stack (also an at-exit hook)|
##
## HANDLERS: define `<n>/<value>:` (the dispatched field's value is the stem; a
## `<n>/%:` rule is the fallback);
## dispatch routes via make's rule precedence and exports the event as $CMK_EVENT.
## Names matching `io.channel.*` / `_declare.channel` are private.
## END: Events
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Backend
io.channel.stackvar=events__$(strip $(1))
io.channel.stack=$($(call io.channel.stackvar,$(strip $(1))))
io.channel.chan=$(patsubst namespace=%,%,$(patsubst chan=%,%,$(strip $(1))))

# Read-only jq query helpers that operate over channel's backing array, 
# newest-first.  Two main modes is enough flexibility for powerful primtives..
# see demos/zahn.mk for an example that builds advanced flow-control from scratch.
define io.channel.filter_field_equal
$(call bind.posargs) && $(call io.stack,$(call io.channel.stack,$(strip $(1)))) | ${jq.run} -c --arg f "$${_1st}" --arg v "$${_2nd}" 'reverse[] | select((.[$$f]|tostring)==$$v)'
endef
define io.channel.first.match.field_equal
$(call bind.posargs) && $(call io.stack,$(call io.channel.stack,$(strip $(1)))) | ${jq.run} -c --arg f "$${_1st}" --arg v "$${_2nd}" 'first(reverse[] | select((.[$$f]|tostring)==$$v)) // empty'
endef

# Code-gen for channel's operators.
# See header for the interface.  Also adds `<n>.purge` as an at-exit hook.
declare.channel=$(call declare.stack,$(call io.channel.stackvar,$(call io.channel.chan,$(1))))$(eval $(call _declare.channel,$(call io.channel.chan,$(1))))
define _declare.channel
$(1).push=$$(call io.stack.push,$$(call io.channel.stack,$(1)))
$(1).push:
	$$(call log.trace, $${@}) 
	$$($(1).push)
$(1).pop:
	$$(call log.trace, $${@}) 
	$$(call io.stack.pop,$$(call io.channel.stack,$(1)))
$(1).filter.field_equal/%:
	$$(call log.trace, $${@}) 
	$$(call io.channel.filter_field_equal,$(1))
$(1).first.match.field_equal/%:
	$$(call log.trace, $${@}) 
	$$(call io.channel.first.match.field_equal,$(1))
$(1).emit=$${jb} $$(strip $$(1)) | $$($(1).push)
$(1).emit:
	@# Push one event (kwargs read from stdin).  Also available as a macro.
	$$(call $(1).emit, `$${stream.stdin.maybe}`)
$(1).emit.type/%:
	@# Emits the given type, with optional extra metadata on stdin.
	$$(call log.trace, $${@}) 
	$$(call $(1).emit, type=$${*} `$${stream.stdin.maybe}`)
$(1).dispatch.drain/%:
	@# Drain the channel (pop to exhaustion), routing each event by `.<field>` to
	@# `<n>/<value>` (with the event exported as CMK_EVENT).  Re-entrant
	@# (re-reads the stack each pop, so handlers may re-emit) and tolerant (a
	@# failing handler does not stop the drain).
	$$(call log.target, $${*})
	while obj=`$$(call io.stack.pop,$$(call io.channel.stack,$(strip $(1))))` \
		&& [ -n "$$$${obj}" ] && [ "$$$${obj}" != null ]; do \
			t=`echo "$$$${obj}" | $${jq.run} -r .$$(strip $${*})` ; \
			echo "$$$${obj}" | $${jq.run} . | $${stream.as.log} ; \
			CMK_EVENT="$$$${obj}" $${make} "$(strip $(1))/$$$${t}" </dev/null || true ; \
		done
$(1).dispatch.by_type: $(1).dispatch.drain/type
$(1).purge:
	$$(call log.trace, $${@}) 
	$$(call io.safe_rm,$$$${$(call io.channel.stackvar,$(1))}) \
	; $$(call io.safe_rm,$$$${$(call io.channel.stackvar,$(1))}.tmp)
export CMK_AT_EXIT_TARGETS += $(1).purge
endef

io.string.hash=$(shell printf "${1}" | sed 's/ /_/g'|sed 's/[.]/_/g'|sed 's/\//_/g')

io.tail/%:; $(trace_maybe) && touch ${*} && tail -f ${*} 2>/dev/null
	@# Tails the named file.  Blocking.  Creates file first if necessary.
	@#
	@# USAGE: ./compose.mk io.tail/<fname>

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
## BEGIN: assert.* targets
##
## The `assert.*` namespace collects RECIPE-level guards -- preconditions a target
## states at the top of its body.  Each logs a clear error and exits nonzero on
## failure, covering environment variables, host tools, stdin streams, and plugin
## availability.  Most are macros (usable inline via `$(call assert.X, ...)`); the
## env + tool guards also expose `assert.X/%` TARGET forms for use as prerequisites.
##
## Sibling guards that live in their OWN namespaces (NOT here): `__plugins__.assert`
## / `__modules__.assert` (parse-time registry asserts) and `_mk.assert.define`
## (the `import.module` define-exists guard).
##
##-------------------------------------------------------------------------------
##
## DOCS:
##  * `[1]:` [Assertions](https://robot-wranglers.github.io/compose.mk/assertions)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# --- Environment assertions ---------------------------------------------------
# Helpers for asserting environment variables are present and non-empty.
# Proof-of-adoption for the `fault` idiom (demos/cmk/fault.cmk): when that module
# is imported, a failed assertion raises a typed `EnvVarUnset` fault (dispatchable,
# carries `var=`).  Without it -- i.e. in plain core -- this stays the dependency-
# free `exit 39`.  The `fault.throw` probe is the degrade switch.
assert.env.var=[[ -z "$${$(strip ${1})}" ]] && { $(if $(call mk.var.defined,fault.throw),$(call fault.throw,EnvVarUnset,var=$(strip ${1})),$(call log.io, ${red}Error:${no_ansi_dim} required variable ${no_ansi}${underline}$(strip ${1})${no_ansi_dim} is unset or empty!); exit 39); } || true
assert.env=$(foreach var_name, ${1}, $(call assert.env.var, ${var_name});)
assert.env/%:; $(call assert.env,$(shell echo ${*}|${stream.comma.to.space}))
	@# Asserts that the (comma-delimited) environment variables are set and non-empty.
	@# Also available as a macro.

# --- Tool assertions ----------------------------------------------------------
# Helper for asserting that tools are available, with support for error messages.
# CMK-lang alias: cmk.assert.tool.required(tool_name, Error if missing)
_assert.tool.required=$(call log.part1,${GLYPH_MK} assert.tool.required ${sep} looking for ${ital}${dim_cyan}$(strip ${1})); which ${1} >/dev/null && $(call log.part2,${green}${GLYPH_CHECK} ${no_ansi_dim}`which ${1}`) || ($(call log.part2,${red} missing!);$(call log.io,${no_ansi}${bold}Error:${no_ansi} $(if $(filter undefined,$(origin 2)),Install tool and retry workflow.,$(2))); exit 1)
assert.tool.required=${_assert.tool.required}
assert.tool.required/%:; $(call _assert.tool.required, ${*})
	@# Asserts that the given tool is available in the environment.
	@# Output is only on stderr, but this shows whereabouts if it is in PATH.
	@# If not found, this exits with an error.  Also available as a macro.

# --- Stream assertions --------------------------------------------------------
# assert.stream.stdin.required -- guard: unless stdin is a stream, log (via the
# calling target, ${@}) and exit 1.
assert.stream.stdin.required=if ${io.tty.stdin}; then $(call log.target, ${red}needs a stream on stdin) ; exit 1 ; fi

# --- Plugin assertions --------------------------------------------------------
# assert.plugin(<name>): RECIPE guard -- passes if plugin <name> is already loaded (in __plugins__) OR is
# AVAILABLE in CMK_PLUGINS_DIR, else logs + exits 1.  The availability fallback is what makes it usable by
# code that COMPILES a plugin rather than importing it (e.g. the repl harness in `_cmk.repl.launch`), where
# the plugin is never in the registry.  (Parse-time registry-only assert is `__plugins__.assert`.)
assert.plugin=$(if $(call __plugins__.has,$(strip ${1})),true,{ [ -n "$(call cmk.plugin.find,${1})" ] || { $(call log.io, ${red}assert.plugin ${sep}${no_ansi} plugin not available${no_ansi_dim}: ${no_ansi}${bold}$(strip ${1})${no_ansi} ${dim}(searched ${CMK_PLUGINS_DIR})) ; exit 1 ; } ; })

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: assert.* targets
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

# Import `define`-block(s) from another file into THIS file's namespace, re-
# establishing each verbatim so every mk.def.*/io.awk consumer works on it
# locally.  Parse-time only (it creates `define`s); call it at top-level.  The
# source file must `include compose.mk` (it provides `mk.def.read`, the $(value)
# reader that preserves `$`/indentation/newlines).  `def=` imports one block (and
# `as=` may rename it); `defs="a b ..."` imports several (each kept under its own
# name), and a spec containing `*`/`?` is a glob matching every define whose name
# fits (so `defs='underload_*'` grabs a whole family).  Errors if the file or any
# spec matches nothing.  Bounded to the file's own `define` lines (not includes).
#
# Load-bearing tricks (per imported block): (1) the generated `define <name> ..
# endef` wrapper makes `$(eval)` store the body VERBATIM (so `$`/`$$` survive);
# (2) a tmpfile + `$(file <)` (not `$(shell)` directly) preserves newlines that
# `$(shell)` would flatten; (3) fetch/read/cleanup run in textual order.
#
# USAGE:
#   $(call import.def, file=<path> def=<name>)
#   $(call import.def, file=<path> def=<name> as=<local_name>)
#   $(call import.def, file=<path> defs="<name> <name> ...")
#   $(call import.def, file=<path> defs="<glob> ...")    # e.g. 'underload_*'
#   $(call import.def, file=<path> def=<name> namespace=<ns>)  # binds <ns>.<name>
# A `namespace=<ns>` prefixes the LOCAL bind name only (`<ns>.<name>`, top-level
# header); the body -- including any nested define -- is untouched.  Omit it to
# import to root (the default).
#
# Compile-time inlining hooks (see `_import.emit`): when `_mk_emit` is a file
# path the import macros APPEND resolved block text to it instead of `$(eval)`ing
# into the live namespace, and `_mk_exclude_from` overrides the never-override
# source.  Both default to empty so the runtime path is unchanged (and
# `--warn-undefined-variables` stays quiet); they are set (via env) only in the
# CMK compile stage.
_mk_emit ?=
_mk_exclude_from ?=
# Consume one resolved define block ${1}=file ${2}=name ${3}=local-name: append its
# text to `_mk_emit` (compile-time) or `$(eval)` it into the namespace (runtime).
_mk.emit.or.eval.def=$(if ${_mk_emit},$(file >> ${_mk_emit},$(call _import.def.one,${1},${2},${3})),$(eval $(call _import.def.one,${1},${2},${3})))
import.def=$(call _import.def, ${1})
# Plural-name alias (identical signature/behavior); reads naturally with `defs=`.
import.defs=$(call _import.def, ${1})

# Names of `define`s in file ${1} whose name matches glob spec ${2} (shell `case`,
# so `*`/`?`/`[..]` are native globs); scans the file's own `define` lines only.
_mk.def.match=$(shell grep -E '^define[[:space:]]' '${1}' 2>/dev/null | awk '{print $$2}' | while read n; do case "$$n" in (${2}) printf '%s\n' "$$n";; esac; done)

# Import ONE define by exact name ${2} from file ${1}, under local name ${3}: read
# verbatim via mk.def.read ($(value)), error if absent, wrap in a fresh `define`.
# Invoke via `$(eval $(call _import.def.one,..))` so the wrapper is parsed.
define _import.def.one
$(shell make -f ${1} mk.def.read/${2} > .tmp.import.def.${3} 2>/dev/null)
$(if $(strip $(file < .tmp.import.def.${3})),,$(error import.def: def `${2}` not found in `${1}`))
define ${3}
$(file < .tmp.import.def.${3})
endef
$(shell rm -f .tmp.import.def.${3})
endef

# Resolve one `defs=` spec: a glob expands to every matching define name (error if
# none), an exact name imports directly.  ${3} is the (possibly empty) namespace
# prefix applied to the LOCAL bind name -- the source name (read from the file) is
# unchanged, so `namespace=N` binds `define N.<name>` (top-level header only).
_import.def.spec=$(if $(findstring *,${2})$(findstring ?,${2}),$(eval _mk_id_names:=$(call _mk.def.match,${1},${2}))$(if ${_mk_id_names},$(foreach _n,${_mk_id_names},$(call _mk.emit.or.eval.def,${1},${_n},${3}${_n})),$(error import.def: no def matching `${2}` in `${1}`)),$(call _mk.emit.or.eval.def,${1},${2},${3}${2}))

define _import.def
$(eval _mk_id_args:=$(subst %,%%,$(subst ",',${1})))
$(call mk.unpack.kwargs, ${_mk_id_args}, file)
$(call mk.unpack.kwargs, ${_mk_id_args}, def, MKID_NONE)
$(call mk.unpack.kwargs, ${_mk_id_args}, defs, MKID_NONE)
$(call mk.unpack.kwargs, ${_mk_id_args}, as, MKID_NONE)
$(call mk.unpack.kwargs, ${_mk_id_args}, namespace, MKID_NONE)
$(eval _mk_id_ns:=$(if $(filter-out MKID_NONE,${kwargs_namespace}),$(strip ${kwargs_namespace}).))
$(if $(wildcard ${kwargs_file}),,$(error import.def: file not found: `${kwargs_file}`))
$(if $(filter-out MKID_NONE,${kwargs_def} ${kwargs_defs}),,$(error import.def: give def=<name> or defs="<a b c>". Input: `${1}`))
$(if $(filter-out MKID_NONE,${kwargs_def}),$(call _mk.emit.or.eval.def,${kwargs_file},${kwargs_def},${_mk_id_ns}$(if $(filter-out MKID_NONE,${kwargs_as}),${kwargs_as},${kwargs_def})))
$(foreach _s,$(filter-out MKID_NONE,${kwargs_defs}),$(call _import.def.spec,${kwargs_file},${_s},${_mk_id_ns}))
endef

# Positional convenience over `import.def` (kept for the old `include.def`
# call-shape; note it now self-evals, with no outer `$(eval ..)` needed).
include.def=$(call import.def, file=$(strip ${2}) def=$(strip ${1}))

# Extract one make target's full definition from a file -- the `^<name>:` header
# plus its tab-indented recipe lines (incl. `@#` docs and `\`-continuations) -- for
# an exact name (glob resolution happens upstream).  Read via `$(value)` so awk's
# `$0`/`$`/backslashes survive make expansion.  `g2r` -- glob (`*`/`?`) to regex.
define .awk.target.extract
function g2r(s,  r,i,c){ r="";
  for(i=1;i<=length(s);i++){ c=substr(s,i,1);
    if(c=="*") r=r ".*";
    else if(c=="?") r=r ".";
    else if(c ~ /[][(){}.^$+|\\]/) r=r "\\" c;
    else r=r c };
  return r }
BEGIN { cap=0; pat = "^" g2r(t) "[ \t]*:([^=]|$)" }
cap && /^\t/ { print; next }
{ cap=0; if ($0 ~ pat) { print; cap=1 } }
endef

# Select whole `define <name>..endef` blocks from a makefile stream whose name
# matches the glob `pat` (exact name when no `*`/`?`), passing nested inner defines
# through verbatim and skipping non-matching blocks.  `g2r` -- glob to regex.
define .awk.select.def
function g2r(s,  r,i,c){ r="";
  for(i=1;i<=length(s);i++){ c=substr(s,i,1);
    if(c=="*") r=r ".*";
    else if(c=="?") r=r ".";
    else if(c ~ /[][(){}.^$+|\\]/) r=r "\\" c;
    else r=r c };
  return r }
BEGIN { rx = "^(" g2r(pat) ")$"; depth=0; cap=0 }
depth==0 && /^define / { if ($2 ~ rx) { cap=1; depth=1; print } else { cap=0; depth=1 }; next }
depth==0 { next }
/^define / { depth++; if (cap) print; next }
/^endef[ \t]*$/ { if (cap) print; depth--; if (depth==0) cap=0; next }
{ if (cap) print }
endef

# Pipeline-stage SELECTors (stdin->stdout): emit the subset of a makefile stream
# named by the stem (a glob with `*`/`?`, else an exact name).  These are the
# composable form of `import.{def,target}`'s extraction, usable inside a
# `flux.column` staging pipeline (e.g. partial module imports).  The awk is read
# from an exported `_cmk_blk_*` var so make does not mangle its `$0`/`$$`.
mk.select.def/% mk.select.defs/%:; @${stream.stdin} | awk -v pat='${*}' "$${_cmk_blk_select_def}"
	@# Emit define block(s) from stdin whose name matches <spec> (glob: `*` `?`).
mk.select.target/% mk.select.targets/%:; @${stream.stdin} | awk -v t='${*}' "$${_cmk_blk_target_extract}"
	@# Emit target block(s) from stdin whose name matches <spec> (glob: `*` `?`).

# Target names defined textually in file ${1} (`^name:` headers, split on
# multi-target rules; the `([^=]|$)` guard skips `:=`/`?=` assignments).  Skips
# `define ... endef` bodies, whose content (e.g. an awk block or a literal with
# `:`) must not be mistaken for target headers.
_mk.target.names=$(shell awk '/^define /{d=1} /^endef/{d=0;next} d{next} /^[^[:space:]#=][^=]*:([^=]|$$)/{ h=$$0; sub(/[ \t]*:.*/,"",h); k=split(h,a," "); for(i=1;i<=k;i++) print a[i] }' '${1}' 2>/dev/null | sort -u)

# Subset of the space-list ${2} that is ALSO a target in file ${1}.  Scans ${1}
# once but emits only the intersection, so this stays cheap even when ${1} is a big
# (e.g. interpreter-inlined) file, and used as the never-override set.  Skips
# `define ... endef` bodies for the same reason as `_mk.target.names`.
_mk.local.of=$(shell awk -v want="${2}" 'BEGIN{ k=split(want,w," "); for(i=1;i<=k;i++) W[w[i]]=1 } /^define /{d=1} /^endef/{d=0;next} d{next} /^[^[:space:]#=][^=]*:([^=]|$$)/{ h=$$0; sub(/[ \t]*:.*/,"",h); n=split(h,a," "); for(j=1;j<=n;j++) if(a[j] in W) print a[j] }' '${1}' 2>/dev/null | sort -u)

# Subset of the space-list ${2} matching the shell glob ${1} (native `*`/`?`/`[..]`).
_mk.glob.filter=$(shell for n in ${2}; do case "$$n" in (${1}) printf '%s\n' "$$n";; esac; done)

# Import one EXACT target ${2} from file ${1}: tmpfile keeps the newlines/tabs a
# bare `$(shell)` would flatten; the recipe parsed by `$(eval)` keeps deferred
# expansion (so `$${y}` survives).  No define-wrapper, since we want a rule.
define _import.target.one
$(eval _mk_it_tmp:=.tmp.import.target.$(subst ?,_,$(subst *,_,$(subst /,_,$(subst %,_,${2})))))
$(shell awk -v t='${2}' '$(value .awk.target.extract)' '${1}' > ${_mk_it_tmp})
$(if $(strip ${3}),$(shell awk -v ns='$(strip ${3})' '$(value .awk.module.namespace)' ${_mk_it_tmp} > ${_mk_it_tmp}.ns && mv ${_mk_it_tmp}.ns ${_mk_it_tmp}))
$(if ${_mk_emit},$(shell cat ${_mk_it_tmp} >> ${_mk_emit}),$(eval $(file < ${_mk_it_tmp})))
$(shell rm -f -- "${_mk_it_tmp}")
endef

# Resolve one spec to source target names (glob or exact), error if it matches
# nothing, then import each EXCEPT names the destination already defines: a local
# target is NEVER overridden, silently (no `make` "overriding recipe" warning,
# which recursion would otherwise spam).  `$(filter)` treats `%` as a wildcard, so
# membership is tested literally via `$(findstring <name>,..)` on the bracketed set.
# ${3} is an optional namespace prefix: when set, each imported target is renamed
# `<ns>.<target>` (so it CANNOT collide with a local) and the local-skip is bypassed.
define _import.target.spec
$(eval _mk_it_hits:=$(call _mk.glob.filter,${2},${_mk_it_src}))
$(if ${_mk_it_hits},,$(error import.target: no target matching `${2}` in `${1}`))
$(foreach _n,${_mk_it_hits},$(if $(if $(strip ${3}),,$(findstring <${_n}>,${_mk_it_localb})),,$(eval $(call _import.target.one,${1},${_n},$(strip ${3})))))
endef

# The target-flavoured sibling of `import.def`: copies whole target(s), header
# (with prerequisites) and recipe, verbatim out of another makefile into this one,
# for sharing targets between a `.cmk` port and its plain-make twin.  Parse-time
# only (it creates rules); call it directly at top-level.  Errors if the file or
# any spec matches nothing.  Quote `targets=` when passing more than one.  A spec
# with `*` (any run) or `?` (one char) is a glob matching every target whose name
# fits; a spec with neither is an exact name.  An import NEVER overrides a target
# the importing file already defines (local wins, silently).  NOTE: scans the given
# <file> textually only (not its includes, not `::`/appended rules).
#
# A `namespace=<ns>` renames each imported target `<ns>.<name>` (so it can't collide
# with a local, and the local-skip is bypassed); omit it to import to root (default).
# USAGE:
#   $(call import.target, file=<path> target=<name>)
#   $(call import.target, file=<path> targets="<name> <name> ...")
#   $(call import.target, file=<path> targets="<glob> ...")   # e.g. 'ul.push/*'
#   $(call import.target, file=<path> target=<name> namespace=<ns>)
import.target=$(call _import.target, ${1})
# Plural-name alias (identical signature/behavior); reads naturally with `targets=`.
import.targets=$(call _import.target, ${1})

define _import.target
$(eval _mk_it_args:=$(subst %,%%,$(subst ",',${1})))
$(call mk.unpack.kwargs, ${_mk_it_args}, file)
$(call mk.unpack.kwargs, ${_mk_it_args}, target, MKIT_NONE)
$(call mk.unpack.kwargs, ${_mk_it_args}, targets, MKIT_NONE)
$(call mk.unpack.kwargs, ${_mk_it_args}, namespace, MKIT_NONE)
$(if $(wildcard ${kwargs_file}),,$(error import.target: file not found: `${kwargs_file}`))
$(eval _mk_it_src:=$(call _mk.target.names,${kwargs_file}))
$(eval _mk_it_localb:=$(foreach _l,$(call _mk.local.of,$(or ${_mk_exclude_from},$(firstword ${MAKEFILE_LIST})),${_mk_it_src}),<${_l}>))
$(eval _mk_it_specs:=$(strip $(filter-out MKIT_NONE,${kwargs_target} ${kwargs_targets})))
$(if ${_mk_it_specs},,$(error import.target: give target=<name> or targets="<a b c>". Input: `${1}`))
$(foreach _s,${_mk_it_specs},$(call _import.target.spec,${kwargs_file},${_s},$(filter-out MKIT_NONE,${kwargs_namespace})))
endef

_import.emit:
	@# Compile-time inliner for ONE `$$(call import.*)`, driven by env vars:
	@# `ekind` (target|targets|def|defs), `eargs` (the arg-string), and
	@# `_mk_exclude_from` (the source being compiled, so locals aren't overridden).
	@# Reuses the normal import machinery, but because `_mk_emit` is set the resolved
	@# blocks are APPENDED to a tmp instead of `$$(eval)`ed; the tmp is printed to
	@# stdout.  Used by `_mk.compile.imports` to bake imports in at compile-time.
	$(eval _mk_emit:=$(shell TMPDIR=. mktemp ./.tmp.mk.emit.XXXXXXXX))
	$(if $(filter target targets,${ekind}),$(call import.target,${eargs}),$(call import.def,${eargs}))
	@cat ${_mk_emit}; $(call io.safe_rm,${_mk_emit})

_mk.compile.imports:
	@# CMK compile stage (stdin->stdout): replaces each
	@# `$$(call import.{target,targets,def,defs}, ..)` line with the resolved blocks
	@# (via `_import.emit`), so imports resolve at COMPILE time and cost nothing at
	@# runtime; all other lines pass through.  `inputf` (the source being compiled, set
	@# by `mk.compile`) seeds the never-override check for local targets.
	${stream.stdin} | while IFS= read -r line; do \
		case "$${line}" in \
			'$$(call import.target,'*|'$$(call import.targets,'*|'$$(call import.def,'*|'$$(call import.defs,'*) \
				rest="$${line#'$$(call import.'}"; \
				k="$${rest%%,*}"; a="$${rest#*,}"; a="$${a%)}"; \
				ekind="$$k" eargs="$$a" _mk_exclude_from="$${inputf:-}" ${make} _import.emit;; \
			*) printf '%s\n' "$${line}";; \
		esac; \
	done

mk.__main__:
	@# Runs the default goal, whatever it is.
	@# We need this for use with the supervisor because 
	@# usage of `mk.supervisor.enter/<pid>` is ALWAYS present,
	@# and that overrides default that would run with an empty CLI.
	case `echo ${MAKEFILE_LIST}|${stream.count.words}` in \
		1) case `echo ${MAKEFILE_LIST} | xargs basename` in \
				compose.mk) (\
					$(call log.trace,empty invocation for compose.mk, returning help) \
					&& ${make} help);; \
				*) ${make} $(.DEFAULT_GOAL);; \
			esac ;; \
		0) $(call log, ${red}error: library list is empty);; \
		*) (\
			$(call log.trace, multiple library files; looking for a default goal..) \
			&& ${make} $(.DEFAULT_GOAL));; \
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
	&& ${mk.def.to.file}/$${def_name},$${tmpf} \
	&& [ -z $${preview:-} ] && true || ${make} io.preview.file/$${tmpf} \
	&& header="mk.def.dispatch${no_ansi}" \
	&& ([ $${TRACE} == 1 ] &&  printf "$${header} ${sep} ${dim}`pwd`${no_ansi} ${sep} ${dim}$${tmpf}${no_ansi}\n" > ${stderr} || true ) \
	&& $(call log.mk, $${header} ${sep} ${cyan}[${no_ansi}${bold}$${intr}${no_ansi}${cyan}] ${sep} ${dim}$${tmpf}) \
	&& which $${intr} > ${devnull} || exit 1 \
	&& $(trace_maybe) \
	&& src="$${intr} $${tmpf}" \
	&& [ -p ${stdin} ] && ${stream.stdin} | eval $${src} || eval $${src}
	
bind.def.to.env=export $(strip ${2})="$(shell ${make} mk.def.read/$(strip ${1}))"
# Pure-make accessor: expands to a define block's raw text with NO sub-make fork.
# `$(call _mk.def.value, <name>)` yields the raw text (make-expansion time).  With any
# 2nd arg it instead yields a single-line, recipe-safe `printf` that reproduces the
# block verbatim on stdout -- pipe it into a command, e.g.
# `$(call _mk.def.value, <name>, _) | cmd`.  (A literal heredoc can't be used in a recipe:
# make splits a recipe on expansion-newlines, so the block is emitted as one `printf '%b'`
# line -- same idea as the triple-quote lowering.)  Newlines become `\n` and `\`/`'` are
# escaped, so `$`/quotes/parens in the block survive both make and the shell intact.  For
# shell-runtime streaming (pipes/redirects/process-substitution) use `${mk.def.read}/<name>`.
_mk.def.value=$(if $(strip $(if $(filter undefined,$(origin 2)),,${2})),printf '%b' '$(subst ','\'',$(subst ${nl},\n,$(subst \,\\,$(value $(strip ${1})))))',$(value $(strip ${1})))
# `$(call _mk.def.to.fd, <name>)` is the recipe-safe `printf '%b'` form of the block -- the single
# seam for FD-materialization.  Used by the `⬦` stream glyph (wrapped in `<(...)`) and by
# `_mk.def.tmpfile` below.  `$(call _mk.def.tmpfile, <name>)` is a shell command-substitution that
# writes the block to a fresh tmpfile and echoes its path (fork-free read; for local file-required
# interpreters via the `⬥` glyph).  The file is created per evaluation under ${CMK_BRF_PREFIX}
# (a run-id-keyed `.tmp.*` name) and swept at end-of-run by the supervisor teardown (top of file);
# `mk.clean` is a manual backstop.
_mk.def.to.fd=$(call _mk.def.value, $(strip ${1}), _)
_mk.def.tmpfile=$$(_brf=$$(mktemp ${CMK_BRF_PREFIX}.XXXXXXXX) && $(call _mk.def.to.fd, ${1}) > $$_brf && printf %s $$_brf)
mk.def.read=CMK_INTERNAL=1 ${make} mk.def.read
mk.def.read/%:; $(info $(call _mk.def.value,${*}))
	@# Reads the named define/endef block from this makefile,
	@# emitting it to stdout. This works around normal behaviour 
	@# of completely wrecking indention/newlines and requiring 
	@# escaped dollar-signs present inside the block.  
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk mk.read_def/<name_of_define>
	@#

mk.def.to.file=${make} mk.def.to.file
mk.def.to.file/%:
	@# Reads the given define/endef block from this makefile context, 
	@# writing it to the given output file. Also available as a macro.
	@#
	@# USAGE: ( explicit filename for output )
	@#   ./compose.mk mk.def.to.file/<def_name>,<fname>
	@#
	@# USAGE: ( use <def_name> as filename )
	@#   ./compose.mk mk.def.to.file/<def_name>
	@#
	$(call mk.unpack.args, def_name out_file) \
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

_mk.help.o2=$(call _mk.help.o,${1}) \
	&& ${io.mktemp} && cat $${parser_cache} | ${jq} "with_entries(select(.key | startswith(\"${2}\")))" > $${tmpf} && _filtered=$${tmpf}
mk.help.namespace/%:
	$(call _mk.help.o2,${MAKEFILE},${*}) \
	&& case "$${format:-}" in \
		""|json) cat $${_filtered};; \
		markdown|md) ( \
			${io.mktemp} && cat $${_filtered} | ${jq} -r '.|keys[]' \
			| sed 's/%//g' | uniq | ${stream.fold} | ${stream.peek} \
			| ${stream.nl.to.space}>$${tmpf}; for key in `cat $${tmpf}`; do cat $${_filtered} | (printf "\n[**\`$${key}\`**](#$${key})\n\n" && ${jq} -r ".[\"$${key}\"].docs[]" 2>/dev/null |${stream.trim}; printf "\n---------\n"); done )| ${stream.preview.maybe} ;; \
		*) $(call log.target,${red} expected format would be set in environment); exit 55;; \
	esac

_mk.help.o=parser_cache=".tmp.$(shell echo `basename ${1}`.parsed.json)" \
	&& $(call io.file.gen.maybe,$${parser_cache},${mkparse} ${1})
mk.help.target/%:; ${mkparse} ${MAKEFILE} --prefix ${*} --markdown --preview 
	@# Shows help docstring for the named target.
	@# By default, this previews the docstring as markdown, using charmbracelet/glow.
	@# Set `preview=0` in environment to override and get raw docstring.
	@# USAGE: ./compose.mk mk.help.target/<target_name>

define cmk.default.sugar
[
	["⋘", "⋙", "$(call compose.import.string, def=__NAME__ import_to_root=TRUE)"],
    ["⫻",  "⫻",  "$(call docker.import, def=__NAME__)"],
	["⟦",  "⟧",  "$(call polyglot.__import__.__AS__,__NAME__,__WITH__)"],
	["🞹",  "🞹", "$(call compose.import.code, def=__NAME__)"],
	["⨖", "⨖", "__NAME__:; $(call __AS__,__WITH__)"],
	["⦖", "⦕", "$(call import.module, def=__NAME__ namespace=__AS__ preprocs=__WITH__)"]
]
endef
# The dialect table: ordered [pattern, replacement] rows, each a LITERAL match (see
# .awk.preprocess.dialect: the pattern's regex metacharacters are auto-escaped before gsub, so
# `.` is a literal dot, never a wildcard -- `cmk.` matches `cmk.` only, never `cmk/`/`cmk)`).
# Patterns need NO escaping here, which is why glyph keywords (ᝏ/ᐉ/...) and plain dotted ones
# (this./cmk.) both Just Work.  `this.`/`cmk.` are the two call-anchors (TARGET and MACRO);
# `cmk.`->`؆` is a sentinel consumed by callform/.awk.cmk.call, restored by .awk.cmk.unsentinel.
define cmk.default.dialect
[
	["ᝏ","cmk.bind."],
	["ᐉ", ".dispatch/"],
	["🡆", "${stream.stdin} | ${jq} -r"],
	["🡄", "${jb}"],
	["this.", "${make} "],
	["cmk.", "؆"]
]
endef

mk.clean:
	@# Cleans `.tmp.*` scratch (files AND dirs) from the cwd, PLUS the staged
	@# `.tmp.module.*` artifacts from CMK_MODULES_DIR.  User-invoked + best-effort
	@# (deliberately NOT an at-exit hook -- see import.module): a non-root `rm`
	@# cannot remove files a ROOT docker submake may have left on a mounted dir.
	rm -rf -- .tmp.* 2>/dev/null || true
	$(if $(filter-out . ./,$(strip ${CMK_MODULES_DIR})),( cd "$(strip ${CMK_MODULES_DIR})" 2>/dev/null && rm -f -- .tmp.module.* ) 2>/dev/null || true)

mk.compile/% mk.compiler/%:; ls ${*} && export __interpreting__=${*} && cat ${*} | (${mk.compile})
	@# Like `mk.compile`, but accepts file as argument instead of using stdin.

mk.compile mk.compiler:; ${mk.compile}
	@# This is a transpiler for the CMK language -> Makefile.
	@# Accepts streaming CMK source on stdin, result on stdout.
	@# Quiet by default, pass quiet=0 to preview results from intermediate stages.
	@#
	@# USAGE:
	@#  echo "<source_code>" | ./compose.mk mk.compiler
	@#

define mk.compile
$(call log.trace, __file__=$${__file__} \
	__interpreter__=${__interpreter__} \
	__interpreting__="$${__interpreting__:-None}" \
	__script__=$${__script__}) \
&& case $${quiet:-1} in \
	*) runner=flux.pipeline;; \
	0) runner=flux.pipeline;; \
esac \
&& ${io.mktemp} && export inputf=$${tmpf} \
&& ${stream.stdin} > $${inputf} \
&& export cmk_pragma=$$(cat $${inputf} | ${.cmk.parse.pragma.hint}) && cmk_pragma_lines= && cmk_join= \
&& { if [ -n "$${cmk_pragma}" ]; then \
		_pout=$$(printf '%s' "$${cmk_pragma}" | ${jq.run.pipe} -r 'to_entries[]? | (if .key!=(.key|ascii_downcase) then "#WARN \(.key)" else empty end), "export CMK_PRAGMA_\(.key|ascii_upcase|gsub("[.-]";"_")) := \(if (.value|type)=="array" then (.value|join(" ")) else (.value|tostring) end)"' 2>/dev/null || true) ; \
		cmk_pragma_lines=$$(printf '%s\n' "$${_pout}" | grep '^export ' || true) ; \
		_pwarn=$$(printf '%s\n' "$${_pout}" | sed -n 's/^#WARN //p' | tr '\n' ' ') ; \
		[ -z "$${_pwarn}" ] || $(call log.compiler, ${yellow}mk.compile ${sep}${no_ansi_dim} pragma ${sep} prefer lowercase keys ${sep} ${no_ansi}$${_pwarn}) ; \
		cmk_join=$$(printf '%s\n' "$${cmk_pragma_lines}" | sed -n 's/^export CMK_PRAGMA_RECIPE_JOIN := //p') ; \
		_pnames=$$(printf '%s\n' "$${cmk_pragma_lines}" | sed -E 's/ :=.*//;s/^export //' | tr '\n' ' ') ; \
		[ -z "$${cmk_pragma_lines}" ] || $(call log.compiler, ${dim}mk.compile ${sep} pragma ${sep} ${ital}$${_pnames}${no_ansi}) ; \
	fi ; true ; } \
&& export CMK_INTERNAL=1 \
&& printf "#!/usr/bin/env -S __interpreting__=$${__interpreting__:-stdin} ${__interpreter__} mk.interpret\nMAKEFILE_LIST+=${CMK_SRC}\n" \
&& { [ -z "$${cmk_pragma_lines}" ] || printf '%s\n' "$${cmk_pragma_lines}" ; } \
&& __interpreting__=$${__interpreting__:-stdin} \
	${make} mk.src \
&& case $${CMK_COMPILER_STEPWISE:-0} in \
	1) cat $${inputf} | style=monokai lexer=makefile ${make} $${runner}/mk.preprocess,io.awk/.awk.dispatch,io.awk/.awk.joinbody,_mk.compile.imports ;; \
	*) cat $${inputf} | ${make} mk.preprocess | awk "$${_cmk_blk_dispatch}" | awk -v JOIN="$${cmk_join:-$${CMK_RECIPE_JOIN:-&&}}" "$${_cmk_blk_joinbody}" | ${make} _mk.compile.imports ;; \
	esac
endef

mk.compile! mk.compiler!:
	@# Like `mk.compile`, but also embeds the result thus removing the include 
	@# for `compose.mk` to produce a completely stand-alone file.  See also: `mk.fork.guest`
	${flux.pipeline}/mk.compile,mk.preprocess.minify | sed "\|^MAKEFILE_LIST+=${CMK_SRC}|d" | ${make} mk.fork.guest


mk.kernel:
	@# Executes the input data on stdin as a kind of "script" that
	@# runs inside the current make-context.  This basically allows
	@# you to treat targets as an instruction-set without any kind
	@# of 'make ... ' preamble.
	@#
	@# This is the BATCH form: the whole stream becomes one `make instr1 instr2 ..`
	@# invocation, so it realizes a *set* of goals once (make builds each at most
	@# once; whitespace separates instructions).  For a *program* (where order &
	@# repetition matter, or a line carries an argument) use `mk.kernel.each`,
	@# which dispatches per line instead.
	@#
	@# USAGE: ( concrete )
	@#  echo flux.ok | ./compose.mk kernel
	@#  echo flux.and/flux.ok,flux.ok | ./compose.mk kernel
	@#
	instructions="`${stream.stdin} | ${stream.nl.to.space}`" \
	&& count=`printf "$${instructions}" | ${stream.count.words}` \
	&& $(call log.target.part1, parsing input stream as instructions ) \
	&& $(call log.target.part2, ${yellow}$${count}${no_ansi_dim} total) \
	&& ${trace_maybe} && ${make} $${instructions}

mk.kernel.each:
	@# Iterative sibling of `mk.kernel`: runs each NON-EMPTY line of the input
	@# stream as its own instruction, in order, each in a SEPARATE recursive
	@# `${make}` (so a line may carry an argument, e.g. `target/arg`).  Fails fast.
	@#
	@# Where `mk.kernel` collapses the whole stream to whitespace and runs it as
	@# ONE `make instr1 instr2 ..` invocation, this re-enters make per line.  That
	@# distinction matters for stateful / repeating programs, because of two
	@# properties of the batch form: (1) make builds each goal at most once per
	@# invocation, so `mk.kernel` would silently DEDUP a repeated instruction;
	@# (2) the whitespace-collapse splits a line that carries an argument.
	@# `mk.kernel.each` preserves both repeats and per-line arguments; use it
	@# when the stream is a *program* (order + repetition significant), and plain
	@# `mk.kernel` when it is just a *set* of goals to realize once.
	@#
	@# USAGE:
	@#   printf 'flux.ok\nflux.ok\n' | ./compose.mk mk.kernel.each
	@#
	${trace_maybe} && while IFS= read -r instr || [ -n "$${instr}" ]; do \
		[ -z "$${instr}" ] || ${make} "$${instr}" </dev/null || exit $$? ; \
	done

mk.repl.kernel:
	@# The generic REPL eval loop for REPL-as-execution-mode.  Reads one target-name per line on stdin
	@# (fed by the tux.repl input widget) and dispatches each as a FRESH `${__interpreting__}
	@# mk.kernel.each` run -- i.e. an interactive shell over THIS program's whole target namespace
	@# (python -i / irb, for a .cmk).  `trap : INT` keeps the loop alive across a ctrl-c interrupt; the
	@# grep drops the cmk compile-pipeline chatter; the trailing \036 (record-separator) tells the
	@# wrapper the command RETURNED, so its spinner stops.
	@#
	@# This is the DEFAULT eval target the runtime wires when a program enters REPL mode via a
	@# `# cmk_pragma ::: { "repl": true } :::` header (`cmk run`) or via `cmk repl <file>`; you do not
	@# normally call it directly.  `${__interpreting__}` is the compiled program, so the file itself
	@# needs no tux.repl import or host_only boilerplate.  At launch it lists the program's LOCAL target
	@# namespace from CMK_REPL_TARGETS (scraped from the source by the runtime; see `_cmk.repl.launch`).
	{ [ -z "$${CMK_REPL_TARGETS:-}" ] || { printf 'local targets:\n' ; for t in $${CMK_REPL_TARGETS}; do printf '  %s\n' "$$t" ; done ; printf '\036\n' ; } ; } ; trap ':' INT ; while IFS= read -r w; do [ -z "$$w" ] && continue ; printf '%s\n' "$$w" | ${__interpreting__} mk.kernel.each 2>&1 | grep -avE '✱|flux[.]timer|cmk run|deduplicated|__main__|minify decorators|blockref triplequote|starting interpreter|mk[.]interpret|mk[.]src|Generating source' || true ; printf '\036\n' ; done

mk.repl.modeline:
	@# Default `read` target for the tux.repl mode-line (the env-driven REPL status line): emit one
	@# JSON object per line (~1Hz) and let the Go wrapper own all styling/glyphs/truncation -- this
	@# only supplies DATA.  This is the runtime successor to (and generalization of) the demo-local
	@# `overlay.read`: it ALWAYS emits a runtime fingerprint (cli/lvl/bin/plugins/modules), and NESTS
	@# a `vm` sub-object reflecting the live __vm__ control stack ONLY when virtual-machine.cmk is imported (a
	@# make-time __plugins__.has gate -- so stale .tmp.* files from a prior non-vm run are ignored)
	@# AND a frames file exists; otherwise `vm` is null and the Go side renders just the diagnostics.
	@#   cli   -- the REPL'd program's CLI, bridged in as CMK_REPL_CLI by the launcher (falls back to
	@#            this read child's own MAKE_CLI, which is just `... mk.repl.modeline`).
	@#   vm    -- {chain,ip,k,e}: chain = the frames' goals + the top frame's pending continuation,
	@#            ip = the innermost goal (the bold instruction pointer), k = stack depth, e = env.
	@# One jq call per tick (jq.run prefers a LOCAL jq; --slurpfile of /dev/null yields [] when a file
	@# is absent).  The trailing printf is a belt-and-suspenders fallback so a jq hiccup still emits
	@# VALID JSON (keeping the Go parser on its happy path).
	@np=`echo $${__plugins__} | wc -w | tr -d ' '`; nm=`echo $${__modules__} | wc -w | tr -d ' '`; \
	bin=`basename "$${CMK_BIN:-compose.mk}"`; cli="$${CMK_REPL_CLI:-$${MAKE_CLI}}"; \
	while true; do f=; e=; \
	  $(if $(call __plugins__.has,virtual-machine.cmk),f=`ls .tmp.CONTROL_STACK_FRAMES.* 2>/dev/null | head -1`; e=`ls .tmp.cmk.vmenv.* 2>/dev/null | head -1`;,:;) \
	  ${jq.run} -nc --arg cli "$$cli" --arg bin "$$bin" --argjson lvl "$${MAKE_LEVEL:-0}" \
	    --argjson np "$$np" --argjson nm "$$nm" \
	    --slurpfile fr "$${f:-/dev/null}" --slurpfile ev "$${e:-/dev/null}" \
	    '($$fr[0]//null) as $$frames | ($$ev[0]//{}) as $$env | {cli:$$cli,lvl:$$lvl,bin:$$bin,plugins:$$np,modules:$$nm,vm:(if ($$frames|type)=="array" and ($$frames|length)>0 then {chain:(($$frames|map(.goal))+(($$frames[-1].cont//"")|split(" ")|map(select(length>0))))|join(" "),ip:($$frames[-1].goal//""),k:($$frames|length),e:$$env} else null end)}' 2>/dev/null \
	    || printf '{"cli":"%s","lvl":0,"bin":"%s","plugins":%s,"modules":%s,"vm":null}\n' "$$cli" "$$bin" "$${np:-0}" "$${nm:-0}"; \
	  sleep 1; \
	done

mk.src:
	@# Returns source-code for this make-context (excluding compose.mk).
	@# This effectively flattens includes, basically concatenating 
	@# MAKEFILE_LIST in reverse order, and is used internally as part 
	@# of mk.compile.  This has a different meaning if called from extensions
	@# 
	$(call assert.env,__script__)
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

# Join `\`-continuation lines into one logical line (stdin->stdout), outside of
# define..endef blocks (depth-tracked), which pass through verbatim.  Used by the
# minify stage so later passes see one statement per recipe line.
define .awk.zip.linefeeds
BEGIN { def_depth = 0; continuation_line = "" }
/^define / { def_depth++; print; next }
/^endef[ \t]*$/ { if (def_depth > 0) def_depth--; print; next }
def_depth > 0 { print; next }
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
# Python-style indentation for CMK recipe bodies (stdin->stdout): tab-indented lines
# pass through verbatim; a space-indented body is normalized to a single leading tab,
# requiring one consistent indent.  Errors (cmk_die) on tabs+spaces mixed in one
# indent, or inconsistent space-indents within a body.  Skips define..endef bodies
# (depth-tracked).  FLAG: bundles validation + normalization + error reporting.
define .awk.cmk.indent
BEGIN { def_depth = 0; space_unit = "" }
/^define / { def_depth++; space_unit = ""; print; next }
/^endef[ \t]*$/ { if (def_depth > 0) def_depth--; print; next }
def_depth > 0 { print; next }
/^[ \t]*$/ { print; next }
/^[ \t]/ {
    match($0, /^[ \t]*/); lead = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH+1)
    if (lead ~ /\t/ && lead ~ / /) cmk_die("indent", "indentation mixes tabs and spaces: " rest)
    if (lead ~ / /) {
        if (space_unit == "") space_unit = lead
        else if (lead != space_unit) cmk_die("indent", "inconsistent indentation in recipe body (expected " length(space_unit) " spaces): " rest)
        print "\t" rest
    } else print $0
    next
}
{ space_unit = ""; print }
endef
# The CMK preprocess stages, in pipeline order -- single source of truth for the fused
# pipeline (`.cmk.<stage>` macros), the stepwise flux.pipeline target-list
# (`mk.preprocess.<stage>`), and the verbose fused-pipeline log line.
cmk.stages=minify decorators dialect sugar receivers tagged callform blockref triplequote indent imports call assign unsentinel
mk.preprocess: flux.timer/.mk.preprocess
.mk.preprocess:
	@# Runs the CMK input preprocessor on stdin.
	@# Default: a fused single-process pipeline (the four stages composed via
	@# their macros, no make-per-stage). CMK_COMPILER_STEPWISE=1 keeps the
	@# step-wise flux.pipeline of the stage *targets* (per-stage previews) for
	@# debugging. Both compose the same stage logic, so output is identical.
	$(call io.mktemp) && export inputf=$${tmpf} \
	&& ${stream.stdin} > $${inputf} \
	&& export cmk_dialect=$$(cat $${inputf} | ${.cmk.parse.dialect.hint}) \
	&& export cmk_sugar=$$(cat $${inputf} | ${.cmk.parse.sugar.hint}) \
	&& export RECEIVERS=$$(cat $${inputf} | ${.cmk.scan.receivers}) \
	&& $(call log.compiler.maybe, $${RECEIVERS// }, mk.preprocess.receivers ${sep}${dim} declared ${sep} ${ital}$${RECEIVERS}${no_ansi}) \
	&& case $${CMK_COMPILER_STEPWISE:-0} in \
		1) cat $${inputf} \
			| ${make} flux.pipeline/$(subst $(space),$(comma),$(addprefix mk.preprocess.,$(cmk.stages))) ;; \
		*) $(call log.compiler.fmt, mk.preprocess ${sep}${dim} fused pipeline, ${dim}${ital}$(cmk.stages)${no_ansi}) \
			&& cat $${inputf} $(foreach _s,$(cmk.stages), | $(.cmk.$(_s))) ;; \
	esac \
	| ${stream.nl.compress} \
	&& printf '\n'

# Stage transforms as composable macros (single source of truth): the stage
# targets below wrap these for standalone/debug use, and the fused fast path in
# `.mk.preprocess` chains them in one process (no make-per-stage). Each is a
# stdin->stdout pipe fragment.
.cmk.minify=grep -a -v '^\#' | sed '/^[ \t]*@\#.*$$/d' | awk "$${_cmk_blk_zip}"
.cmk.indent=awk "$${_cmk_blk_indent}"
.cmk.imports=awk "$${_cmk_blk_imports}"
.cmk.call=awk "$${_cmk_blk_call}"
.cmk.assign=awk "$${_cmk_blk_assign}"
.cmk.unsentinel=awk "$${_cmk_blk_unsentinel}"
.cmk.receivers=awk -v RECEIVERS="$${RECEIVERS}" "$${_cmk_blk_receivers}"
# Pre-scan: extract receiver names from the source's `declare.*`/`*.import` calls + sugar blocks --
# the namespaces that scaffold a `<name>.<method>` target family.  Emits a deduped space-list for the
# receivers stage's -v RECEIVERS.  Per kind:
#   channel / module / def / target import -- `namespace=NAME`, and the `⦖ .. ⦕ as NAME` sugar
#                 (as-clause); `chan=NAME` is still accepted for channels as a legacy alias
#   polyglot / single-image container -- `def=NAME` (block-name namespace; anchored to
#                 polyglot/container tokens so a module's *source* `def=` never leaks in)
#   sugar blocks -- `⟦ NAME` (polyglot), `🞹 NAME` (code), `⫻ Dockerfile.NAME` (image; prefix stripped)
# Over-registration is harmless: the receivers stage only fires on `NAME.method<call-suffix>` in recipe
# content.  Multi-service compose keeps the `ᐉ`/`.dispatch` send -- its service names are dynamic (from
# the compose file), so a compile-time scan cannot know them.
.cmk.scan.receivers=( grep -aoE 'declare\.channel[^)]*chan=[A-Za-z0-9._-]+|namespace=[A-Za-z0-9._-]+|(declare\.polyglots?|polyglots?\.import|declare\.container|docker\.import)[^)]*def=[A-Za-z0-9._-]+|⦕[ \t]*as[ \t]+[A-Za-z0-9._-]+|(⟦|🞹|⫻)[ \t]*[A-Za-z0-9._-]+' || true ) | sed -E 's/.*(chan=|namespace=|def=|as[ \t]+)//; s/^(⟦|🞹|⫻)[ \t]*//; s/^Dockerfile\.//' | sort -u | tr '\n' ' '
.cmk.decorators=awk "$${_cmk_blk_dec}"
# Dialect/sugar as pipe-stage macros (verbatim transcription of the target bodies
# below; only `${@}` -> literal name and `#` -> `\#` for the make-variable comment
# trap). Wrapped in (...) so they compose in the fused pipeline; each reads stdin
# at its eval and writes stdout. NB: literal `#` inside a make *variable* starts a
# comment, hence the `\#`.
.cmk.dialect=( $(call io.mktemp) && hint_file=$${tmpf} && case $${cmk_dialect} in "") ( dialect=$${dialect:-cmk.default.dialect} && $(call log.compiler, mk.preprocess.dialect ${sep}${dim} using ${ital}$${dialect}) && if [ "$${dialect}" = cmk.default.dialect ]; then printf '%s' "$${_cmk_blk_dialect}" > $${hint_file}; else ${mk.def.read}/$${dialect} > $${hint_file}; fi );; *) ( $(call log.compiler, mk.preprocess.dialect ${sep}${dim} using dialect from file) && printf "$${cmk_dialect}" > $${hint_file} && printf "\# cmk_dialect ::: $${cmk_dialect} :::\n" );; esac && $(call io.mktemp) && parser_file=$${tmpf} && cat $${hint_file} | ${jq} -r ".[] | \" | awk -v bs='\\\\\\\\' -v amp='&' -v old='\(.[0])' -v new='\(.[1])' '${.awk.preprocess.dialect}'\"" > $${parser_file} && printf '\n' && ${stream.stdin} | eval ${stream.stdin} `cat $${parser_file}` && printf "\# finished mk.preprocess.dialect $${cmk_dialect}" )
.cmk.sugar=( $(call io.mktemp) && hint_file=$${tmpf} && case $${cmk_sugar} in "") ( sugar=$${sugar:-cmk.default.sugar} && $(call log.compiler, mk.preprocess.sugar ${sep}${dim} using ${ital}$${sugar}) && if [ "$${sugar}" = cmk.default.sugar ]; then printf '%s' "$${_cmk_blk_sugar}" > $${hint_file}; else ${mk.def.read}/$${sugar} > $${hint_file}; fi );; *) ( $(call log.compiler, mk.preprocess.sugar ${sep}${dim} using sugar from file) && printf "$${cmk_sugar}" > $${hint_file} && printf "\# cmk_sugar ::: $${cmk_sugar} :::\n" );; esac && $(call io.mktemp) && parser_file=$${tmpf} && $(call io.mktemp) && sugar_awk=$${tmpf} && printf '%s' "$${_cmk_blk_sugarawk}" > $${sugar_awk} && cat $${hint_file} | ${jq} -r ".[] | \" | awk -f $${sugar_awk} '\(.[0])' '\(.[1])' '\(.[2])' \"" > $${parser_file} && eval cat /dev/stdin `cat $${parser_file}` && printf "\# finished mk.preprocess.sugar $${cmk_sugar}" )
.cmk.triplequote=awk "$${_cmk_blk_triplequote}"
.cmk.blockref=awk "$${_cmk_blk_blockref}"
.cmk.tagged=awk "$${_cmk_blk_tagged}"
.cmk.callform=awk "$${_cmk_blk_callform}"
mk.preprocess.minify:; ${stream.stdin} | ${.cmk.minify}
	@# Assuming stdin is makefile source, minifies it and outputs to stdout
mk.preprocess.indent:; ${stream.stdin} | ${.cmk.indent}
	@# Normalizes python-style recipe-body indentation on stdin: space-indented
	@# bodies are rewritten to a leading tab; tab-indented bodies pass through.
	@# Errors on mixed (tabs+spaces in one indent) or mismatched indentation.
	@# Runs LAST, after sugar has lowered its literal blocks to define..endef,
	@# which this skips verbatim (so no sugar/dialect syntax is hardcoded here).
mk.preprocess.imports:; ${stream.stdin} | ${.cmk.imports}
	@# Lowers the fixed import-name sugar `NAME(args)` -> `$(call NAME,args)` on stdin
	@# (compose.import*/polyglot*/import.*).  Balanced+recursive via the shared lower_calls.
mk.preprocess.call:; ${stream.stdin} | ${.cmk.call}
	@# Lowers the generic macro-call sugar `cmk.NAME(args)` -> `$(call NAME,args)` on stdin
	@# (balanced + recursive).  Runs after imports, before assign.
mk.preprocess.receivers:; ${stream.stdin} | ${.cmk.receivers}
	@# Anchorless receiver sends on stdin: injects `${make} ` before `R.method...` for each
	@# declared receiver R (RECEIVERS env, scanned from `declare.*` in the source), so the
	@# tagged/callform stages then lower it like a `this.` send.  Runs after sugar, before tagged.
	@# Inert when RECEIVERS is empty (the standalone case) and inside define..endef.
mk.preprocess.assign:; ${stream.stdin} | ${.cmk.assign}
	@# Lowers the `⇐` assignment operator on stdin (`LHS ⇐ RHS` -> `LHS=` + backtick-RHS).
	@# Runs LAST of the call-lowering stages (RHS using this./cmk.() is already lowered).
mk.preprocess.unsentinel:; ${stream.stdin} | ${.cmk.unsentinel}
	@# Restores the macro-anchor sentinel `؆` back to `cmk.` on stdin -- any `؆` surviving the
	@# call stages is a `cmk.` that was not a call (text/string).  Runs LAST in the chain.
mk.preprocess/%:
	@# A version of `mk.preprocess` that accepts a file-arg.
	@#
	@# USAGE: ./compose.mk mk.preprocess/<fname>
	@#
	fname=${*} && case ${*} in -) fname=/dev/stdin;; esac \
	&& cat $${fname} | ${make} mk.preprocess
mk.preprocess.decorators:; ${stream.stdin} | ${.cmk.decorators}
	@# Runs the decorator-preprocessor on stdin.
	@# NB: This must come before sugar/dialects.
define .awk.decorators
# CMK bind-declarations (`ᝏ`) are written on the line(s) IMMEDIATELY ABOVE a
# target (python-decorator style).  By DEFAULT they relocate to the LEADING recipe
# line(s) of that target, so the later joinbody pass chains `decorator && body` into
# one shell (the decorator's exports/bindings then reach every recipe line).  A
# decorator carrying a `postfix_mode=<conn>` kwarg instead relocates to AFTER the
# body, chained to it by <conn> -- one of `&&` (default; run after success), `;` (run
# always), or `||` (run only on failure: a per-target catch).  The kwarg is stripped
# before the macro call.  A decorator can also declare a DEFAULT mode via a companion
# `bind.<name>.postfix_mode := <conn>` line (scanned here into pdefault[]), so a bare
# `ᝏ<name>` is treated as postfix without repeating the kwarg; an explicit kwarg still
# wins.  The compiler runs BEFORE the compiled makefile's vars exist, so this default
# must be visible in the SOURCE TEXT (hence a scanned companion line, not $(eval)) and
# must appear before the decorator is used.  The dialect lowers `ᝏfoo(a)` ->
# `cmk.bind.foo(a)` -> `$(call bind.foo,a)`.  Body lines are re-emitted VERBATIM (they
# keep their own tab/space indent, which the indent stage normalises); only injected
# decorator lines get a leading tab.  joinbody honours a line's trailing connector, so
# a non-`&&` postfix mode is realised by appending <conn> to the PRECEDING emitted line.
function is_target(s) { return (s ~ /^[^\t#][^=]*:([^=]|$)/) }
function classify(line,   conn, cleaned, name) {
    # Sort a buffered `ᝏ...` line into pre[] (prefix) or post[]/postc[] (postfix).  An
    # explicit `postfix_mode=` kwarg wins; otherwise consult the pdefault[] registry.
    conn = ""
    if (line ~ /postfix_mode/) {
        conn = line; sub(/.*postfix_mode=?/, "", conn); sub(/[,)].*/, "", conn)
        if (conn == "") conn = "&&"
        cleaned = line
        sub(/[ \t]*,?[ \t]*postfix_mode(=[^,)]*)?[ \t]*/, "", cleaned)
        sub(/\([ \t]*,[ \t]*/, "(", cleaned)
    } else {
        name = line; sub(/^ᝏ/, "", name); sub(/\(.*/, "", name); sub(/[ \t]+$/, "", name)
        if (name in pdefault) conn = pdefault[name]
        cleaned = line
    }
    if (cleaned !~ /\(/) cleaned = cleaned "()"
    if (conn == "") { pren++; pre[pren] = cleaned; return }
    if (conn != "&&" && conn != ";" && conn != "||") cmk_die("decorators", "postfix_mode must be one of: && ; || (got: " conn ")")
    postn++; post[postn] = cleaned; postc[postn] = conn
}
function emit_chain(first, firsttab,   k, n, txt) {
    # Emit [first] + post[1..postn] as recipe lines.  postc[k] is the connector that
    # PRECEDES post[k]; append it to the previous element so joinbody uses it.  `first`
    # is the last body line (firsttab="") or an inline recipe (firsttab="\t").
    n = 1; cseq[1] = first; ctab[1] = firsttab; cconn[1] = ""
    for (k = 1; k <= postn; k++) { n++; cseq[n] = post[k]; ctab[n] = "\t"; cconn[n] = postc[k] }
    for (k = 1; k <= n; k++) {
        txt = ctab[k] cseq[k]
        if (k < n) txt = txt " " cconn[k+1]
        print txt }
}
function emit_post(   k) {
    # Flush a deferred postfix target: body lines (last one joined to the postfix
    # chain), then the postfix decorators.  A body-less target degrades to plain lines.
    if (bn >= 1) { for (k = 1; k < bn; k++) print body[k]; emit_chain(body[bn], "") }
    else { for (k = 1; k <= postn; k++) print "\t" post[k] }
    bn = 0; postn = 0; inpost = 0
}
BEGIN { in_def = 0; pren = 0; postn = 0; bn = 0; inpost = 0 }
{
    if (inpost) {
        if ($0 ~ /^[ \t]*$/) { emit_post(); print; next }
        if ($0 ~ /^[ \t]/) { body[++bn] = $0; next }
        emit_post()
    }
    if ($0 ~ /^bind\..*\.postfix_mode[ \t]*:?=/ && !in_def) {
        dname = $0; sub(/^bind\./, "", dname); sub(/\.postfix_mode[ \t]*:?=.*/, "", dname)
        dmode = $0; sub(/.*\.postfix_mode[ \t]*:?=[ \t]*/, "", dmode); sub(/[ \t]*$/, "", dmode)
        pdefault[dname] = dmode; print; next
    }
    if ($0 ~ /^ᝏ/ && !in_def) { classify($0); next }
    if (pren > 0 || postn > 0) {
        if ($0 ~ /ᝏ/) cmk_die("decorators", "inline decorators (target: ᝏ...) are no longer supported; put ᝏ on the line ABOVE the target")
        if (!is_target($0)) cmk_die("decorators", "a ᝏ decorator must be immediately above a target (no blank line between)")
        r = index($0, ";"); c = index($0, ":")
        if (r > c) {
            hdr = substr($0, 1, r-1); rec = substr($0, r+1); sub(/^[ \t]+/, "", rec)
            print hdr; for (i = 1; i <= pren; i++) print "\t" pre[i]
            emit_chain(rec, "\t"); pren = 0; postn = 0; next }
        else {
            print $0; for (i = 1; i <= pren; i++) print "\t" pre[i]; pren = 0
            if (postn > 0) { inpost = 1; bn = 0 }
            next }
    }
    if ($0 ~ /^define /) { in_def = 1; print; next }
    if ($0 ~ /^endef[ \t]*$/) { in_def = 0; print; next }
    if (in_def) { print; next }
    if ($0 ~ /ᝏ/ && is_target($0)) cmk_die("decorators", "inline decorators (target: ᝏ...) are no longer supported; put ᝏ on the line ABOVE the target")
    print $0
}
END { if (inpost) emit_post(); if (pren > 0 || postn > 0) cmk_die("decorators", "trailing ᝏ decorator has no target") }
endef
	
mk.preprocess.dialect:; ${.cmk.dialect}
	@# Runs dialect preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	@# (body lives in the `.cmk.dialect` macro, shared with the fused fast path.)
# LITERAL (not regex) substitution of `old`->`new` outside define-blocks.  `old`/`new` arrive via
# `-v` (per rule); BEGIN regex-escapes the pattern's ERE metacharacters so the subsequent gsub
# matches them as plain text -- a `.` in a dialect keyword is a literal dot, never a wildcard (the
# bare gsub treated `old` as an ERE, which silently corrupted `cmk/`, `cmk)`, the `.cmk` ext, ...).
# `bs` (a backslash) and `amp` come in via `-v` too: this awk source can hold NO string literal
# (its `"` would close the embedding jq string), NO `$` and NO literal `\` (the jq/eval layer that
# assembles the per-rule invocation would eat them) -- hence implicit-$0 gsub + param-fed escapes.
.awk.preprocess.dialect=\
	BEGIN{ block=0; gsub(/[].*+?(){}|[]/, bs bs amp, old); gsub(/[&]/, bs bs amp, new) } /^define/{block=1} /^endef/{block=0} !block{gsub(old,new)} 1

mk.preprocess.sugar:; ${.cmk.sugar}
	@# Runs sugar-preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	@# (body lives in the `.cmk.sugar` macro, shared with the fused fast path.)

mk.preprocess.triplequote:; ${.cmk.triplequote}
	@# Lowers `'''..'''`/`"""..."""` literals to `printf` on stdin.
	@# Part of the CMK->Makefile transpilation process.
	@# (body lives in the `.cmk.triplequote` macro, shared with the fused fast path.)
mk.preprocess.tagged:; ${.cmk.tagged}
	@# Lowers CMK tagged callable-target sugar on stdin: `${make} NAME'''X'''` ->
	@# `'''X''' | ${make} NAME`.  Runs after dialect, before callform/triplequote.
	@# (body lives in the `.cmk.tagged` macro, shared with the fused fast path.)
mk.preprocess.callform:; ${.cmk.callform}
	@# Lowers CMK unified call-form sugar on stdin for BOTH anchors: `(args)` = arguments,
	@# `[stream]` = stdin (either order).  Macro `cmk.NAME(a,b)[S]` -> `S | cmk.NAME(a,b)`
	@# (the late `.awk.cmk.call` stage finishes it); target `${make} NAME(a,b)[S]` ->
	@# `S | ${make} NAME/a,b`.  Runs after dialect+tagged, before blockref/triplequote.
	@# (body lives in the `.cmk.callform` macro, shared with the fused fast path.)
mk.preprocess.blockref:; ${.cmk.blockref}
	@# Lowers CMK block-reference glyphs on stdin: `⬦NAME` -> a stream FD via
	@# `<($(call _mk.def.to.fd, NAME))`, `⬥NAME` -> a real local file via
	@# `$(call _mk.def.tmpfile, NAME)`.  Runs after callform.  Inert inside define..endef.
	@# (body lives in the `.cmk.blockref` macro, shared with the fused fast path.)
# Header-hint parsers as single-source macros: extract the `:::`-delimited JSON
# from a `# cmk_dialect/sugar ::: ... :::` header comment. The targets below wrap
# these (kept standalone/debug-invocable + tested); `.mk.preprocess` expands them
# INLINE (no make-per-hint re-parse). NB: a literal `#` in a make *variable*
# starts a comment, hence the `\#` throughout (cf. `.cmk.minify`).
.cmk.parse.sugar.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/{exit}'` && rest="$${tmp\#*cmk_sugar :::}" && if [ "$${rest}" = "$${tmp}" ]; then true ; else echo "$${rest//:::*}" | sed 's/^\#//g' | ${jq.run.pipe} -c ; fi ) 2>/dev/null || true
# Compiler pragma hint: a JSON object of per-program knobs in a `# cmk_pragma ::: { ... } :::` header.
# Each key `foo` is normalized (upcase, `.`/`-`->`_`) and the compiler exports it as `CMK_PRAGMA_FOO` -- a
# namespace the compiler ALONE writes, so a pragma can never clobber an internal `CMK_*` var.  Consumers
# read it back through the `cmk.pragma` / `cmk.pragma.append` resolvers (pragma > env > default).  Values
# may be scalars (replace) or arrays (a list that ACCUMULATES via cmk.pragma.append).  `recipe_join` (the
# block-body join &&/;/none) is just the key the joinbody reads at compile time.  Marker-aware (coexists
# with cmk_dialect/cmk_sugar); GATED on the marker + piped via ${jq.run.pipe} so a no-pragma file does NO
# jq work and a dockerized jq (host has none) still reads stdin (plain ${jq} lacks docker `-i`).
# REACHABILITY: a pragma value lands as a make-var (parse/recipe time), so it cannot configure the
# EARLY bash-header / supervisor context -- CMK_SUPERVISOR, CMK_DISABLE_HOOKS, CMK_BOOTLOADER_DISABLED,
# CMK_SUPERVISOR_STEP_HOOK and the compile-stage CMK_COMPILER_* stay shebang/env-only.  A scalar pragma
# is also a FROZEN commitment (it beats the invoker env, with a supersession warning); use the env var,
# not a pragma, for an invoker-overridable default.
.cmk.parse.pragma.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/{exit}'` && rest="$${tmp\#*cmk_pragma :::}" && if [ "$${rest}" = "$${tmp}" ]; then true ; else echo "$${rest//:::*}" | sed 's/^\#//g' | ${jq.run.pipe} -c ; fi ) 2>/dev/null || true
.cmk.parse.dialect.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/{exit}'` && rest="$${tmp\#*cmk_dialect :::}" && if [ "$${rest}" = "$${tmp}" ]; then $(call log.trace, no dialect hint in file) ; else ( echo "$${rest//:::*}" | sed 's/^\#//g' | ${jq.run.pipe} -c . || ($(call log.target, ${red}failed parsing dialect hint!); exit 79) ) ; fi )

# ── compiler-pragma resolvers (read back what `cmk_pragma` injected as CMK_PRAGMA_*) ──
# io.str.upper(<s>): fork-free uppercase (subst chain over [a-z]); cmk.pragma.key folds a knob name to its
# CMK_PRAGMA_ suffix (upcase + `.`/`-`->`_`), so `vm_legacy`/`vm.legacy`/`VM-LEGACY` all resolve the same.
io.str.upper=$(subst a,A,$(subst b,B,$(subst c,C,$(subst d,D,$(subst e,E,$(subst f,F,$(subst g,G,$(subst h,H,$(subst i,I,$(subst j,J,$(subst k,K,$(subst l,L,$(subst m,M,$(subst n,N,$(subst o,O,$(subst p,P,$(subst q,Q,$(subst r,R,$(subst s,S,$(subst t,T,$(subst u,U,$(subst v,V,$(subst w,W,$(subst x,X,$(subst y,Y,$(subst z,Z,${1}))))))))))))))))))))))))))
cmk.pragma.key=$(subst -,_,$(subst .,_,$(call io.str.upper,$(strip ${1}))))
# cmk.pragma(<name>,<default>)        -- SCALAR / replace (pragma wins, then env, then default).  WARNS
# when a pragma supersedes an INVOKER-set env var (origin environment/command line, not a makefile default).
cmk.pragma=$(call _cmk.pragma.scalar,$(call cmk.pragma.key,${1}),$(if $(filter-out undefined,$(origin 2)),${2}))
_cmk.pragma.warn=$(if $(and $(call mk.var.defined,CMK_PRAGMA_${1}),$(call mk.var.from.invoker,CMK_${1}),$(filter-out $(CMK_${1}),$(CMK_PRAGMA_${1}))),$(warning pragma ${1}=$(CMK_PRAGMA_${1}) supersedes env CMK_${1}=$(CMK_${1})))
_cmk.pragma.scalar=$(call _cmk.pragma.warn,${1})$(or $(call mk.var.opt,CMK_PRAGMA_${1}),$(call mk.var.opt,CMK_${1}),$(strip ${2}))
# cmk.pragma.append(<name>,<default>) -- LIST / accumulate (env value AND pragma BOTH contribute, like +=).
cmk.pragma.append=$(call _cmk.pragma.list,$(call cmk.pragma.key,${1}),$(if $(filter-out undefined,$(origin 2)),${2}))
_cmk.pragma.list=$(or $(strip $(call mk.var.opt,CMK_${1}) $(call mk.var.opt,CMK_PRAGMA_${1})),$(strip ${2}))

.mk.parse.sugar.hint:
	$(call log.trace, ${@} ${sep} parsing sugar hint..)
	${.cmk.parse.sugar.hint}
.mk.parse.dialect.hint:
	$(call log.trace, ${@} ${sep} parsing dialect hint..)
	${.cmk.parse.dialect.hint}

include/%:; $(call mk.yield, MAKEFILE=${*} ${make} -f${*} ${mk.cli.continuation})
	@# Dynamic includes. Experimental stuff for reflection support.
	@#
	@# This works by using code-generation and turning over the execution, 
	@# so it requires the supervisor/signals hack to short-circuit the 
	@# original execution!
	@#
	@# USAGE: ( generic )
	@#   ./compose.mk include/<makefile>
	@#
	@# USAGE: ( concrete )
	@#   ./compose.mk include/demos/no-include.mk foo:flux.ok mk.let/bar:foo bar
	@#

# `_include.set(<kwargs>)` -- include one-or-many files, honoring shared
# `prefix=` (default `.`) and `strict=` (default 1) kwargs.  Each remaining token
# is a bare path or `file=<path>` (absolute paths resolve as-is).  Single-kwargs
# string, like the rest of the import family (`_import.def`, `import.module`,
# `_include`).  The singular and plural verbs below are identical spellings of
# this -- the count is no longer a behavior difference -- per the established
# def/defs, target/targets idiom.
# Each file is routed through `import.module` as a FLAT, VERBATIM file import:
# the module spine's fast-path recognizes that shape and binds the file directly
# (copy-free `include`).  So `include.*` is literally a preset of import.module
# (a plugin = "the module with an empty pipeline").
define _include.set
$(call mk.unpack.kwargs, ${1}, prefix, .)
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(foreach _incf,$(filter-out strict=% prefix=%,$(patsubst file=%,%,$(shell echo "$(strip ${1})"))),$(call import.module, file=${_incf} flat=1 preprocs=stream.echo prefix=$(strip ${kwargs_prefix}) strict=${kwargs_strict}))
endef
# include.file / include.files -- `include` one-or-many cwd-relative (or
# explicit/absolute) makefiles, with the family's import-logging + clean missing
# error.  `strict=0` -> lenient (log + continue).  The `cmk.include.file(<path>)`
# call-sugar lowers to the singular form.
# USAGE: $(call include.file, events.mk)  |  $(call include.files, a.mk b.mk)
include.file=$(eval $(call _include.set, prefix=. ${1}))
include.files=$(eval $(call _include.set, prefix=. ${1}))

# __plugins__ / __modules__ -- registries of what the include/import family has loaded (plugin tokens /
# module names).  Both are EXPORTED, so a spawned re-parsing child (e.g. the tux.repl wrapper's workers)
# inherits "what the parent already loaded".  That is what makes `require` idempotent ACROSS processes: a
# child's `require` sees the inherited entry and skips the re-import (and its staging race) -- the clean
# successor to the host_only=/CMK_HOST flag (use `require` for a child-safe import instead of host_only=1).
# Within ONE process `_include`'s MAKEFILE_LIST check already dedups; the registry adds the cross-process
# layer + a queryable by-NAME list (MAKEFILE_LIST is by staged-path).
export __plugins__ ?=
export __modules__ ?=
# <reg>.has(<name>)      -- non-empty iff <name> (the FIRST word of the arg) is in the registry.
# <reg>.require(<spec>)  -- import <spec> UNLESS its name is already registered; idempotent + child-safe.
# <reg>.assert(<name>)   -- $(error) unless <name> is registered (a dependency check, e.g. for a declaration).
# Module names are the def= name or the file= basename (what `_import.module` registers); plugin names
# are the include tokens (e.g. `tux.repl.cmk`).
__plugins__.has=$(strip $(filter $(firstword ${1}),${__plugins__}))
__modules__.has=$(strip $(filter $(firstword ${1}),${__modules__}))
_mk.module.name=$(or $(strip $(patsubst def=%,%,$(filter def=%,${1}))),$(basename $(notdir $(strip $(patsubst file=%,%,$(filter file=%,${1}))))))
__plugins__.require=$(if $(call __plugins__.has,${1}),,$(call include.plugins,${1}))
__modules__.require=$(if $(call __modules__.has,$(call _mk.module.name,${1})),,$(call import.module,${1}))
_registry.assert.fail=$(call log.import.error,${red}$(1) not loaded: ${bold}$(2)${no_ansi})$(error CMK_REGISTRY_ASSERT)
__plugins__.assert=$(if $(call __plugins__.has,${1}),,$(call _registry.assert.fail,plugin,$(firstword ${1})))
__modules__.assert=$(if $(call __modules__.has,${1}),,$(call _registry.assert.fail,module,$(firstword ${1})))

# CMK_PLUGINS_DIR is a ':'-separated search PATH for plugin/include LOOKUP (like
# $PATH): `include.plugin`/`assert.plugin` try each element, first existing wins.
# Default `.cmk`.  Element 0 is ALSO the single WRITABLE staging dir (CMK_MODULES_DIR)
# and must be a working-dir-relative dir so container-dispatch -- which bind-mounts
# CWD->/workspace and does NOT forward CMK_PLUGINS_DIR -- can see it; absolute elements
# are host-side lookup fallbacks only.  (Path elements may not contain spaces.)
export CMK_PLUGINS_DIR?=.cmk
# Where `import.module` STAGES + imports materialized modules (the `.tmp.module.*`
# files).  A SINGLE writable dir -- the FIRST element of CMK_PLUGINS_DIR by default
# (never the whole colon-path), which keeps the just-staged re-include and mk.clean
# single-dir and the staging dir container-mountable.
export CMK_MODULES_DIR?=$(firstword $(subst :, ,${CMK_PLUGINS_DIR}))
# _mk.path.split(<path>) -- split a ':'-separated search path into space-joined dirs.
_mk.path.split=$(subst :, ,$(1))
# _mk.path.resolve(<prefix>,<file>) -- resolve <file> against a (possibly ':'-path)
# <prefix> to a SINGLE path:
#   * absolute <file> (/...)   -> used as-is;
#   * single-element <prefix>  -> <prefix>/<file>, with NO $(wildcard) probe (so a
#     just-staged module file -- a wildcard-cache miss this run -- re-includes by its
#     literal path exactly as before);
#   * multi-element <prefix>   -> first EXISTING <dir>/<file> across the path, else a
#     <first-element>/<file> fallback (so the strict-missing error + mkdir still name
#     a sensible dir).  Pure make builtins -- no $(shell), no per-parse fork.
_mk.path.resolve=$(strip $(if $(filter /%,$(strip $(2))),$(strip $(2)),$(if $(filter 1,$(words $(call _mk.path.split,$(1)))),$(strip $(1))/$(strip $(2)),$(firstword $(wildcard $(foreach d,$(call _mk.path.split,$(1)),$(strip $(d))/$(strip $(2)))) $(firstword $(call _mk.path.split,$(1)))/$(strip $(2))))))
# cmk.plugin.find(<name>) -- RECIPE-time bash: echo the first <dir>/<name> on the
# CMK_PLUGINS_DIR search path that exists (empty if none).  IFS=: is subshell-local +
# POSIX-portable (busybox/macOS).  Use this anywhere bash needs to locate a plugin file
# (the raw ${CMK_PLUGINS_DIR}/<name> breaks once the value holds a colon).
cmk.plugin.find=$(shell n='$(strip $(1))'; p="$$CMK_PLUGINS_DIR"; IFS=:; for d in $$p; do [ -f "$$d/$$n" ] && { printf '%s' "$$d/$$n"; break; }; done)
# File EXTENSIONS that mark a plugin as cmk-lang (the JIT-compile path).  Covers
# the `.cmk` and `.CMK` spellings plus the `.cmk.mk`/`.CMK.mk` double-extension (a
# `.mk` tail so editors/tooling treat it as a makefile, the inner `.cmk` marking
# the source dialect).  Used by both the `filter` and `filter-out` sides below so
# the partition can't drift.
_mk.cmk.exts:=%.cmk %.CMK %.cmk.mk %.CMK.mk
# include.plugin / include.plugins -- include one-or-many plugins from
# CMK_PLUGINS_DIR.  The plugin's EXTENSION decides how it binds:
#   *.mk                 -> verbatim `include` (fast, copy-free) via _include.set
#                           -- plain-make plugins stay simple.
#   *.cmk / *.cmk.mk     -> JIT-compile (lower via mk.compile) THEN include, via
#     (and .CMK variants)    import.module (flat=1) -- a cmk-lang plugin, lowered
#                           at include time whether we arrived via `make -f` or
#                           `cmk run`.  See _mk.cmk.exts.
# `strict=1` (default) errors on a missing plugin; `strict=0` logs + continues
# (honored for BOTH kinds).  `prefix=` may be overridden (defaults to
# CMK_PLUGINS_DIR).  The .cmk existence/strict/logging policy lives HERE (mirroring
# _include) so the general import.module primitive stays untouched; .mk just
# delegates to _include.set.
# USAGE: $(call include.plugin, foo.mk)  |  $(call include.plugins, a.mk b.cmk strict=0)
include.plugin=$(eval $(call _include.plugins, ${1}))
include.plugins=$(eval $(call _include.plugins, ${1}))
define _include.plugins
$(call mk.unpack.kwargs, ${1}, prefix, ${CMK_PLUGINS_DIR})
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(eval _mkip_files:=$(filter-out strict=% prefix=%,$(patsubst file=%,%,$(shell echo "$(strip ${1})"))))
$(if $(filter-out ${_mk.cmk.exts},${_mkip_files}),$(call _include.set, prefix=$(strip ${kwargs_prefix}) strict=$(strip ${kwargs_strict}) $(filter-out ${_mk.cmk.exts},${_mkip_files})))
$(foreach _mkip_c,$(filter ${_mk.cmk.exts},${_mkip_files}),$(call _include.cmk.one,$(call _mk.path.resolve,${kwargs_prefix},${_mkip_c}),$(strip ${kwargs_strict}),${_mkip_c}))
$(if ${_mkip_files},$(eval __plugins__:=$(sort ${__plugins__} ${_mkip_files})))
endef
# _include.cmk.one(<resolved-path>,<strict>,<orig-token>) -- bind ONE cmk-lang
# plugin: lower it (mk.compile, via import.module flat=1) then include at root,
# mirroring _include's strict policy + import-logging for a missing source.
define _include.cmk.one
$(if $(wildcard ${1}),$(call import.module, file=${1} flat=1)$(call log.import.part1, include ${sep} ${dim}strict=${ital}${2} ${sep} ${dim_ital}${3} )$(call log.import.part2, ${GLYPH_CHECK} ${dim}(cmk lowered)),$(call log.import.part1, include ${sep} ${dim}strict=${ital}${2} ${sep} ${dim_ital}${3} )$(if $(filter 0,$(strip ${2})),$(call log.import.part2, ${dim}${1}${no_ansi} ${GLYPH_XXX} (missing -- skipping)),$(call log.import.part2, ${GLYPH_XXX}${1}${no_ansi} (missing))$(call log.import.error, ${red}Declared cmk-plugin missing: ${bold}${3})$(error CMK_INCLUDE_MISSING)))
endef

# The ONE guarded-`include` primitive behind the whole verbatim-include family
# (include.plugin/plugins/files, include.file) AND the module bind.  Resolves
# the include path as `<prefix>/<file>`, EXCEPT an absolute `file` (starts with `/`)
# is used as-is -- which is what lets `include.file` (prefix=.) take an
# explicit/absolute path.  `strict=1` errors on absence (CMK_INCLUDE_MISSING);
# `strict=0` logs + continues.  INCLUDE-ONCE: if the resolved path is already in
# MAKEFILE_LIST it is SKIPPED -- this dedups double-imports AND is the cycle-breaker
# that makes a file/module importing itself (directly or via staged re-entry, or a
# mutual a<->b cycle) terminate instead of looping forever.
define _include
${nl}
$(call mk.unpack.kwargs, ${1}, file, ${1})
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(call mk.unpack.kwargs, ${1}, prefix, ${CMK_PLUGINS_DIR})
$(eval _mk_plug:=$(call _mk.path.resolve,${kwargs_prefix},${kwargs_file}))
$(call log.import.part1, include ${sep} ${dim}strict=${ital}${kwargs_strict} ${sep} ${dim_ital}${kwargs_file} )
ifneq ($(filter $(abspath ${_mk_plug}),$(abspath ${MAKEFILE_LIST})),)
$(call log.import.part2, ${dim}${_mk_plug}${no_ansi} (already included -- skipping))
else
$(shell d=$(firstword $(call _mk.path.split,${kwargs_prefix})); ls $$d 2>/dev/null > /dev/null || mkdir -p $$d)
ifeq ($(shell ${trace_maybe} && ls ${_mk_plug} 2>/dev/null >/dev/null && echo 0 || echo 1),1)
ifeq (${kwargs_strict},1)
$(call log.import.part2, ${GLYPH_XXX}${_mk_plug}${no_ansi} (missing))
$(call log.import.error, ${red}Declared import missing: ${bold}${kwargs_file})
$(call log.import.error, Consider ${bold}strict=0${no_ansi} for conditional inclusion)
$$(error CMK_INCLUDE_MISSING)
else
$(call log.import.part2, ${dim}${_mk_plug}${no_ansi} ${GLYPH_XXX})
endif
else
include ${_mk_plug}
$(call log.import.part2, ${GLYPH_CHECK})
endif
endif
endef

# import.module(def=<name> | file=<path> [namespace=<ns>] [preprocs=...])
# -- stage a module into CMK_MODULES_DIR as `.tmp.module.<ns>` and import it
# (strict, prefix=that dir), like any other plugin.  `def` and `file` are
# MUTUALLY EXCLUSIVE (exactly one required):
#   - def=<name>  -- materialize the in-scope `define <name>` block (read
#     verbatim via $(value), written with $(file)).
#   - file=<path> -- copy an existing makefile.
# The NAMESPACE (prefix on every module-level assignment/target) is `namespace=` if
# given, else the def name, else the file's basename sans extension.  (CMK_MODULE is
# instead the module's own SOURCE identity -- def name or basename -- so it reads the
# same however imported.)  The staged file is keyed <source>-<dest>, so different
# sources to the same namespace coexist; two with the SAME identity (same def name or
# basename) still collide -- resolve via distinct `namespace=`.  `preprocs=` is a
# COLON-delimited `flux.column/` pipeline (`a:b:c`) the body is filtered through,
# defaulting to `mk.compile` (CMK-Lang is a superset of Makefile, so a pure-make body
# compiles to itself while CMK sugar is lowered).  Pass `preprocs=stream.echo` for a
# verbatim passthrough, or chain e.g. `stream.echo:mk.compile`.  (Colon not comma: a
# comma is split by `$(call)` before this kwarg is read.)  So an inline/generated
# define OR a loose file can act as an importable plugin.
# For a PARTIAL/star import add `targets=<name|glob>` or `defs=<name|glob>` (mutually
# exclusive): a `mk.select.*` stage is prepended so only matching members are kept.
# `flat=1` is a ROOT import -- namespace + CMK_MODULE-header stages are OMITTED, so the
# body lands in the global namespace; the four combinations (flat/namespaced x
# verbatim/compiled) span the whole matrix.  A flat + verbatim + un-selected FILE
# import is the FAST-PATH: it binds the source directly (copy-free `include`, correct
# self-referential MAKEFILE_LIST) -- exactly what the `include.*` verbs lower to.
# USAGE: $(call import.module, def=<name>)            (namespace=<name>)
#        $(call import.module, def=<name> namespace=<alias>)
#        $(call import.module, def=<name> targets='<glob>')   # partial import
#        $(call import.module, file=<path> flat=1 preprocs=stream.echo)  # = a plain include
# NB: dispatch uses $(if) -- a LAZY function, only the taken branch expands.
# `ifeq` is a directive whose branches' side effects (mkdir/$(file)/cp) would
# ALL run during expansion regardless of the condition, corrupting state.
# Namespace a module body (stdin->stdout): prefix every top-level assignment/target
# LHS with `<ns>.`.  Recipe lines, comments, blanks, RHS values, private `.`/`_`
# names, and nested define bodies (depth-tracked) all pass through verbatim.
# Read via `$(value)` so awk's `$0`/`$` survive make expansion.
define .awk.module.namespace
/^\t/ { print; next }
/^[ ]*#/ { print; next }
/^[ ]*$/ { print; next }
/^[ ]*define[ ]/ { depth++; print; next }
/^[ ]*endef[ ]*$/ { if (depth>0) depth--; print; next }
depth > 0 { print; next }
/^[._]/ { print; next }
/^[A-Za-z][A-Za-z0-9_.%\/-]*[ \t]*[:=+?!]/ { print ns "." $0; next }
{ print }
endef

# Pipeline stage: namespace a module body read on STDIN -- prefix every module-level
# assignment/target LHS with `<ns>.`, where <ns> is the DESTINATION namespace taken
# LITERALLY from the stem (PURE; no header).  Reading the awk from the exported
# `_cmk_blk_module_ns` keeps make from mangling its `$0`.
_mk.module.namespace/%:; @${stream.stdin} | awk -v ns='${*}' "$${_cmk_blk_module_ns}"
	@# Prefix module-level LHS with `<ns>.` (stdin->stdout); see _mk.module.stage.

# Pipeline stage: prepend the `export CMK_MODULE := <source>` module-identity header.
# The stem is the SOURCE module (def name / file basename) -- a module's OWN identity,
# independent of the destination namespace it is imported under -- so a `def=M`
# imported `as Alias` still reads `CMK_MODULE=M`.  A special case of general header
# injection, kept SEPARATE from namespacing so a flat/root import can simply OMIT it.
_mk.module.header/%:; @{ echo 'export CMK_MODULE := ${*}'; ${stream.stdin}; }
	@# Prepend `export CMK_MODULE := <source>` (stdin->stdout); see _mk.module.stage.

# Each staged module gets `export CMK_MODULE := <name>` injected at its top
# (a make-var AND an export), and its body NAMESPACED so every module-level
# variable-assignment / target-name is prefixed with `$(CMK_MODULE).`.  So a
# module's recipes read their identity via $${CMK_MODULE}, and `var`/`tgt`
# become `<name>.var`/`<name>.tgt`.  Both staging paths funnel through
# _mk.module.stage, which runs the source through the staging pipeline
# `_mk.module.namespace/<name> : <preprocs|mk.compile>` (colon-delimited).
# (name = the def name, or a file's basename sans extension)
# _mk.module.key(<src>,<dest>) -- the staging-key for the `.tmp.module.<key>.mk`
# file: just `<dest>` when source == destination (the common case -- keeps the
# filename tidy), else `<src>-<dest>` so that two DISTINCT sources imported to the
# SAME destination namespace get distinct staged files instead of colliding under
# one (e.g. `def=A namespace=shared` and `def=B namespace=shared`).
_mk.module.key=$(if $(filter $(strip ${1}),$(strip ${2})),$(strip ${2}),$(strip ${1})-$(strip ${2}))
# _mk.hash.file(<path>) -- a short, stable hex digest of a file's CONTENT, used to
# make a file-import's staged-key content-addressed.  Uses `cksum` (POSIX: present
# in coreutils + busybox/alpine + BSD/macOS, so NO md5/md5sum platform split),
# trimmed by awk to 7 hex (~268M space).  Two payoffs over hashing the path:
#   * basename-collision proof -- two DISTINCT files sharing a basename have
#     distinct content -> distinct keys -> distinct staged files (no silent drop);
#   * staleness proof -- editing the source changes the digest, so a FAILED
#     recompile can't fall back to the prior run's STALE staged output (which is
#     keyed under the old bytes); the new key's file is simply absent -> a clean
#     error instead of silently including stale output.
# (Identical content at different paths collapses to one key -- benign: the two
# are byte-identical, so a single include is correct.)
_mk.hash.file=$(shell cksum < "$(1)" | awk '{printf "%07x",$$1%268435456}')
# _mk.module.stage(<key>,<srcfile>[,<preprocs>][,<select>][,<flat>][,<source>][,<dest>])
#   -> CMK_MODULES_DIR/.tmp.module.<key>.mk
# <key> names the staged file; <dest> is the namespace prefix; <source> is the
# module's OWN identity injected as CMK_MODULE (<source> and <dest> differ under a
# `namespace=` override).  ${4} select-stage is prepended for partial/star imports.
# ${5}=flat: when 1, OMIT the namespace+header stages (a root/flat import).
# MEMOIZED: the staged `.mk` is regenerated only when ABSENT/empty or OLDER than its
# source.  The CMK runtime parses a program in several re-exec'd `make` processes per
# run (supervisor re-exec + the `mk.interpret` trampoline + GNU make's restart), and
# each parse re-evaluates the parse-time `$(shell)` below -- so without this guard a
# single `.cmk` plugin is recompiled once PER parse (5x+ for one include).  The
# from_file key is content-addressed (`<basename>-<cksum>`), so a staged file's
# existence means THIS exact source was already lowered; the `-nt` check is the
# belt-and-suspenders staleness guard that also forces a recompile for the def path
# (whose `.raw` is rewritten each parse).  Atomic `.out`->mv preserved, so a present
# `.mk` is always a complete, successful compile.
_mk.module.stage=$(shell mkdir -p ${CMK_MODULES_DIR})$(shell _o=${CMK_MODULES_DIR}/.tmp.module.${1}.mk; if [ -s "$$_o" ] && [ "$$_o" -nt "${2}" ]; then true; else cat ${2} | CMK_INTERNAL=1 make -f $(firstword $(filter %compose.mk,${MAKEFILE_LIST}) ${MAKEFILE}) flux.column/$(if $(strip ${4}),$(strip ${4}):)$(if $(filter 1,$(strip ${5})),,_mk.module.namespace/${7}:_mk.module.header/${6}:)$(or $(strip ${3}),mk.compile) > $$_o.out && mv $$_o.out $$_o 2>/dev/null; fi; true)
# _mk.module.from_def(<def-name>,<dest-ns>,...) / _mk.module.from_file(<path>,<dest-ns>,...)
# -- ${1} is the content source (def name to $(value), or file to read) AND the
# CMK_MODULE identity; ${2} is the destination namespace (prefix).  The staged file
# is keyed on <source>-<dest> (collapsed; see _mk.module.key).  from_file ALSO
# appends a content digest (see _mk.hash.file): `<basename>[-<dest>]-<hash>`, so two
# distinct files sharing a basename+namespace don't collide, and an edited source
# can't reuse a prior run's stale staged output.  (from_def keys on the def NAME,
# which is already unique per make run, so it needs no digest.)
# _mk.assert.define(<name>): parse-time guard -- errors unless a `define <name>` is in scope.
_mk.assert.define=$(if $(call mk.var.undefined,${1}),$(error import.module: no such define: $(strip ${1}) [CMK_MODULE_MISSING]))
# IDEMPOTENT `.raw` write: the def value is written to a `.raw.new` and promoted only
# when it DIFFERS from the existing `.raw` -- so an unchanged def re-import (the common
# re-parse case) leaves the `.raw` mtime untouched, which lets `_mk.module.stage`'s
# `-nt` memoization SKIP the recompile.  An unconditional `$(file >)` would bump the
# mtime every parse and defeat that cache (as the from_file content-hash key already
# avoids).  `cmp` is POSIX (coreutils/busybox/BSD), so no platform split.
_mk.module.from_def=$(call _mk.assert.define,${1})$(shell mkdir -p ${CMK_MODULES_DIR})$(eval _mk_mod_k:=$(call _mk.module.key,${1},${2}))$(file > ${CMK_MODULES_DIR}/.tmp.module.${_mk_mod_k}.raw.new,$(value ${1}))$(shell _r=${CMK_MODULES_DIR}/.tmp.module.${_mk_mod_k}.raw; if cmp -s "$$_r.new" "$$_r"; then rm -f "$$_r.new"; else mv "$$_r.new" "$$_r"; fi)$(call _mk.module.stage,${_mk_mod_k},${CMK_MODULES_DIR}/.tmp.module.${_mk_mod_k}.raw,${3},${4},${5},${1},${2})$(call _include, prefix=${CMK_MODULES_DIR} strict=1 file=.tmp.module.${_mk_mod_k}.mk)
_mk.module.from_file=$(if $(wildcard ${1}),,$(error import.module: no such file: ${1} [CMK_MODULE_MISSING]))$(eval _mk_mod_k:=$(call _mk.module.key,$(basename $(notdir ${1})),${2})-$(call _mk.hash.file,${1}))$(call _mk.module.stage,${_mk_mod_k},${1},${3},${4},${5},$(basename $(notdir ${1})),${2})$(call _include, prefix=${CMK_MODULES_DIR} strict=1 file=.tmp.module.${_mk_mod_k}.mk)
# _mk.module.from_def_flat(<def-name>) -- the DEF analogue of the file FAST-PATH: a
# flat (root) + verbatim (preprocs=stream.echo) import of an IN-SCOPE define whose
# staged output would be byte-identical to its body, so it skips staging entirely and
# binds the def value directly with $(eval $(value ..)).  No sub-make, no temp file --
# which also makes it the ONLY def-import that works when compose.mk has been inlined
# into one image (the `mk.interpret` shebang), where the staging sub-make cannot
# locate a standalone compose.mk in MAKEFILE_LIST.
_mk.module.from_def_flat=$(call _mk.assert.define,${1})$(eval $(value ${1}))
import.module=$(eval $(call _import.module,${1}))
# A partial/star module import: `defs=`/`targets=` (mutually exclusive) prepend a
# `mk.select.*` stage so only the matching defines/targets are namespaced+compiled
# into scope.  Omit both to import the whole module (the default).
define _import.module
${nl}
$(call mk.unpack.kwargs, ${1}, def)
$(call mk.unpack.kwargs, ${1}, file)
$(call mk.unpack.kwargs, ${1}, namespace)
$(call mk.unpack.kwargs, ${1}, preprocs)
$(call mk.unpack.kwargs, ${1}, defs)
$(call mk.unpack.kwargs, ${1}, targets)
$(call mk.unpack.kwargs, ${1}, flat, 0)
$(call mk.unpack.kwargs, ${1}, prefix, .)
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(if $(and $(strip ${kwargs_def}),$(strip ${kwargs_file})),$(error import.module: def= and file= are mutually exclusive [CMK_MODULE_ARGS]))
$(if $(strip ${kwargs_def}${kwargs_file}),,$(error import.module: requires def=<name> or file=<path> [CMK_MODULE_ARGS]))
$(if $(and $(strip ${kwargs_defs}),$(strip ${kwargs_targets})),$(error import.module: defs= and targets= are mutually exclusive [CMK_MODULE_ARGS]))
$(eval _mk_mod_sel:=$(if $(strip ${kwargs_targets}),mk.select.targets/$(strip ${kwargs_targets}),$(if $(strip ${kwargs_defs}),mk.select.defs/$(strip ${kwargs_defs}))))
# A flat (root) + verbatim (stream.echo) + un-selected import is the FAST-PATH: its
# staged output is byte-identical to the source, so it skips staging.  For a FILE that
# means binding it directly (copy-free include); for a DEF, eval-ing the value in place.
$(eval _mk_mod_flatverb:=$(if $(filter 1,$(strip ${kwargs_flat})),$(if $(filter stream.echo,$(strip ${kwargs_preprocs})),$(if $(strip ${kwargs_defs}${kwargs_targets}),,1))))
$(eval _mk_mod_fast:=$(if ${_mk_mod_flatverb},$(if $(strip ${kwargs_file}),FAST)))
$(eval _mk_mod_fast_def:=$(if ${_mk_mod_flatverb},$(if $(strip ${kwargs_def}),FAST)))
$(if ${_mk_mod_fast},$(call _include, prefix=$(strip ${kwargs_prefix}) strict=$(strip ${kwargs_strict}) file=$(strip ${kwargs_file})),$(if ${_mk_mod_fast_def},$(call _mk.module.from_def_flat,$(strip ${kwargs_def})),$(if $(strip ${kwargs_def}),$(call _mk.module.from_def,$(strip ${kwargs_def}),$(or $(strip ${kwargs_namespace}),$(strip ${kwargs_def})),$(strip ${kwargs_preprocs}),${_mk_mod_sel},$(strip ${kwargs_flat})),$(call _mk.module.from_file,$(strip ${kwargs_file}),$(or $(strip ${kwargs_namespace}),$(basename $(notdir $(strip ${kwargs_file})))),$(strip ${kwargs_preprocs}),${_mk_mod_sel},$(strip ${kwargs_flat})))))$(eval __modules__:=$(sort ${__modules__} $(call _mk.module.name,def=$(strip ${kwargs_def}) file=$(strip ${kwargs_file}))))
endef

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
	@# This is similar to `include`, and (simulates) changes to the `make` runtime.
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
		    | grep -a -vE "^include ([^ ]*/)?$(notdir ${CMK_SRC})" \
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
		stdbuf -o0 -e0 $${tmpf} $${continuation:-} ; rc=$$? \
	; { [ -z "$${MAKE_SUPER}" ] || [ $${rc} -eq 0 ] || echo $${rc} > .tmp.mk.super.$${MAKE_SUPER} ; } \
	; exit $${rc}

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: cli.* targets
##
## The `cli.*` namespace is compose.mk's subcommand-CLI machinery -- it turns a target
## namespace into a `compose.mk <ns> <sub> <args>` dispatcher.  Two layers live here:
##
##  * `cli.subcommands` -- the reusable ENGINE (`cli.subcommands.enter` + the
##    `_cli.subcommands.*` internals + the `.awk.subcommands.tail` tail-capture).  Any
##    program gets a subcommand CLI in one line; `bind.subcommands` is its CMK-lang
##    `ᝏsubcommands` decorator form.
##  * `cli.cmk` -- the built-in CLIENT: the public `cmk` front-end (build | compile |
##    run | repl | doc) and its `cli.cmk.*` handlers, plus the private `_cmk.*`
##    compile/repl helpers.  `cmk` is the short public alias for `cli.cmk`.
##
##-------------------------------------------------------------------------------
##
## DOCS:
##  * `[1]:` [Subcommands](https://robot-wranglers.github.io/compose.mk/subcommands)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# --- The reusable subcommand engine (`cli.subcommands`) -----------------------
# Turn any namespace into a `compose.mk <ns> <sub> <args>` subcommand CLI in one line:
#   <ns>:; $(call cli.subcommands.enter)
# All kwargs are optional and auto-detected; pass any to override:
#   namespace    defaults to the target name (${@}).
#   subs         reflected from the `.<ns>.<sub>` handler targets (source order).
#   default      the first reflected subcommand (the bare-form fallback).
# plus a handler target per subcommand, either form:
#   `.<ns>.<sub>/%`  parametric: the `%` stem is the first arg, the rest in `argv`.
#   `.<ns>.<sub>`    non-parametric: takes no stem; all args arrive in `argv`.
# `cli.cmk` and `demos/subcommands.mk` are clients.
# Tail capture is robust: `.awk.subcommands.tail` reads the goal list positionally,
# starting just after the always-present `mk.supervisor.enter/<pid>` token, and strips
# the hook-rewrite's `flux.pre/* flux.post/*` decorations.  So a client needs NO entry
# in the `.awk.rewrite.targets.maybe` skip-list; an unregistered namespace merely incurs
# a harmless no-op `flux.pre/<ns>` before dispatch.

# Recovers a dispatcher's CLI tail from a (possibly hook-decorated) MAKE_CLI on stdin:
# drop up to & including `mk.supervisor.enter/<pid>`, drop flux.pre/* flux.post/*, drop
# the leading namespace token, print the rest.  Unit-tested via `io.awk/.awk.subcommands.tail`.
define .awk.subcommands.tail
{ for(i=1;i<=NF;i++){
	if(!seen){ if($i ~ /^mk\.supervisor\.enter\//) seen=1; continue }
	if($i ~ /^flux\.(pre|post)\//) continue
	a[++n]=$i } }
END { s=""; for(i=2;i<=n;i++) s=s (s==""?"":" ") a[i]; print s }
endef

# Emit a target's leading `@#` docstring block (the `\t@# ...` recipe-prefix comments
# right under `^<t>:`), prefix-stripped, for surfacing in subcommand usage.  Pure awk,
# multi-file (FNR resets), name regex-escaped.  Minified (cf. .awk.preprocess.dialect).
define .awk.docstring
BEGIN{gsub(/[.+*?^$()\[\]{}|\/\\]/,"\\\\&",t);pat="^" t "[ \t]*:"} FNR==1{c=0} !c&&$0~pat{c=1;next} c&&/^\t@#/{l=$0;sub(/^\t@#[ ]?/,"",l);print l;next} c{c=0}
endef

# Fast, define-aware enumeration of a makefile's PUBLIC target base-names -- the single
# source of truth behind `cli.completion.*` AND the repl's local-target banner (tux.repl.cmk).
# A pure single-pass awk scan (no make/Docker re-exec, unlike mkparse/_help_gen/mk.targets),
# so it is cheap enough for shell tab-completion.  Mirrors tests/_targets.py: skips
# `define..endef` bodies (which embed Dockerfiles/awk/heredocs whose lines look like targets),
# matches `^<names>:` (rejecting `:=`/`::` and recipe/comment/indented lines), splits
# multi-target lines, and drops private (leading `.`/`_`) + leftover-pattern (`%`) names.
# Parametric `foo/%` collapses to base `foo` by default; pass `-v param=keep` to emit `foo/%`
# verbatim (the repl wants the arg-hint; completion wants the bare base).  POSIX-awk only
# (index/substr/split) so it runs under gawk/BSD-awk/busybox.
define .awk.completion.scan
/^define[ \t]/      { ind=1; next }
/^endef([ \t]|$)/   { ind=0; next }
ind                 { next }
/^[ \t#]/           { next }
{
  ci=index($0,":"); if (ci==0) next
  head=substr($0,1,ci-1); rest=substr($0,ci)
  if (rest ~ /^:[=:]/) next
  if (head !~ /^[A-Za-z0-9._%\/! -]+$/) next
  n=split(head,toks,/[ \t]+/)
  for (i=1;i<=n;i++){ t=toks[i]; if(t=="") continue
    s=index(t,"/"); base=(s>0)?substr(t,1,s-1):t
    c=substr(base,1,1); if(c=="."||c=="_"||c=="-") continue
    if(index(base,"%")>0||base=="") continue
    out=(param=="keep")?t:base
    if(!(seen[out]++)) print out }
}
endef

# Optimized internal-recursion prefix for dispatch/transform sub-makes: mark internal
# + skip re-installing the target-rewrite/at-exit hooks and the SIGINT supervisor.  The
# client keeps the real supervisor at the top level; a handler that execs a program
# re-enables CMK_SUPERVISOR itself (see `cli.cmk.run/%`).
_cli.subcommands.make=CMK_INTERNAL=1 CMK_DISABLE_HOOKS=1 CMK_SUPERVISOR=0 ${make}

# Generic multi-line usage, derived from subcmd_ns + subcmd_subs (stderr): a header
# then one tree-line per subcommand, with parametric subs (`.<ns>.<sub>/%`) annotated
# `<arg> [args..]`, opt-in `subcmd_optional` subs annotated `[<arg>]`, and the rest bare --
# so it's clear which ones accept an argument and whether it is required or optional.
_cli.subcommands.usage=( doc=`awk -v t="$${subcmd_name}" "$${_cmk_blk_docstring}" $${__interpreting__:-} ${MAKEFILE_LIST} 2>/dev/null` ; [ -z "$${doc}" ] || printf '%s\n' "$${doc}" | while IFS= read -r dl; do $(call log.io, ${dim}$${subcmd_name} ${sep}${no_ansi_dim} $${dl}${no_ansi}); done ; $(call log.loop.top, ${dim}$${subcmd_name} ${sep}${no_ansi} USAGE${no_ansi_dim}: ${no_ansi}$${subcmd_name} ${bold}<subcommand>${no_ansi}${dim} [args..]) && nsalt=`echo "$${subcmd_ns}" | tr ' ' '|'` && last=$$(echo "$${subcmd_subs}" | awk '{print $$NF}') && for s in $${subcmd_subs}; do if grep -qE "^($${nsalt})[$${subcmd_sep}]$${s}/%" ${MAKEFILE_LIST} 2>/dev/null; then lbl="${bold_cyan}$${s}${no_ansi}${dim_ital} <arg> [args..]"; elif case " $${subcmd_optional:-} " in *" $${s} "*) true;; *) false;; esac; then lbl="${bold_cyan}$${s}${no_ansi}${dim_ital} [<arg>]"; else lbl="${bold_cyan}$${s}"; fi; if [ "$${s}" = "$${last}" ]; then $(call log.loop.item.last, $${lbl}); else $(call log.loop.item, $${lbl}); fi; done )

# Subcommand-dispatch error ($(1)=message tail): proper logging (a red `log.io` line +
# the generated usage), then THROW the recognizable `CMK_UNKNOWN_SUBCOMMAND` token and
# fail.  Mirrors `_include`, which logs via `log.import.error` then throws the
# symbolic `$(error CMK_INCLUDE_MISSING)` -- here the construct is a runtime recipe (no
# parse-time `$(error)`), so the token is emitted to stderr and the recipe exits nonzero.
_cli.subcommands.error=( $(call log.io, ${red}$${subcmd_name} ${sep}${no_ansi} $(1)) ; ${_cli.subcommands.usage} ; $(call log.io, ${red}${bold}CMK_UNKNOWN_SUBCOMMAND${no_ansi}) ; exit 1 )

# Entrypoint body for a subcommand CLI.  All kwargs optional (key=val, like
# `compose.import`); auto-detected when omitted (detection lives in `cli.subcommands`):
#   namespace='<ns..>'  one OR MORE space-separated namespaces, searched in order like
#                       an MRO (first match wins).  Defaults to `.<target-name>`.
#   sep=<s>             separator between namespace and sub in a handler name (default `.`).
#   subs='<a b ..>'     reflected from the `<ns><sep><sub>` handlers (source order)
#   default=<sub>       the first reflected subcommand (the bare-form fallback)
#   optional='<a b ..>' subs (NON-parametric, so all args land in `$$argv`) that take an
#                       OPTIONAL arg -- rendered `<sub> [<arg>]` in usage (vs parametric
#                       `<sub> <arg> [args..]` and the plain no-arg `<sub>`).
# So a handler is `<ns><sep><sub>[/%]` (e.g. `.greet.hello/%`).  NB: SINGLE-quote any
# space-bearing value (`namespace`, `subs`); `mk.unpack.kwargs` mangles double-quoted
# multi-word values.  Captures the CLI tail robustly, then does the ONE yield.
# NESTING: a non-parametric handler may ITSELF be a `cli.subcommands.enter` (a sub-group),
# so `prog a b c` threads a->b->c.  A DISPATCHED handler (the engine runs it via
# `_cli.subcommands.make`, i.e. CMK_INTERNAL=1) reads its remaining words from `$$argv` -- that
# is how the engine forwards them, and the handler's own command line is just its name.  A
# TOP-LEVEL entry (CMK_INTERNAL=0: the supervisor's `cmk`/`greet`, or a program goal) uses the
# MAKE_CLI parse instead -- crucial because `cmk run` LEAKS the program continuation into `$$argv`,
# which must NOT be mistaken for a forwarded subcommand tail.
define cli.subcommands.enter
$(eval _subcmd_args:=$(if $(filter undefined,$(origin 1)),,$(1)))$(call mk.unpack.kwargs, ${_subcmd_args}, namespace, .${@})$(call mk.unpack.kwargs, ${_subcmd_args}, sep, .)$(call mk.unpack.kwargs, ${_subcmd_args}, subs,)$(call mk.unpack.kwargs, ${_subcmd_args}, default,)$(call mk.unpack.kwargs, ${_subcmd_args}, optional,)tail=`if [ "$${CMK_INTERNAL:-0}" = 1 ] && [ -n "$${argv:-}" ]; then echo "$${argv:-}"; else case "$${MAKE_CLI}" in \
		*mk.supervisor.enter/*) echo "$${MAKE_CLI}" | awk -f <(${mk.def.read}/.awk.subcommands.tail) ;; \
		*) _t="$${MAKE_CLI#*${@}}"; [ "$${_t}" = "$${MAKE_CLI}" ] && echo "" || echo "$${_t}" ;; \
	esac; fi | xargs` \
	&& $(call mk.yield, subcmd_name=${@} subcmd_ns=\"$(strip ${kwargs_namespace})\" subcmd_sep=$(strip ${kwargs_sep}) subcmd_default=$(strip ${kwargs_default}) subcmd_subs=\"$(strip ${kwargs_subs})\" subcmd_optional=\"$(strip ${kwargs_optional})\" subcmd_tail=\"$${tail}\" ${_cli.subcommands.make} cli.subcommands)
endef

cli.subcommands:
	@# Shared subcommand-dispatch engine (reusable; see `cli.subcommands.enter`).
	@# Reads subcmd_name/subcmd_ns/subcmd_sep/subcmd_subs/subcmd_default/subcmd_tail from
	@# the env and routes the first tail word to its handler.  A parametric handler
	@# `<ns><sep><sub>/%` gets the next word as its stem (the rest in $${argv}); a
	@# non-parametric `<ns><sep><sub>` gets all the remaining args in $${argv}.  An
	@# unrecognized first word routes to the default sub ONLY when the default is
	@# parametric (the word becomes its arg, e.g. `cmk <file>` -> `cmk run <file>`); when
	@# the default is non-parametric, an unrecognized first word is an unknown-subcommand
	@# error.  empty/help/-h/--help prints usage.  Never yields.
	@#
	@# subcmd_ns may be a SPACE-SEPARATED list of namespaces, searched in order like an
	@# MRO (the first namespace that defines a handler for the sub wins).  subcmd_subs (the
	@# union across namespaces) and subcmd_default are auto-detected when empty by reflecting
	@# the `<ns><sep><sub>` handler targets in ${MAKEFILE_LIST} (parametric or not).
	sub="`echo "$${subcmd_tail}" | cut -d' ' -f1`" \
	&& rest="`echo "$${subcmd_tail}" | cut -d' ' -f2- -s`" \
	&& [ -n "$${subcmd_subs}" ] || subcmd_subs=`for ns in $${subcmd_ns}; do grep -hoE "^$${ns}[$${subcmd_sep}][A-Za-z0-9_-]+(/%|:)" ${MAKEFILE_LIST} 2>/dev/null | sed -E "s|^$${ns}[$${subcmd_sep}]||;s|/%$$||;s|:$$||"; done | awk '!s[$$0]++' | xargs` \
	&& [ -n "$${subcmd_default}" ] || subcmd_default=`echo "$${subcmd_subs}" | awk '{print $$1}'` \
	&& if [ -z "$${sub}" ] || [ "$${sub}" = help ] || [ "$${sub}" = -h ] || [ "$${sub}" = --help ]; then \
		${_cli.subcommands.usage} ; \
	else \
		case " $${subcmd_subs} " in \
			*" $${sub} "*) tsub="$${sub}"; targs="$${rest}"; fellthrough=0 ;; \
			*) tsub="$${subcmd_default}"; targs="$${subcmd_tail}"; fellthrough=1 ;; \
		esac \
		&& handler="" && isparam=0 \
		&& for ns in $${subcmd_ns}; do \
			if grep -qE "^$${ns}[$${subcmd_sep}]$${tsub}/%" ${MAKEFILE_LIST} 2>/dev/null; then handler="$${ns}$${subcmd_sep}$${tsub}"; isparam=1; break; fi; \
			if grep -qE "^$${ns}[$${subcmd_sep}]$${tsub}:" ${MAKEFILE_LIST} 2>/dev/null; then handler="$${ns}$${subcmd_sep}$${tsub}"; isparam=0; break; fi; \
		done \
		&& if [ -z "$${tsub}" ] || [ -z "$${handler}" ] || { [ "$${fellthrough}" = 1 ] && [ "$${isparam}" != 1 ]; }; then \
			$(call _cli.subcommands.error, unknown subcommand${no_ansi_dim}: ${no_ansi}$${sub}) ; \
		elif [ "$${isparam}" = 1 ]; then \
			arg1="`echo "$${targs}" | cut -d' ' -f1`" \
			&& argv="`echo "$${targs}" | cut -d' ' -f2- -s`" \
			&& argv="$${argv}" ${_cli.subcommands.make} $${handler}/$${arg1} ; \
		else \
			argv="$${targs}" ${_cli.subcommands.make} $${handler} ; \
		fi ; \
	fi

# CMK-lang decorator form of `cli.subcommands.enter`: writing `ᝏsubcommands` (kwargs
# optional, exactly like the macro) on the line ABOVE a target turns that target into
# a subcommand CLI.  Unlike the bare macro, a *bare* `ᝏsubcommands` (no kwargs) defaults
# to the tree-glyph namespaces `├`/`╰` (sep `┈`), so handlers are `├┈<sub>` / `╰┈<sub>`;
# pass kwargs to override.  The $(origin)/$(strip) guard keeps it warning-clean for any
# arg-count.  See demos/cmk/subcommands.cmk.
bind.subcommands=$(call cli.subcommands.enter,$(or $(strip $(if $(filter-out undefined,$(origin 1)),${1})),namespace='├ ╰' sep=┈))

# --- The `cmk` CLI client (`cli.cmk`) -----------------------------------------
# `cmk` is a convenient *public* subcommand front-end uniting several CMK workflows
# (build / compile / run / doc), built as a thin client of the `cli.subcommands` engine
# above.  The heavy lifting is delegated to existing internals (mk.pkg, mk.compiler[!],
# mk.compile, mk.interpret/%); the `.cmk.*`/`_cmk.*` helpers below are internal.

# Generic, reusable: succeeds iff stdout is a terminal (i.e. NOT redirected).
io.tty.stdout=[ -t 1 ]
# ..and stdin (i.e. NOT a pipe/redirect).  Prefer these over inlining `[ -t N ]` -- and ESPECIALLY
# in CMK-lang, where a bare `[ .. ]` can clash with the `[..]` stream call-form (the macro hides
# the brackets from the compiler).
io.tty.stdin=[ -t 0 ]

# Shared file-hygiene guards ($(1)=path).  guard.input fails; the warns continue.
_cmk.guard.input=[ -f "$(1)" ] || { $(call log.io, ${red}cmk ${sep}${no_ansi} no such file${no_ansi_dim}: ${no_ansi}${underline}$(1)${no_ansi}); exit 1; }
_cmk.warn.ext=case "$(1)" in *.cmk) true;; *) $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} note: ${no_ansi}${underline}$(1)${no_ansi_dim} has no .cmk extension);; esac
_cmk.warn.output=([ -e "$(1)" ] && $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} overwriting ${no_ansi}${underline}$(1)) || true)

# REPL-as-execution-mode launch -- the irreducible core->plugin BRIDGE.  Core can't import the tux.repl
# plugin (where the harness + the launch LOGIC now live, in its `tux.repl.run` target), so this just
# exports the three CMK_REPL_* env vars the target reads, compiles the PLUGIN (with a `__main__:
# tux.repl.run` line appended) into a 2nd temp, and runs it.  The scrape + runner-pinning + wrapper exec
# are all in the plugin now.  (See `cli.cmk.run/%` pragma branch + `cli.cmk.repl`; tux.repl.cmk's `tux.repl.run`.)
# $(1)=tux.repl kwarg tail (`eval=.. [read=.. print=.. exit_after=..]`; NO runner -- the plugin pins it).
# $(2)=the PROGRAM SOURCE (the plugin scrapes the launch-banner's LOCAL target namespace from it).
# `tmpf` must already hold the compiled PROGRAM (the runner).
_cmk.repl.launch=$(call assert.plugin, tux.repl.cmk) && export CMK_REPL_RUNNER="$${tmpf}" CMK_REPL_SOURCE="$(strip $(2))" CMK_REPL_KWARGS="$(1)" CMK_REPL_CLI="$${MAKE_CLI}" && tmpf2=$$(TMPDIR=`pwd` mktemp ./.tmp.cmk.repl.XXXXXXXXX) && trap "rm -f $${tmpf} $${tmpf2}" EXIT && $(call log.io, ${dim}cmk ${sep}${no_ansi} repl ${sep}${dim} launching harness ${sep} ${no_ansi}$(1)) && { cat "$(call cmk.plugin.find,tux.repl.cmk)" ; printf '\n__main__: tux.repl.run\n' ; } | ${_cli.subcommands.make} mk.compile > $${tmpf2} && chmod +x $${tmpf2} && CMK_INTERNAL=0 CMK_SUPERVISOR=1 ${make} mk.interpret/$${tmpf2}

cli.cmk:; $(call cli.subcommands.enter, namespace=cli.cmk default=run optional=repl)
	@# Public subcommand interface for CMK programs: build | compile | run | repl | doc.  The canonical
	@# entrypoint; `cmk` is a short alias (both dispatch to the `cli.cmk.*` handlers).
	@# `cli.cmk <file>` is shorthand for `cli.cmk run <file>`; files should end in `.cmk`.
	@# `cli.cmk repl [<file>]` opens an interactive shell over a program's target namespace.
cmk:; $(call cli.subcommands.enter, namespace=cli.cmk default=run optional=repl)
	@# Public subcommand interface for CMK programs: build | compile | run | repl | doc.  Short alias for `cli.cmk`.
	@# `cmk <file>` is shorthand for `cmk run <file>`; files should end in `.cmk`.
	@# `cmk repl [<file>]` opens an interactive shell over a program's target namespace (or, with no
	@# file, a simple shell over the core namespace).

# `cmk cli` -- a NESTED subcommand group (a handler that is itself a `cli.subcommands.enter`,
# see the nesting note there) for shell integration:
#   cmk cli complete [file]   emit a self-contained bash completion script (eval it)
#   cmk cli init     [file]   install that script into the user's bash-completion dir
#   cmk cli targets  [file]   the underlying target enumerator (debug primitive)
# `file` defaults to the interpreted program (`$$__interpreting__`) else `${CMK_SRC}`, so a
# `cmk run` program inherits this: `./your.cmk cmk cli complete` emits completion for itself.
# See `.awk.completion.scan` for the (fast, define-aware) enumerator shared with the repl.
cli.cmk.cli:; $(call cli.subcommands.enter, namespace=cli.cmk.cli default=complete optional='complete init targets')
	@# Shell-integration subcommands: complete | init | targets.  See `cmk cli <sub> help`.

cli.cmk.cli.complete:
	@# Emit a self-contained bash tab-completion script (stdout); eval it:
	@#   eval "$$(./compose.mk cmk cli complete)"   # registers compose.mk, ./compose.mk, cmk
	@#   eval "$$(./your.cmk   cmk cli complete)"   # a cmk-run program (inherited; registers itself)
	@# Optional first arg = a makefile to complete (default: interpreted program else CMK_SRC).
	@# Bakes a stdlib target snapshot + embeds the scanner for a live scan of the typed file, so
	@# one function (keyed on $$COMP_WORDS[0]) serves every registered command.  zsh: first run
	@# `autoload -U +X bashcompinit && bashcompinit`.  Static scan: eval-generated/imported
	@# targets are not seen (completion is a convenience, not authoritative).
	@#
	@# QUERY MODE (CMK_COMPLETE_QUERY=1): instead of the script, read a LINE buffer on stdin and
	@# print the target names that complete its last word (one per line) -- used by the repl's
	@# Tab handler (the Go wrapper pipes the input buffer through and applies the result).
	case "$${CMK_COMPLETE_QUERY:-0}" in \
	1) buf="`cat`" \
		&& case "$${buf}" in *' '|'') word='' ;; *) word="`printf '%s' "$${buf}" | awk '{print $$NF}'`" ;; esac \
		&& file="$${__interpreting__:-${CMK_SRC}}" \
		&& { awk -f <(${mk.def.read}/.awk.completion.scan) ${CMK_SRC} 2>/dev/null ; \
		     { [ -f "$${file}" ] && [ "$${file}" != "${CMK_SRC}" ] && awk -f <(${mk.def.read}/.awk.completion.scan) "$${file}" 2>/dev/null ; } || true ; } \
		   | sort -u | awk -v w="$${word}" 'w==""||index($$0,w)==1' ;; \
	*) cmd="`echo "$${argv:-}" | cut -d' ' -f1`" \
		&& cmd="$${cmd:-$${__interpreting__:-${CMK_SRC}}}" \
		&& base="`basename "$${cmd}"`" \
		&& stdlib="`awk -f <(${mk.def.read}/.awk.completion.scan) ${CMK_SRC} 2>/dev/null | sort -u | tr '\n' ' '`" \
		&& scanner="`${mk.def.read}/.awk.completion.scan`" \
		&& printf '%s\n' '# compose.mk bash completion (generated)' \
		&& printf '_CMK_STDLIB_TARGETS=%s\n' "\"$${stdlib}\"" \
		&& printf '%s\n' "read -r -d '' _CMK_SCAN_AWK <<'CMK_AWK_EOF'" \
		&& printf '%s\n' "$${scanner}" \
		&& printf '%s\n' 'CMK_AWK_EOF' \
		&& printf '%s\n' '_cmk_complete() {' \
		&& printf '%s\n' '  local cur file extra words' \
		&& printf '%s\n' '  cur="$${COMP_WORDS[COMP_CWORD]}"; file="$${COMP_WORDS[0]}"; extra=""' \
		&& printf '%s\n' '  [ -f "$$file" ] && [ -r "$$file" ] && extra="$$(awk "$$_CMK_SCAN_AWK" "$$file" 2>/dev/null)"' \
		&& printf '%s\n' '  words="$$_CMK_STDLIB_TARGETS $$extra"' \
		&& printf '%s\n' '  COMPREPLY=( $$(compgen -W "$$words" -- "$$cur" | sort -u) ); return 0' \
		&& printf '%s\n' '}' \
		&& printf 'complete -F _cmk_complete -o default %s %s\n' "$${base}" "./$${base}" \
		&& { [ "$${base}" = "compose.mk" ] && printf 'complete -F _cmk_complete -o default cmk\n' || true; } ;; \
	esac

cli.cmk.cli.init:
	@# Install bash completion for a program into the user's bash-completion dir, idempotently
	@# (one file; NO shell-rc edits).  Optional first arg = makefile (default: interpreted program
	@# else CMK_SRC).  Activate by reloading the shell (or `source` the file); undo by deleting it.
	@#   ./compose.mk cmk cli init            # completion for compose.mk + cmk
	@#   ./your.cmk    cmk cli init           # completion for your program (inherited)
	cmd="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& cmd="$${cmd:-$${__interpreting__:-${CMK_SRC}}}" \
	&& base="`basename "$${cmd}"`" \
	&& dir="$${XDG_DATA_HOME:-$${HOME}/.local/share}/bash-completion/completions" \
	&& mkdir -p "$${dir}" && dest="$${dir}/$${base}" \
	&& argv="$${cmd}" CMK_INTERNAL=1 ${make} cli.cmk.cli.complete > "$${dest}" \
	&& $(call log.io, ${dim}cmk cli init ${sep}${no_ansi} installed completion for ${ital}$${base}${no_ansi} ${sep} ${dim}$${dest}) \
	&& $(call log.io, ${dim}cmk cli init ${sep}${no_ansi} reload your shell to activate ${sep} ${dim}undo: rm $${dest})

cli.cmk.cli.targets:
	@# Debug primitive: print public target base-names (define/endef-aware) for a makefile.
	@# Optional first arg = file (default: interpreted program else CMK_SRC).
	@#   ./compose.mk cmk cli targets   |   ./your.cmk cmk cli targets
	f="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& f="$${f:-$${__interpreting__:-${CMK_SRC}}}" \
	&& awk -f <(${mk.def.read}/.awk.completion.scan) "$${f}" 2>/dev/null | sort -u

cli.cmk.build/%:
	@# `cmk build` helper: package the given .cmk into a self-extracting executable.
	$(call _cmk.guard.input,${*}) \
	&& $(call _cmk.warn.ext,${*}) \
	&& bin="$${argv:-$$(basename ${*} .cmk)}" \
	&& $(call _cmk.warn.output,$${bin}) \
	&& $(call log.io, ${dim}cmk build ${sep}${no_ansi} ${underline}${*}${no_ansi} ${dim}-> ${no_ansi}$${bin}) \
	&& bin="$${bin}" ${_cli.subcommands.make} mk.pkg/${*}

cli.cmk.compile/%:
	@# `cmk compile` helper: simple highlighted preview (tty), else full standalone.
	$(call _cmk.guard.input,${*}) \
	&& $(call _cmk.warn.ext,${*}) \
	&& if [ -n "$${argv:-}" ]; then \
		$(call _cmk.warn.output,$${argv}) \
		&& $(call log.io, ${dim}cmk compile ${sep}${no_ansi} ${underline}${*}${no_ansi} ${dim}-> ${no_ansi}$${argv}) \
		&& cat ${*} | ${_cli.subcommands.make} mk.compiler! > $${argv} ; \
	elif ${io.tty.stdout}; then \
		$(call log.io, ${dim}cmk compile ${sep}${dim} preview ${sep} ${no_ansi}${underline}${*}) \
		&& errto=$$( [ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] && echo /dev/null || echo /dev/stderr ) \
		&& ${_cli.subcommands.make} mk.compiler/${*} 2>$${errto} | style=monokai lexer=makefile ${make} stream.pygmentize ; \
	else \
		cat ${*} | ${_cli.subcommands.make} mk.compiler! ; \
	fi

# --- `cli.cmk.run/%` helpers (the compile + pragma-threading the recipe below composes) -----------------
# All operate on `$$tmpf` (the compiled program) in the recipe shell; the boot/repl helpers are wrapped
# in `{ ...; }` so they compose in the recipe's `&&` chain (a no-match `if` exits 0).

# _cmk.compile(<source>) -- compile a .cmk SOURCE to the (already-mktemp'd) `$$tmpf`, executable.
_cmk.compile=cat $(1) | ${_cli.subcommands.make} mk.compile > $${tmpf} && chmod +x $${tmpf}
# _cmk.pragma.scrape(<KEY>) -- echo the compiled `export CMK_PRAGMA_<KEY> := <val>` value from $$tmpf.
_cmk.pragma.scrape=sed -n 's/^export CMK_PRAGMA_$(1) := //p' $${tmpf} | head -1
# _cmk.interpret.self(<source>) -- the normal (non-repl) path: re-exec the program self-supervised, with
# any extra CLI words as the make continuation (`cmk run <file> <target..>`).
_cmk.interpret.self=CMK_INTERNAL=0 CMK_SUPERVISOR=1 continuation="$${argv:-}" __interpreting__=$(strip $(1)) ${make} mk.interpret/$${tmpf}

# BOOT PRAGMAS: `hooks`/`bootloader_disabled`/`bootloaders` are read pre-make by the bash header, so the
# generic CMK_PRAGMA_* injection can't reach them.  We scrape them from the compiled output and thread the
# canonical env into the program's re-exec (scalars: pragma wins + a loud notice; `bootloaders` APPENDS).
# _cmk.boot.scalar(<KEY>,<ENVVAR>,<truthy-case-pat>,<on-match>,<else>,<label>).
_cmk.boot.scalar=_v=$$($(call _cmk.pragma.scrape,$(1))) ; if [ -n "$${_v}" ]; then case "$${_v}" in $(3)) _o="$(4)";; *) _o="$(5)";; esac ; $(call log.io, ${yellow}cmk run ${sep}${no_ansi} pragma $(6)=$${_v} ${sep} sets $(2)=$${_o} (overrides env/default)${no_ansi}) ; export $(2)="$${_o}" ; fi
# _cmk.boot.bootloaders -- the LIST knob: APPEND the pragma's loaders to any invoker CMK_BOOTLOADER.
_cmk.boot.bootloaders=_v=$$($(call _cmk.pragma.scrape,BOOTLOADERS)) ; if [ -n "$${_v}" ]; then _bl="$${CMK_BOOTLOADER:-} $${_v}" ; export CMK_BOOTLOADER="$${_bl\# }" ; $(call log.io, ${dim}cmk run ${sep}${no_ansi_dim} sourcing bootloaders via pragma ${sep} ${no_ansi}$${_v}) ; fi
# _cmk.boot.thread -- apply all three boot pragmas.
_cmk.boot.thread={ $(call _cmk.boot.scalar,HOOKS,CMK_DISABLE_HOOKS,off|false|0|no|OFF|FALSE|NO,1,0,hooks) ; $(call _cmk.boot.scalar,BOOTLOADER_DISABLED,CMK_BOOTLOADER_DISABLED,""|0|off|false|no,,1,bootloader_disabled) ; $(call _cmk.boot.bootloaders) ; }

# REPL PRAGMA: build the tux.repl kwarg string into `_rk` from the scraped `repl` value in `$$_bp_repl` --
# `true`-ish -> the generic `eval=mk.repl.kernel`; an OBJECT -> its read/eval/print/exit_after keys (jq).
# _cmk.repl.objkey(<key>,<jq-default>) reads one object key.
_cmk.repl.objkey=printf '%s' "$${_bp_repl}" | ${jq.run.pipe} -r '.$(1) // $(2)' 2>/dev/null
_cmk.repl.kwargs={ case "$${_bp_repl}" in true|1|on|yes|TRUE|ON|YES) _rk="eval=mk.repl.kernel" ;; *) _re=$$($(call _cmk.repl.objkey,eval,"mk.repl.kernel")) ; _rr=$$($(call _cmk.repl.objkey,read,empty)) ; _rp=$$($(call _cmk.repl.objkey,print,empty)) ; _rx=$$($(call _cmk.repl.objkey,exit_after,empty)) ; _rk="eval=$${_re}" ; [ -z "$${_rr}" ] || _rk="$${_rk} read=$${_rr}" ; [ -z "$${_rp}" ] || _rk="$${_rk} print=$${_rp}" ; [ -z "$${_rx}" ] || _rk="$${_rk} exit_after=$${_rx}" ;; esac ; }

cli.cmk.run/%:
	@# `cmk run` helper: compile then exec (no yield; the program self-supervises).  The compile +
	@# pragma-threading is factored into the `_cmk.*` helpers above; see those for the boot/repl details.
	@# REPL PRAGMA: a `repl` pragma (true, or a {read,eval,print,exit_after} object) makes the DEFAULT
	@# action (no target args) launch the interactive tux.repl harness over the program's targets instead
	@# of running __main__ -- REPL-as-execution-mode.  An explicit `cmk run <file> <target>` bypasses it
	@# and runs the target (like `python script.py` vs bare `python`); `cmk repl <file>` forces the mode.
	$(call _cmk.guard.input,${*}) \
	&& $(call _cmk.warn.ext,${*}) \
	&& $(call log.io, ${dim}cmk run ${sep}${no_ansi} ${underline}${*}) \
	&& $(call io.mktemp) \
	&& export __interpreting__=${*} \
	&& $(call _cmk.compile, ${*}) \
	&& $(call _cmk.boot.thread) \
	&& _bp_repl=$$($(call _cmk.pragma.scrape,REPL)) \
	&& if [ -n "$${_bp_repl}" ] && [ -z "$${argv:-}" ]; then \
			$(call _cmk.repl.kwargs) \
			&& $(call log.io, ${yellow}cmk run ${sep}${no_ansi} pragma repl ${sep} entering REPL execution mode${no_ansi}) \
			&& $(call _cmk.repl.launch, $${_rk}, ${*}) ; \
		else \
			$(call _cmk.interpret.self, ${*}) ; \
		fi

cli.cmk.repl:
	@# `cmk repl [<file>]` helper: launch the interactive REPL over a program's target namespace -- even
	@# one with no `repl` pragma.  WITH a file, it compiles it and wires the generic kernel dispatcher over
	@# the file's targets (typing a target name runs it; ctrl-d exits) -- the explicit / universal form of
	@# the `repl` pragma `cmk run` honors (the pragma declares it as a program's default; this forces it).
	@# With NO file, it drops to a simple shell over the CORE namespace only (an empty program: no local
	@# targets, no banner).  The optional file arrives via `argv` (non-parametric), so `cmk repl` and
	@# `cmk repl <file>` share one handler.  Needs a tty.
	f="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& $(call io.mktemp) \
	&& export __interpreting__=$${tmpf} \
	&& if [ -n "$${f}" ]; then \
		$(call _cmk.guard.input,$${f}) \
		&& $(call _cmk.warn.ext,$${f}) \
		&& $(call log.io, ${dim}cmk repl ${sep}${no_ansi} ${underline}$${f}) \
		&& $(call _cmk.compile, $${f}) ; \
	else \
		$(call log.io, ${dim}cmk repl ${sep}${no_ansi_dim} no file ${sep} simple shell over the core namespace) \
		&& printf '__main__:; @true\n' | $(call _cmk.compile, -) ; \
	fi \
	&& $(call _cmk.repl.launch, eval=mk.repl.kernel, $${f})

cli.cmk.doc/%:
	@# `cmk doc` helper: add a mode-matching shebang (if missing), chmod +x, compile-check.
	$(call _cmk.guard.input,${*}) \
	&& $(call _cmk.warn.ext,${*}) \
	&& cmkref="$(if $(strip ${docker.cmk.mount}),compose.mk,./compose.mk)" \
	&& shebang="#!/usr/bin/env -S $${cmkref} cmk run" \
	&& if head -1 ${*} | grep -q '^#!' ; then \
		$(call log.io, ${dim}cmk doc ${sep}${dim} shebang already present ${sep} ${no_ansi}${underline}${*}) ; \
	else \
		$(call io.mktemp) \
		&& { printf '%s\n' "$${shebang}" ; cat ${*} ; } > $${tmpf} \
		&& cat $${tmpf} > ${*} \
		&& $(call log.io, ${dim}cmk doc ${sep}${no_ansi} added shebang ${sep}${dim} $${shebang}) ; \
	fi \
	&& chmod +x ${*} \
	&& $(call log.io, ${dim}cmk doc ${sep}${dim} compile-check ${sep} ${no_ansi}${underline}${*}) \
	&& ( ${_cli.subcommands.make} mk.compiler/${*} >/dev/null 2>/dev/null \
		&& $(call log.io, ${dim}cmk doc ${sep} ${green}compiles ok) \
		|| ( $(call log.io, ${red}cmk doc ${sep}${no_ansi} compile errors:) ; ${_cli.subcommands.make} mk.compiler/${*} >/dev/null ; exit 1 ) )

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: cli.* targets
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

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

mk.parse/%:; ${mkparse} ${*}
	@# Parses the given Makefile, returning JSON output that describes the targets, docs, etc.

mk.parse:
	@# Parse / merge for each Makefile in MAKEFILE_LIST
	echo "${MAKEFILE_LIST}" | ${stream.space.to.nl} \
	| ${flux.each}/mk.parse | ${jq} -s '.[0] * .[1]'

mk.pkg:; set -x && archive="$${archive} ${CMK_SRC}" ${make} mk.self
	@# Like `mk.self`, but includes `compose.mk` source also.

mk.pkg/%:
	@# Packages a make-target, a `.mk` file, or a `.cmk` app as a single-file executable.
	@#
	@# This works by using `makeself` to bundle/freeze/release a self-extracting
	@# archive that includes `compose.mk` plus whatever is being packaged.  Dispatch
	@# is by suffix, and everything is referenced/bundled by basename so the produced
	@# binary is portable (it needs no `compose.mk` or source on the target host, and
	@# works the same whether this `compose.mk` is vendored or installed globally):
	@#
	@#   *.cmk  -> freeze a CMK app   (entrypoint re-interprets the bundled `.cmk`)
	@#   *.mk   -> freeze a makefile  (entrypoint runs its default goal)
	@#   *      -> package a target of the current Makefile  (the original behavior)
	@#
	@# `bin` defaults to the input's basename (no extension).  For inputs that pull in
	@# sibling files (relative `include`/`import.*`), add them to the bundle with
	@# `archive` as a space-separated list of extra files or directories.
	@#
	@# USAGE:
	@#  ./compose.mk mk.pkg/<target_name>           # e.g. mk.pkg/flux.ok
	@#  ./compose.mk mk.pkg/path/to/app.cmk         # freeze a CMK app
	@#  ./compose.mk mk.pkg/path/to/app.mk          # freeze a makefile
	@#  archive="file1 dir1" ./compose.mk mk.pkg/path/to/app.cmk
	@#
	pkg_in="${*}" && case "$${pkg_in}" in \
	  *.cmk) base=`basename "$${pkg_in}"` \
	    && bin="$${bin:-$${base%.cmk}}" archive="$${pkg_in} $${archive:-}" script=bash \
	       script_args="$(notdir ${CMK_SRC}) mk.interpret! $${base}" ${make} mk.pkg ;; \
	  *.mk)  base=`basename "$${pkg_in}"` \
	    && bin="$${bin:-$${base%.mk}}" archive="$${pkg_in} $${archive:-}" script=make \
	       script_args="${MAKE_FLAGS} -f $${base}" ${make} mk.pkg ;; \
	  *)     ${make} .mk.pkg/$${pkg_in} ;; \
	esac

ifeq (${__interpreting__},) 
.mk.pkg/%:; cmd=${*} bin=$${bin:-${*}} label=$${label:-${*}} ${make} mk.pkg.root
mk.pkg.root:
	@# Packages the application root, or the given command if provided.
	label=$${label:-${*}} bin=$${bin:-${*}} script=make \
	script_args="${MAKE_FLAGS} -f ${MAKEFILE} $${cmd:-}" \
	${make} mk.pkg
else 
mk.pkg.root:
	@# Packages the application root, or the given command if provided.
	@# `mk.pkg` bundles ${CMK_SRC}, which `mk.self` lands at the archive root by
	@# basename, so run THAT copy via `bash` (compose.mk's shebang interpreter):
	@# no `./compose.mk`-at-cwd assumption and no executable-bit requirement (an
	@# `include`d compose.mk often isn't chmod +x), while keeping the shebang's
	@# supervisor trampoline that `mk.interpret!` relies on.
	label=$${label:-${*}} bin=$${bin:-${*}} script=bash \
	script_args="$(notdir ${CMK_SRC}) mk.interpret! ${__interpreting__} $${cmd:-}" \
	${make} mk.pkg
.mk.pkg/%:; cmd=${*} bin=$${bin:-${*}} label=$${label:-${*}} ${make} mk.pkg.root
endif
mk.namespace.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Newline-delimited output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.namespace.filter/<prefix>
	@#
	${trace_maybe} \
	&& pattern="${*}" \
	&& ${mkparse} --prefix $${pattern} $${path:-${MAKEFILE}} | ${jq} -r '.|keys[]'

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

mk.targets/% mk.parse.shallow/%:; ${mkparse} --shallow ${*} | ${jq} -r '.[]'
	@# Returns only local targets from the given file, ignoring includes.
	@# Returns a newline-delimited list of targets inside the given Makefile.
	@# Unlike `mk.parse`, this is "flat" and too naive to parse targets that come 
	@# via includes.  Targets starting with "." are considered private, and 
	@# ommitted from the return value.
	
mk.targets.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Simple, pipe-friendly output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.targets.filter/<namespace>
	@#
	${trace_maybe} && pattern="${*}" && pattern="$${pattern//./[.]}" \
	&& ${make} mk.targets | grep ^$${pattern}

mk.parse.block/%:; set -x && subcommand=cblocks; ${mkparse} --pattern "$${pattern:-}" ${*}
	@# Pulls out documentation blocks that match the given pattern.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.block/<makefile>
	@#
	@# EXAMPLE:
	@#   pattern='TUI' make mk.parse.block/compose.mk
	@#

mk.targets mk.parse.targets mk.targets.local mk.parse.local:; ${make} mk.parse.shallow/$${path:-${MAKEFILE}}
	@# Returns only local targets for the current Makefile, ignoring includes
	@# Output of `mk.parse.shallow/` for the current val of MAKEFILE.

mk.parse.targets/%:; path=${*} ${make} mkparse | ${jq} -r '. | keys'
	@# Parses the given Makefile, returning target-names only. Simple, pipe-friendly output. 
	@# Also available as a macro.  
	@# WARNING: Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: 
	@#   ./compose.mk mk.parse.targets/<file>
	@#
mk.parse.targets=${make} mk.parse.targets
mk.targets.local=${mk.parse.targets} | sort | uniq
mk.targets.local.public=${mk.targets.local} | grep -v '^self.' | grep -v '^[.]' | sort -V

mk.reconn/%:; make --reconn -f ${*}
	@# Runs makefile in dry-run / reconn mode 

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

mk.set/%:; $(eval $(shell echo ${*}|cut -s -d/ -f1):=$(shell echo ${*}|cut -s -d/ -f2-))
	@# Setter for make variables, available as a target. 
	@# This is experimental stuff for reflection support.
	@#
	@# USAGE: ./compose.mk mk.set/<key>/<val>

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
# Single source for supervisor-pid detection: the child make whose PPid is
# MAKE_SUPER (returns empty when MAKE_SUPER is unset/has no child). Inlined by
# BOTH `mk.supervisor.pid` and `mk.interrupt` so the hot interrupt path computes
# it in-process instead of paying a full `${make} mk.supervisor.pid` re-parse.
_mk.supervisor.pid.find=case "${OS_NAME}" in Darwin) ps auxo ppid|grep $${MAKE_SUPER}$$|awk '{print $$2}';; *) awk -v me="$${MAKE_SUPER}" 'FNR==1{n=split(FILENAME,a,"/"); p=a[n-1]} /^PPid:/{if($$2==me) print p}' /proc/[0-9]*/status 2>/dev/null || true;; esac
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
		*) ${_mk.supervisor.pid.find} ;; \
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
			&& super=`${_mk.supervisor.pid.find} || true` \
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
	
# _mk.supervisor.bootloader: the supervisor's LOADER AGGREGATOR.  The polyglot header
# `source`s ONLY this; it in turn sources each "loader" define -- currently just the
# trampoline dispatch loop, but it is the single extension point: add supervisor behavior
# by adding a `define _mk.supervisor.<name>` and one `_cmk_load` line here, with NO header
# edit.  `_cmk_load <define-name>` lifts that define's body out of the file (the same
# `.awk.rewrite.targets.maybe` sed trick) and `source`s it in the header's shell -- so a
# loader runs with $_make_ / $_targets / $MAKE_SUPER set, and any vars it sets (e.g. the
# trampoline's $st) stay visible to the header (no subshell; _cmk_load uses no `local`).
# CMK_BOOTLOADER: an optional path to exactly ONE user bootloader file, sourced FIRST -- at
# BOOT, before the trampoline runs the program.  It therefore sees pre-run state
# ($_targets / $MAKE_SUPER, NOT yet $st) and can SET UP the run (e.g. a TUI overlay), then
# reach the end via an `EXIT` trap (which fires when the supervisor shell exits, where $st is
# final) -- both ends, not just after.  A user bootloader must NOT trap INT/TERM (that would
# clobber the supervisor's own SIGINT trap).  If set it must exist (missing = fatal, and now
# fails FAST, before any target runs).  Keep it portable (Linux/OSX/Alpine); see
# demos/user-bootloader.sh.
define _mk.supervisor.bootloader
_cmk_load() { source <(sed -n "/^define $1/,/^endef/{/^define/d;/^endef/d;p}" ${0}); }
for _ref in ${CMK_BOOTLOADER}; do
  if [ -f "${_ref}" ]; then source "${_ref}";
  elif sed -n "/^define ${_ref}\$/,/^endef/p" ${0} | grep -q .; then _cmk_load "${_ref}";
  else printf 'compose.mk: CMK_BOOTLOADER ref not found (file or define): %s\n' "${_ref}" >/dev/stderr; exit 1; fi
done
_cmk_load _mk.supervisor.trampoline
endef

# _mk.supervisor.trampoline: the supervisor's trampoline DISPATCH LOOP, kept OUT of the polyglot
# header so that bash/Makefile-comment stays small.  make stores this define verbatim and
# NEVER expands it; the bootloader lifts its body out of the file with the same
# `sed -n '/^define X/,/^endef/{..}'` trick used for `.awk.rewrite.targets.maybe`, and
# `source`s it -- so it runs in the header's shell with $_make_ / $_targets / $MAKE_SUPER
# already set (no make-expansion layer: this is plain bash, lifted raw).  It re-dispatches
# each pending continuation FLAT (read from the .tmp.cmk.mbox mailbox that `mk.trampoline`
# writes), re-applies the hook-rewrite + fires the step hook, then recovers the exact exit
# code and cleans the run's scratch files.  A non-VM run executes the body exactly once.
define _mk.supervisor.trampoline
cmk_mbox=".tmp.cmk.mbox.${MAKE_SUPER}"; next="${_targets}"; cmk_hop=0; cmk_hopmax="${CMK_TRAMPOLINE_MAX:-10000}"; st=0
rm -f -- "$cmk_mbox" 2>/dev/null || true
while [ -n "$next" ]; do
  cmk_hop=$((cmk_hop+1))
  if [ "$cmk_hop" -gt "$cmk_hopmax" ]; then printf 'compose.mk: trampoline hop limit %s exceeded\n' "$cmk_hopmax" >/dev/stderr; st=70; break; fi
  rm -f -- "$cmk_mbox" 2>/dev/null || true
  ${_make_} mk.supervisor.enter/${MAKE_SUPER} $next 2> >(awk '{ if (match($0, /make(\[[0-9]+\])?: \*\*\* \[/) && RSTART>1) { print substr($0,1,RSTART-1); print substr($0,RSTART) } else print }' | sed '/^make.*:.*mk.interrupt\/SIGINT.*Killed/,/^make:.*Error.*/d' >/dev/stderr)
  st=$?
  if grep -q '^CONT=' "$cmk_mbox" 2>/dev/null; then
    raw="$(sed -n 's/^CONT=//p' "$cmk_mbox" | tail -1)"
    rm -f -- "$cmk_mbox" ".tmp.mk.super.${MAKE_SUPER}" 2>/dev/null || true
    case ${CMK_DISABLE_HOOKS:-0} in
      0) next="$(echo $raw | awk -f <(sed -n '/^define .awk.rewrite.targets.maybe/,/^endef/{/^define/d;/^endef/d;p}' ${0}))";;
      1) next="$raw";;
    esac
    if [ "${CMK_SUPERVISOR_STEP_HOOK:-flux.noop}" != flux.noop ]; then CMK_STEP_INDEX=$cmk_hop CMK_STEP_CONT="$next" CMK_STEP_CODE=$st CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} $CMK_SUPERVISOR_STEP_HOOK || true; fi
  else
    next=""
  fi
done
CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} mk.supervisor.exit/${st}
if [ -f .tmp.mk.super.${MAKE_SUPER} ]; then
  code=`cat .tmp.mk.super.${MAKE_SUPER} 2>/dev/null`; rm -f .tmp.mk.super.${MAKE_SUPER}
  case "${code}" in ''|*[!0-9]*) :;; *) st=${code};; esac
fi
rm -f -- .tmp.cmk.brf.${MAKE_SUPER}.* "$cmk_mbox" .tmp.cmk.vmenv.${MAKE_SUPER} .tmp.CONTROL_STACK_FRAMES.${MAKE_SUPER} 2>/dev/null || true
endef

mk.supervisor.enter/%:
	@# Unconditionally executed by the supervisor program, prior to main pipeline.
	@# Argument is always supervisors PPID.  Not to be confused with 
	@# the supervisors pid; See instead 'mk.supervisor.pid'
	@# 
	$(eval export MAKE_SUPER:=${*}) \
	$(call io.safe_rm,.tmp.mk.super.${*}) \
	&& $(call log.trace, ${GLYPH_MK} ${@} ${sep} ${red}started pid ${no_ansi}$${MAKE_SUPER})

mk.supervisor.exit/%:
	@# Unconditionally executed by the supervisor program after main pipeline,
	@# regardless of whether that  pipeline was successful. Argument is always
	@# the exit-status of the main pipeline.
	@#
	@# NB: this only runs the at-exit handlers (CMK_AT_EXIT_TARGETS).  The EXACT
	@# process exit-code is delivered by the bash supervisor wrapper (top of file),
	@# which reads `.tmp.mk.super.${MAKE_SUPER}` (written by `mk.yield`/`mk.exit.code`).
	@# This recipe therefore exits 0 even when <status> is nonzero: the wrapper
	@# ignores this recipe's own code, so `exit ${*}` would only make `make` print
	@# a spurious `*** Error <status>` on stderr.  <status> is ~always 130 -- a
	@# `cmk run`/`mk.yield` unwinds the supervisor via SIGINT, so the main pipeline
	@# exits 128+2 (the wrapper's sed scrubs that pipeline's own SIGINT error, but
	@# not this separate sub-make's).  An at-exit handler that genuinely FAILS still
	@# surfaces -- the `&&` chain breaks before the `exit 0`.
	@#
	header="${GLYPH_MK} mk.supervisor.exit ${sep}" \
	&& $(call log.trace, $${header} ${red} status=${*} ${sep} ${bold}pid=$${MAKE_SUPER}) \
	&& $(call log.trace, $${header} ${red} calling exit handlers: $(call cmk.pragma.append, at_exit_targets)) \
	&& case "$(strip $(call cmk.pragma.append, at_exit_targets))" in \
		flux.noop) : ;; \
		*) CMK_DISABLE_HOOKS=1 CMK_INTERNAL=0 ${make} $(call cmk.pragma.append, at_exit_targets) ;; \
	esac \
	&& exit 0
	
mk.supervisor.trap/%:
	@# Executed by the supervisor program when the given signal is trapped.
	@#
	header="${GLYPH_MK} mk.supervisor.trap ${sep}" \
	&& $(call log.trace, $${header} ${red}${*} ${sep} ${dim}Supervisor trapped signal)

mk.targets.simple/%:; ${make} mk.targets/${*} | grep -v '%$$'
	@# Returns only local targets from the given file, 
	@# excluding parametric targets, and ignoring included targets.

mk.targets.parametric:; ${make} mk.parse.local | grep '%' | sed 's/\/%//g'
	@# This finds only the parametric targets in the current namespace.
	@#
	@# Note that targets like 'foo/%:' are automatically converted to simply 'foo', 
	@# which makes this friendly for use with stuff like `flux.starmap`, etc.
	@#

mk.targets.filter.parametric/%:
	@# Filters all parametric targets by the given pattern.
	pattern="`printf ${*}|sed 's/\./[.]/g'`" \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.part1, ${GLYPH_IO} mk.targets.filter.parametric ${sep} matching \'$${pattern}\') || true) \
	&& targets="`${make} mk.targets.parametric | grep "^$${pattern}" || true`" \
	&& count=`printf "$${targets}"|${stream.count.lines}` \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.part2, ${yellow}$${count}${no_ansi_dim} total) || true ) \
	&& printf "$${targets}"

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
# STRICT: a key given more than once is a hard error (no silent last-wins).  The
# check is fork-free (`$(filter)`/`$(words)`, no subshell) so it is safe on this
# hot, parse-time helper.  Runs BEFORE extraction to fail fast.
define mk.unpack.kwargs
$(eval _kwargs_dupes:=$(filter $(strip ${2})=%,${1}))
$(if $(filter-out 0 1,$(words ${_kwargs_dupes})),$(shell $(call log.mk, ${red}mk.unpack.kwargs ${sep}${no_ansi} duplicate kwarg ${bold}$(strip ${2})${no_ansi}${dim} = ${no_ansi}${_kwargs_dupes}$(if $(strip ${@}),${dim} ${sep} in ${no_ansi}${@})))$(error mk.unpack.kwargs: duplicate kwarg '$(strip ${2})' (${_kwargs_dupes})$(if $(strip ${@}), in '${@}') [CMK_UNPACKED_DUPLICATE_KWARG]))
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

# CMK_YIELD_HOOK: an optional shell command fired by `mk.yield` immediately BEFORE it
# transfers control, with the jump target exported as $CMK_YIELD_TARGET.  This is the one
# seam an external reflection / control-stack layer needs: it observes (or reconciles for)
# every yield WITHOUT core knowing anything about stacks or files.  It defaults to `true`
# (a no-op) -- zero cost, no filesystem, byte-identical legacy behavior -- so it is fully
# backwards-compatible; a consumer opts in by setting it.  The hook is fired in a subshell
# and can never break the transfer (its failure is swallowed).  See demos/vm.mk.
CMK_YIELD_HOOK ?= true
define mk.yield
	header="${GLYPH_MK} mk.yield ${sep}${dim}" \
	&& yield_to="$(if $(filter undefined,$(origin 1)),true,$(1))" \
	&& $(call log.trace, $${header} Yielding to:${dim_cyan} $(call strip, $${yield_to})) \
	&& ( export CMK_YIELD_TARGET="$${yield_to}"; $(CMK_YIELD_HOOK) || true ) \
	&& eval $${yield_to} \
	; rc=$$? ; if [ $${rc} -eq 0 ]; then echo 0 > .tmp.mk.super.$${MAKE_SUPER}; \
		elif [ ! -f .tmp.mk.super.$${MAKE_SUPER} ]; then echo $${rc} > .tmp.mk.super.$${MAKE_SUPER}; fi \
	; case "$${CMK_SUPERVISOR:-1}" in \
		0) exit $${rc} ;; \
		*) ${mk.interrupt} ;; \
	esac
endef
# ^ The interrupt unwinds the SUPERVISOR's make stack after `eval` ran the continuation.
# With NO supervisor (CMK_SUPERVISOR=0 -- e.g. a NESTED `cli.subcommands.enter` dispatched via
# `_cli.subcommands.make`), there is nothing to signal: `mk.interrupt` would just log "Supervisor
# is disabled" and exit 1 (noise + a spurious error).  So we skip it and propagate `rc` directly;
# the real top-level yield still fires its own interrupt to unwind the whole stack once.

# CMK_SUPERVISOR_STEP_HOOK: optional target fired by the supervisor's trampoline loop
# once per CONTINUING step (default flux.noop, a no-op).  The loop double-gates it (only
# when overridden AND only on a real trampoline step), so it costs nothing on the fast
# path.  Future supervisor extensions (step-debug, schedulers, per-step tracing) hook here
# with CMK_STEP_INDEX / CMK_STEP_CONT / CMK_STEP_CODE exported -- no further wrapper edits.
CMK_SUPERVISOR_STEP_HOOK ?= flux.noop

# mk.trampoline: the trampoline transfer primitive -- a SIBLING of `mk.yield` (which it
# does NOT modify).  Where mk.yield runs the continuation INLINE (`eval` -> a nested make)
# and then interrupts -- so successive jumps NEST processes -- mk.trampoline does NOT eval.
# It writes the next goals to the supervisor mailbox and interrupts, so the supervisor's
# dispatch loop re-runs them at TOP LEVEL (flat, no nesting).  This is what `__vm__` uses
# for control transfer.  Requires the supervisor + the loop (a supervised `./compose.mk` /
# `mk.interpret` run).  Atomic mailbox write (temp + mv); fires the same CMK_YIELD_HOOK
# observation seam.  Invariant: a transferring recipe must not also `mk.exit.code` it
# (transfer XOR terminal exit), since the loop drops the per-step exit-code pidfile.
# _mk.interrupt.fast: a cheaper `${mk.interrupt}` for the trampoline hot path.  `mk.interrupt`
# re-parses the WHOLE combined makefile (`${MAKE} -f ${MAKEFILE} mk.interrupt`) just to send
# one signal -- paid PER HOP, and ~40x costlier on make 4.4.  This instead runs the SAME
# `mk.interrupt/SIGINT` recipe from a 2-line standalone makefile materialized on a process
# substitution (`make -f <(printf ..)`), so the per-hop reparse is a couple of lines, not all
# of compose.mk.  It preserves the exact `mk.interrupt/SIGINT ... Killed` marker the wrapper's
# stderr filter keys on, so output stays clean.  The supervisor's child PID is found HERE with
# the canonical, OS-portable `_mk.supervisor.pid.find` (ps on Darwin / awk-over-/proc on Linux)
# and passed in as $CMK_INT_SUPER -- so the standalone makefile (`_mk.interrupt.tiny`, emitted
# verbatim via `$(value ..)` to keep `$$`/`$*` for the tiny make's parse) needs NO pid-find:
# no awk, hence no single quotes, so the single-quoted `printf` stays shell-safe, and there is
# NO duplicated pid-find logic and NO new tool dependency (avoids pgrep, which busybox/BSD
# handle inconsistently).  `kill -KILL $$` unwinds via the standalone make's death == this
# recipe's failure, exactly like the old helper sub-make.
_mk.interrupt.tiny=mk.interrupt/%:\n\t@{ [ -n "$$CMK_INT_SUPER" ] && kill -$* $$CMK_INT_SUPER 2>/dev/null; } ; kill -KILL $$$$\n
_mk.interrupt.fast=_super=`${_mk.supervisor.pid.find} 2>/dev/null` ; CMK_INTERNAL=1 CMK_INT_SUPER="$${_super}" ${MAKE} -f <(printf '%b' '$(value _mk.interrupt.tiny)') mk.interrupt/SIGINT
define mk.trampoline
	header="${GLYPH_MK} mk.trampoline ${sep}${dim}" \
	&& cont_to="$(if $(filter undefined,$(origin 1)),,$(1))" \
	&& $(call log.trace, $${header} transfer:${dim_cyan} $(call strip, $${cont_to})) \
	&& ( export CMK_YIELD_TARGET="$${cont_to}"; $(CMK_YIELD_HOOK) || true ) \
	&& printf 'CONT=%s\n' "$${cont_to}" > .tmp.cmk.mbox.$${MAKE_SUPER}.tmp \
	&& mv -f .tmp.cmk.mbox.$${MAKE_SUPER}.tmp .tmp.cmk.mbox.$${MAKE_SUPER} \
	; ${_mk.interrupt.fast}
endef

mk.exit.code/%:; [ -z "$${MAKE_SUPER}" ] || echo "${*}" > .tmp.mk.super.$${MAKE_SUPER} ; exit ${*}
	@# Records an EXACT process exit-code, then fails so the make stack unwinds
	@# NORMALLY (flux.*.finally / cleanup arms still run).  The bash supervisor
	@# wrapper reads it out-of-band and the top-level `./compose.mk` exits with <N>.
	@# Requires CMK_SUPERVISOR=1 (no out-of-band channel without it; degrades to the
	@# usual make exit 2).  Contrast `mk.yield`, which short-circuits via signal and
	@# SKIPS intermediate finally arms.
	@#
	@# USAGE: ... || ${make} mk.exit.code/42      (or `$(call mk.exit.code,42)` inline)
	@#

# Macro form of `mk.exit.code/<N>` for inline use inside other recipes.
mk.exit.code=([ -z "$${MAKE_SUPER}" ] || echo "${1}" > .tmp.mk.super.$${MAKE_SUPER}) ; exit ${1}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## Control stack + `__vm__` CEK machine: EXTRACTED to the `.cmk/virtual-machine.cmk` plugin (bodies are
## pure-make jq/awk, imported VERBATIM).  Consumers import it explicitly:
##     $(call include.plugins, virtual-machine.cmk)
## (and `$(call declare.cmk.virtual_machine, exclude=..)` for the opt-in reflective env).
## See demos/call_stack.mk, demos/vm.mk, demos/cmk/overlay.cmk.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mk.exit.clear:; @[ -z "$${MAKE_SUPER}" ] || $(call io.safe_rm,.tmp.mk.super.$${MAKE_SUPER})
	@# Retracts any pending exact exit-code recorded by `mk.exit.code` (drops the
	@# supervisor pidfile).  Custom handlers that SWALLOW a failure (e.g. `|| true`)
	@# and intend to succeed must call this, else the recorded code still reaches the
	@# top-level process.  `flux.try.except.finally` calls it automatically when its
	@# `except` arm recovers, so this is only for hand-rolled error handling.
	@#
	@# USAGE: ... || { ${make} this.thing.handled ; ${make} mk.exit.clear ; }
	@#        (or `$(call mk.exit.clear)` inline)

# Macro form of `mk.exit.clear` for inline use inside other recipes.
mk.exit.clear=([ -z "$${MAKE_SUPER}" ] || $(call io.safe_rm,.tmp.mk.super.$${MAKE_SUPER}))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: flux.* targets
##
## The flux.* targets describe a miniature workflow library. Combining flux with 
## container dispatch is similar in spirit to things like declarative pipelines 
## in Jenkins, but simpler, more portable, and significantly easier to use.  
##
## What's a workflow in this context? Shell by itself is fine for what you might
## call "process algebra", and using operators like `&&`, `||`, `|` in the grand 
## unix tradition goes a long way. And adding `make` to the mix already provides 
## DAGs.
##
## What `flux.*` targets add is *flow-control constructs* and *higher-level 
## join/loop/map* instructions over other make-targets, taking inspiration from 
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

flux.echo/%:; echo "${*}"
	@# Simply echoes the given argument.
	@# Mostly used in testing, but also provided for completeness.. 
	@# you can think of this as the "identity function" for flux algebra.

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
	@# Exactly `flux.pipeline`, but assumes `:` delimiter instead of comma

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

flux.do.unless/%:; ${make} flux.do.when/`printf ${*}|cut -d, -f1`,flux.negate/`printf ${*}|cut -d, -f2-`
	@# Runs the 1st target iff the 2nd target fails.
	@# This is a version of 'flux.if.then', see those docs for more details.
	@#
	@#  USAGE: ( generic )
	@#    ./compose.mk flux.do.unless/<umbrella>,<dry>
	@#
	@#  USAGE: ( concrete ) 
	@#    ./compose.mk flux.do.unless/flux.ok,flux.fail
	@#

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
	 ${stream.space.to.nl} | ${stream.peek.summary} \
	| xargs -I% sh ${dash_x_maybe} -c "${make} ${*}/% || exit 255"
flux.each=${make} flux.each

flux.each.json/%:
	@# Given a target, treats each part of the nl-delimited input stream as arguments,
	@# returning JSON-ouput of `{key: target(key), .. }`
	@# USAGE:
	@#   ls *.md | make flux.each.json/flux.echo
	$(call log.target, mapping key -> ${dim_cyan}${*}${no_ansi_dim}(key))
	${stream.peek.summary} \
	| xargs -I {} bash ${dash_x_maybe} -c 'echo "{\"{}\": $$(${make} ${*}/{})}"'

flux.fail:
	@# Alias for 'exit 1', which is POSIX failure.
	@# This is mostly for used for testing other pipelines.
	@#
	@# See also the `flux.ok` target.
	@#
	$(call log.flux, flux.fail ${sep} ${red}failing${no_ansi} as requested!)  \
	&& exit 1

flux.finally/% flux.always/%:; $(call _flux.always)
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

flux.indent/%:; ${make} flux.indent.sh cmd="${make} ${*}"
	@# Given a target, this runs it and indents both the resulting output for both stdout/stderr.
	@# See also the 'stream.indent' target.
	@#
	@# USAGE:
	@#   ./compose.mk flux.indent/<target>
	@#

flux.indent.sh:; $${cmd}  1> >(sed 's/^/  /') 2> >(sed 's/^/  /')
	@# Similar to flux.indent, but this works with any shell command.
	@#
	@# USAGE:
	@#  cmd="echo foo; echo bar >/dev/stderr" ./compose.mk flux.indent.sh
	@#

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

flux.loop.watch/%:; watch --interval $${interval:-2} --color ${make} ${*}
	@# Loops the given target forever, using `watch` instead of the while-loop default.
	@# This requires `watch` is actually available.

# like stream.peek, but prefaced with a line-count
stream.peek.summary=tee >($(call log.target, $${msg:-streaming} ${sep} ${yellow}`${stream.stdin}|wc -l` lines)) 

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

flux.fold/%:
	@# Left-fold over stdin lines (i.e. reduce WITH an explicit initial value).
	@# The accumulator is threaded through the <reducer> target's STDIN; the
	@# current line is passed as the `val` env-var; the reducer prints the new
	@# accumulator.  The accumulator is seeded by the `acc` env-var, or else the
	@# <init> arg (default empty).  This is the same shape the `stream.*` reducers
	@# already have, so they can be dropped in as reducers directly.
	@#
	@# USAGE: ( bundle a stream into a JSON array, reusing a stdlib reducer )
	@#   printf 'a\nb\nc\n' | ./compose.mk flux.fold/stream.json.array.append,[]
	@#   ["a","b","c"]
	@#
	@# USAGE: ( a scalar reducer reads the accumulator from stdin )
	@#   add:; @echo $$(( `$${stream.stdin}` + $${val} ))
	@#   printf '1\n2\n3\n4\n' | ./compose.mk flux.fold/add,0   # -> 10
	@#
	reducer="`printf '${*}' | cut -d, -f1`" \
	&& acc="$${acc:-`printf '${*}' | cut -s -d, -f2-`}" \
	&& while IFS= read -r val; do \
		acc="`printf '%s' "$${acc}" | val="$${val}" ${make} $${reducer}`" \
	; done \
	&& printf '%s\n' "$${acc}"

flux.reduce/%:
	@# Reduce over stdin lines, seeded by the FIRST line (no initial value).
	@# Implemented via `flux.fold`: seed `acc` from the head, fold the tail.
	@# Fails on empty input.  See `flux.fold` for the reducer contract.
	@#
	@# USAGE:
	@#   printf '3\n1\n4\n1\n5\n' | ./compose.mk flux.reduce/<reducer>
	@#
	${io.mktemp} && ${stream.stdin} > $${tmpf} \
	&& ([ -s $${tmpf} ] || ($(call log.target, ${red}flux.reduce: empty input); exit 1)) \
	&& tail -n +2 $${tmpf} | acc="`head -n1 $${tmpf}`" ${make} flux.fold/${*}

flux.NIY:; $(call log.target, ${red}Target Not Implemented Yet); exit 1
	@# Shorthand for "not implemented yet".  Exits immediately as failure.

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
flux.pipeline=${make} flux.pipeline
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

flux.split/%:; export targets="${*}" && ${make} flux.split
	@# Alias for flux.split, but accepts arguments directly

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
	&& ( r=$${times}; rc=0; \
		 while [ $$r -gt 0 ]; do \
			${make} $${target}; rc=$$?; \
			[ $$rc -eq 0 ] && break; \
			r=$$((r-1)); \
			[ $$r -le 0 ] && break; \
			$(call log.flux, $${header} (${no_ansi}${yellow}failed.${no_ansi_dim} waiting ${dim_green}${FLUX_POLL_DELTA}s${no_ansi_dim})) \
			; sleep $${interval:-${FLUX_POLL_DELTA}}; \
		 done; exit $$rc )

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
	&& $(call io.safe_rm,${flux.stage.file}) 2>/dev/null || $(call log, $${header} ${yellow} could not remove stack file!)

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

flux.stage.clean:; rm -f -- .flux.stage.*
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

flux.stage.push:; ${stream.stdin} | ${make} flux.stage.push/${FLUX_STAGE}
	@# Push the JSON data on stdin into the stack for the implied stage 
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk flux.stage.push
	@#

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

# Recipe-body shorthands for the stage operators: `${flux.stage.<op>}/<stage>` is just
# terser than spelling out `${make} flux.stage.<op>/<stage>` (and reads better in a recipe).
# Each expands to the sub-make invocation, so `${@}` (current target name) is a tidy stage.
# NB `flux.stage.file` stays a PATH var (`.flux.stage.${*}`), so it is intentionally absent.
flux.stage.enter=${make} flux.stage.enter
flux.stage.exit=${make} flux.stage.exit
flux.stage.push=${make} flux.stage.push
flux.stage.pop=${make} flux.stage.pop
flux.stage.stack=${make} flux.stage.stack
flux.stage.clean=${make} flux.stage.clean
flux.stage.wrap=${make} flux.stage.wrap

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

define _flux.timer
${trace_maybe} && start_time=$$(date +%s%N) \
	&& ${make} ${1} \
	&& end_time=$$(date +%s%N) \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& delta=$$(awk -v ns="$$time_diff_ns" 'BEGIN {printf "%.9f", ns / 1000000000}') \
	&& $(call log.flux, flux.timer ${sep} `echo ${1}|cut -d/ -f2-` ${sep} ${dim}$${label:-done in} ${yellow}$${delta}s)
endef
flux.timer/%:; $(call _flux.timer,${*})
	@# Emits run time for the given make-target in seconds.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timer/<target_to_run>

flux.timeout/%: assert.tool.required/timeout
	@# Runs the given target for the given number of seconds, then stops it with TERM.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timeout/<seconds>/<target>
	@#
	timeout=`printf ${*} | cut -d/ -f1` \
	&& target=`printf ${*} | cut -d/ -f2-` \
	&& $(call log.io, flux.timeout ${sep} running target ${bold}$${target} ${no_ansi_dim} for ${yellow} $${timeout} seconds) \
	&& timeout $${timeout}s ${make} $${target} \
	; stat=$$? \
	&& case $${stat} in \
		124) $(call log.io, ${@} ${sep} timed out as requested);; \
		*) $(call log.io, ${@} ${sep} finished with no timeout); exit $${stat};; \
	esac

flux.timeout.sh:
	@# Like `flux.timeout/<target>` but works with a shell command.
	@#
	@# USAGE: (tails docker logs for up to 10s, then stops)
	@#   cmd='docker logs -f xxxx' timeout=10 ./compose.mk flux.timeout.sh 
	$(call log.io, flux.timeout ${sep} running command ${bold}$${cmd} ${no_ansi_dim} for ${yellow} $${timeout} seconds) \
	&& timeout $${timeout}s bash -c "$${cmd}" \
	; stat=$$? \
	&& case $${stat} in \
		124) $(call log.io, ${@} ${sep} timed out as requested);; \
		*) $(call log.io, ${@} ${sep} finished with no timeout); exit $${stat};; \
	esac

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
		1) $(call log.flux, $${header} ${underline}${cyan}except${no_ansi_dim} ${sep} $${except}) && ${make} $${except} && { $(call mk.exit.clear); exit_status=0; } || exit_status=1; ;; \
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
flux.try.finally/%:; ${make} flux.try.except.finally/$(call mk.unpack.arg,1),flux.noop,$(call mk.unpack.arg,2)
	@# Performs a try/finally operation with the named targets.
	@# This is just `flux.try.except.finally` where `except` is `flux.noop`.
	@#
	@# USAGE: (generic)
	@#  ./compose.mk flux.try.finally/<try_target>,<finally_target>
	@#

flux.watchdog/%:; cmd="${make} ${*}" ${make} io.inotify/$${path}
	@# Runs the given target once, and again in a loop whenever the given path changes.
	@# Requires inotify.
	@#
	@# USAGE: path='..' make flux.watchdog/<target>
	@#

flux.wrap/%:; ${make}	flux.and/`echo ${*} | sed 's/:/,/g'`
	@# Same as `flux.and` except that it accepts commas or colon-delimited args.
	@# You can use this to disambiguate targets that need to have "," reserved.
	@#
	@# This performs an 'and' operation with the named targets, equivalent to the
	@# default behaviour of `make t1 t2 .. tN`.  Mostly used as a wrapper in case
	@# targets are unary
	@#

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
# stream.stdin.maybe -- emit stdin's contents IF a stream is attached, else
# nothing (a tty / no pipe degrades gracefully).  Use inside a command
# substitution: `cmd `${stream.stdin.maybe}``.
stream.stdin.maybe=${io.tty.stdin} || ${stream.stdin}
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


# Pass stream to nushell with given command.  (Internal use)
 _stream.parse.nushell=img=${IMG_NUSHELL} entrypoint=nu cmd="-c '${stream.stdin} | ${1}'" CMK_INTERNAL=1 quiet=1 ${make} docker.run.sh
stream.nushell:;  $(call  _stream.parse.nushell, $${cmd})
	@# Runs the input stream through the given nushell pipeline.
	@# See also: nushell [official docs](https://www.nushell.sh/cookbook/parsing.html)
	@#
	@# EXAMPLE: 
	@#   echo '{}' | cmd='from json | to yaml' ${make} stream.nushell

stream.nushell/%:; cmd="`echo ${*} | sed 's/,/|/g' | sed 's/_/ /g'`" && $(call  _stream.parse.nushell, $${cmd})
	@# Runs the input stream through the given nushell pipeline.
	@# Pipeline is given as argument, converting underscores to space and commas to pipes.  
	@# See also: nushell [official docs](https://www.nushell.sh/cookbook/parsing.html)
	@#
	@# USAGE:
	@#    echo '{"foo":"bar"}'|./compose.mk stream.nushell/from_json,to_yaml
	@#

stream.nushell.parse stream.parse stream.parse.patterns:; $(call  _stream.parse.nushell, parse \"$${pattern}\" | to json)
	@# Use nushell to parse arbitrary input to JSON given a pattern.
	@# See also: nushell [official docs](https://www.nushell.sh/cookbook/parsing.html)
	@#
	@# EXAMPLE: 
	@#   cargo search shells --limit 10 
	@#     | pattern='{crate_name} = {version} #{description}' ./compose.mk stream.parse

stream.nushell.parse_cols stream.parse.cols stream.parse.columns:
	@# Use nushell to try to parse column-oriented input to JSON
	@# See also: nushell [official docs](https://www.nushell.sh/cookbook/parsing.html)
	@#
	@# USAGE: 
	@#   df -h | ./compose.mk stream.parse.json
	$(call  _stream.parse.nushell, detect columns | to json)
	

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
	
stream.strip:; ${stream.stdin} | awk '{gsub(/[\t\n]/, ""); gsub(/ +/, " "); print}' ORS=''
	@# Pipe-friendly helper for stripping whitespace.
	@#

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

stream.comma.to.json:; ${stream.stdin} | ${stream.comma.to.nl} | ${make} stream.nl.to.json.array
	@# Converts comma-delimited input into minimized JSON array
	@#
	@# USAGE:
	@#   > echo 1,2,3 | ./compose.mk stream.comma.to.json
	@#   ["1","2","3"]
	@#

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
stream.grep.safe=grep -iv -e password -e passwd -e key -e cert
stream.grep.safe:; ${stream.grep.safe}
# Run image previews differently for best results in github actions. 
# See also: https://github.com/hpjansson/chafa/issues/260
stream.img=${stream.stdin} \
	| docker run -i --entrypoint chafa compose.mk:tux `[ "$${GITHUB_ACTIONS:-false}" = "true" ] \
	&& echo "--size 100x -c full --fg-only --invert --symbols dot,quad,braille,diagonal" \
	|| echo "--center on"` /dev/stdin

# Converts multiple sequential newlines to just one.  `RS='\0'` reads the whole
# stream as a single record so the gsub spans it; we deliberately do NOT re-emit
# `RS` (a NUL), which otherwise lands in the compiled output and makes
# `make` warn "NUL character seen" on every re-parse of an interpreted file.
stream.nl.compress=awk -v RS='\0' '{ gsub(/\n{2,}/, "\n"); printf "%s", $$0 }'

stream.chafa=${stream.img}
stream.img stream.chafa stream.img.preview: tux.require; ${stream.img}
	@# Given an image file on stdin, this shows a preview on the console. 
	@# Under the hood, this works using a dockerized version of `chafa`.
	@#
	@# USAGE: ( generic )
	@#   > cat docs/img/docker.png | ./compose.mk stream.img.preview
	@#

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

stream.json.object.append stream.json.append:; ${stream.stdin} | ${jq} ". + {\"$${key}\": \"$${val}\"}"
	@# Appends the given key/val to the input object.
	@# This is usually used to build JSON objects from scratch.
	@#
	@# USAGE:
	@#	 > echo {} | key=foo val=bar ./compose.mk stream.json.object.append
	@#   {"foo":"bar"}
	@#

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
	@#  Converts newline-delimited input stream into a CSV row

stream.nl.to.json.array=( _tmp="`cat /dev/stdin | ${stream.nl.to.space}`"; ${jb.array} $${_tmp} )  
stream.nl.to.json.array:; ${stream.nl.to.json.array}
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
## | Variable Name        | Description                                                                  |
## | -------------------- | ---------------------------------------------------------------------------- |
## | TUI_BOOTSTRAP        | *Target-name that is used to bootstrap the TUI.  *                           |
## | TUX_BOOTSTRAPPED     | *Contexts for which the TUI has already been bootstrapped.*                  |
## | TUI_SVC_NAME         | *The name of the primary TUI svc.*                                           |
## | TUI_THEME_NAME       | *The name of the theme.*                                                     |
## | TUI_TMUX_SOCKET      | *The path to the tmux socket.*                                               |
## | TUI_THEME_HOOK_PRE   | *Target called when init is in progress but the core layout is finished*     |
## | TUI_THEME_HOOK_POST  | *Name of the post-theme hook to call.  This is required for buttons.*        |
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
export _TUI_TMUXP_PROFILE_DATA_ = $(value .sh.tmuxp.profile)

export TUI_THEME_NAME?=powerline/double/green
export TUI_THEME_HOOK_PRE?=.tux.init.theme
export TUI_THEME_HOOK_POST?=.tux.init.buttons
export TUI_CONTAINER_IMAGE?=compose.mk:tux
export TUI_SVC_BUILD_ORDER?=dind_base,tux
export TUX_LAYOUT_CALLBACK?=.tux.commander.layout
# TMUXP (the tmuxp profile path) is no longer a fixed `.tmp.tmuxp.yml`; tux.mux.detach
# generates it per-run via io.mktemp (auto-removed on exit), previews it under
# verbose, and exports it into the container so .tux.init reads the same file.

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
tux.require: ${CMK_COMPOSE_FILE}
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
	pane_targets=`printf "${*}" | ${stream.comma.to.nl} | nl -v0 | awk '{print ".tux.pane/" $$1 "/" substr($$0, index($$0,$$2))}'` \
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
	&& export cmd="${make.dind} ${*}" && ${tux.dispatch.sh}

# `cmd` (the command to run in the tux container) and `svc` reach the inner
# `compose.dispatch.sh` purely by environment inheritance: callers export `cmd`
# (tux.dispatch/% above) or set it in the env (the tux.dispatch.sh target below),
# `svc=tux` is a prefix on the inner make, and both flow down to that recipe. (The
# old form re-passed `cmd=\"$cmd\"`, but the outer recipe shell expanded `$cmd`
# from an *unset* var (a prefix-assignment isn't visible to its own command's
# expansions), so the dispatched target was silently dropped and `true` ran.)
tux.dispatch.sh=sh ${dash_x_maybe} -c "svc=tux ${make} tux.require compose.dispatch.sh/${TUI_COMPOSE_FILE}"
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
	&& suffix=.yml && $(call io.mktemp) && export TMUXP=$${tmpf} \
	&& eval "$${_TUI_TMUXP_PROFILE_DATA_}" > $${TMUXP}  \
	&& $(call log.part2, ${dim_green}ok) \
	&& if [ "$${verbose:-0}" = 1 ]; then $(call log.preview.file, $${TMUXP}); fi \
	&& cmd="${trace_maybe}" \
	&& cmd="$${cmd} && tmuxp load -d -S ${TUI_TMUX_SOCKET} $${TMUXP}" \
	&& cmd="$${cmd} && TMUX=${TMUX} tmux list-sessions" \
	&& cmd="$${cmd} && label='TUI Init' ${make.dind} io.print.banner $${TUI_INIT_CALLBACK}" \
	&& cmd="$${cmd} && label='TUI Layout' ${make.dind} io.print.banner $${TUX_LAYOUT_CALLBACK} $${reattach}" \
	&& trap "${docker.compose} -f ${TUI_COMPOSE_FILE} stop -t 1; rm -f $${TMUXP}" exit \
	&& $(call log.tux, $${header} Enter main loop for TUI) \
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} \
	&& compose_env="${docker.env.standard} \
		-e TUI_TMUX_SOCKET=${TUI_TMUX_SOCKET} \
		-e TUI_TMUX_SESSION_NAME=${TUI_TMUX_SESSION_NAME} \
		-e TUI_INIT_CALLBACK=$${TUI_INIT_CALLBACK} \
		-e TUX_LAYOUT_CALLBACK=$${TUX_LAYOUT_CALLBACK} \
		-e TUI_SVC_STARTED=1 \
		-e geometry=$${geometry:-} \
		-e reattach=$${reattach} \
		-e k8s_commander_targets=$${k8s_commander_targets:-} \
		-e tux_commander_targets=$${tux_commander_targets:-} \
		-e TMUXP=$${TMUXP}" \
	&& ${docker.compose.run} ${dash_x_maybe} -c "$${cmd}" $(_compose_quiet) \
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
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} \
	&& ${docker.compose.run} ${dash_x_maybe} -i $(_compose_quiet)

tux.shell.pipe: tux.require
	@# A pipe into the shell for the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.shell
	${trace_maybe} \
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} compose_run_flags=-T \
	&& ${docker.compose.run} ${dash_x_maybe} -c "`${stream.stdin}`" $(_compose_quiet)

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
	&& cat "$${TMUXP:-/dev/null}" | yq -r .windows[].panes[].name | ${stream.peek} \
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
	&& ( tmux select-pane -t 0.0 || true ) || $(call log.tux, ${@} ${sep}${dim} ${red}Failed initializing panes)

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
	
.tux.geo.get:; tmux list-windows | sed -n 's/.*layout \(.*\)] @.*/\1/p'
	@# Gets the current geometry for tmux.  No arguments.
	@# Output format is suitable for use with '.tux.geo.set' so that you can save manual changes.
	@#
	@# USAGE:
	@#  ./compose.mk .tux.geo.get
	@#

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
		 | xargs -I% echo "{\"name\":\"%\",\"shell_command\":\"${make.dind} %\"}" \
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
	&& ${make} ${TUI_THEME_HOOK_PRE} .tux.theme.set/${TUI_THEME_NAME}  \
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
.tux.widget.img.rotate:; display_target=.tux.img.rotate ${make} .tux.widget.img
	@# Like `.tux.widget.img`, but sets up a rotating version of the image.

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
        RUN wget -q --show-progress --progress=bar:force:noscroll -O /usr/share/figlet/Roman.flf https://raw.githubusercontent.com/xero/figlet-fonts/fbf3b68dd0fcd1e63c0f04d3c79eea2743bb377c/Roman.flf
        RUN wget -q --show-progress --progress=bar:force:noscroll -O /usr/share/figlet/3d.flf https://raw.githubusercontent.com/xero/figlet-fonts/fbf3b68dd0fcd1e63c0f04d3c79eea2743bb377c/3d.flf
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

define .sh.tmuxp.profile
cat <<EOF
# This tmuxp profile is generated by compose.mk into a per-run temp file
# (io.mktemp, auto-removed on exit). Do not edit by hand. For transparency,
# run with verbose=1 to have tux.mux.detach preview it (log.preview.file).
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
export COMPOSE_PROFILES?=
compose.ctx.display_profile=$(shell [ "$(COMPOSE_PROFILES)" = "" ] && echo "" || echo "${dim}${bold_cyan}▐░${no_ansi}${ital}$(COMPOSE_PROFILES)${no_ansi_dim}${bold_cyan}░▌") 
compose.ctx.display=${bold_green}$(or ${target_namespace},${compose_file_stem}) ${sep} ${compose.ctx.display_profile} ${sep} 
compose.with_profile/%:
	@# Runs the given targets with the given COMPOSE_PROFILE.  
	@# Comma-separated profile-names is "and", not "intersection"!
	@#
	@# USAGE:
	@#   compose.with_profile/<profile>/<t1>,<t2>,..
	@#
	prof=`printf ${*}|cut -d/ -f1` \
	targets="`printf ${*} | cut -d/ -f2- | ${stream.comma.to.space}`" \
	&& $(call log.target,$${prof} ${cyan_flow_right} $${targets}) \
	&& COMPOSE_PROFILES=$${prof} ${make} $${targets}

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
# here, but note that these opts are not available for some versions of compose.
# Lazy + derived from the memoized `docker.compose` probe (no separate per-parse
# `docker compose --help` spawn). 1 iff compose is unavailable. Only expanded by
# the compose.import code paths below (call time), not at parse.
COMPOSE_MISSING=$(if $(filter docker,$(firstword ${docker.compose})),0,1)

# Single define; the missing-compose guard is checked at call time (COMPOSE_MISSING
# is lazy) so it no longer needs a parse-time `ifeq` (which probed docker).
define compose.get_services
$(if $(filter 1,${COMPOSE_MISSING}),,$(shell if [ "${CMK_INTERNAL}" = "0" ]; then \
		(${trace_maybe} && ([ "$(strip ${1})" = "" ] && echo -n "" || COMPOSE_PROFILES=${COMPOSE_PROFILES} ${docker.compose} -f ${1} config --services||echo -n ""))  ; \
	else echo -n ""; fi))
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
	${trace_maybe} && entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} `printf $${*}|cut -d/ -f2-`" \
	${make} ${compose_file_stem}/`printf $${*}|cut -d/ -f1`

${compose_file_stem}/$(compose_service_name).logs:
	@# Logs for this service.  NB: Uses "follow" mode by default, so this is blocking
	${make} docker.logs.follow/`${make} ${compose_file_stem}/$(compose_service_name).ps | ${jq} -r .ID` \
	|| $$(call log.docker, ${compose_file_stem}/$(compose_service_name).logs ${sep} ${red} failed${no_ansi} showing logs for ${bold}${compose_service_name}${no_ansi}.. could not find id?)

${compose_file_stem}.exec.bg/%:; detach=1 ${make} ${compose_file_stem}.exec/$${*}
${compose_file_stem}.exec/%:
	@# Like ${compose_file_stem}.dispatch, but using exec instead of run
	@# Foregrounded by default.  Pass detach=1 to override.
	@#
	@# USAGE:
	@#   ./compose.mk ${compose_file_stem}.exec/<svc>/<target>
	@#   detach=0 ./compose.mk ${compose_file_stem}.exec/<svc>/<target>
	@#   cmd=whoami ./compose.mk ${compose_file_stem}.exec/<svc>
	@#
	@$$(eval detach:=$(shell if [ -z $${detach:-} ]; then echo ""; else echo "--detach"; fi)) 
	${trace_maybe} \
	&& svc="`printf $${*}|cut -d/ -f1`" \
	&& target="`printf $${*}|cut -d/ -s -f2-`" \
	&& case $$$${target} in \
		"") cmd="$$$${cmd:-whoami}";; \
		*) cmd="${make} $$$${target}";; \
	esac \
	&& tmp="${no_ansi}${bold}::" \
	&& case $$$${target} in \
		"") disp="${no_ansi}${bold}[${no_ansi}${dim_ital}$$$${cmd:-?}${no_ansi}${bold}]";; \
		*) disp="${no_ansi}${ital}$$$${target}";; \
	esac \
	&& $$(call log.docker, ${compose.ctx.display} ${bold_cyan}exec ${sep} ${dim}$$$${svc} ${sep} $$$${disp} ${cyan_flow_right}) \
	&& set -x && docker compose -f ${compose_file} exec $${detach} \
		$$$${svc} $$$${cmd} 
# 2> >(grep -v 'variable is not set' >&2)

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

$(compose_service_name).assert_running ${compose_file_stem}.assert_running/$(compose_service_name):
	[ -n "`${make} ${compose_file_stem}/$(compose_service_name).ps`" ] \
		&& exit 0 || exit 23

${compose_file_stem}/$(compose_service_name).pipe:
	@# A pipe into the $(compose_service_name) container @ $(compose_file).
	@# Specify 'entrypoint=...' to override the default spec.
	@#
	@# EXAMPLE: 
	@#   echo echo hello-world | ./compose.mk  ${compose_file_stem}/$(compose_service_name).pipe
	@#
	${stream.stdin} | pipe=yes ${make} ${compose_file_stem}/$(compose_service_name)

${compose_file_stem}.restart: ${compose_file_stem}.down ${compose_file_stem}.up.detach
${compose_file_stem}.restart.fg: ${compose_file_stem}.down ${compose_file_stem}.up
${compose_file_stem}.restart/$(compose_service_name): \
	${compose_file_stem}/$(compose_service_name).stop ${compose_file_stem}.up/$(compose_service_name)

${compose_file_stem}.with_profile/%:
	@# USAGE: make docker-compose.with_profile/all/up,sto
	prof=`printf $${*} | cut -d/ -f1` \
	&& targets="`printf $${*} | cut -d/ -f2- | ${stream.comma.to.nl} | xargs -I% echo ${compose_file_stem}.%|${stream.nl.to.space}|${stream.space.to.comma}`" \
	&& ${trace_maybe} && ${make} compose.with_profile/$$$${prof}/$$$${targets}

${compose_file_stem}/$(compose_service_name).ps:
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

${compose_file_stem}.exec.shell/$(compose_service_name):
	@# Open interactive shell for the container.  Requires that `up` already happened, and is still running
	set -x && docker exec -it `${make} ${compose_file_stem}/$(compose_service_name).ps \
		| ${jq} -e -r .ID` `${make} ${compose_file_stem}/$(compose_service_name).get_shell`

$(eval ifeq ($$(import_to_root), TRUE)
$(compose_service_name).ps: ${compose_file_stem}/$(compose_service_name).ps
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

$(compose_service_name).exec.shell: ${compose_file_stem}.exec.shell/$(compose_service_name)
	@# Open interactive shell for the container.  Requires that `up` already happened, and is still running
	
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

${namespaced_service}.pipe:; pipe=yes ${make} ${namespaced_service}
${target_namespace}.$(compose_service_name).exec/%:; ${make} ${compose_file_stem}.exec/$(compose_service_name)/$${*}
${target_namespace}.$(compose_service_name).exec:; ${make} ${compose_file_stem}.exec/$(compose_service_name)
${target_namespace}.$(compose_service_name).exec.shell: ${compose_file_stem}.exec.shell/$(compose_service_name)

${target_namespace}.$(compose_service_name).dispatch/%:
	@# Dispatch named target in $(compose_service_name) container
	${make} ${compose_file_stem}.dispatch/$(compose_service_name)/$${*}
${target_namespace}.get_config: ${compose_file_stem}/$(compose_service_name).get_config
${target_namespace}.ps: ${compose_file_stem}.ps
${target_namespace}.$(compose_service_name).assert_running: ${compose_file_stem}.assert_running/$(compose_service_name)
${target_namespace}.$(compose_service_name).restart: ${compose_file_stem}.restart/$(compose_service_name)

${target_namespace}.$(compose_service_name).stop: ${compose_file_stem}/$(compose_service_name).stop
${target_namespace}.$(compose_service_name).up: ${compose_file_stem}.up/$(compose_service_name)
${target_namespace}.$(compose_service_name).up.detach: ${compose_file_stem}.up.detach/$(compose_service_name)
${target_namespace}.up.detach: ${compose_file_stem}.up.detach
${target_namespace}.restart: ${compose_file_stem}.restart
${target_namespace}.restart.fg: ${compose_file_stem}.restart.fg
# ${target_namespace}.down: ${compose_file_stem}.down
${target_namespace}.$(compose_service_name).shell: ${compose_file_stem}/$(compose_service_name).shell
${target_namespace}.$(compose_service_name).ps: ${compose_file_stem}/$(compose_service_name).ps
${target_namespace}.$(compose_service_name).build: ${compose_file_stem}.build/$(compose_service_name)
${target_namespace}.$(compose_service_name).shell.pipe: ${compose_file_stem}/$(compose_service_name).shell.pipe
${target_namespace}.$(compose_service_name): ${compose_file_stem}/$(compose_service_name)
${target_namespace}.up: ${compose_file_stem}.up
${namespaced_service}.command/%:; cmd="$${*}" ${make} ${compose_file_stem}/$(compose_service_name)
${namespaced_service}: 
	@# Target dispatch for $(compose_service_name)
	@#
	[ -z "${MAKE_CLI_EXTRA}" ] && true || verbose=0 \
	&& ${trace_maybe} && ${make} ${compose_file_stem}/${compose_service_name}
${namespaced_service}/%:
	@# Dispatches the named target inside the $(compose_service_name) service, as defined in the ${compose_file} file.
	@#
	@# EXAMPLE: 
	@#  # mapping a public Makefile target to a private one that is executed in a container
	@#  my-public-target: ${namespaced_service}/myprivate-target
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

mk.docker.rmi/%:; CMK_INTERNAL=1 img="compose.mk:${*}" ${make} docker.rmi
	@# Removes images with `docker rmi`.  Uses the compose.mk prefix automatically.

# Scaffolds dispatch/shell/run targets for the given docker image.  Accepts
# EITHER `file=<path>` (build from a Dockerfile path) or `def=<name>` (build from
# an inline `Dockerfile.<name>` define) -- `def=` present routes to the def-based
# body (`_docker.import.def`).  The $(if) is LAZY, so only the taken branch
# expands (both bodies have parse-time side effects via $(eval)/unpack).
docker.import=$(eval $(if $(findstring def=,${1}),$(call _docker.import.def,${1}),$(call _docker.import,${1})))
# DEPRECATED aliases -- emit a yellow parse-time warning (log.import.deprecated),
# then delegate to `docker.import`.  Prefer `docker.import` (def= or file=) directly.
docker.import.def=$(call log.import.deprecated,docker.import.def,docker.import with def=/file=)${docker.import}
docker.image.import=$(call log.import.deprecated,docker.image.import,docker.import with def=/file=)${docker.import}
define _docker.import.def
ifeq ($${CMK_INTERNAL},1)
else
$(call mk.unpack.kwargs, ${1}, def)
$(eval img_name:=$(patsubst Dockerfile.%,%,${kwargs_def}))
$(call mk.unpack.kwargs, ${1}, namespace, $${img_name})
${kwargs_namespace}.img:=compose.mk:${img_name}
${kwargs_namespace}.clean: mk.docker.rmi/${img_name}
${kwargs_namespace}.dispatch/%:; 
	@# Dispatch the given target in the `${kwargs_namespace}` container
	img=${img_name} hostname=${img_name} ${make} mk.docker.dispatch/$${*}
${kwargs_namespace}.build: 
	$$(call log.docker, $${@} ${sep} ${dim}(via def=${no_ansi}${kwargs_def}) ${sep} ${cyan_flow_right}) \
	&& ${make} Dockerfile.build/${img_name} \
	&& $$(call log.target, ${bold}${green}${GLYPH_CHECK}) 
${kwargs_namespace}.shell:; entrypoint="$$$${entrypoint:-bash}" ${make} ${kwargs_namespace}
${kwargs_namespace}:; img="${img_name}" hostname="${img_name}" ${make} mk.docker.run.sh 
endif
endef
define _docker.import
ifeq ($${CMK_INTERNAL},1)
else
$(call mk.unpack.kwargs, ${1}, file, undefined)
$(call mk.unpack.kwargs, ${1}, namespace)
$(call mk.unpack.kwargs, ${1}, img,compose.mk:$${kwargs_namespace})
${kwargs_namespace}.img:=${kwargs_img}
${kwargs_namespace}.dispatch/%:; img=${kwargs_img} hostname=${kwargs_img} \
	${make} docker.dispatch/$${*}
${kwargs_namespace}.build:
	${trace_maybe} \
	&& case ${kwargs_file} in \
		undefined) $$(call log.docker, $${@} ${sep} docker.importfile is undefined!) ;; \
		*) ( \
			$$(call log.docker, $${@} ${sep} ${dim}(via img=${no_ansi}${kwargs_img} ${dim}file=${no_ansi}${kwargs_file}${dim}) ${sep} ${cyan_flow_right}) \
			&& tag=${kwargs_img} ${make} docker.build/${kwargs_file} \
			&& $$(call log.target, ${bold}${green}${GLYPH_CHECK}) \
		);; \
	esac
${kwargs_namespace}.shell:; entrypoint="$$$${entrypoint:-sh}" ${make} ${kwargs_namespace}
${kwargs_namespace}:; img="${kwargs_img}" hostname="${kwargs_img}" ${make} docker.run.sh 
endif
endef

# Helper macro, defaults to root-import with an optional dispatch-namespace.
# If not provided, the default dispatch namespace is `services`.
#
# USAGE: 
#   $(call compose.import, file=docker-compose.yml)
#   $(call compose.import, file=docker-compose.yml namespace=▰)
#   $(call compose.import, file=docker-compose.yml namespace=▰ import_to_root=TRUE)

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

# Lazy dispatcher: decide the missing-compose no-op at call time (COMPOSE_MISSING
# is lazy) instead of via a parse-time `ifeq` that probed docker. The real body
# (renamed `.real`) is unchanged.
compose.import.generic=$(if $(filter 1,${COMPOSE_MISSING}),,$(call compose.import.generic.real,$(1),$(2),$(3)))
define compose.import.generic.real
$(eval target_namespace:=$(strip $(1)))
$(eval compose_file:=$(strip $(3)))
$(eval cached:=$(call io.string.hash,$(target_namespace)$(2)$(3)))
$(call log.import.part1,${dim}compose.import.generic ${sep} ${compose_file})
ifndef $${cached}
$$(eval ${cached} := 1)
$(call log.import.part2,${dim}namespace=${bold}${target_namespace})

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
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}build ${sep} ${dim_ital}all services) \
	&&  $(trace_maybe) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build $${_docker_quiet_flag}

${compose_file_stem}.build.quiet $(target_namespace).build.quiet:
	@# Quiet build for all services in the given file.
	@#
	@# USAGE: ./compose.mk  <compose_stem>.build.quiet
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	@$$(eval export svc_disp:=$(shell echo echo $$$${svc:-all services}))
	$(call log.docker, ${compose.ctx.display} ${bold_cyan}build ${sep} ${dim_ital}$${svc_disp})
	$(trace_maybe) \
	&& quiet=1 label="build finished in" ${make} flux.timer/compose.build/${compose_file}

${compose_file_stem}.build.quiet/% ${compose_file_stem}.require/%:
	@# Quiet build for the named service in the ${compose_file} file
	@#
	@# USAGE: 
	@#   ./compose.mk  ${compose_file_stem}.build.quiet/<svc_name>
	@#
	$(trace_maybe) && ${make} io.quiet.stderr/${compose_file_stem}.build/$${*}

${compose_file_stem}.build/% $(target_namespace).build/%:
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
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}stop ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} stop -t 1 2> >(grep -v '\] Stopping'|grep -v '^ Container ' >&2)
 

${compose_file_stem}.down $(target_namespace).down:
	@# Bring down all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}down ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} down -t 1 2> >(grep -v '^Network.*Removing'|grep -v '^Network.*Removed' >&2)

${compose_file_stem}.up:
	@# Brings up all services in the given compose file.
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${dim_ital} $$$${svc:-all services})
	${docker.compose} -f $${compose_file} up $$$${svc:-}
${compose_file_stem}.up.detach:
	@# Brings up all services in the given compose file.
	@# Stops all services for the ${compose_file} file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${dim_ital} $$$${svc:-all services})
	${docker.compose} -f $${compose_file} up -d $$$${svc:-}

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
		${docker.cmk.mount} \
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
${compose_file_stem}.ps:
	@# Returns JSON for names only.
	$$(call log.target, ${no_ansi}file=${dim}${ital}${compose_file})
	docker compose -f ${compose_file} ps --format json | ${jq} .Service | ${jq} -s .

else
$(call log.import.part2,${GLYPH_CHECK} cached)
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
# ${1}=block name, ${2}=the `with` kwargs string (e.g. `img=X entrypoint=Y` for a
# container, or `bind=T` for a target).  Both forward verbatim to polyglot.import,
# which routes container-vs-bind on the `bind=` kwarg; `as container`/`as target`
# is the readability label that selects which of these it lowers to.
polyglot.__import__.target=$(call polyglot.import, def=$(strip ${1}) $(strip ${2}))
polyglot.__import__.container=$(call polyglot.import, def=$(strip ${1}) $(strip ${2}))

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

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## Aliases use the `alias=${original}` idiom (a recursive reference, same as
## `docker.image.import`), so each forwards its arg(s) to the original verbatim.
## No trailing inline comments on the assignments below -- make would otherwise
## fold the leading whitespace into the value.  The docs header is a `## BEGIN:`
## comment-block so it is extractable via `mk.parse.block` (subcommand=cblocks).
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: DeclarationIndex: All the `declare.*` macros.
##
## The parse-time DECLARATION namespace.  Members run at parse/expansion time
## (via `$(eval)`/`$(call)`), code-generating make state before any recipe runs.
## Most are convenience aliases onto the canonical `*.import` declaration macros
## (one verb-first name per kind of thing you can bring into scope); `declare.stack`
## (core) and `declare.channel` (core) are unique primitives.  See each
## original's own USAGE for the exact kwargs it accepts.
##
## | name | delegates to | brings into scope    |
## |-------------------|----------------------|---------------------------|
## | declare.stack     |  (core primitive)     | <VAR> -- a per-run-unique stack-name var |
## | declare.channel   | (core primitive)    | namespace=<n> -- an event channel (stack+ops) |
## | declare.module    | import.module  | def=<name>\|file=<path> [namespace=] [targets=/defs= for partial] |
## | declare.plugin    | include.plugin | <file..> from CMK_PLUGINS_DIR [strict=0 -> log+continue] |
## | declare.plugins   | include.plugins| plural spelling of declare.plugin (both take one-or-many) |
## | declare.files     | include.files  | <file..> cwd-relative/explicit [strict=0 -> log+continue] |
## | declare.def       | import.def     | file=<path> def=<name> [as=] [namespace=]  (one define)  |
## | declare.defs      | import.defs    | file=<path> defs="<glob> .." [namespace=]  (many)        |
## | declare.target    | import.target  | file=<path> target=<name> [namespace=]                   |
## | declare.targets   | import.targets | file=<path> targets="<glob> .." [namespace=]             |
## | declare.container   | docker.import          | file=<path>\|def=<name> -- scaffold image |
## | declare.compose     | compose.import    | file=<docker-compose.yml> [namespace=]   |
## | declare.polyglot    | polyglot.import   | a polyglot (foreign-language) block      |
## | declare.polyglots   | polyglots.import  | many polyglot blocks                     |
## | declare.cmk.virtual_machine | .cmk/virtual-machine.cmk plugin | the reflective __vm__ env: prefix=<p> \| exclude=<prefixes> |
## END: DeclarationIndex
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
declare.module=${import.module}
declare.plugin=${include.plugin}
declare.plugins=${include.plugins}
declare.files=${include.files}
declare.def=${import.def}
declare.defs=${import.defs}
declare.target=${import.target}
declare.targets=${import.targets}
declare.container=${docker.import}
declare.compose=${compose.import}
declare.polyglot=${polyglot.import}
declare.polyglots=${polyglots.import}

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
&& $(call _mk.unpack.kwargs,${1},entrypoint_args,-x) \
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
		1)  $${entrypoint} $${entrypoint_args} $${tmpf};; \
		*) ( true \
			&& case $${quiet:-1} in \
				0) cat $${tmpf} | ${stream.as.log};; \
			esac && ${trace_maybe} \
			&& entrypoint=$${entrypoint} cmd="$${entrypoint_args} $${tmpf}" ${make} $${svc}) \
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

# Thin wrapper so `log.target` works as a decorator: `ᝏlog.target(msg)` logs the
# given message before the target's body runs; `ᝏlog.target()` (zero args) logs
# the target name.  The $(origin) guard passes the message only when present, so
# it stays warning-clean for any arg-count.  Returns 0 (log.target does), so it
# composes with the recipe-body `&&`-join.
bind.log.target=$(call log.target,$(if $(filter-out undefined,$(origin 1)),${1}))

# `ᝏio.pushd(dir)` decorator: run the WHOLE target body from `dir`.  The compiler
# relocates the decorator to the head of the recipe and the joinbody pass
# `&&`-chains the body into ONE shell, so this directory change persists to every
# command in the target (without it each recipe line is its own shell and the
# change would not carry).  Uses bash `pushd` (the recipe SHELL is bash) rather
# than `cd` so the body can `popd` back to the caller's dir if it wants; the
# stack listing is muted.  Fails fast (nonzero) if `dir` is missing, aborting the
# `&&`-chain.
bind.io.pushd=pushd "$(strip ${1})" >/dev/null

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

bind.args.from_params=$(bind.posargs)
bind.posargs=$(call _bind.posargs,$(strip $(or $(if $(filter undefined,$(origin 1)),,$(1)),${comma})))
define _bind.posargs
kwargs_delim=$(strip $(if $(filter undefined,$(origin 1)),${comma},$(1))) \
&& _1st="`echo ${*} | cut -d$${kwargs_delim} -f 1`" \
&& _2nd="`echo ${*} | cut -d$${kwargs_delim} -f 2`" \
&& _3rd="`echo ${*} | cut -d$${kwargs_delim} -f 3`" \
&& _4th="`echo ${*} | cut -d$${kwargs_delim} -f 4`" \
&& _5th="`echo ${*} | cut -d$${kwargs_delim} -f 5`" \
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

define _help_gen
(LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : ${stderr_devnull} | awk -v RS= -F: '/(^|\n)# Files(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' | LC_ALL=C sort| uniq || true)
endef
mkparse:
	@#
	prefix=`case $${prefix:-} in "") echo;; *) echo "--prefix $${prefix}";; esac` \
	&& local=`case $${local:-} in "") echo;; *) echo "--local";; esac` \
	&& preview=`case $${preview:-} in "") echo;; *) echo "--preview";; esac` \
	&& ${trace_maybe} && ${mkparse} $${path:-${MAKEFILE}} $${prefix} $${local} $${preview} --public 

help.local: 
	@# Lists only local targets (no includes)
	@# Used from an included makefile, not with compose.mk itself. 
	$(call log.target, Listing local targets only)
	${mkparse} $${path:-${MAKEFILE}} --shallow --local --names-only
help.local.all:; ${mkparse} $${path:-${MAKEFILE}} --local --preview
	@# Shows all help for all local targets 

help.local/%: 
	@# Renders help for a local target, i.e. just the ones that do NOT come from includes.
	@# Used from an included makefile, not with compose.mk itself. 
	$(call log.target, Listing local targets only)
	${mkparse} $${path:-${MAKEFILE}} --local --preview --prefix ${*}

help/%:; ${mkparse} $${path:-${MAKEFILE}} --prefix ${*} --markdown --preview
	@# 

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
	&& count="`echo "$${key}" | ${stream.count.words}`" \
	&& case $${count} in \
		0) ( $(call _help_gen) > $${tmpf} \
			&& count=`cat $${tmpf} | ${stream.count.lines}` && count="${yellow}$${count}${dim} items" \
			&& cat $${tmpf} \
			&& $(call log.docker, help ${sep} ${dim}Answered help for: ${no_ansi}${bold}top-level ${sep} $${count}) \
			&& case ${MAKEFILE} in \
				${CMK_SRC}) $(call log.docker, help ${sep} ${dim}For more specific help use ${no_ansi}${red}${MAKEFILE} help/<target>) ;; \
				*) ( \
					case ${MAKEFILE} in \
						Makefile) _tmp=make;; \
						*) _tmp="make -f ${MAKEFILE}";; \
					esac \
					&& $(call log.docker, help ${sep} To omit included-targets run: ${no_ansi}${red}$${_tmp} help.local) \
					);; \
			esac ); ;; \
		1) ( ( ${mkparse} $${path:-${MAKEFILE}} --local --public --preview --prefix $${key} ) ;  $(call mk.yield,true) ); ;; \
		*) ( $(call log.docker, help ${sep} ${red}Not sure how to help with $${key} ($${count}) ${no_ansi}$${key}) ; ); ;; \
	esac 

# Code-gen shim for `loadf`
define .sh.loadf
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
include ${CMK_DIND_SRC}
\$(eval \$(call compose.import.generic, ▰, TRUE, ${fname}))
EOF
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## END: Macros
## BEGIN: Special targets (only available in stand-alone mode)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
ifeq ($(CMK_STANDALONE),1)
export LOADF = $(value .sh.loadf)
loadf: compose.loadf

# NB: the yq/jq/jb CLI proxy-wrappers below are gated to stand-alone (tool) mode
# on purpose. In library mode (`include compose.mk`, e.g. the `loadf`-generated
# file) a loaded compose-file may legitimately define a service named `yq`/`jq`,
# and defining these here too would trigger make's "overriding recipe" warning.
# Only the bare TARGETS are gated; the `${yq}`/`${jq}`/`${jb}` macros stay global.

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
endif

# Lower container-dispatch call sugar: rewrite every `NAME.dispatch(args)` on a line
# to `NAME.dispatch/args`.
define .awk.dispatch
{ while (match($$0, /([[:alnum:]_.]+)\.dispatch\(([^)]+)\)/, arr)) {
    before = substr($$0, 1, RSTART-1); after = substr($$0, RSTART+RLENGTH)
    $$0 = before arr[1] ".dispatch/" arr[2] after
    }
    print }
endef
# Sugar-block lowering: turn a `<open>NAME ... <close>` marked block (open/close
# regexes and an output template come from ARGV) into `define NAME .. endef`, then
# substitute the block's `with ..`/`as ..` trailer (block arguments) into the template
# placeholders __WITH__/__AS__/__NAME__/__REST__.  The trailer may spill onto the lines
# after the close marker.  `finalize_trailer` -- render and emit the template.
# FLAG: refactor candidate -- one stage doing block-boundary tracking, trailer
# parsing, and template substitution; could split into discrete passes.
define .awk.sugar
BEGIN {
 if (ARGC < 3) {
    print "Usage: script.awk open_pattern close_pattern post_process_template" > "/dev/stderr"
    exit 1 }
 open_pattern = ARGV[1]; close_pattern = ARGV[2]
 post_process_template = ARGV[3]
 delete ARGV[1]; delete ARGV[2]; delete ARGV[3]
}
function finalize_trailer(   cur_template, with_clause, as_clause, m, pm, rem) {
 cur_template = post_process_template
 with_clause = ""; as_clause = ""
 rem = pending_remainder
 if (match(rem, /^with[ \t]*\(([^()]*)\)[ \t]*(as[ \t]+.+)?[ \t]*$/, pm)) { rem = "with " pm[1] (pm[2] ? " " pm[2] : "") }
 if (match(rem, /^with (.+)\s+as\s+(.+)$/, m)) { with_clause = m[1]; as_clause = m[2] }
 else if (match(rem, /^as[ \t]+(.+)$/, m)) { as_clause = m[1] }
 else if (match(rem, /^with[ \t]+(.+)$/, m)) { with_clause = m[1] }
 gsub(/__WITH__/, with_clause, cur_template)
 gsub(/__AS__/, as_clause, cur_template)
 gsub(/__NAME__/, pending_name, cur_template)
 gsub(/__REST__/, rem, cur_template)
 print cur_template
 pending_remainder = ""; pending_name = ""; awaiting_trailer = 0
}
awaiting_trailer == 1 {
 if ($0 ~ /^[ \t]*$/) { if (pending_remainder == "") next; finalize_trailer(); next }
 stripped = $0; sub(/^[ \t]+/, "", stripped); sub(/[ \t]+$/, "", stripped)
 if (pending_remainder == "" && stripped ~ /^(with|as)[ \t(]/) { pending_remainder = stripped; next }
 if (stripped ~ /^as[ \t]/ && pending_remainder ~ /(^|[ \t])with([ \t]|$)/ && pending_remainder !~ /(^|[ \t])as([ \t]|$)/) { pending_remainder = pending_remainder " " stripped; next }
 finalize_trailer()
}
$0 ~ open_pattern && block_mode == 0 {
 block_name = $0
 sub(open_pattern, "", block_name)
 sub(/^[ \t]+/, "", block_name)
 sub(/[ \t]+$/, "", block_name)
 print "define " block_name
 block_mode = 1; next
}
$0 ~ close_pattern && block_mode == 1 {
 print "endef"
 remainder = $0; sub(close_pattern, "", remainder); sub(/^[ \t]+/, "", remainder); sub(/[ \t]+$/, "", remainder)
 pending_remainder = remainder
 pending_name = block_name
 awaiting_trailer = 1
 block_mode = 0
 next
}
block_mode == 1 { print $0 }
block_mode == 0 { print $0 }
END { if (awaiting_trailer == 1) finalize_trailer() }
endef
# Lower CMK triple-delimiter literals to a %-safe `printf`, in two modes mirroring
# shell quoting: `'''TEXT'''` -> single-quoted (literal; shell `$VAR`/`` `cmd` `` pass
# through), `"""TEXT"""` / ```TEXT``` -> double-quoted (interpolating).  Make expansion
# happens in both.  Inert inside define..endef (polyglots pass through).
# `sq`/`dq` -- single/double-quote-escape a string.  `emit` -- render the printf.
define .awk.triplequote
function sq(s,   n,p,i,r) {
    n = split(s, p, "'"); r = p[1]
    for (i = 2; i <= n; i++) r = r "'\\''" p[i]
    return "'" r "'" }
function dq(s,   r) {
    r = s; gsub(/\\/, "\\\\", r); gsub(/"/, "\\\"", r)
    return "\"" r "\"" }
function emit(content, interp,   n,p,i,fmt,args) {
    n = split(content, p, "\n"); fmt = "%s"; args = (interp ? dq(p[1]) : sq(p[1]))
    for (i = 2; i <= n; i++) { fmt = fmt "\\n%s"; args = args " " (interp ? dq(p[i]) : sq(p[i])) }
    return "printf '" fmt "' " args }
BEGIN { in_def = 0; SQ = "'''"; DQ = "\"\"\""; BT = "```" }
{
    rest = $0; out = ""
    while (1) {
        a = index(rest, SQ); b = index(rest, DQ); g = index(rest, BT)
        if (a == 0 && b == 0 && g == 0) { out = out rest; break }
        p = 0
        if (a != 0 && (p == 0 || a < p)) { p = a; delim = SQ; interp = 0 }
        if (b != 0 && (p == 0 || b < p)) { p = b; delim = DQ; interp = 1 }
        if (g != 0 && (p == 0 || g < p)) { p = g; delim = BT; interp = 1 }
        out = out substr(rest, 1, p - 1)
        after = substr(rest, p + 3)
        c = index(after, delim)
        if (c > 0) {
            dc = substr(delim, 1, 1); rl = 0
            while (substr(after, c + rl, 1) == dc) rl++
            out = out emit(substr(after, 1, c - 1 + rl - 3), interp); rest = substr(after, c + rl) }
        else {
            content = after; closed = 0
            while ((getline nl) > 0) {
                c = index(nl, delim)
                if (c > 0) {
                    dc = substr(delim, 1, 1); rl = 0
                    while (substr(nl, c + rl, 1) == dc) rl++
                    content = content "\n" substr(nl, 1, c - 1 + rl - 3); rest = substr(nl, c + rl); closed = 1; break }
                content = content "\n" nl }
            out = out emit(content, interp)
            if (!closed) rest = "" } }
    print out }
endef
# Lower CMK block-reference glyphs to a file argument: `⬦NAME` -> a stream FD
# `<($(call _mk.def.to.fd, NAME))`, `⬥NAME` -> a real file `$(call _mk.def.tmpfile, NAME)`.
# NAME is `[A-Za-z0-9._/-]+`; glyph width via length() (mawk/gawk safe).  Inert inside
# define..endef (polyglots pass through).
define .awk.blockref
BEGIN { in_def = 0; FD = "⬦"; FILE = "⬥" }
{
    rest = $0; out = ""
    while (1) {
        a = index(rest, FD); b = index(rest, FILE)
        if (a == 0 && b == 0) { out = out rest; break }
        if (a != 0 && (b == 0 || a < b)) { p = a; gl = length(FD); kind = "fd" }
        else { p = b; gl = length(FILE); kind = "file" }
        out = out substr(rest, 1, p - 1)
        after = substr(rest, p + gl)
        name = ""; i = 1; L = length(after)
        while (i <= L) { ch = substr(after, i, 1); if (ch ~ /[A-Za-z0-9._\/-]/) { name = name ch; i++ } else break }
        if (name == "") { out = out substr(rest, p, gl); rest = after; continue }
        if (kind == "fd") out = out "<($(call _mk.def.to.fd, " name "))"
        else out = out "$(call _mk.def.tmpfile, " name ")"
        rest = substr(after, i) }
    print out }
endef
# Join a target's recipe body into ONE shell invocation: every line but the last gets a
# trailing connector so the body shares shell state and is fail-fast.  The connector is the
# `-v JOIN` arg (the `recipe_join` pragma): default/`&&` -> ` && \`, `;` -> ` ; \`, `none` ->
# no join (each line stays a separate recipe-line; no shared shell state).  Runs LAST; skips
# define..endef bodies (depth-tracked).  `comment_pos` -- index of a real trailing shell
# `#` comment (ignoring quotes/`$(..)`/`${..}`; `$#`/`foo#bar`/`${V#x}` stay intact),
# else 0.  `strip_comment` -- drop that comment.  `flush` -- emit the buffered body.
# FLAG: refactor candidate -- comment-scanning + buffering + connector logic in one;
# `comment_pos`/`strip_comment` could be a separate pass.
define .awk.joinbody
BEGIN { def_depth = 0; n = 0
    CONN = " && \\"; if (JOIN == ";") CONN = " ; \\"; else if (JOIN == "none") CONN = "" }
function comment_pos(s,   i, L, c, q, depth, prevch) {
    L = length(s); q = ""; depth = 0; i = 1
    while (i <= L) {
        c = substr(s, i, 1)
        if (q != "") {
            if (q == "\"" && c == "\\") { i += 2; continue }
            if (c == q) q = ""
            i++; continue }
        if (c == "'" || c == "\"" || c == "`") { q = c; i++; continue }
        if (c == "$" && (substr(s, i+1, 1) == "(" || substr(s, i+1, 1) == "{")) { depth++; i += 2; continue }
        if (depth > 0 && (c == ")" || c == "}")) { depth--; i++; continue }
        if (depth == 0 && c == "#") {
            prevch = (i == 1) ? "" : substr(s, i-1, 1)
            if (i == 1 || prevch == " " || prevch == "\t") return i }
        i++ }
    return 0 }
function strip_comment(s,   p, r) {
    p = comment_pos(s); if (p == 0) return s
    r = substr(s, 1, p - 1); sub(/[ \t]*$/, "", r); return r }
function flush(   i, conn) {
    for (i = 1; i <= n; i++) {
        if (i < n) {
            if (buf[i] ~ /\\$/) conn = ""
            else if (buf[i] ~ /(;|&&|\|\||\||&)[ \t]*$/) conn = (CONN == "" ? "" : " \\")
            else conn = CONN
            print "\t" buf[i] conn }
        else print "\t" buf[i] }
    n = 0 }
/^define / { flush(); def_depth++; print; next }
/^endef[ \t]*$/ { flush(); if (def_depth > 0) def_depth--; print; next }
def_depth > 0 { print; next }
/^\t/ {
    c = $0; sub(/^\t/, "", c); c = strip_comment(c)
    if (c ~ /^[ \t]*$/) next
    if (c ~ /^[-+]/) { flush(); print "\t" c; next }
    if (n > 0) sub(/^@/, "", c)
    buf[++n] = c; next }
{ flush(); print }
END { flush() }
endef

# Shared error helpers for CMK compiler awk stages: print a stage-tagged message to
# stderr and exit 79 (the compile-error code).  `cmk_die` -- bare error.
# `cmk_die_at` -- error citing the offending source line (defaults to current NR/$0).
define .awk.cmk.errors
function cmk_die(stage, msg) {
	printf "compose.mk (cmk:%s) error: %s\n", stage, msg > "/dev/stderr"
	exit 79 }
function cmk_die_at(stage, msg, lineno, src) {
	if (lineno == "") lineno = NR
	if (src == "") src = $0
	printf "compose.mk (cmk:%s) error: %s\n  at line %s: %s\n", stage, msg, lineno, src > "/dev/stderr"
	exit 79 }
endef

# Shared define..endef guard for line-oriented CMK stages: pass define-block bodies
# (raw polyglot/awk/docstring text) through untouched.  Prepended before a stage's main
# `{...}` rule.  Depth-tracked, so NESTED defines pass through verbatim too.
define .awk.cmk.defskip
/^define / { def_depth++; print; next }
/^endef[ \t]*$/ { if (def_depth > 0) def_depth--; print; next }
def_depth > 0 { print; next }
endef

# Shared triple-quote literal parser for the sugar stages (tagged, callform).
# `is_delim` -- is a string one of `'''`/`"""`/```` ``` ````?  `parse_literal(s, stage)` --
# read a leading literal from `s` (multi-line via getline), setting globals LIT_ (the
# literal incl. delimiters) and REM_ (the remainder); cmk_die_at if unterminated.
define .awk.cmk.litparse
function is_delim(s) { return (s == "'''" || s == "\"\"\"" || s == "```") }
function parse_literal(s, stage,   delim, after, c, dc, rl, lit, nl) {
	delim = substr(s, 1, 3); after = substr(s, 4)
	c = index(after, delim)
	if (c > 0) {
		dc = substr(delim, 1, 1); rl = 0; while (substr(after, c+rl, 1) == dc) rl++
		LIT_ = substr(s, 1, 3 + (c-1) + rl); REM_ = substr(after, c+rl); return }
	lit = s
	while ((getline nl) > 0) {
		c = index(nl, delim)
		if (c > 0) {
			dc = substr(delim, 1, 1); rl = 0; while (substr(nl, c+rl, 1) == dc) rl++
			LIT_ = lit "\n" substr(nl, 1, (c-1)+rl); REM_ = substr(nl, c+rl); return }
		lit = lit "\n" nl }
	cmk_die_at(stage, "unterminated triple-quoted literal (no closing " delim ")", START_NR, START_SRC) }
endef

# Shared call-lowering helper for the sugar stages.  `lower_calls(text)` rewrites
# `NAME(args)` -> `$(call NAME,args)` with balanced parens, recursing on the args.  The
# trigger is set by the calling stage's BEGIN: TRIG_MODE="prefix" scans for the fixed
# string TRIG_PREFIX; TRIG_MODE="names" matches any NAMESET[] key (longest wins).  A
# trigger with no `(`, or an unbalanced `(`, is re-emitted verbatim.
define .awk.cmk.lower
function lower_calls(text,   result, pos, hit, name, lit, astart, args, paren, c, p, kp, klen, blen, bname, bpos) {
	result = ""; pos = 1
	while (pos <= length(text)) {
		if (TRIG_MODE == "prefix") {
			hit = index(substr(text, pos), TRIG_PREFIX)
			if (hit == 0) { result = result substr(text, pos); break }
			result = result substr(text, pos, hit - 1)
			pos = pos + hit - 1 + length(TRIG_PREFIX)
			lit = TRIG_PREFIX; name = ""
			while (pos <= length(text) && substr(text, pos, 1) ~ /[A-Za-z0-9._-]/) { name = name substr(text, pos, 1); pos++ }
			if (substr(text, pos, 1) != "(") { result = result lit name; continue } }
		else {
			bpos = 0
			for (p = pos; p <= length(text) && bpos == 0; p++) {
				blen = 0
				for (kp in NAMESET) { klen = length(kp); if (substr(text, p, klen) == kp && substr(text, p+klen, 1) == "(" && klen > blen) { blen = klen; bname = kp } }
				if (blen > 0) { bpos = p } }
			if (bpos == 0) { result = result substr(text, pos); break }
			result = result substr(text, pos, bpos - pos)
			pos = bpos + length(bname); lit = ""; name = bname }
		if (pos > length(text)) { result = result lit name; break }
		pos++
		astart = pos; paren = 1
		while (pos <= length(text) && paren > 0) { c = substr(text, pos, 1); if (c == "(") paren++; else if (c == ")") paren--; pos++ }
		if (paren > 0) { result = result lit name "(" substr(text, astart); break }
		args = substr(text, astart, pos - astart - 1)
		result = result "$(call " name "," lower_calls(args) ")" }
	return result }
endef

# Stage: import-name sugar -- lower the fixed set of import shorthands `NAME(args)` ->
# `$(call NAME,args)` (balanced + recursive via lower_calls).  Inert in define..endef.
define .awk.cmk.imports
BEGIN { TRIG_MODE = "names"
	NAMESET["compose.import"]; NAMESET["compose.import.string"]; NAMESET["compose.import.script"]
	NAMESET["compose.import.code"]; NAMESET["polyglot.import"]; NAMESET["polyglots.import"]
	NAMESET["polyglot.import.file"]; NAMESET["import.def"]; NAMESET["import.target"]
	NAMESET["import.defs"]; NAMESET["import.targets"] }
{ print lower_calls($0) }
endef
# Stage: generic macro-call sugar -- lower `cmk.NAME(args)` -> `$(call NAME,args)`.  The
# macro anchor is the dialect sentinel `؆` (dialect rewrites `cmk.`->`؆`); the late
# .awk.cmk.unsentinel restores any leftover `؆`.
define .awk.cmk.call
BEGIN { TRIG_MODE = "prefix"; TRIG_PREFIX = "؆" }
{ print lower_calls($0) }
endef
# Stage: restore the macro-anchor sentinel -- map any `؆` that survived call-lowering
# back to `cmk.` (it was `cmk.` content, not a call).  Blanket gsub; runs LAST.
define .awk.cmk.unsentinel
{ gsub(/؆/, "cmk."); print }
endef
# Stage: anchorless receiver sends.  A name `R` declared a receiver (passed via
# -v RECEIVERS) needs no `this.`/`cmk.` anchor: `R.method(args)`, `R.method[stream]`,
# `R.method/arg`, and adjacent `R.method'''lit'''` get a `${make} ` anchor injected
# (later lowered by tagged/callform).  Fires only at a word boundary, only when a call-
# suffix follows the method path, and only in recipe content (never a target spec);
# skips a token already `${make} `-anchored.  Inert without receivers / in define..endef.
# `rc_name` -- char is part of a name?  `rc_delim3` -- string is a triple-delimiter?
# `rc_scan` -- inject anchors across one segment.
# FLAG: refactor candidate -- word-boundary + receiver-match + suffix-detect + recipe/
# target discrimination all in one scan.
define .awk.cmk.receivers
function rc_name(c) { return (c ~ /[A-Za-z0-9._-]/) }
function rc_delim3(s) { return (s == "'''" || s == "\"\"\"" || s == "```") }
function rc_scan(seg,   out, i, L, hit, prev, blen, r, rl, m, suf) {
	out = ""; i = 1; L = length(seg)
	while (i <= L) {
		hit = 0; prev = (i == 1) ? "" : substr(seg, i-1, 1)
		if (!rc_name(prev) && prev != "؆") {
			blen = 0
			for (r in RSET) { rl = length(r); if (substr(seg, i, rl) == r && substr(seg, i+rl, 1) == "." && rl > blen) blen = rl }
			if (blen > 0) {
				m = i + blen
				while (m <= L && rc_name(substr(seg, m, 1))) m++
				suf = substr(seg, m, 1)
				if (suf == "(" || suf == "[" || suf == "/" || rc_delim3(substr(seg, m, 3))) {
					if (!(i > 8 && substr(seg, i-8, 8) == "${make} ")) {
						out = out "${make} " substr(seg, i, m - i); i = m; hit = 1 } } } }
		if (!hit) { out = out substr(seg, i, 1); i++ }
	}
	return out }
BEGIN { _rn = split(RECEIVERS, _ra, " "); RCOUNT = 0
	for (_ri = 1; _ri <= _rn; _ri++) if (_ra[_ri] != "") { RSET[_ra[_ri]] = 1; RCOUNT++ } }
{
	if (RCOUNT == 0) { print; next }
	line = $0
	if (line ~ /^[ \t]/) { print rc_scan(line); next }
	sc = index(line, ";")
	if (sc == 0) { print line; next }
	print substr(line, 1, sc) rc_scan(substr(line, sc+1))
}
endef
# Stage: the `⇐` assignment operator -- `LHS ⇐ RHS` -> ``LHS=`RHS` ``, capturing RHS to
# the nearest shell separator (`;` `&&` `||`) or trailing `\` (several per line).  Runs
# after the call stage; inert in define..endef.  `assign` -- rewrite one line's `⇐`s.
define .awk.cmk.assign
function assign(s,   out, cont, p, rest, ce, k, i, term) {
	out = ""; cont = ""
	if (s ~ /[ \t]*\\$/) { sub(/[ \t]*\\$/, "", s); cont = " \\" }
	term[1]=";"; term[2]="&&"; term[3]="||"
	while ((p = index(s, " ⇐ ")) > 0) {
		out = out substr(s, 1, p-1) "=`"
		rest = substr(s, p + length(" ⇐ "))
		ce = length(rest) + 1
		for (i = 1; i <= 3; i++) { k = index(rest, term[i]); if (k > 0 && k < ce) ce = k }
		out = out substr(rest, 1, ce-1) "`"
		s = substr(rest, ce) }
	return out s cont }
{ line = $0; if (index(line, " ⇐ ")) line = assign(line); print line }
endef

# CMK tagged callable-target sugar: `${make} NAME'''LIT'''` -> `'''LIT''' | ${make} NAME` (the
# triple-delimiter ADJACENT to NAME, no parens/brackets).  Target-only (macros use `[stream]`).
# Runs BEFORE callform (so callform's target branch then sees a bare `${make} NAME`).  Reuses
# is_delim/parse_literal (litparse).  Skips `.dispatch`.  Inert in define..endef.
define .awk.tagged
{
	START_NR = NR; START_SRC = $0
	line = $0; out = ""; i = 1; L = length(line); MK = "${make} "
	while (i <= L) {
		p = index(substr(line, i), MK)
		if (p == 0) { out = out substr(line, i); break }
		abs = i + p - 1
		out = out substr(line, i, p - 1)
		npos = abs + length(MK); name = ""
		while (npos <= L) { ch = substr(line, npos, 1); if (ch ~ /[A-Za-z0-9._\/-]/) { name = name ch; npos++ } else break }
		if (name == "") { out = out MK; i = abs + length(MK); continue }
		if (name ~ /\.dispatch$/) { out = out MK name; i = npos; continue }
		if (is_delim(substr(line, npos, 3))) {
			parse_literal(substr(line, npos), "tagged")
			out = out LIT_ " | " MK name
			line = REM_; L = length(line); i = 1; continue }
		out = out MK name; i = npos }
	print out
}
endef

# CMK unified "call-form" sugar -- ONE stage for both call anchors: the macro anchor
# `cmk.` and the target anchor `${make} ` (post-dialect `this.`).  `NAME(args)` supplies
# args, `NAME[stream]` supplies stdin (combinable in either order); a stream may be a
# triple-quote literal, a balanced `[...]` command (which may nest call-forms), or a
# block-ref glyph.  Bare `NAME` (no `(`/`[`) is left verbatim.  Errors (cmk_die_at) on
# unterminated literal/bracket/paren or mixed content after a literal.  Runs after
# dialect+tagged, before blockref+triplequote; inert in define..endef.  The full
# transform table and nesting examples live in tests/test_callform_cmk.py.
# `extract_balanced` -- capture balanced `[...]`/`(...)` content.  `eat_parens` -- parse a
# leading `(args)` group.  `parse_body` -- parse a `[stream]` body, recursing through
# `lower` for nested call-forms.  `build_call` -- emit the lowered call.  `lower` --
# re-entrant scan of one record, lowering each call-form found.
# FLAG: refactor candidate -- highest-complexity block (dual-anchor parse + stream parse
# + recursion + shared-buffer save/restore); consider splitting per-anchor.
define .awk.callform
function extract_balanced(bp, oc, cc, what,   depth, k, c) {
	depth = 1; k = bp
	while (k <= L && depth > 0) { c = substr(line, k, 1); if (c == oc) depth++; else if (c == cc) depth--; if (depth == 0) break; k++ }
	if (depth != 0) cmk_die_at("callform", "unterminated " what "; unquoted is single-line, use triple-quotes for multi-line", START_NR, START_SRC)
	EB_ = substr(line, bp, k - bp); EB_REM = k + 1 }
function eat_parens(s,   depth, q, ch) {
	PAREN_ = ""; PREM_ = s; HAVE_P = 0
	if (substr(s, 1, 1) != "(") return
	depth = 1; q = 2
	while (q <= length(s) && depth > 0) { ch = substr(s, q, 1); if (ch == "(") depth++; else if (ch == ")") depth--; if (depth == 0) break; q++ }
	if (depth != 0) cmk_die_at("callform", "unterminated (args)", START_NR, START_SRC)
	PAREN_ = substr(s, 2, q - 2); PREM_ = substr(s, q + 1); HAVE_P = 1 }
function parse_body(bp,   j, m, t, b, srem, sline, sL, srec) {
	j = bp
	while (j <= L && (substr(line, j, 1) == " " || substr(line, j, 1) == "\t")) j++
	if (is_delim(substr(line, j, 3))) {
		parse_literal(substr(line, j), "callform")
		t = REM_
		while (1) {
			m = 1; while (m <= length(t) && (substr(t,m,1)==" "||substr(t,m,1)=="\t")) m++
			if (m <= length(t)) {
				if (substr(t,m,1) != "]") cmk_die_at("callform", "expected ']' after the literal (mixed content not supported)", START_NR, START_SRC)
				BODY_ = LIT_; BREM_ = substr(t, m+1); return }
			if (RECURSING || (getline t) <= 0) cmk_die_at("callform", "unterminated [stream]; no closing ']'", START_NR, START_SRC) } }
	extract_balanced(bp, "[", "]", "[stream]")
	b = EB_; srem = EB_REM; sub(/^[ \t]+/, "", b); sub(/[ \t]+$/, "", b)
	if (substr(b,1,length(FD))==FD || substr(b,1,length(FILE))==FILE) b = "cat " b
	else { sline = line; sL = L; srec = RECURSING; RECURSING = 1; b = lower(b); RECURSING = srec; line = sline; L = sL }
	BODY_ = b; BREM_ = substr(line, srem) }
function build_call(type, name, args, hadp,   a) {
	if (type == "macro") { if (!hadp) return "$(call " name ")"; return MAC name "(" args ")" }
	if (!hadp) return MK name
	a = args; gsub(/[ \t]+/, "", a); return MK name "/" a }
function lower(rec,   out, i, pm, pt, type, alen, p, abs, npos, name, cc, ch, nxt, hadp, args) {
	line = rec; out = ""; i = 1; L = length(line); MK = "${make} "; MAC = "؆"; FD = "⬦"; FILE = "⬥"
	while (i <= L) {
		pm = index(substr(line, i), MAC); pt = index(substr(line, i), MK)
		if (pm == 0 && pt == 0) { out = out substr(line, i); break }
		if (pt != 0 && (pm == 0 || pt < pm)) { type = "target"; alen = length(MK); p = pt }
		else { type = "macro"; alen = length(MAC); p = pm }
		abs = i + p - 1
		out = out substr(line, i, p - 1)
		npos = abs + alen; name = ""
		if (type == "target") cc = "[A-Za-z0-9._/-]"; else cc = "[A-Za-z0-9._-]"
		while (npos <= L) { ch = substr(line, npos, 1); if (ch ~ cc) { name = name ch; npos++ } else break }
		if (name == "") { out = out substr(line, abs, alen); i = npos; continue }
		if (type == "target" && name ~ /\.dispatch$/) { out = out MK name; i = npos; continue }
		hadp = 0; args = ""; nxt = substr(line, npos, 1)
		if (nxt == "(") {
			eat_parens(substr(line, npos))
			if (substr(PREM_, 1, 1) != "[") { out = out build_call(type, name, PAREN_, 1); line = PREM_; L = length(line); i = 1; continue }
			args = PAREN_; hadp = 1; line = PREM_; L = length(line); npos = 1
			parse_body(npos + 1) }
		else if (nxt == "[") {
			parse_body(npos + 1)
			eat_parens(BREM_)
			if (HAVE_P) { args = PAREN_; hadp = 1; BREM_ = PREM_ } }
		else { out = out substr(line, abs, npos - abs); i = npos; continue }
		out = out BODY_ " | " build_call(type, name, args, hadp)
		line = BREM_; L = length(line); i = 1 }
	return out
}
{ START_NR = NR; START_SRC = $0; print lower($0) }
endef


# Compile-stage def-blocks captured literally (via `$(value)`, like mk.def.read)
# and exported so the `.cmk.*` stage macros can read them straight from the
# environment, with no per-block `mk.def.read` sub-make and no temp files. `:=` here
# (after all the define blocks above) freezes the unexpanded body; export ships it
# verbatim. `awk "$_zip"`/`printf '%s' "$_dialect_dict"|jq` consume them in-shell.
export _cmk_blk_zip := $(value .awk.zip.linefeeds)
export _cmk_blk_module_ns := $(value .awk.module.namespace)
export _cmk_blk_select_def := $(value .awk.select.def)
export _cmk_blk_target_extract := $(value .awk.target.extract)
# Stages that can raise parser errors prepend the shared `.awk.cmk.errors` prelude
# (cmk_die/cmk_die_at), separated by a literal newline (${nl}).
export _cmk_blk_indent := $(value .awk.cmk.errors)${nl}$(value .awk.cmk.indent)
export _cmk_blk_dec := $(value .awk.cmk.errors)${nl}$(value .awk.decorators)
export _cmk_blk_tagged := $(value .awk.cmk.errors)${nl}$(value .awk.cmk.defskip)${nl}$(value .awk.cmk.litparse)${nl}$(value .awk.tagged)
export _cmk_blk_callform := $(value .awk.cmk.errors)${nl}$(value .awk.cmk.defskip)${nl}$(value .awk.cmk.litparse)${nl}$(value .awk.callform)
export _cmk_blk_dialect := $(value cmk.default.dialect)
export _cmk_blk_sugar := $(value cmk.default.sugar)
export _cmk_blk_sugarawk := $(value .awk.sugar)
export _cmk_blk_imports := $(value .awk.cmk.defskip)${nl}$(value .awk.cmk.lower)${nl}$(value .awk.cmk.imports)
export _cmk_blk_call := $(value .awk.cmk.defskip)${nl}$(value .awk.cmk.lower)${nl}$(value .awk.cmk.call)
export _cmk_blk_unsentinel := $(value .awk.cmk.unsentinel)
export _cmk_blk_receivers := $(value .awk.cmk.errors)${nl}$(value .awk.cmk.defskip)${nl}$(value .awk.cmk.receivers)
export _cmk_blk_assign := $(value .awk.cmk.defskip)${nl}$(value .awk.cmk.assign)
export _cmk_blk_dispatch := $(value .awk.dispatch)
export _cmk_blk_triplequote := $(value .awk.cmk.defskip)${nl}$(value .awk.triplequote)
export _cmk_blk_blockref := $(value .awk.cmk.defskip)${nl}$(value .awk.blockref)
export _cmk_blk_joinbody := $(value .awk.joinbody)
export _cmk_blk_docstring := $(value .awk.docstring)

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

# Rewrite CLI goals to add pre/post hooks: a plain target `T` becomes
# `flux.pre/T T flux.post/T`.  Whole-line bypass for special invocations
# (help/jq/jb/yq/cmk/include/loadf, mk.interpret/compile/preprocess); per-field
# bypass for `.`-prefixed and path-like (`/`) tokens.
define .awk.rewrite.targets.maybe
{ if ($0 ~ /help/ || $0 ~ /jb/ || $0 ~ /yq/ || $0 ~ /jq/ || $0 ~ /include/ || $0 ~ /loadf/ || $0 ~ /cmk/) {
    print $0; next }
  if ($0 ~ /mk.interpret/ || $0 ~ /mk.compile/ || $0 ~ /mk.preprocess/) { print $0; next }
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
	&& fdata="`cat $${fname}`" \
	&& $(call log.mk, mk.fork.section ${sep} ${dim}section=${dim_cyan}$${section} ${sep} ${dim}loading ${bold}$${fname}) \
	&& [ -z "$${shebang:-}" ] \
		&& true || printf "$${shebang}\n" \
	&& cat ${CMK_BIN} \
		| TARGET_SECTION=$${section} \
		PREFIX='$(shell echo "$${PREFIX:-}")' \
		POSTFIX="$${POSTFIX:-}" POSTHOOK=$${POSTHOOK:-} \
		GUEST_DATA="$${fdata}" \
			CMK_INTERNAL=1 ${make} io.awk/.awk.fork.section
# Replace a guest/payload section in a forked compose.mk: between the
# `# 𒄡 BEGIN <TARGET_SECTION>` / `END` markers, drop the old body and inject
# PREFIX + GUEST_DATA + POSTFIX + POSTHOOK (from ENVIRON); pass other lines through.
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