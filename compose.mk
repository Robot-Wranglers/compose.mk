#!/usr/bin/env bash
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
# executable as both a bash script and a Makefile.  This allows working around
# the poor signal-handling that Make supports by default, plus several other
# advanced features such as short-circuiting `make` from attempting to parse
# the full CLI, and "pre" / "post" targets.  See documentation and usage info
# at https://github.com/robot-wranglers/compose.mk/signals/, especially
# re: `mk.interrupt` and `mk.yield`.
#
#/* \
_make_="make -sS --warn-undefined-variables -f ${0}"; export MAKEFLAGS="${MAKEFLAGS:+${MAKEFLAGS} }--no-print-directory"; trace="${TRACE:-${trace:-0}}"; \
export CMK_TWIN_PATH=""; \
case "${CMK_TWIN:-1}" in 0|off|false|no) :;; *) \
	_twin_dir="${XDG_CACHE_HOME:-$HOME/.cache}/compose.mk/twin"; \
	_twin_id=$(cksum "${0}" 2>/dev/null | awk '{print $1"-"$2}'); \
	_twin_="${_twin_dir}/${_twin_id}.${0##*/}"; \
	if [ -n "${_twin_id}" ] && [ ! -s "${_twin_}" ]; then mkdir -p "${_twin_dir}" 2>/dev/null && awk '/^define /{d++} d&&/^endef[ \t]*$/{d--} { if(!d && !p && $0 ~ /^\t[ \t]*@?#/) print ""; else print; p=($0 ~ /\\[ \t]*$/) }' "${0}" > "${_twin_}.$$" 2>/dev/null && mv "${_twin_}.$$" "${_twin_}" 2>/dev/null; fi; \
	if [ -s "${_twin_}" ]; then _make_="make -sS --warn-undefined-variables -f ${_twin_}"; export CMK_TWIN_PATH="${_twin_}"; export MAKEFILE="${0}"; fi; ;; \
esac; \
no_ansi="\033[0m"; green="\033[92m"; dim="\033[2m"; yellow="\033[93m"; bold="\033[1m"; sep="${no_ansi}//${dim}";\
export CMK_BIN=${0}; export __file__=${0}; export __cmk__=${0}; \
_cmk_bootloader_log() { printf '%b\n' "${yellow}${bold}⚠${no_ansi}${dim}${yellow} $*${no_ansi}" >&2; }; \
_cmk_awk() { sed -n "/^define $1/,/^endef/{/^define/d;/^endef/d;p;}" ${0}; }; \
_cmk_load() { source <(_cmk_awk "$1"); }; \
_cmk_reap() { command -v docker >/dev/null 2>&1 || return 0; _cmk_ids=$(docker ps -aq --filter label=cmk.run="${MAKE_SUPER:-${CMK_RUN_ID:-none}}-${CMK_REAP_SALT:-0}" 2>/dev/null); [ -n "${_cmk_ids:-}" ] && docker rm -f ${_cmk_ids} >/dev/null 2>&1; return 0; }; \
for _d in make awk sed; do command -v "$_d" >/dev/null 2>&1 || _cmk_miss="${_cmk_miss:+$_cmk_miss }$_d"; done; \
[ -z "${_cmk_miss:-}" ] || { _cmk_bootloader_log "compose.mk: missing required tool(s) on PATH: $_cmk_miss\n  compose.mk needs bash + make + awk + sed. Install them, e.g.:\n    alpine: apk add make gawk sed   (gawk -- the compiler needs GNU awk, not busybox awk)\n    nixos:  nix-shell -p gnumake gawk gnused"; exit 127; }; \
export CMK_RUN_ID="${CMK_RUN_ID:-$$}"; \
export CMK_REAP_SALT="$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' \n')"; CMK_REAP_SALT="${CMK_REAP_SALT:-$$}"; \
case ${CMK_SUPERVISOR:-1} in \
	0) ([ "${trace}" == 0 ] || \
		printf "ᐂ ${sep}Skipping setup for signal handlers..\n${no_ansi}">/dev/stderr); \
		trap "_cmk_reap" EXIT; trap "exit 143" SIGTERM; \
		${_make_} ${@}; __exit_code__=$?; ;; \
	1) ([ "${trace}" == 0 ] || \
		printf "ᐂ ${sep} Installing supervisor..\n\033[0m" > /dev/stderr); \
		export MAKE_SUPER=$(exec sh -c 'echo "$PPID"'); \
		[ "${trace}" == 1 ] && set -x || true;  \
		trap "_cmk_reap; CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} mk.super.trap/SIGINT; " SIGINT; \
		trap "_cmk_reap" EXIT; \
		trap '' PIPE; \
		case ${CMK_DISABLE_HOOKS:-0} in \
			0) [ $# -eq 0 ] \
				&& __argv__="mk.__main__" \
				|| __argv__="$(echo ${@} | awk -f <(_cmk_awk .awk.rewrite.targets.maybe))";; \
			1) __argv__="${@:-mk.__main__}";; \
		esac; \
		if [ -n "${CMK_BOOTLOADER_DISABLED}" ]; then printf "ᐂ ${sep} \033[93mbootloader disabled (CMK_BOOTLOADER_DISABLED) -- running targets directly\n${no_ansi}" >/dev/stderr; ${_make_} ${__argv__}; __exit_code__=$?; else _cmk_load _mk.super.bootloader; fi; ;; \
esac \
; exit ${__exit_code__}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: constants :: Colors, glyphs, and Makefile boilerplate
##
## Ends the supervisor / signals boilerplate above and starts make-side setup.
## The invocation hints declared here:
##
## * MAKE :: Prefer `make` instead as an expansion for recursive calls
## * MAKEFILE :: The path to the Makefile being used at the top-level
## * MAKE_CLI :: A complete CLI invocation for this process (reliable on Linux, partial on macOS)
## * MAKEFILE_LIST :: Prefer `makefile_list`, derived from MAKE_CLI.
##     The list of includes, from 'include ..' or given at the CLI with '-f ..'
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
SHELL:=bash
# Version floor, checked at parse time in syntax every old make accepts; it must sit above the first modern construct or users see a bare missing-separator error instead of this.
ifeq ($(filter-out 3.% 4.0 4.0.% 4.1 4.1.%,$(MAKE_VERSION)),)
$(error compose.mk needs GNU make >= 4.2 but this is $(MAKE_VERSION). Stock macOS ships 3.81 forever; install a modern make (macOS: brew install make, then put the gnubin dir first on PATH or invoke gmake; debian/ubuntu: apt install make; alpine: apk add make))
endif
# --no-print-directory neutralizes an inherited `-w`/print-directory (env or outer make): those
# `Entering/Leaving directory` lines are noise and corrupt the block-fed `awk -f <(..)` process-subs
# (io.awk) by prepending to the awk program.  Kept in MAKEFLAGS (auto-exported, so sub-makes inherit the
# suppression) but stripped from MAKE_FLAGS below, so it never lands on a recursive `make` command line:
# MAKE_CLI is captured from the cmdline and the subcommands parser reads it, so a stray flag there would
# corrupt subcommand resolution.  The bash-trampoline appends it to the env MAKEFLAGS for the same reason.
MAKEFLAGS:=-s -S --warn-undefined-variables --no-builtin-rules --no-print-directory
.SUFFIXES:
# Mark staged/remade makefiles + flux markers intermediate.  Scoped to `.tmp.*.mk`, not
# bare `.tmp.*`: make wildcard-expands these prereqs at every (recursive) parse, so a bare
# glob would hold every leaked `mktemp ./.tmp.XXXX` scratch file -- make memory then grows
# with scratch count.  Only `.mk`-suffixed `.tmp.*` (hosted/module caches) are make targets.
.INTERMEDIATE: .tmp.*.mk .flux.*
export TERM?=xterm-256color
# Host-invariant probes, resolved once: `:=` + `$(or $(value VAR),...)` freezes the value so the
# `$(shell)` runs a single time (a recursive exported `?=` would re-run in every parse-time shell
# under GNU make 4.4+, a ~40x slowdown), while honoring any value already set in the env or on the
# CLI. `$(value VAR)` (not `$(VAR)`) reads a preset without tripping --warn-undefined-variables when
# unset. The XDG cache holds compose.mk's built host artifacts; override CMK_XDG_CACHE to relocate.
export OS_NAME := $(or $(value OS_NAME),$(shell uname -s))
# OS_MACOS: non-empty on macOS (Darwin); test with 'ifdef OS_MACOS'.
OS_MACOS := $(filter Darwin,${OS_NAME})
export CMK_XDG_CACHE := $(or $(value CMK_XDG_CACHE),$(shell echo "$${XDG_CACHE_HOME:-$${HOME}/.cache}")/compose.mk)
# Put compose.mk's XDG bin first on PATH so host tools it installs there (e.g. `jb.init` -> json.bash) are
# found ahead of any dockerized fallback.  Guarded so recursive sub-makes (which inherit the exported PATH)
# don't keep re-prepending it as MAKELEVEL grows.
ifeq ($(findstring ${CMK_XDG_CACHE}/bin:,${PATH}),)
export PATH := ${CMK_XDG_CACHE}/bin:${PATH}
endif

# m5.declare: batch off-col0 assignments; each comma-arg is a full make assignment (= ?= := += ), whitespace/newlines trimmed. Hoisted here for the color block, its first consumer.
m5.declare.slots := 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32
m5.declare = $(foreach _n,$(m5.declare.slots),$(eval $(strip $(if $(filter undefined,$(origin $(_n))),,$($(_n))))))
# m5.declare!: like m5.declare but exports each var; empty slots are skipped so a bare export never flips on export-all.
m5.declare! = $(foreach _n,$(m5.declare.slots),$(if $(strip $(if $(filter undefined,$(origin $(_n))),,$($(_n)))),$(eval export $(strip $($(_n))))))

# Pre-declared (?= empty) so native `$(VAR)` reads are safe under
# --warn-undefined-variables, which lets us replace per-parse
# `$(shell echo $${VAR:-default})` subshell forks with native `$(or $(VAR),default)`.
$(call m5.declare, quiet ?=, trace ?=, NO_COLOR ?=)
# NB: CMK_DIND is declared+exported later (`export CMK_DIND?=0`); do not
# pre-declare it here, since that would make the later `?=` skip and leave CMK_DIND
# empty+unexported, breaking docker-in-docker propagation.

# Color constants and other stuff for formatting user-messages
ifeq ($(NO_COLOR),1) # https://no-color.org/
$(call m5.declare, no_ansi=, green=, yellow=, dim=, underline=, bold=, ital=, no_color=, red=, cyan=)
else
$(call m5.declare, \
	no_ansi = \033[0m, green = \033[92m, yellow = \033[33m, blue = \033[38;5;27m, \
	dim = \033[2m, underline = \033[4m, bold = \033[1m, ital = \033[3m, \
	no_color = \e[39m, red = \033[91m, cyan = \033[96m)
endif
$(call m5.declare, \
	dim_red = ${dim}${red}, dim_yellow = ${dim}${yellow}, bold_red = ${bold}${red}, \
	bold_yellow = ${bold}${yellow}, dim_cyan = ${dim}${cyan}, bold_cyan = ${bold}${cyan}, \
	bold_green = ${bold}${green}, bold.underline = ${bold}${underline}, dim_green = ${dim}${green}, \
	dim_ital = ${dim}${ital}, dim_ital_cyan = ${dim}${ital}${cyan}, no_ansi_dim = ${no_ansi}${dim})
cyan_flow_left=${bold_cyan}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
cyan_flow_right=${no_ansi_dim}⋙${dim}${cyan}⋙${no_ansi}${bold_cyan}⋙${no_ansi} 
green_flow_left=${bold_green}⋘${dim}⋘${no_ansi_dim}⋘${no_ansi}
green_flow_right=${no_ansi_dim}⋙${dim_green}⋙${no_ansi}${green}⋙${bold_green}⋙ 
sep=${no_ansi}//

# Glyphs used in log messages 📢 🤐; _GLYPH_* are the raw marks, GLYPH_* the colorized wrappers for the loggers (warn=yellow, error=red, lang_off=∅ marks a hosted-bypass line).
$(call m5.declare, \
	_GLYPH_COMPOSE = ${bold}≣${no_ansi}, _GLYPH.DOCKER = ${bold}≣${no_ansi}, \
	_GLYPH_MK = ${bold}✱${no_ansi}, _GLYPH_IO = ${bold}⇄${no_ansi}, \
	_GLYPH_TUI = ${bold}⏣${no_ansi}, _GLYPH_FLUX = ${bold}Φ${no_ansi}, \
	_GLYPH_WARN = ${bold}⚠${no_ansi}, _GLYPH_ERROR = ${bold}🛇${no_ansi}, _GLYPH_LANG_OFF = ∅)
$(call m5.declare, \
	GLYPH_COMPOSE = ${green}${_GLYPH_COMPOSE}${dim_green}, GLYPH.DOCKER = ${green}${_GLYPH.DOCKER}${dim_green}, \
	GLYPH_MK = ${green}${_GLYPH_MK}${dim_green}, GLYPH_IO = ${green}${_GLYPH_IO}${dim_green}, \
	GLYPH_TUI = ${green}${_GLYPH_TUI}${dim_green}, GLYPH_FLUX = ${green}${_GLYPH_FLUX}${dim_green}, \
	GLYPH_WARN = ${yellow}${_GLYPH_WARN}${dim_yellow}, GLYPH_ERROR = ${red}${_GLYPH_ERROR}${dim_red}, \
	GLYPH_LANG_OFF = ${yellow}${_GLYPH_LANG_OFF}${no_ansi_dim})
GLYPH_DEBUG=${dim}(debug=${no_ansi}${verbose}${dim})${no_ansi}${dim}(quiet=${no_ansi}$(quiet)${dim})${no_ansi}${dim}(trace=${no_ansi}$(trace)${dim})
$(call m5.declare, GLYPH_SPARKLE=✨, GLYPH_CHECK=✔, GLYPH_XXX=${red}✗, GLYPH_SUPER=${green}ᐂ${dim_green})
GLYPH_NUMS=① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩
# NB: native `${1}+1` without a subshell.  `$(words $(wordlist 1,N,LIST) +)` counts
# the first N words plus one extra token, i.e. N+1 (and N=0 -> empty wordlist -> 1).
# Reusing the glyph list as the counting source matches the old subshell arithmetic
# byte-for-byte, including out-of-range (-> empty `$(word)`). Hot path: every log line.
GLYPH.NUM=${dim_green}$(word $(words $(wordlist 1,${1},${GLYPH_NUMS}) +),${GLYPH_NUMS})${no_ansi}
# GLYPH_ARRS=🡨 🡩 🡪 🡫 🡬 🡭 🡮 🡯 🡒 🡑
GLYPH_ARRS=▋ ▊ ▉ █ █ █ █ █ ▏ ▎ ▍
GLYPH.ARRS=${dim_green}$(word $(words $(wordlist 1,${1},${GLYPH_ARRS}) +),${GLYPH_ARRS})${no_ansi}
$(call m5.declare, GLYPH.tree_item := ├─, GLYPH.tree_last := ╰─)

# Literal newline and other constants
# See also: https://www.gnu.org/software/make/manual/html_node/Syntax-of-Functions.html#Special-Characters
empty:=
space:= $(empty) $(empty)
define nl


endef
comma=,

# FIXME: docs 
# NB: keep this RECURSIVE (`?=`), unlike the OS_NAME/DOCKER_UID/DOCKER_GID probes:
# it is load-bearing for DIND / container-dispatch path resolution, and freezing it to
# the parse-time pwd (`:=`) mangles the in-container `-f`. It also does not hit the
# make-4.4 $(shell) blowup in practice (set/inherited before the parse-time storm).
_dhw.origin:=$(origin DOCKER_HOST_WORKSPACE)
export DOCKER_HOST_WORKSPACE?=$(shell pwd)
# freeze to simple: make 4.4 re-expands exported recursive vars per child, ~330 pwd spawns per bare-host run
export DOCKER_HOST_WORKSPACE:=$(DOCKER_HOST_WORKSPACE)
# a pwd-derived default stays process-local: exporting it would masquerade as a deliberate override for any descendant with a different cwd, and the dind crossing rides docker.env.standard instead
ifeq (undefined,$(_dhw.origin))
unexport DOCKER_HOST_WORKSPACE
endif

ifdef OS_MACOS
$(call m5.declare!, DOCKER_UID:=0, DOCKER_GID:=0, DOCKER_UGNAME:=root)
export MAKE_CLI:=$(shell echo `which make` `ps -o args -p $${PPID} | tail -1 | cut -d' ' -f2-` | { [ -z "$${CMK_TWIN_PATH:-}" ] && cat || sed "s|$${CMK_TWIN_PATH}|$${CMK_BIN:-$${CMK_TWIN_PATH}}|g"; })
else
$(call m5.declare!, \
	DOCKER_UID := $(or $(value DOCKER_UID),$(shell id -u)), \
	DOCKER_GID := $(or $(value DOCKER_GID),$(shell getent group docker 2> /dev/null | cut -d: -f3 || id -g)), \
	DOCKER_UGNAME := user)
export MAKE_CLI:=$(shell \
	( cat /proc/$${PPID}/cmdline 2>/dev/null \
		| tr '\0' ' ' \
		| { [ -z "$${CMK_TWIN_PATH:-}" ] && cat || sed "s|$${CMK_TWIN_PATH}|$${CMK_BIN:-$${CMK_TWIN_PATH}}|g"; } ) ||echo '?')
endif

# pure-make split, replacing the old awk spawn: mark spaces, break on the marked double-dash separator, unmark field two.
export MAKE_CLI_EXTRA:=$(subst §, ,$(word 2,$(subst §--§, ,$(subst ${space},§,${MAKE_CLI}))))
export MAKEFILE_LIST:=$(call strip,${MAKEFILE_LIST})
# MAKE_FLAGS feeds recursive `make` command lines (and thus MAKE_CLI), so strip the
# env-only `--no-print-directory` here -- it stays in MAKEFLAGS (inherited) for suppression.
export MAKE_FLAGS:=$(shell ( [ `echo ${MAKEFLAGS} | cut -c1` = - ] && echo "${MAKEFLAGS}" || echo "-${MAKEFLAGS}" ) | sed 's/--no-print-directory//g; s/  */ /g; s/ *$$//')
# per-process temp-file token, one probe per parse (the probe shell's parent is this make).
_cmk.pid := $(shell echo $$PPID)
export MAKEFILE?=$(firstword $(MAKEFILE_LIST))
export TRACE?=$(or $(trace),0)
# Returns everything on the CLI *after* the current target.
# WARNING: do not refactor as VAR=val !
define mk.cli.continuation
$${MAKE_CLI#*${@}}
endef

# This is the canonical safe way to call `make` recursively.
# It determines better-than-default values for MAKE and MAKEFILE_LIST,
# and uses the lowercase.  Defaults are not reliable!
# pure-make scan of MAKE_CLI for -f arguments, frozen at parse; dollars ride through the recursion as ¤ so argv text is never re-expanded.
_mk.cli.fscan=$(if $(strip $(1)),$(if $(filter -f,$(firstword $(1))),$(word 2,$(1)) $(call _mk.cli.fscan,$(wordlist 3,$(words $(1)),$(1))),$(patsubst -f%,%,$(filter -f%,$(firstword $(1)))) $(call _mk.cli.fscan,$(wordlist 2,$(words $(1)),$(1)))))
makefile_list:=$(addprefix -f,$(strip $(subst ¤,$$,$(call _mk.cli.fscan,$(subst $$,¤,$(value MAKE_CLI))))))
CMK_TWIN_PATH ?=
CMK_BIN ?=
# The twin.map and twin.unmap helpers swap the docstring-blanked execution twin for its source file (and back) in path lists; identity surfaces unmap, spawn sites map.
twin.map = $(if $(CMK_TWIN_PATH),$(subst $(CMK_BIN),$(CMK_TWIN_PATH),$(1)),$(1))
twin.unmap = $(if $(CMK_TWIN_PATH),$(subst $(CMK_TWIN_PATH),$(CMK_BIN),$(1)),$(1))
make=make ${MAKE_FLAGS} $(call twin.map,${makefile_list})

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: SelfPath :: Where is compose.mk? One var per context
##
## Several vars answer this, each for a different context (they are not
## redundant).  The last few bridge the host / dispatch-container boundary,
## where a host path is meaningless inside the container.
##
## | name            | what it answers                   |
## |-----------------|-----------------------------------|
## | cmk.self        | host abspath; the source of truth |
## | CMK_SRC         | source to read/include, this proc |
## | CMK_BIN         | invocation path ($0)              |
## | CMK_ARGV0       | name to show the user in help     |
## | CMK_DOCKER_PATH | where it's mounted in-container   |
## | CMK_DIND_SRC    | include path: host and container  |
##
## Derived host / container helpers (detailed below): docker.cmk.mount (the `-v`
## bind), makefile_list.dind / make.dind (the host `-f` rewritten to the mount).
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# The SelfPath family (each var mapped by the table above) answers "where is compose.mk?" for a
# different context. All are recursive (`=`) so paths resolve freshly at each use. The container mount
# vars expand empty when compose.mk already lives in the workspace, leaving vendored dispatch unchanged;
# one instead binds the host-built cache in so the container reuses it. A shared probe computes the
# source path, workspace, and relative form; its escaped comment char stops make truncating the value.
# Compiled-program runs carry no compose.mk in their makefile list; the inherited interpreter path fills in.
cmk.self = $(abspath $(or $(call twin.unmap,$(firstword $(filter %compose.mk,$(MAKEFILE_LIST)))),${__interpreter__}))
$(call m5.declare, CMK_VERSION:=0.0.0-dev, CMK_DOCKER_PATH:=/usr/local/bin/compose.mk)
# In-container the interpreter lives under the local mount point, so the host anchor misses; retry on cwd.
_cmk.ws.probe=s='${cmk.self}'; ws="$${DOCKER_HOST_WORKSPACE:-$$PWD}"; rel="$${s\#$$ws/}"; case "$$rel" in "$$s") rel="$${s\#$$PWD/}";; esac
# A relative cache path is anchored to the docker-host workspace; docker reads one as a volume name.  Nested crossings inherit the resolved host path, since the daemon they talk to is the host daemon.
docker.hosted.mount.src=$${HOSTED_CACHE_HOST:-$(if $(filter /%,${HOSTED_CACHE}),${HOSTED_CACHE},$${workspace:-$${DOCKER_HOST_WORKSPACE:-$${PWD}}}/$(patsubst ./%,%,${HOSTED_CACHE}))}
docker.hosted.mount=$(if $(wildcard ${HOSTED_CACHE}),-v ${docker.hosted.mount.src}:/cmk-hosted/$(notdir ${HOSTED_CACHE}):ro -e HOSTED_CACHE_DIR=/cmk-hosted -e HOSTED_CACHE_HOST="${docker.hosted.mount.src}",)
makefile_list.dind=$(if $(strip ${docker.cmk.mount}),$(patsubst -f${cmk.self},-f${CMK_DOCKER_PATH},${makefile_list}),${makefile_list})
make.dind=make ${MAKE_FLAGS} ${makefile_list.dind}
# parse-time freeze (inputs are stable by here); recursive form cost one probe per child under make 4.4
export CMK_DIND_SRC:=$(shell ${_cmk.ws.probe}; if [ "$$rel" = "$$s" ]; then echo "${CMK_DOCKER_PATH}"; else echo "$$rel"; fi)

# Stream constants
$(call m5.declare, stderr:=/dev/stderr, stdin:=/dev/stdin, devnull:=/dev/null)
stderr_stdout_indent=2> >(sed 's/^/  /') 1> >(sed 's/^/  /')
$(call m5.declare, stderr_devnull:=2>${devnull}, all_devnull:=1>${devnull} 2>&1)
streams.join:=2>&1 

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.grammar :: Compiler-side grammar primitives
##
## The shared lexemes, the operator layer, and the dot-operator dispatch.  The
## grammar-hole table (lang.grammar.ctx) resolves the @@SYM_*@@ / @@TOKEN_SELF@@
## awk placeholders from these regexes (one source, no drift).
##
## * lang.rex.name :: A cmk identifier char class (name / namespace / method)
## * lang.rex.define :: A define-block opener line (generic)
## * lang.rex.recv.* :: Source-scan receiver-decl patterns
## * lang.rex.banana.open.* :: Multi-line banana-opener grammar
## * lang.grammar.token_self :: The literal instance-binder token ${self}
## * lang.grammar.ctx[.fill] :: awk grammar-hole table + its filler
## * lang.grammar.kwargs.* :: decl-kwarg vocab (ctor/class/machine/subject)
## * lang.grammar.ops :: The operator/dunder table (+= __add__, /= __div__, …)
## * lang.grammar.guarded_call :: Call a target; error clearly if it is undefined
## * lang.grammar.handle.target :: A .PHONY target twinning a &-handle callable
##
## * lang.grammar.dunder :: Look up an operator char in lang.grammar.ops.
##     A literal `%` op-char is `\%`-escaped so filter/patsubst don't wildcard it.
## * lang.grammar.dot.* :: Recipe-level dispatch for `foo(|a|).bar(|b|)`.
##     new (mark raw payload) → op / op.tbl (fold left by op-char) → run (__call__).
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lang.rex.name   := [A-Za-z0-9._-]
# Callform-position identifier class: the name class plus the predicate and bang suffix, admitted only where a trailing open-paren marks a call.
lang.rex.name.call := [A-Za-z0-9._?!-]
lang.rex.define := ^define
lang.rex.recv.banana   = ${lang.rex.name}+(\([^()|]*\))?[([{]\|
lang.rex.recv.kwarg    = namespace=${lang.rex.name}+
lang.rex.recv.def      = (docker\.import|code\b)[^)]*def=${lang.rex.name}+
lang.rex.recv.importas = ^[ \t]*import[ \t]+.*[ \t]+as[ \t]+${lang.rex.name}+([ \t]*,[ \t]*${lang.rex.name}+)*
lang.rex.recv.openlist = ^[ \t]*(open|import)[ \t]+${lang.rex.name}+([ \t]*,[ \t]*${lang.rex.name}+)*
lang.rex.recv.star     = ^[ \t]*\*[ \t]+${lang.rex.name}+([ \t]*,[ \t]*${lang.rex.name}+)*
lang.rex.recv.fromimport = ^[ \t]*from[ \t]+${lang.rex.name}+[ \t]+import[ \t]+(\*|${lang.rex.name}+([ \t]*,[ \t]*${lang.rex.name}+)*)
lang.rex.recv.goal     = ^[ \t]*goal[ \t]+${lang.rex.name}+
lang.rex.recv.capture  = ^[ \t]*&?${lang.rex.name}+[ \t]*<-
# Shared banana-opener grammar -- one source for the two awk stages that gate on "does this line
# open a multi-line banana?": `dedent` (strip the body's indent to col-0) and `sugar` (lower the
# block).  A new opener prefix is added here once; both stages inherit it, injected via the
# `@@BANANA_OPEN_*@@` `$(subst)` placeholders at each awk block's export.  (`lang.rex.recv.banana` above is a
# different projection -- it extracts the bound name for the pre-scan -- so it stays separate.)
#   named  = optional `LHS =`/`:=` value-prefix + a `path.. name` word-run, or a `[ctor..] *`
#            anonymous-dissolve prefix (the ctor path is optional).    assign = `name <op> (|`.
lang.rex.banana.open.named  = ^[ \t]*((${lang.rex.name}+[ \t]*:?=[ \t]*)?(${lang.rex.name}+[ \t]+)*${lang.rex.name}+(\([^()|]*\))?|(${lang.rex.name}+[ \t]+)*\*[ \t]*)[([{]\|
lang.rex.banana.open.assign = ^[ \t]*${lang.rex.name}+[ \t]*(:=|=|<-)[ \t]*[([{]\|
lang.grammar.token_self := $${self}
lang.grammar.ops := +=__add__ /=__div__ |=__pipe__ %=__mod__
lang.grammar.dunder = $(call lang.grammar.ops.resolve,$(m5[1]))
lang.grammar.guarded_call = $(if $(call m5.undefined?,$(m5[2])),$(error cmk-fault errno=GRAMMAR code=65 :: cmk: ${1}),$(call $(m5[2]),${3}))
lang.grammar.dot.new = $(eval $(m5[2]).__raw_body__ := 1)$(call lang.grammar.guarded_call,unknown dot-chain constructor `$(m5[1])` -- an operand must be an ANONYMOUS ctor(| .. |) (a NAMED `ctor name(| .. |)` is a module-level declaration -- not a chain operand),$(or $(m5[1]),lang.banana.fragment!),def=$(m5[2]))
lang.grammar.dot.op  = $(call lang.grammar.guarded_call,the dot (.) operator is undefined for the kind of `$(m5[1])` -- its constructor must define a `.__dot__` method (see demos/cmk/banana-fluent.cmk),$(m5[1]).__dot__,$(m5[2]))
lang.grammar.dot.op.tbl = $(call lang.grammar.guarded_call,the `$(call lang.grammar.dunder,$(m5[3]))` operator is undefined for the kind of `$(m5[1])` -- its constructor must define that dunder (see demos/cmk/banana-fluent.cmk),$(m5[1]).$(call lang.grammar.dunder,$(m5[3])),$(m5[2]))
lang.grammar.dot.run = $(call lang.grammar.guarded_call,dot-chain result is not callable -- the kind must define a `.__call__` method,$(m5[1]).__call__,)
lang.grammar.handle.target = $(eval .PHONY: $(m5[1]))$(eval $(m5[1]):;@$$(call $(m5[1])))
# lang.grammar.ctx: awk grammar-hole table (@@SYM@@); .fill folds it in.
lang.grammar.ctx := BANANA_OPEN_ASSIGN BANANA_OPEN_NAMED SYM_DEFINE SYM_NAME SYM_NAME_CALL TOKEN_SELF
lang.grammar.ctx.BANANA_OPEN_ASSIGN = $(lang.rex.banana.open.assign)
lang.grammar.ctx.BANANA_OPEN_NAMED  = $(lang.rex.banana.open.named)
lang.grammar.ctx.SYM_DEFINE         = $(lang.rex.define)
lang.grammar.ctx.SYM_NAME           = $(lang.rex.name)
lang.grammar.ctx.SYM_NAME_CALL      = $(lang.rex.name.call)
lang.grammar.ctx.TOKEN_SELF         = $(lang.grammar.token_self)
lang.grammar.ctx.fill = $(call m5.quasi/%,$1,$(lang.grammar.ctx),lang.grammar.ctx)
# lang.grammar.kwargs.*: declaration-kwarg vocab (drives m5 accessor codegen).
lang.grammar.kwargs.ctor    := def bases umbrella ns nsprefix
lang.grammar.kwargs.class   := ifaces classvars bind
lang.grammar.kwargs.machine := machine img flag feed entrypoint
lang.grammar.kwargs.subject := def namespace file
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: m5 :: The string-templating macro engine (an m4 in make)
##
## Notation simulates a type system: ? read, ! force/eval, % fill one hole, /
## fold over a context, [..] index.  Two changequote domains: ${X} vs @@X@@.
##
## * m5? :: Read pole — a var's raw value
## * m5! :: Eval pole — evaluate text as makefile
## * m5.self! :: Establish the m5.self context (receiver) at a constructor head
## * m5.set / m5.set.op :: Implicit-self setattr via m5!: set(name,val) / set.op(name,op,val)
## * m5.def! :: Write pole — freeze a body into a named define
## * m5.def.! :: Write, live — the name self-evals its template on each use
## * m5.ctx? :: Read a kwarg from a k=v list (quote-aware, strips)
## * m5.at / m5.rest :: List ops: element at a dynamic index; the list minus its head
## * m5.select / m5.pluck :: Keep (or read) list elements whose %-patterned var is defined
## * m5[1] / m5[2..4] :: Inline positional arg accessors (expand in-frame)
## * m5[1][KEY] / m5[def|namespace|file] :: Arg-1 kwarg accessors (quote-aware)
## * m5[1].gensym / m5.gensym :: codegen kwarg accessors from a key list
## * m5[__self__] :: The receiver (= m5[1]); the self that m5.set stamps onto
## * m5.__splat__ :: All positional call args, space-joined (undefined dropped)
## * m5.tmpl% :: Fill one ${X} hole (make domain)
## * m5.quasi% :: Fill one @@X@@ hole (awk domain)
## * m5.splice! :: Join a list of block values, newline-separated
##
## * m5.tmpl/% :: Fold a fill over a context (→ a thunk).
##     seed[.self] / seed.ns build seed / ns-prefixed tmpls; !=eval.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
m5? = $(value $(1))
m5! = $(eval $(1))
m5.def! = $(eval define $(m5[1])$(nl)$(2)$(nl)endef)
m5.def.! = $(eval $(m5[1]) = $$(eval $$(call $(m5[2]),$$(strip $$(1)))))
m5.self! = $(eval m5.self := $(1))
m5.set = $(call m5!,$(m5.self).$(1) := $(2))
m5.set.op = $(call m5!,$(m5.self).$(1) $(2) $(3))
# Save/restore stack: a scalar plus a shadow list, ꙮ standing in for an empty value.
m5.stack.push = $(or $(1),ꙮ) $(2)
m5.stack.top = $(patsubst ꙮ,,$(firstword $(1)))
m5.ctx? =$(if $(call m5.lex.quoted?,$(1)),$(subst «qk.s»,$(space),$(patsubst $(m5[2])=%,%,$(filter $(m5[2])=%,$(call m5.lex.qnorm,$(1))))),$(strip $(patsubst $(m5[2])=%,%,$(filter $(m5[2])=%,${1}))))
# m5.table: KEY=VALUE subscript table; .dispatch/.call = jump table.
define m5.table
$(eval $(strip $(1)).__all__ :=)
$(eval $(strip $(1)).__default__ := $(m5[3]?))
$(foreach _m5t_e,$(2),$(eval _m5t_k := $(strip $(word 1,$(subst =,$(space),$(_m5t_e)))))$(eval _m5t_v := $(strip $(word 2,$(subst =,$(space),$(_m5t_e)))))$(eval $(strip $(1))[$(_m5t_k)] := $(_m5t_v))$(eval $(strip $(1)).rev[$(_m5t_v)] := $(strip $(call m5.lex.uniq,$(call m5|,$(strip $(1)).rev[$(_m5t_v)],) $(_m5t_k))))$(eval $(strip $(1)).__all__ += $(_m5t_k)))
$(eval $(strip $(1)).resolve = $$(call m5|,$(strip $(1))[$$(strip $$(m5[1]))],$$(or $$(m5[2]?),$($(strip $(1)).__default__))))
$(eval $(strip $(1)).reverse = $$(call m5|,$(strip $(1)).rev[$$(strip $$(m5[1]))],$$(m5[2]?)))
$(eval $(strip $(1)).has? = $$(if $$(call m5.defined?,$(strip $(1))[$$(strip $$(m5[1]))]),$$(strip $$(m5[1])),))
$(eval $(strip $(1)).dispatch = $$(call $$(call $(strip $(1)).resolve,$$(m5[1])),$$(m5[2]?),$$(m5[3]?),$$(m5[4]?)))
$(eval $(strip $(1)).call = $$(if $$(call $(strip $(1)).has?,$$(m5[1]))$($(strip $(1)).__default__),$$(call $(strip $(1)).dispatch,$$(m5[1]),$$(m5[2]?),$$(m5[3]?),$$(m5[4]?)),$$(call mk.error, no dispatch handler for `$$(strip $$(m5[1]))` in table $(strip $(1)), errno=NOT_CALLABLE)))
endef
m5.table/* = $(foreach _m5t_k,$($(strip $(m5[1])).__all__),$(call $(m5[2]),$(_m5t_k),$($(strip $(m5[1]))[$(_m5t_k)])))
# m5.marm cellvar: arm a var to self-memoize its own value (run-once).
m5.marm = $(eval $(strip $(m5[1])) = $$(eval $(strip $(m5[1])) := $(value $(strip $(m5[1]))))$$($(strip $(m5[1]))))
# m5.memoize var: cache _var.detect into var on first read.
m5.memoize = $(eval $(strip $(m5[1])) = $$(_$(strip $(m5[1])).detect))$(call m5.marm,$(strip $(m5[1])))
# m5.memoize.fn cache fn arg: cache fn's result keyed by arg.
m5.memoize.fn = $(if $(call m5.defined?,$(strip $(m5[1]))[$(strip $(m5[3]))]),,$(eval $(strip $(m5[1]))[$(strip $(m5[3]))] := $(call $(strip $(m5[2])),$(m5[3]))))$($(strip $(m5[1]))[$(strip $(m5[3]))])
# m5.memoize! key: run-scoped once-guard (MAKE_SUPER-keyed marker).
m5.memoize! = ( f=".tmp.mk.super.$(call m5|,MAKE_SUPER,${_cmk.pid}).once.$(strip $(1))" ; if [ -e "$$f" ]; then false ; else : > "$$f" ; fi )
# m5.mtable.upd tbl key a [b]: 3-arg ternary, 2-arg callable-ref.
m5.mtable.upd = $(if $(m5[4]?),$(eval $(strip $(m5[1]))[$(strip $(m5[2]))] = $$(shell $(m5[3]) 2>/dev/null || echo $(m5[4]))),$(eval $(strip $(m5[1]))[$(strip $(m5[2]))] = $$($(strip $(m5[3])))))$(call m5.marm,$(strip $(m5[1]))[$(strip $(m5[2]))])$(eval $(strip $(m5[1])).__all__ += $(strip $(m5[2])))
# m5.mtable name: self-memoizing cells; .update keys a check per name.
define m5.mtable
$(call m5.table,$(strip $(1)),,)
$(eval $(strip $(1)).update = $$(call m5.mtable.upd,$(strip $(1)),$$(m5[1]),$$(m5[2]),$$(m5[3]?)))
endef
# m5[N]/m5[N]?: in-frame strip-normalized arg accessors, codegen 1..9
$(foreach _n,1 2 3 4 5 6 7 8 9,$(eval m5[$(_n)] = $$(strip $$($(_n))))$(eval m5[$(_n)]? = $$(if $$(filter undefined,$$(origin $(_n))),,$$(m5[$(_n)]))))
# m5[N][i]: one-based numeric subscript (word i of arg N's list), codegen 1..9 x 1..16
$(foreach _n,1 2 3 4 5 6 7 8 9,$(foreach _i,1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16,$(eval m5[$(_n)][$(_i)] = $$(word $(_i),$$(m5[$(_n)])))))
# m5[N] dot-accessors over arg N; the m5.__acc__ list is the vocabulary the compiler consumes
m5.__acc__ := len first last rest
$(foreach _n,1 2 3 4 5 6 7 8 9,$(eval m5[$(_n)].len = $$(words $$(m5[$(_n)])))$(eval m5[$(_n)].first = $$(firstword $$(m5[$(_n)])))$(eval m5[$(_n)].last = $$(lastword $$(m5[$(_n)])))$(eval m5[$(_n)].rest = $$(wordlist 2,$$(words $$(m5[$(_n)])),$$(m5[$(_n)]))))
# m5.at list i: the element of a list at a dynamic one-based index.  m5.rest: the list minus its first word.
m5.at = $(word $(m5[2]),$(m5[1]))
m5.rest = $(wordlist 2,$(words $(1)),$(1))
# docker.cmk.mount: workspace bind-mount flag, memoized in place.
docker.cmk.mount=$(shell ${_cmk.ws.probe}; [ -n "$$s" ] && [ "$$rel" = "$$s" ] && echo "-v $${CMK_BIN_HOST:-$$s}:${CMK_DOCKER_PATH}:ro -e CMK_BIN_HOST=$${CMK_BIN_HOST:-$$s}" || true)
$(call m5.marm, docker.cmk.mount)
m5[__self__] = $(m5[1])
# Origin predicates (ifdef/ifndef); m5| = read-or-default (eager).
m5.defined? = $(filter-out undefined,$(origin $(m5[1])))
m5.undefined? = $(filter undefined,$(origin $(m5[1])))
m5.given? = $(or $(findstring environment,$(origin $(m5[1]))),$(findstring command,$(origin $(m5[1]))))
m5| = $(if $(call m5.defined?,${1}),$($(m5[1])),${2})
# m5.select list pat / m5.pluck list pat: keep (or read) the elements whose pat-named var is defined.
m5.select = $(strip $(foreach _m5s_e,$(m5[1]),$(if $(call m5.defined?,$(subst %,$(_m5s_e),$(m5[2]))),$(_m5s_e))))
m5.pluck = $(strip $(foreach _m5s_e,$(call m5.select,${1},${2}),$($(subst %,$(_m5s_e),$(m5[2])))))
# m5[1][K]/m5[K]: kwarg accessors codegen'd from lang.grammar.kwargs.* vocab
m5[1].gensym = $(foreach _k,$(1),$(eval m5[1][$(_k)] = $$(call m5.ctx?,$$(1),$(_k))))
m5.gensym = $(foreach _k,$(1),$(eval m5[$(_k)] = $$(call m5.ctx?,$$(1),$(_k))))
$(call m5[1].gensym, ${lang.grammar.kwargs.ctor} ${lang.grammar.kwargs.class} ${lang.grammar.kwargs.machine})
$(call m5.gensym, ${lang.grammar.kwargs.subject})
m5.__splat__=$(strip $(foreach _as,1 2 3 4 5 6 7 8 9,$(if $(filter-out undefined,$(origin $(_as))),$($(_as)))))
# m5.__args__: the callform stem as a positional tuple (Python *args). bare -> list; (N)/(N-) -> field/range
# (delim arg2 default comma, default arg3); .unpack binds names positionally (x, y = args).
m5.__args__ = $(if $(m5[1]),$(call mk.unpack.any,$(1),$(or $(m5[2]?),$(comma)),$(m5[3]?)),$(subst $(or $(m5[2]?),$(comma)),$(space),${*}))
m5.__args__.unpack = $(call mk.unpack.args,$(1))
# m5.__args__.first: NON-`-s` field-1 passthrough (whole stem if no delim), for the raw cut forks.
m5.__args__.cut = $(if $(findstring $(or $(m5[2]?),$(comma)),${*}),$(call m5.__args__,$(1),$(m5[2]?)),${*})
m5.__args__.first = $(call m5.__args__.cut,1,$(m5[1]?))
# m5.__kwargs__: keyed view (Python **kwargs). bare(subj) -> the kwarg string; (subj,key) -> value.
m5.__kwargs__ = $(if $(m5[2]),$(call mk.kwargs.get,$(1),$(2)),$(1))
m5.tmpl% = $(subst $${$(m5[2])},$(m5[3]),$(1))
m5.quasi% = $(subst @@$(m5[2])@@,${3},${1})
m5.tmpl/%  = $(if $(m5[2]),$(call m5.tmpl/%,$(call m5.tmpl%,$(1),body$(words x $(3)),$(firstword $(2))),$(wordlist 2,$(words $(2)),$(2)),x $(3)),$(1))
m5.tmpl/seed = $(call m5.tmpl/%,$(call m5.tmpl%,$(call m5.tmpl%,$(call m5?,$(1)),1,$(2)),self,$(firstword $(3))),$(3),)
m5.tmpl/seed.self = $(call m5.tmpl/%,$(call m5.tmpl%,$(call m5.tmpl%,$(call lang.class.comp.self.xform,$(1)),1,$(2)),self,$(firstword $(3))),$(3),)
m5.tmpl/seed.ns =$(call m5.tmpl%,$(call m5.tmpl%,$(call m5.tmpl%,$(call m5?,$(1)),1,$(2)),self,$(3)),body1,$(4))
m5.tmpl! = $(eval $(if $(filter undefined,$(origin 4)),$(call m5.tmpl/seed,$(1),$(m5[2]?),$(m5[3]?)),$(call m5.tmpl/seed.ns,$(1),$(2),$(3),$(4))))
m5.quasi/% = $(if $(m5[2]),$(call m5.quasi/%,$(call m5.quasi%,$1,$(firstword $2),$($(m5[3]).$(firstword $2))),$(wordlist 2,$(words $2),$2),$3),$1)
m5.splice! = $(foreach _qq,${1},$(call m5?,$(strip ${_qq}))$(nl))

# mk.kwargs.get -- alias of m5.ctx?, kept for callers outside the middle.
mk.kwargs.get = $(call m5.ctx?,${1},${2})
# get + un-sentinel: decode the sentinel at final-consumption only.
_mk.kwargs.getd=$(subst ${lang.comp.kwargs.sp},${space},$(call m5.ctx?,${1},${2}))
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: m5.lex :: Fork-free pure-make lexer (+ m5.tok data: chars/marks)
##
## The awk/sed-fork replacement for hotpath string work: sentinel-guarded
## protect/restore, tokenize, per-token/per-line map, list combinators.  Same «X»
## sentinel domain as the class-body desugar.
##
## * m5.tok.tab.char / .lparen / .rparen :: Whitespace-safe char constants
## * m5.ctx.dchars :: The delimiter char-set the tokenizer splits on
## * m5.lex.protect / .restore :: Encode / decode the «X» sentinel quote-domain
## * m5.lex.tok / .tok/% / .tok/* :: Tokenize (wrap delimiters) + map over tokens
## * m5.lex.line/* :: Map a function over each line
## * m5.lex.upper / .split :: Leaf string ops (uppercase; split on colon)
## * m5.lex.kwarg? / .glob? / .quoted? :: Token-shape predicates (non-empty is true)
## * m5.lex.rev / .uniq :: List ops, callable (reverse; keep-first dedup)
## * m5.lex.qnorm :: Quote-aware kwarg normalizer (.dq/.sq split by quote parity)
## * m5[dollar] / m5[space] / m5[tab] / m5[nl] / m5[break] :: The «X» sentinel alphabet
## * m5.tok.marks :: The sentinel alphabet as DATA (name→glyph→char); the accessors derive from it
## * m5.quasi.protect / m5.quasi.restore :: The dollar-changequote (guard / unguard across a rewrite)
## * m5.escape / m5.unescape / m5.strip :: Variadic over a mark-LIST: char<->glyph / glyph->'' (dollar via m5.quasi)
## * m5.lex.bare :: Strip protected whitespace glyphs (inspect token structure)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# list ops (rev/uniq): defined first; m5.table (data below) uses uniq.
m5.lex.rev=$(if $(m5[1]),$(call m5.lex.rev,$(wordlist 2,$(words ${1}),${1})) $(firstword ${1}))
m5.lex.uniq = $(if $(m5[1]),$(firstword $(1)) $(call m5.lex.uniq,$(filter-out $(firstword $(1)),$(wordlist 2,$(words $(1)),$(1)))))
# data: the «X» sentinel alphabet + tokenizer char-sets (lookup tables)
# m5.tok glyphs: a point-lookup table; __all__ is the mark registry.
$(call m5.table, m5.tok, dollar=«D» space=«S» tab=«T» nl=«N» break=«B»)
m5.tok.marks := $(m5.tok.__all__)
# fan each glyph out to its dotted accessor + bracket alias.
$(foreach _m5t_m,$(m5.tok.__all__),$(eval m5.tok.$(_m5t_m) := $(m5.tok[$(_m5t_m)]))$(eval m5[$(_m5t_m)] := $(m5.tok[$(_m5t_m)])))
m5.tok.dollar.char = $$
m5.tok.space.char = $(space)
m5.tok.nl.char = $(nl)
m5.tok.ws := space tab nl
# m5[<mark>] bracket aliases are generated above from the table.
m5.tok.tab.char := $(subst |,,|	|)
m5.tok.lparen := (
m5.tok.rparen := )
m5.ctx.dchars := = : / [ ] < > ; " ' | ! ? * + - ~ @ & ^ `

# callables: leaf value->value transforms (escape/tokenize/case/qnorm)
m5.quasi.protect = $(subst $$,$(m5[dollar]),$(1))
m5.quasi.restore = $(subst $(m5[dollar]),$$,$(1))
m5.escape = $(if $(2),$(call m5.escape,$(if $(filter dollar,$(firstword $(2))),$(call m5.quasi.protect,$(1)),$(subst $(m5.tok.$(firstword $(2)).char),$(m5.tok.$(firstword $(2))),$(1))),$(wordlist 2,$(words $(2)),$(2))),$(1))
m5.unescape = $(if $(2),$(call m5.unescape,$(if $(filter dollar,$(firstword $(2))),$(call m5.quasi.restore,$(1)),$(subst $(m5.tok.$(firstword $(2))),$(m5.tok.$(firstword $(2)).char),$(1))),$(wordlist 2,$(words $(2)),$(2))),$(1))
m5.strip = $(if $(2),$(call m5.strip,$(subst $(m5.tok.$(firstword $(2))),,$(1)),$(wordlist 2,$(words $(2)),$(2))),$(1))
m5.lex.protect = $(call m5.escape,$(1),dollar $(m5.tok.ws))
m5.lex.restore = $(call m5.unescape,$(subst $(space),,$(1)),$(m5.tok.ws) dollar)
m5.lex.bare = $(call m5.strip,$(1),space tab)
m5.lex.tok = $(call m5.lex.tok/%,$(m5.ctx.dchars),$(subst $(m5[dollar]),$(m5[break])$(m5[dollar])$(m5[break]),$(subst $(m5[space]),$(m5[break])$(m5[space])$(m5[break]),$(subst $(m5[tab]),$(m5[break])$(m5[tab])$(m5[break]),$(subst $(m5[nl]),$(m5[break])$(m5[nl])$(m5[break]),$(subst $(m5.tok.lparen),$(m5[break])$(m5.tok.lparen)$(m5[break]),$(subst $(m5.tok.rparen),$(m5[break])$(m5.tok.rparen)$(m5[break]),$(subst $(comma),$(m5[break])$(comma)$(m5[break]),$(1)))))))))
m5.lex.upper=$(subst a,A,$(subst b,B,$(subst c,C,$(subst d,D,$(subst e,E,$(subst f,F,$(subst g,G,$(subst h,H,$(subst i,I,$(subst j,J,$(subst k,K,$(subst l,L,$(subst m,M,$(subst n,N,$(subst o,O,$(subst p,P,$(subst q,Q,$(subst r,R,$(subst s,S,$(subst t,T,$(subst u,U,$(subst v,V,$(subst w,W,$(subst x,X,$(subst y,Y,$(subst z,Z,${1}))))))))))))))))))))))))))
m5.lex.split=$(subst :, ,$(1))
# predicates: token-shape tests over a raw string; non-empty is true, like the origin predicates.
m5.lex.kwarg? = $(findstring =,$(1))
m5.lex.glob? = $(findstring *,$(1))$(findstring ?,$(1))
m5.lex.quoted? = $(findstring ",$(1))$(findstring ',$(1))
# qnorm: quote-aware kwarg space-normalizer (.dq/.sq by quote parity)
m5.lex.qnorm = $(subst «qk.p»,$(space),$(call m5.lex.qnorm.sq,$(call m5.lex.qnorm.dq,$(subst $(space),«qk.s»,$(1)))))
m5.lex.qnorm.dq = $(call m5.lex.qnorm.dq.rec,$(subst ",$(space),$(1)))
m5.lex.qnorm.dq.rec = $(if $(m5[1]),$(subst «qk.s»,«qk.p»,$(firstword $(1)))$(word 2,$(1))$(call m5.lex.qnorm.dq.rec,$(wordlist 3,$(words $(1)),$(1))))
m5.lex.qnorm.sq = $(call m5.lex.qnorm.sq.rec,$(subst ',$(space),$(1)))
m5.lex.qnorm.sq.rec = $(if $(m5[1]),$(firstword $(1))$(subst «qk.p»,«qk.s»,$(word 2,$(1)))$(call m5.lex.qnorm.sq.rec,$(wordlist 3,$(words $(1)),$(1))))

# combinators: higher-order -- map/fold a function over tokens/lines
m5.lex.tok/% = $(if $(1),$(call m5.lex.tok/%,$(wordlist 2,$(words $(1)),$(1)),$(subst $(firstword $(1)),$(m5[break])$(firstword $(1))$(m5[break]),$(2))),$(2))
m5.lex.tok/* = $(call m5.lex.restore,$(foreach _t,$(subst $(m5[break]),$(space),$(call m5.lex.tok,$(call m5.lex.protect,$(1)))),$(call $2,$(_t))))
m5.lex.line/* = $(call m5.quasi.restore,$(subst $(m5[tab]),$(m5.tok.tab.char),$(subst $(m5[space]),$(space),$(subst $(space),$(nl),$(foreach _line,$(subst $(nl),$(space),$(subst $(space),$(m5[space]),$(subst $(m5.tok.tab.char),$(m5[tab]),$(call m5.quasi.protect,$(1))))),$(call $2,$(_line)))))))
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: m5.auto :: The automata zoo (reusable machines over word-lists)
##
## Parsing engines parameterized by a spec namespace whose members supply the
## domain decisions. First inhabitant: a one-token-lookahead Mealy machine.
##
## * m5.auto[look-ahead] :: One-token-lookahead automaton CONSTRUCTOR.
##     name = m5.auto[look-ahead](trigger, emit, skip, mark, commit.mark, commit.plain)
##     stamps `name` as a callable name(words): walk the word-list threading
##     (pending, acc), hold a trigger token, classify by peeking the next.
##     Components are EXPLICIT args (greppable wiring), not member-dispatch.
## * m5.auto.la :: Shared runner (+ .go/.seg/.np/.wp) over the 6-tuple spec.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

m5.auto.la = $(call m5.auto.la.go,$(1),$(2),,)
m5.auto.la.go = $(if $(1),$(call m5.auto.la.seg,$(firstword $(1)),$(wordlist 2,$(words $(1)),$(1)),$(2),$(3),$(4)),$(if $(3),$(call $(word 6,$(2)),$(3))$(4)))
m5.auto.la.seg = $(if $(4),$(call m5.auto.la.wp,$(1),$(2),$(3),$(4),$(5)),$(call m5.auto.la.np,$(1),$(2),$(3)))
m5.auto.la.np = $(if $(call $(word 1,$(3)),$(1)),$(call m5.auto.la.go,$(2),$(3),$(1),),$(call $(word 2,$(3)),$(1))$(call m5.auto.la.go,$(2),$(3),,))
m5.auto.la.wp = $(if $(call $(word 3,$(3)),$(1)),$(call m5.auto.la.go,$(2),$(3),$(4),$(5)$(1)),$(if $(call $(word 4,$(3)),$(1)),$(call $(word 5,$(3)),$(4))$(5)$(1)$(call m5.auto.la.go,$(2),$(3),,),$(call $(word 6,$(3)),$(4))$(5)$(call m5.auto.la.seg,$(1),$(2),$(3),,)))
m5.auto[look-ahead] = $(eval $(m5[1]) = $$(call m5.auto.la,$$(1),$(m5[2]) $(m5[3]) $(m5[4]) $(strip $(5)) $(strip $(6)) $(strip $(7))))

# dogfood: mint lang.grammar.ops as a point-lookup table.
$(call m5.table, lang.grammar.ops, $(lang.grammar.ops), __dot__)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Returns "-x" iff trace is enabled.  (This is used with calls to bash/sh to show the command)
dash_x_maybe:=`[ $${TRACE} == 1 ] && echo -x || true`
export HOSTNAME?=$(shell hostname)
# freeze to simple: containers preset the hostname env var but a bare host pays the probe per child under make 4.4
export HOSTNAME:=$(HOSTNAME)
GLYPH_HOSTNAME= ${bold}[${no_ansi_dim}${ital}$${HOSTNAME}${no_ansi}${bold}]${no_ansi}
trace_maybe=[ "${TRACE}" == 1 ] && set -x || true
GLYPH_INDENT_BASE ?= 0
GLYPH_MAKELEVEL_INDENT=$$(_d=$$(( $${MAKELEVEL:-0} - $${GLYPH_INDENT_BASE:-0} )); printf '%*s' $$(( _d>0 ? _d*2 : 0 )) '')

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: log :: Themed MAKELEVEL-aware stderr messages (gated by quiet)
##
## Messages go to stderr (stdout stays clean); log prepends the target
## stem as a header; log.base is the headerless primitive channels use;
## channels are table-generated, one row per glyph (_log.tmpl.*).
##
## * log / .locals / .pad_* :: the common target-stem logger + kin
## * log.base[.part1/.part2] :: headerless primitive + two-part pair
## * log.stdout / log.prefix.* :: stdout twin + per-line prefixes
## * log.{io,mk,docker,flux,tux} :: glyph channels (+.part1/2/.maybe)
## * log.error / log.warn[.once] :: status channels + .err/.warning
## * log.json[.min] / log.compiler[.fmt] / log.trace.* :: gated variants
## * log.loop.* :: tree-row loggers
## * log.module / log.import :: parse-time loggers (imports gated)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
log.prefix.makelevel.glyph=${dim}$(call GLYPH.NUM, ${MAKELEVEL})
log.prefix.makelevel.indent=
# log.prefix.tag -- optional run-tag prefix, one definition for every channel.
log.prefix.tag=$${CMK_LOG_PRE:+$${CMK_LOG_PRE} }
log.prefix.lang=$(if $(filter 0,$(__hosted__.enabled)),${GLYPH_LANG_OFF} ,)
log.prefix.makelevel=${log.prefix.makelevel.glyph} ${log.prefix.lang}${log.prefix.makelevel.indent}
log.prefix.loop.inner=${log.prefix.makelevel}${log.prefix.tag}${bold}${dim_green}${GLYPH.tree_item}${no_ansi}
log.prefix.loop.last=${log.prefix.makelevel}${log.prefix.tag}${bold}${dim_green}${GLYPH.tree_last}${no_ansi}
# FIXME: log.stdout is misnamed -- log.base redirects it to stderr.
log.stdout=printf "${log.prefix.makelevel} ${log.prefix.tag}$(strip $(if $(filter undefined,$(origin 1)),...,$(1))) ${no_ansi}\n"
# FIXME: log callchain tangled -- part1/trace bypass log.stdout.
log.base=([ "$(or $(quiet),0)" == "1" ] || ( ${log.stdout} >${stderr} ))
log._json=$(call log.base, ${dim}${bold_green}${@} ${no_ansi_dim} ${cyan_flow_right}); ${jb.docker} ${2} | ${jq.run} ${1} . | ${stream.as.log}
log.json=$(call log._json,,${1})
log.json.min=$(call log._json,-c,${1})
log=$(call log.io, ${dim_ital}$(strip $(or $(m5[1]?),$(shell printf "${@}" | cut -d/ -f2-)))${no_ansi})
log.pad_top=printf '\n' >> /dev/stderr; ${log}
log.pad_bottom=${log}; printf '\n'>>/dev/stderr
# log.repr -- LOG-only display name; anon operands read as class#seq
log.repr.pound := \#
log.repr = $(strip $(if $(and $(filter __%,$(m5[1])),$(findstring .,$(m5[1]))),$(firstword $(subst ., ,$(patsubst __%,%,$(m5[1]))))$(log.repr.pound)$(word 2,$(subst ., ,$(patsubst __%,%,$(m5[1])))),$(m5[1])))
# log.ctx[.c] -- located target-stem header, guarded off-recipe.
log.ctx.c = $(if $(filter-out undefined,$(origin @)),$(1)$(firstword $(subst /, ,${@}))${no_ansi} ${sep} ,)
log.ctx = $(call log.ctx.c,${dim_green})
define _log.tmpl.plain
log.@@N@@ = $(call log.base, ${@@G@@} ${log.ctx}$(1))
log.@@N@@.as = $(call log.base, ${@@G@@} ${dim_green}$(1)${no_ansi} ${sep} $(2))
log.@@N@@.part1 = $(call log.base.part1, ${@@G@@} ${log.ctx}$(1))
log.@@N@@.part2 = $(call log.base.part2, $(1))
log.@@N@@.maybe = ( case "${1}" in *[![:space:]]*) $(call log.@@N@@, ${1}) ;; esac )
endef
m5.ctx.log := io:GLYPH_IO mk:GLYPH_MK docker:GLYPH.DOCKER flux:GLYPH_FLUX tux:GLYPH_TUI
m5.ctx.log.stat := error:GLYPH_ERROR:red warn:GLYPH_WARN:yellow
$(foreach _r,$(m5.ctx.log),$(eval $(call m5.quasi%,$(call m5.quasi%,$(value _log.tmpl.plain),N,$(word 1,$(subst :, ,$(_r)))),G,$(word 2,$(subst :, ,$(_r))))))
define _log.tmpl.stat
log.@@N@@ = $(call log.base, ${@@G@@} $(call log.ctx.c,${@@C@@})${@@C@@}$(strip $(or $(m5[1]?),$(shell printf "${@}" | cut -d/ -f2-)))${no_ansi})
endef
$(foreach _r,$(m5.ctx.log.stat),$(eval $(call m5.quasi%,$(call m5.quasi%,$(call m5.quasi%,$(value _log.tmpl.stat),N,$(word 1,$(subst :, ,$(_r)))),G,$(word 2,$(subst :, ,$(_r)))),C,$(word 3,$(subst :, ,$(_r))))))
log.err=${log.error}
log.warning=${log.warn}
# log.warn.once <key> <msg>: emit msg via log.warn once per run.
log.warn.once=$(call m5.memoize!,$(strip $(1))) && $(call log.warn,$(2)) || true
log.part1=([ -z "$${quiet:-}" ] && (printf "${log.prefix.makelevel}${log.prefix.tag}${GLYPH_IO}${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep}${dim_ital} `echo "$(strip $(or $(1),))"| ${stream.lstrip}` ${no_ansi_dim}..${no_ansi}") || true )>${stderr}
log.part2=([ -z "$${quiet:-}" ] && $(call log.base.part2, ${1}) || true)
log.test=$(call log.io, ${dim_green} $(shell printf "${@}" | cut -d/ -f1) ${sep} ${dim}..\n  ${cyan_flow_right}${dim_ital_cyan}$(or $(1),$(shell printf "${@}" | cut -d/ -f2-)))
log.trace=[ "${TRACE}" == "0" ] && true || (printf "${log.prefix.makelevel}${log.prefix.tag}${log.ctx}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr} )
log.trace.fmt=( ${log.trace} && [ "${TRACE}" == "0" ] && true || (printf "${2}" | fmt -w 70 | ${stream.indent.to.stderr} ) )
log.trace.part1=[ "${TRACE}" == "0" ] && true || $(call log.base.part1, ${1})
log.trace.part2=[ "${TRACE}" == "0" ] && true || $(call log.base.part2, ${1})
log.rerouting=$(call log.base, ${dim}${_GLYPH_IO}${dim} $(shell echo ${@} | sed 's/\/.*//') ${sep}${dim} Invoked from top; rerouting to tool-container)
log.locals =$(call log, ${bold}variables:${dim} (target-local)) && $(__locals__) | ${jq} . | ${stream.indent} | ${stream.as.log}
log.file.contents=$(call log, file=$(m5[1])) && cat ${1} | ${stream.as.log}
log.preview.file=$(call log, ${cyan}$(m5[1])) ; $(call io.preview.file, ${1})
log.compiler=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.base, ${GLYPH_MK} ${1}))
log.compiler.fmt=( $(call log.compiler, ${1}) && ( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || ( printf '%b\n' "${2}" | ${stream.fold} | awk -v p="$$(printf '%b' '${GLYPH_MK}')" '{print p" "$$0}' | ${stream.indent.to.stderr} ) ) )

log.module=$(shell $(call log.mk, ${1}))
log.module.error=$(shell $(call log.error, ${1}))
log.module.fail=$(call log.module.error, ${1})$(error cmk-fault errno=GENERIC code=1 :: $(or $(m5[2]),CMK_FAIL: $(m5[1])))
log.import=$$(if $$(filter-out 0,$${CMK_LOG_IMPORTS}),$$(call log.module, ${dim}__import__ ${sep}${dim} ${1}))
log.import.part1=$$(shell [ $${CMK_LOG_IMPORTS} == 0 ] || $$(call \
	log.base.part1, ${GLYPH_MK} ${dim}__import__  ${sep}${dim} ${1}))
log.import.part2=$$(shell [ $${CMK_LOG_IMPORTS} == 0 ] || $$(call log.base.part2, ${1}))
log.import.error=$$(call log.module, ${red}${dim}__import__ ${sep}${dim} ${red}${1}${no_ansi})

log.loop.top=printf "${log.prefix.makelevel}${log.prefix.tag}${log.ctx}`echo "$(or $(1),)"| ${stream.lstrip}`${no_ansi}\n" >${stderr}
log.stdout.loop.item=(printf "${log.prefix.loop.inner}`echo "$(or $(1),)" | sed 's/^ //'`${no_ansi}\n")
log.loop.item=(${log.stdout.loop.item}>${stderr})
log.loop.item.last=( printf "${log.prefix.loop.last}`echo "$(or $(1),)" | sed 's/^ //'`${no_ansi}\n" > ${stderr} )
log.trace.loop.top=[ "${TRACE}" == "0" ] && true || $(call log.loop.top, ${1})
log.trace.loop.item=[ "${TRACE}" == "0" ] && true || $(call log.loop.item, ${1})
log.loop.part1=(printf "${log.prefix.loop.inner}`echo "$(or $(1),)" | ${stream.lstrip}` ${no_ansi_dim}..${no_ansi}" >${stderr})
log.loop.part2=(printf "${no_ansi} `echo "$(or $(1),)" | ${stream.lstrip}`${no_ansi}\n" >${stderr})

log.stdout.part1=(case $${quiet:-} in \
	""|0) printf "${log.prefix.makelevel} ${log.prefix.tag}$(strip $(or $(1),)) ${no_ansi_dim}..${no_ansi}";; esac)
log.stdout.part2=(case $${quiet:-} in \
	""|0) printf "${no_ansi} $(strip $(or $(1),)) ${no_ansi}\n";; esac)
	
log.base.part1=(${log.stdout.part1}>${stderr})
log.base.part2=(${log.stdout.part2}>${stderr})
log.compiler.part1=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.base.part1, ${GLYPH_MK} ${1}))
log.compiler.part2=( [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.base.part2, ${1}))
log.trace.compiler.part1=( [ "${TRACE}" == "0" ] && true || $(call log.base.part1, ${GLYPH_MK} ${1}))
log.trace.compiler.part2=( [ "${TRACE}" == "0" ] && true || $(call log.base.part2, ${1}))
log.trace.compiler.fmt=( [ "${TRACE}" == "0" ] && true || ( $(call log.base, ${GLYPH_MK} ${1}) && printf '%b\n' "${2}" | fmt -w 64 | ${stream.indent.to.stderr} ) )
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


docker.run.base:=docker run --rm -i -v $${DOCKER_HOST_WORKSPACE:-$${PWD}}:/workspace -w/workspace

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Environment Variables :: Knobs, paths, and interpreter state
##
## Internal knobs, host/container paths, and interpreter state; most are `?=`
## overridable from the environment.  Order-independent knobs are clustered at the
## body head; the rest is an ordered bootstrap.  The two critical ones lead:
##
## * CMK_INTERNAL :: 1 for a nested / internal (non-top-level) cmk invocation, else 0.
##     Set by the host-side recursive helpers (io.bash, mk.def.read, module staging,
##     cli-subcommands, the hosted build) and at the container-dispatch boundary, so
##     running inside a dispatch container is just one case of "internal".  It gates
##     DIND and skips re-scaffolding the heavyweight `*.import` verbs on every nested
##     sub-make.  For the strict "literally inside a container?" test use
##     CMK_IN_CONTAINER (a subset, set only at dispatch).
## * CMK_STAGE_DIR :: The one dir compose.mk writes host artifacts into.
##     Writable CMK_MODULES_DIR wins (co-located with the workspace bind-mount,
##     reused in container); an explicit value is trusted; else (read-only default
##     `.cmk`) it falls back to the writable user XDG cache.
##
## * CMK_IN_CONTAINER :: 1 only literally inside a dispatch container
## * CMK_LIB / CMK_STANDALONE :: Library-mode vs standalone-mode flags
## * CMK_DIND :: 1 if docker-in-docker is allowed
## * CMK_SUPERVISOR :: 1 if the supervisor / signal handling is enabled
## * CMK_LOG_IMPORTS :: 1 to log module-level imports (default 0)
## * CMK_COMPILER_VERBOSE :: 1 to allow compiler debug messages
## * CMK_IMPORT_DISCOVER :: 1 = register-only import mode (discovery pass); default 0
## * CMK_SANDBOX / CMK_SANDBOX_SRC :: Sandbox-partition toggles (empty = off)
## * TRACE :: 1 for extra verbosity (finer than verbose)
## * trace :: Alias for TRACE; very noisy (appends make -x)
## * verbose :: 1 to show debug output
## * quiet :: 1 to suppress debug output
## * force :: 1 to force operations
##
## * CMK_PLUGINS_DIR :: PATH-like plugin/include search path (colon-sep); default .cmk
## * CMK_MODULES_DIR :: Preferred staging-dir seed (1st CMK_PLUGINS_DIR element)
## * CMK_XDG_CACHE :: XDG cache dir for host artifacts (built binaries, caches)
## * CMK_NATIVE_CACHE :: Native-compile cache dir (under the stage dir)
## * CMK_EXTRA_REPO :: Extra repo search dir (default .)
## * CMK_SCRATCH / CMK_IO_STACK / CMK_BRF_PREFIX :: Run-id-keyed .tmp.* scratch names
##
## * CMK_SRC :: Path to compose.mk source to read / include
## * cmk.self :: compose.mk host abspath (single source of truth)
## * CMK_BIN :: compose.mk invocation / exe path
## * CMK_DOCKER_PATH :: Where compose.mk is mounted inside a dispatch container
## * CMK_DIND_SRC :: compose.mk include-path for host + in-container DIND runs
##
## __dunders__ (interpreter state, exported):
## * __interpreter__ :: Invocation path (== CMK_BIN)
## * __interpreting__ :: CMK_SRC unless overridden
## * __file__ :: CMK_SRC (standalone) or the invoked file (library)
## * __script__ :: Interpreted script path (None if not interpreting)
##
## * CMK_PRE / CMK_POST :: Targets run before / at end of the run (m4wrap)
## * CMK_YIELD_HOOK :: Yield seam (subshell, failure swallowed); default true
## * CMK_SUPERVISOR_STEP_HOOK :: Supervisor step-trampoline hook
##
## * CMK_COMPOSE_FILE :: Temp file for the embedded TUI
## * DOCKER_HOST_WORKSPACE / workspace :: DIND volume workspace path (override)
## * COMPOSE_IGNORE_ORPHANS :: Honored by docker compose to quiet output
## * GITHUB_ACTIONS :: true if running inside GitHub Actions
## * DEBIAN_CONTAINER_VERSION / ALPINE_VERSION :: Default base image versions
## * IMG_CARBONYL / IMG_NUSHELL / IMG_IMGROT / IMG_MONCHO_DRY :: Pinned tool images
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Exported knobs: order-independent ?= defaults, overridable from env.
$(call m5.declare!, \
	CMK_COMPILER_VERBOSE?=1, COMPOSE_IGNORE_ORPHANS?=True, CMK_COMPOSE_FILE?=.tmp.compose.mk.yml, CMK_DIND?=0, \
	CMK_INTERNAL?=0, CMK_IN_CONTAINER?=0, CMK_SUPERVISOR?=1, CMK_EXTRA_REPO?=., \
	CMK_LOG_IMPORTS?=0, CMK_IMPORT_DISCOVER?=0, GITHUB_ACTIONS?=false, \
	DEBIAN_CONTAINER_VERSION?=debian:bookworm, ALPINE_VERSION?=3.21.2)
# Below: an ORDERED bootstrap (paths, interpreter-state, lib/standalone) -- keep in order.
export CMK_PRE ?= flux.noop
__cmk_pre__.append = $(eval export CMK_PRE += $(m5[1]))
__cmk_pre__.targets = $(call __pragma__.append, cmk_pre, flux.noop)
export CMK_POST ?= flux.noop
__cmk_post__.append = $(eval export CMK_POST += $(m5[1]))
__cmk_post__.targets = $(call __pragma__.append, cmk_post, flux.noop)
export verbose:=$(shell [ "$${quiet:-0}" == "1" ] && echo 0 || echo $${verbose:-1})

# CMK_LANG: 1=load hosted (default), 0=bypass; env over pragma.
__hosted__.enabled := $(if $(filter 0 false no off,$(call m5|,CMK_LANG,$(call m5|,CMK_PRAGMA_CMK_LANG,1))),0,1)
#export CMK_SRC:=$(filter %compose.mk,${MAKEFILE_LIST})
export CMK_SRC:=$(or $(filter %compose.mk,${MAKEFILE_LIST}),${MAKEFILE})
export CMK_BIN?=${CMK_SRC}
export __interpreter__ ?= ${CMK_BIN}


export CMK_PLUGINS_DIR?=.cmk
export CMK_MODULES_DIR?=$(firstword $(subst :, ,${CMK_PLUGINS_DIR}))
export CMK_STAGE_DIR := $(or $(value CMK_STAGE_DIR),$(shell d='${CMK_MODULES_DIR}'; if [ -d "$$d" ] && [ -w "$$d" ]; then printf %s "$$d"; elif [ ! -e "$$d" ] && $(if $(filter file,$(origin CMK_MODULES_DIR)),false,true); then printf %s "$$d"; else printf %s '${CMK_XDG_CACHE}'; fi))


CMK_NATIVE_CACHE ?= ${CMK_STAGE_DIR}/native
# stage a make value to a native-cache file, ensuring the dir; write-if-changed via a pid temp so a concurrent reader never sees a truncated file.
mk.native.stage = $(shell mkdir -p ${CMK_NATIVE_CACHE})$(file >${1}.${_cmk.pid},${2})$(shell if cmp -s "${1}.${_cmk.pid}" "${1}"; then rm -f "${1}.${_cmk.pid}"; else mv -f "${1}.${_cmk.pid}" "${1}"; fi)
$(call m5.declare, CMK_SANDBOX?=, CMK_SANDBOX_SRC?=, CMK_YIELD_HOOK?=true, CMK_SUPERVISOR_STEP_HOOK?=flux.noop)

export __interpreting__?=

# One id per run: memoized in place, so the unsupervised path mints it once instead of per read.
_mk.run.id=$(if $(call m5.defined?,MAKE_SUPER),${MAKE_SUPER},$(shell uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N))
$(call m5.marm, _mk.run.id)
ifeq ($(origin CMK_IO_STACK),undefined)
export CMK_IO_STACK := .tmp.cmk.stack.${_mk.run.id}
endif
ifeq ($(origin CMK_BRF_PREFIX),undefined)
export CMK_BRF_PREFIX := .tmp.cmk.brf.${_mk.run.id}
endif
ifeq ($(origin CMK_SCRATCH),undefined)
export CMK_SCRATCH := .tmp.cmk.scratch.${_mk.run.id}
endif

##
export __script__?=None
export __file__?=$(word 1, $(MAKEFILE_LIST))
.DEFAULT_GOAL:=__main__

ifneq ($(findstring compose.mk, ${MAKE_CLI}),)
export CMK_LIB=0
export CMK_STANDALONE=1
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


# Used internally.  If this is container-dispatch and DIND,
# then DOCKER_HOST_WORKSPACE should be treated carefully
ifeq ($(or $(CMK_DIND),0), 1)
export workspace?=$(shell echo ${DOCKER_HOST_WORKSPACE})
# freeze to simple: this sh spawn hides from path-level tracing but is still paid per child under make 4.4
export workspace:=$(workspace)
export CMK_INTERNAL=0
endif

# docker.cmk.bin: the interpreter's exec-ready in-container path, from the include-oriented CMK_DIND_SRC.
docker.cmk.bin=$(if $(filter /%,${CMK_DIND_SRC}),${CMK_DIND_SRC},./${CMK_DIND_SRC})
docker.env.standard=-e DOCKER_HOST_WORKSPACE=$${DOCKER_HOST_WORKSPACE:-$${PWD}} -e TERM=$${TERM:-xterm} -e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE} -e CMK_IO_STACK=$${CMK_IO_STACK} -e __file__="$${__file__:-}" -e __cmk__="$${__cmk__:-}" -e __interpreter__="${docker.cmk.bin}" ${docker.env.ambient}
# the ambient chain rides the same crossing as the io-stack: run-scoped state a nested dispatch must see.
docker.env.ambient=-e __ambient__="$${__ambient__:-}" -e __ambient_stack__="$${__ambient_stack__:-}" -e __ambient_parent__="$${__ambient_parent__:-}"

ifeq (${TRACE},1)
$(shell printf "trace=$${TRACE} quiet=$${quiet} verbose=$${verbose:-} ${yellow}CMK_INTERNAL=$${CMK_INTERNAL} CMK_DIND=$${CMK_DIND} $(if $(filter 0,$(__hosted__.enabled)),${GLYPH_LANG_OFF}CMK_LANG=0 ,)${MAKE_CLI}${no_ansi}\n" > /dev/stderr)
endif 


# Tool container images (pinned; override from environment).
$(call m5.declare, \
	IMG_CARBONYL?=fathyb/carbonyl, IMG_NUSHELL?=ghcr.io/nushell/nushell:latest-alpine, IMG_IMGROT?=robotwranglers/imgrot:07abe6a, \
	IMG_MONCHO_DRY=moncho/dry@sha256:6fb450454318e9cdc227e2709ee3458c252d5bd3072af226a6a7f707579b2ddd, IMG_GUM?=v0.16.0, \
	IMG_CURL=curlimages/curl:8.13.0, IMG_TUX_PROGRESS?=ghcr.io/mattvonrocketstein/tux.progress:0.0.21, \
	IMG_JQ?=ghcr.io/jqlang/jq:1.7.1, IMG_YQ?=mikefarah/yq:4.43.1, IMG_GLOW?=charmcli/glow:v1.5.1)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.seed :: The seed / allocation engine (over the m5 substrate)
##
## Reify a define into a self-evaling seed, then force it into an instance:
## fill / capture is the m5 layer; grow! / materialize! do the forcing.
##
## * lang.seed :: The base allocation-body seed (installs an instance .__tmpl)
## * lang.ctor.__new__ :: the plain constructor reify (folded here)
## * lang.seed.grow! :: The force atom: bind-then-force (eval the call)
## * m5.tmpl!/* :: Fold: materialize a tmpl body over each of a list
## * lang.seed.materialize! :: Materialize capability tmpls onto an instance
## * lang.seed.ns :: The ns-prefixed instance seed
## * lang.seed.ns! :: Reify the ns-prefixed seed
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

define lang.seed
$(m5[1]).__tmpl = $$(eval self := $$(or $$(call m5.ctx?,$$(1),namespace),$$(call m5.ctx?,$$(1),def),$$(firstword $$(1))))$$(eval $${self}.__ctor__ := $(m5[1]))$$(eval $$(call m5.tmpl/seed,$(m5[1]).__body,$$(1),$$(foreach _kv,$$(filter def%,$$(1)),$$(word 2,$$(subst =, ,$$(_kv))))))$$(eval $${self}.__dir__ := $$(sort $$(patsubst $${self}.%,%,$$(filter $${self}.%,$$(.VARIABLES)))))
$$(call m5.def.!,$(m5[1]),$(m5[1]).__tmpl)
endef
lang.seed.grow! = $(eval $(call $(1),$(2),$(m5[3]?),$(m5[4]?)))
m5.tmpl!/* = $(foreach _b,$(3),$(call m5.tmpl!,$(strip $(_b)),$(2),$(m5[1])))

lang.seed.materialize! = $(call m5.tmpl!/*,$(m5[1]),def=$(m5[1]),$(m5[2]))

define lang.seed.ns
$(eval _udef := $(m5[1][def]))
$(call m5.def!,$(_udef).__body,$(value $(_udef)))
$(_udef).__tmpl = $$(call m5.tmpl!,$(_udef).__body,$$(1),$(m5[1][nsprefix]).$$(foreach _kv,$$(filter def%,$$(1)),$$(word 2,$$(subst =, ,$$(_kv)))),$$(foreach _kv,$$(filter def%,$$(1)),$$(word 2,$$(subst =, ,$$(_kv)))))
$$(call m5.def.!,$(_udef),$(_udef).__tmpl)
endef
lang.seed.ns! = $(call lang.seed.grow!,lang.seed.ns,${1})

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.ctor :: The constructor factory (allocate + configure)
##
## The generic constructor kind, built on the seed engine: __new__ allocates by
## reifying the seed; the verb runs __new__ then the class metaclass stamp and
## reflection.  (lang.ctor.__init__ decomposition is pending.)
##
## * lang.ctor! :: The constructor factory verb (allocate + configure)
## * lang.ctor.__new__ / .__init__ :: Allocate then configure
## * lang.ctor.ns_prefix :: Compute an instance namespace prefix
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.ctor! = $(call lang.ctor.__new__,${1})$(call lang.ctor.__init__,${1})

lang.ctor.__new__ = $(eval _snd := $(m5[1][def]))$(eval _snp := $(call lang.ctor.ns_prefix,$(_snd),$(m5[1][ns])))$(if $(_snp),$(call lang.seed.ns!,def=$(_snd) nsprefix=$(_snp)),$(call m5.self!,$(_snd))$(call m5.def!,$(_snd).__body,$(value $(_snd)))$(call m5.def!,$(_snd).__ctor_src__,$(value $(_snd)))$(call m5.set,__ctor_initkw__,)$(eval $(_snd).__ctor_copy__ = $$(eval define $$(strip $$1)$${nl}$$(value $(_snd).__ctor_src__)$${nl}endef)$$(call lang.ctor.__new__,def=$$(strip $$1)))$(call lang.seed.grow!,lang.seed,$(_snd)))

lang.ctor.__init__ = $(call m5.self!,$(_snd))$(call m5.set,__metaclass__,constructor)$(call m5.set,__mcls_kwargs__,$(filter-out def=%,${1}))$(call m5.set,__mcls_mint_ns__,$(_snp))$(call lang.class.classvar!/*,$(filter-out def=%,${1}),$(_snd))$(call m5.tmpl!,lang.class.__init__,$(call m5.lex.rev,$(subst $(comma),$(space),$(filter-out MKID_NONE,$(m5[1][bases])))),$(_snd))$(eval $(_snd).__mixins := $(strip $($(_snd).__mixins) $(_snd)))

# lang.ctor.ns_prefix: compute an instance namespace prefix
lang.ctor.ns_prefix = $(if $(m5[2]),$(if $(filter .,$(m5[2])),$(m5[1]),$(m5[2])))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.class :: The class-kind metaclass engine
##
## Constructs and reflects a cmk class: reflection stamp, recipe-target
## inheritance, the fork-free class-body desugar, and the metaclass tail.
##
## * lang.class! :: The class-kind verb (grow a seed, or the umbrella path)
## * lang.class.__new__ :: Allocate: grow the class seed (reflection init is intrinsic)
## * lang.class.__init__ :: Stamp a kind reflection (mixins / bases / mro)
## * define lang.type :: The class-body metaclass template
## * lang.class.classvar / .classvar!/* :: declare / fold classvars=
## * lang.class.copy :: Rebuild a class under a new name
## * children / childtest.default relocated to lang.module section
##
## * lang.class.umbrella / .umbrella! :: Mint a class child under a ns, bind its leaf
## * lang.class.target.manifest / .manifest.ensure :: List + memoize a class recipe targets
## * lang.class.shadowclean / .rec :: Keep-first dedup of the mixin-chain targets
## * lang.class.mixin.effective / .clean :: Drop a redundant self-target on a real override
##
## * lang.class.comp.self.* :: Fork-free self.x desugar: preprocess + a spec for m5.auto[look-ahead]
## * lang.class.comp.classvar.* :: Fork-free bare-classvar lowering (lower / line / dirty)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lang.class.__new__ = $(call lang.seed.grow!,lang.type,${1})
lang.class! = $(if $(filter-out MKID_NONE,$(m5[1][umbrella])),$(call lang.module!,$(m5[1][def]))$(eval $(m5[1][def]) = $$(call lang.class.umbrella!,$(m5[1][def]),$$(m5.__splat__))),$(call lang.class.__new__,${1}))

#  stamps a kind's reflection (mixins/bases/mro) so the class and
# constructor engines spell bases identically.  The faces below route through
# lang.seed.grow!; the dsl face adds cmk.Fragment and an optional runtime backing.
define lang.class.__init__
${self}.__mixins := $(foreach _w,${1},$(if $(call m5.defined?,$(_w).__mixins),$($(_w).__mixins),$(_w)))
${self}.__bases__ := $(strip $(call m5.lex.rev,$(call m5.select,${1},%.__mixins)))
${self}.__mro__ := $(sort ${self} $(foreach _pb,$(${self}.__bases__),$($(_pb).__mro__)))
${self}.__ifaces__ := $(strip $(subst $(comma),$(space),$(call m5.ctx?,$(${self}.__ctor_initkw__),ifaces)))
endef

# The OOP metaclass over its own class-body template: first word names the class, the
# rest its mixin chain (order = linear MRO; a chain-word that is-a class adds its own
# chain).  Each instance binds self + reflection dunders; list or banana form.
define lang.type
$(eval _cdef := $(m5[1][def]))
$(eval _cn := $(or $(_cdef),$(firstword $(1))))
$(if $(_cdef),$(call m5.def!,$(_cn).__mixin,$(value $(_cn))))
$(eval $(_cn).__ctor_initkw__ := $(1))
# bases = tail words, `bases=` stripped; `bases=A,B`, `bases=A`, bare `A B` all read the same.
# m5.lex.rev reverses them: cmk resolves last-wins (shadowclean), so reversing makes the LEFTMOST
# base win (Python L-to-R MRO); __bases__ is un-reversed in 
# Default base: a no-bases class gets Loggable (a name-bound logger) free -- guarded to fire only
# once Loggable is minted, never for Loggable/Named, nor protocols (they mint via cmk.protocol).
$(eval _ctail := $(wordlist 2,$(words $(1)),$(1)))
$(eval _cifc := $(subst $(comma),$(space),$(patsubst ifaces=%,%,$(filter ifaces=%,$(_ctail)))))
$(eval _cdecl := $(subst $(comma),$(space),$(patsubst bases=%,%,$(filter-out ifaces=% classvars=%,$(_ctail)))))
$(if $(strip $(_cdecl)),,$(if $(call m5.defined?,Loggable.__mixins),$(if $(filter $(_cn),Loggable Named),,$(eval _cdecl := Loggable))))
$(eval _cdecl := $(strip $(_cdecl) $(_cifc)))
$(eval _craw := $(call m5.lex.rev,$(_cdecl)) $(if $(_cdef),$(_cn).__mixin))
$(if $(filter $(_cn),$(_craw)),$(call mk.error, cmk: class `$(_cn)` cannot list itself as a base, errno=CLASS_DECL))
# the trait-composition reflection (`.__mixins`/`.__bases__`/`.__mro__`) is stamped by a shared
# step so the constructor minter can spell `bases=` the same way; the own-body mixin is already
# folded into `_craw` above, so the chain passed in is complete.
$(call m5.tmpl!,lang.class.__init__,$(_craw),$(_cn))
$(call lang.class.classvar!/*,$(1),$(_cn))
$(eval _cmix := $($(_cn).__mixins))
# resolve recipe-target overrides: strip any base mixin's target that a more-derived mixin
# redefines, so the capture below emits one recipe per target (no `overriding recipe` warning).
$(eval _cmix := $(call lang.class.shadowclean,$(_cn),$(_cmix)))
# classvar closure: classvars of this class and its mixins.
$(eval _cvars := $(sort $(call m5.pluck,$(_cn) $(_cmix) $(_cifc),%.__classvars__)))
$(_cn).__tmpl = $$(eval self_stack := $$(call m5.stack.push,$$(self),$$(self_stack)))$$(eval self :=$$(or $$(call m5.ctx?,$$(1),namespace),$$(call m5.ctx?,$$(1),def),$$(firstword $$(1))))$$(eval $${self}.__class__ := $(_cn))$(foreach _cv,$(_cvars),$$(eval $${self}.$(_cv) := $(firstword $(call m5.pluck,$(_cn) $(_cmix) $(_cifc),%.$(_cv)))))$$(eval $${self}.__ctor__ := $(_cn))$$(eval $${self}.__im_self__ := $${self})$$(eval $${self}.%: self := $${self})$(foreach _b,$(_cmix),$$(eval $$(call m5.tmpl/seed.self,$(strip $(_b)),$$(1),$${self})))$$(if $$(filter-out undefined,$$(origin $${self}.__raw_body__)),,$$(if $$(value $${self}),$$(eval $$(call m5.tmpl/seed.self,$${self},$$(1),$${self}))$$(if $$(filter-out undefined,$$(origin $${self}.__isprotocol__)),,$$(eval undefine $${self}))))$$(eval $${self}.__dir__ := $$(sort $$(patsubst $${self}.%,%,$$(filter $${self}.%,$$(.VARIABLES)))))$$(if $$(filter-out undefined,$$(origin $${self}.__minted__)),$$(eval $$(call $${self}.__minted__,$$(1))))$$(eval self := $$(call m5.stack.top,$$(self_stack)))$$(eval self_stack := $$(call m5.rest,$$(self_stack)))
$$(call m5.def.!,$(_cn),$(_cn).__tmpl)
endef

# Recipe-target inheritance: let a subclass override a base recipe target without make's
# `overriding recipe` warning.  target.manifest lists the target suffixes in PURE make (no
# fork: it runs for every class on every parse).  .awk.self.strip does the block removal,
# but only on a real override (off the hot path for current classes).
lang.class.target.manifest = $(sort $(patsubst self%,%,$(patsubst $(lang.grammar.token_self)%,%,$(patsubst $(lang.grammar.token_self),__self__,$(patsubst %:,%,$(patsubst %:;,%,$(filter-out $(lang.grammar.token_self).__doc__% self.__doc__%,$(filter $(lang.grammar.token_self)%: $(lang.grammar.token_self)%:; self.%: self.%:;,$(value $(m5[1]))))))))))
lang.class.manifest.ensure = $(call m5.self!,$(m5[__self__]))$(if $(call m5.defined?,$(m5[1]).__targets__),,$(call m5.set,__targets__,$(call lang.class.target.manifest,$(m5[1]))))
# dedup the mixin chain keep-FIRST: a diamond lists a shared base twice; without this it
# is captured twice (double-stamping targets = `overriding recipe`).  Keep-first pins it at
# its earliest slot, matching Python MRO (a base sits after all its subclasses).
lang.class.shadowclean = $(eval _scu := $(call m5.lex.uniq,$(2)))$(foreach _m,$(_scu),$(call lang.class.manifest.ensure,$(_m)))$(strip $(call lang.class.shadowclean.rec,$(1),$(_scu)))
lang.class.shadowclean.rec = $(if $(m5[2]),$(call lang.class.mixin.effective,$(1),$(firstword $(2)),$(sort $(foreach _l,$(wordlist 2,$(words $(2)),$(2)),$($(strip $(_l)).__targets__)))) $(call lang.class.shadowclean.rec,$(1),$(wordlist 2,$(words $(2)),$(2))))
lang.class.mixin.effective = $(if $(filter $(3),$($(m5[2]).__targets__)),$(call lang.class.mixin.clean,$(1),$(2),$(filter $(3),$($(m5[2]).__targets__))),$(m5[2]))
# the clone path, fired only on a real recipe-target override (inert for current classes).
# Its awk+input scratch is lazy and keyed on $$PPID (the make pid), so concurrent sub-makes
# can't collide on a fixed name; the scratch is written and removed within this one call.
lang.class.mixin.clean = $(eval _claw := .tmp.cmk.awk.self.strip.${_cmk.pid})$(eval _clnm := _cmk.clean.$(m5[1]).$(subst /,_,$(subst .__mixin,,$(m5[2]))))$(eval _clin := .tmp.cmk.cclin.$(subst /,_,$(subst .,_,$(m5[2]))).${_cmk.pid})$(eval _cldrop := $(subst /,_,$(subst .,_,$(subst ${space},-,$(strip $(m5[3]))))))$(file > $(_claw),$(value .awk.self.strip))$(file > $(_clin),$(value $(m5[2])))$(eval _clout := $(shell set -- `cat $(_clin) $(_claw) | cksum`; o=.tmp.cmk.mixin.$(subst /,_,$(subst .,_,$(m5[2]))).$(_cldrop).$$1-$$2.mk; [ -f "$$o" ] || { awk -v drop='$(m5[3])' -f $(_claw) $(_clin) > $$o.${_cmk.pid} 2>/dev/null && mv -f $$o.${_cmk.pid} $$o || o=$$o.${_cmk.pid}; }; rm -f $(_claw) $(_clin); echo $$o))$(eval define $(_clnm)$(nl)$(file < $(_clout))$(nl)endef)$(_clnm)

# class umbrella under arg1; _qualified = out-param (read post-mint)
lang.class.umbrella = $(call m5.self!,$(m5[__self__]))$(call lang.module!,$1)$(eval _given := $(call m5.ctx?,$2,def))$(eval _qualified := $(if $(findstring .,$(_given)),$(_given),$(m5[1]).$(_given)))$(if $(filter $(m5[1]).%,$(_qualified)),$(eval _leaf := $(patsubst $(m5[1]).%,%,$(_qualified)))$(if $(filter $(_leaf),$($(m5[1]).__all__)),,$(call m5.set.op,__all__,+=,$(_leaf)))$(if $(filter $(_qualified),$(_given)),,$(eval define $(_qualified)$(nl)$(value $(_given))$(nl)endef)),)$(patsubst def=$(_given),def=$(_qualified),$2)

# mint an umbrella child then alias its bare leaf into the scope
lang.class.umbrella! = $(call lang.class!,$(call lang.class.umbrella,$1,$2))$(if $(filter $(m5[1]).%,$(_qualified)),$(call lang.module.bind,$1,$(patsubst $(m5[1]).%,%,$(_qualified))),)

# -- lang.class.comp + lang.mk: class-body self/classvar desugar (no fork) --
lang.class.comp.self.xform = $(if $(call m5.defined?,$(1).__xf__),,$(eval define $(1).__xf__$(nl)$(call m5.quasi.protect,$(call lang.class.comp.self.xform.raw,$(1)))$(nl)endef))$(call m5.quasi.restore,$(value $(1).__xf__))
lang.class.comp.self.xform.raw = $(call lang.class.comp.classvar.lower,$(if $(findstring self,$(subst $${self},,$(value $(1)))),$(call lang.class.comp.self.tok,$(value $(1))),$(value $(1))))
lang.class.comp.self.tok = $(call m5.lex.line/*,$(1),lang.class.comp.self.line)
# self.hdr: self-target header; SKIP inline `;` via self.walk.
lang.class.comp.self.hdr = $(if $(findstring ;,$(1)),,$(if $(call m5.lex.kwarg?,$(call m5.lex.bare,$(1))),,$(if $(findstring :,$(call m5.lex.bare,$(1))),$(filter self.%,$(call m5.lex.bare,$(1))))))
lang.class.comp.self.line = $(if $(call lang.class.comp.self.hdr,$(1)),$(subst self.,$(m5[dollar]){self}.,$(1)),$(if $(findstring self,$(subst $(m5[dollar]){self},,$(1))),$(call lang.class.comp.self.walk,$(subst $(m5[break]),$(space),$(call m5.lex.tok,$(call lang.class.comp.self.pre,$(1))))),$(1)))
lang.class.comp.self.pre = $(subst $(m5[dollar]){self.,$(m5[dollar]){$(m5[dollar]){self}.,$(subst $(m5[dollar])$(m5.tok.lparen)self.,$(m5[dollar])$(m5.tok.lparen)$(m5[dollar]){self}.,$(1)))
lang.class.comp.self.trigger? = $(filter self.%,$(1))
lang.class.comp.self.emit = $(if $(filter self,$(1)),$(m5[dollar]){self},$(1))
lang.class.comp.self.skip? = $(filter $(m5[space]),$(1))
lang.class.comp.self.mark? = $(filter = : ? +,$(1))
lang.class.comp.self.commit.plain = $(m5[dollar])$(m5.tok.lparen)$(m5[dollar]){self}.$(patsubst self.%,%,$(1))$(m5.tok.rparen)
$(call m5.auto[look-ahead],lang.class.comp.self.walk,lang.class.comp.self.trigger?,lang.class.comp.self.emit,lang.class.comp.self.skip?,lang.class.comp.self.mark?,lang.class.comp.self.commit.mark,lang.class.comp.self.commit.plain)
lang.class.comp.self.commit.mark = $(m5[dollar]){self}.$(patsubst self.%,%,$(1))
lang.class.comp.classvar.lower = $(call m5.lex.line/*,$(1),lang.class.comp.classvar.line)
lang.class.comp.classvar.line = $(if $(filter $(m5[dollar]){self}%,$(call m5.strip,$(1),space)),$(1),$(call lang.class.comp.classvar.line.2,$(1),$(firstword $(call m5.unescape,$(subst $(m5[space])=$(m5[space]),=,$(1)),space))))
lang.class.comp.classvar.line.2 = $(if $(call m5.lex.kwarg?,$(2)),$(if $(call lang.class.comp.classvar.dirty,$(word 1,$(subst =, ,$(2))))$(findstring $(m5[dollar]),$(1))$(findstring $(comma),$(1)),$(1),$(m5[space])$(m5[space])$(m5[dollar])(call$(m5[space])lang.seed.grow!,lang.class.classvar,$(m5[dollar]){self},$(subst $(m5[space])=$(m5[space]),=,$(patsubst $(m5[space])$(m5[space])%,%,$(1))))),$(1))
lang.class.comp.classvar.dirty = $(findstring .,$(1))$(findstring {,$(1))$(findstring [,$(1))$(findstring :,$(1))
lang.class.classvar = $(m5[1]).__classvars__ += $(word 1,$(subst =, ,$2))$(if $(word 2,$(subst =, ,$2)),$(nl)$(m5[1]).$(word 1,$(subst =, ,$2)) := $(patsubst $(word 1,$(subst =, ,$2))=%,%,$2))
lang.class.classvar!/* = $(foreach _p,$(call _mk.kwargs.getd,$1,classvars),$(call lang.seed.grow!,lang.class.classvar,$2,$(_p)))
lang.class.copy = $(eval define $(m5[2])$(nl)$(value $(m5[1]).__mixin)$(nl)endef)$(call lang.class!,$(subst def=$(m5[1]),def=$(m5[2]),$(value $(m5[1]).__ctor_initkw__)))


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.module :: Namespace membership / bare-name binding
##
## A module is a `.__all__` registry whose members bind to bare names.
##
## * lang.module.core :: The registry: every namespace carrying a `.__all__`
## * lang.module! :: Install the `.__open__` / `.__dir__` accessors
##
## * lang.module.bind :: Copy members to bare names.
##     A cold miss defers; a remake rebinds.  Errors on a non-member once the
##     hosted cache is loaded.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.module.core = $(patsubst %.__all__,%,$(filter %.__all__,$(.VARIABLES)))

lang.module! = $(call m5.self!,$(m5[__self__]))$(if $(call m5.defined?,$(m5[1]).__open__),,$(call m5.set.op,__all__,?=,)$(eval $(m5[__self__]).__open__ = $$(call lang.module.bind,$(m5[1]),$$(or $$(strip $${1}),$$($(m5[1]).__all__))))$(eval $(m5[__self__]).__dir__ = $$(sort $$(patsubst $(m5[1]).%,%,$$(filter $(m5[1]).%,$$(.VARIABLES))))))

lang.module.bind = $(foreach _n,$(m5[2]),$(if $(or $(call m5.defined?,$(m5[1]).$(_n)),$(filter $(m5[1]).$(_n).%,$(.VARIABLES))),$(if $(call m5.defined?,$(m5[1]).$(_n)),$(eval define $(_n)$(nl)$(value $(m5[1]).$(_n))$(nl)endef),)$(foreach _a,$(filter $(m5[1]).$(_n).%,$(.VARIABLES)),$(eval define $(patsubst $(m5[1]).$(_n).%,$(_n).%,$(_a))$(nl)$(value $(_a))$(nl)endef)),$(if ${__hosted__.loaded},$(call mk.error, cmk: `$(_n)` is not a member of module `$(m5[1])`, errno=MODULE_MEMBER),)))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.dsl :: A class backed by a runtime / machine / entrypoint
##
## A dsl is a class whose instances carry a runtime backing.
##
## * lang.dsl! :: Kind verb / metaclassing.
##     Binds child `dsl <name>` into caller scope, and `dsl.<name>` scope.
## * lang.dsl.__new__ :: Allocate fragment, pass to initialize
## * lang.dsl.__init__ :: Initialize runtime from { machine | entrypoint | img }
##
## * lang.dsl.machine.proxy :: Runtime half of a machine-backed dsl.
##     An ambient, specifically a bound machine (.__in__) runs the shape 
##     as a def through machine-dispatch (args as argv). A bare bound
##     target runs it as a file.  Shared by the fragment call/stream dunders.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.dsl! = $(call lang.dsl.__new__,$(call lang.class.umbrella,dsl,${1}))$(if $(filter dsl.%,$(_qualified)),$(call lang.module.bind,dsl,$(patsubst dsl.%,%,$(_qualified))),)

# dsl.export!: publish a dsl class's listed body members as class attributes for lookups.
dsl.export! = $(eval $(strip $1).__all__ := $2)$(eval $(call $(strip $1), def=$(strip $1).__spec))$(foreach _m,$2,$(eval $(strip $1).$(_m) = $$($(strip $1).__spec.$(_m))))

lang.dsl.__new__ = $(call lang.seed.grow!,lang.type,def=$(m5[1][def]) bases=$(if $(filter-out MKID_NONE,$(m5[1][bases])),$(filter-out MKID_NONE,$(m5[1][bases]))$(comma))cmk.Fragment$(if $(filter-out MKID_NONE,$(m5[1][ifaces])), ifaces=$(filter-out MKID_NONE,$(m5[1][ifaces])))$(if $(filter-out MKID_NONE,$(m5[1][classvars])), classvars=$(m5[1][classvars])))$(call lang.dsl.__init__,${1})

lang.dsl.__init__ = $(if $(filter-out MKID_NONE,$(m5[1][machine])),$(eval $(m5[1][def]).__machine__ := $(m5[1][machine])),$(if $(filter-out MKID_NONE,$(m5[1][bind])),$(eval $(m5[1][def]).__machine__ := $(m5[1][bind])),$(if $(strip $(patsubst MKID_NONE,,$(m5[1][entrypoint]))$(patsubst MKID_NONE,,$(m5[1][img]))),$(if $(call m5.defined?,cmk.machine),$(call cmk.machine, def=$(m5[1][def]).machine $(strip $(foreach _k,entrypoint img cmd feed flag,$(if $(filter-out MKID_NONE,$(call m5.ctx?,${1},$(_k))),$(_k)=$(call m5.ctx?,${1},$(_k)),))))$(eval $(m5[1][def]).__machine__ := $(m5[1][def]).machine),$(if $(or $(filter-out 1,$(__hosted__.enabled)),${__hosted__.loaded}),$(call mk.error, cmk: `dsl $(m5[1][def])` machine-backing needs the machine kind (minted by the hosted partition), errno=DSL_BACKING),)))))

lang.dsl.machine.proxy = $(if $(call m5.defined?,$(m5[1]).__in__),CMK_LAMBDA_ARGV="$(m5[2])" $(call $(m5[1]).__in__,$(m5[3]).shape),${make} io.with.file/$(m5[3]).shape/$(m5[1]))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.proto :: The protocol metaclass / capability seed-bodies
##
## The protocol data model: a metaclass, plus the capability bodies that named
## protocols mix in via ifaces= (materialized by lang.seed.materialize!).
##
## * lang.proto.registry :: Explicitly-registered conformers
## * lang.proto.provided_by :: Structural conformance check
## * lang.proto.__new__ :: Type identity + defining dunder
## * lang.proto.__init__ :: Reflection: bases / mro / mixins / abstract set
## * lang.proto.tmpl.callable :: __call__ default (a bare X() errors)
## * lang.proto.tmpl.materializable :: Freeze body: raw flag + shape + blockref
##
## * lang.proto.tmpl.templatable :: Fill the shape with call args.
##     __fill__ / __mod__ / render build a filled body from the call args.
## * lang.proto.tmpl.feedable :: How a program file reaches its entrypoint.
##     feed / feed_flag: a trailing file arg (default), stdin, or after a flag;
##     read from the decl keywords or the instance body.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.proto.registry :=
lang.proto.provided_by=$(if $(filter-out $(call m5.select,$($(m5[1]).abstract),$(m5[2]).%),$($(m5[1]).abstract)),$(if $(filter $(m5[2]),$($(m5[1]).registry)),1,),1)
lang.proto.__new__ = $(call m5.self!,$(m5[__self__]))$(call m5.set,__isprotocol__,1)$(call m5.set.op,dunder,?=,$(call m5.ctx?,$2,dunder))$(call lang.class.classvar!/*,$2,$(m5[1]))
lang.proto.__init__ = $(call m5.self!,$(m5[__self__]))$(call m5.set.op,__bases__,?=,$(subst :,$(space),$(subst $(comma),$(space),$(call m5.ctx?,$2,bases))))$(call m5.set.op,__ifaces__,?=,$(subst :,$(space),$(subst $(comma),$(space),$(call m5.ctx?,$2,ifaces))))$(call m5.set,__ifmix,$(foreach _if,$($(m5[1]).__ifaces__),$(if $(call m5.defined?,$(_if).__mixins),$($(_if).__mixins),$(_if))))$(call m5.set.op,__mro__,?=,$(sort $(m5[1]) $(foreach _pb,$($(m5[1]).__bases__),$($(_pb).__mro__))))$(call m5.set.op,abstract,?=,$(sort $(subst :,$(space),$(subst $(comma),$(space),$(or $(call m5.ctx?,$2,abstract),$($(m5[1]).dunder)))) $(foreach _pb,$($(m5[1]).__bases__),$($(_pb).abstract))))$(call m5.set.op,__concretized__,?=,$(if $(or $(findstring $(lang.grammar.token_self).,$(subst $(lang.grammar.token_self).__doc__,,$(value $(m5[1])))),$(findstring self.,$(subst $(lang.grammar.token_self).__doc__,,$(value $(m5[1])))),$(strip $($(m5[1]).__ifmix))),1,))$(call m5.set,__mixins,$(strip $($(m5[1]).__ifmix) $(if $($(m5[1]).__concretized__),$(m5[1]))))

define lang.proto.tmpl.templatable
${self}.__fill__ = $(eval lang.banana.tmp := $(call lang.banana.__mod__,${self}.shape,${__args__}))$(eval $(call $(${self}.__ctor__), def=$(lang.banana.tmp)))$(lang.banana.tmp)
${self}.__mod__ = $(call ${self}.__fill__,$($(strip ${__args__}).shape))
${self}.render = $(call ${self}.__fill__,${__args__})
endef

define lang.proto.tmpl.callable
${self}.__call__ = $(call mk.error, cmk: .__call__ not implemented on `${self}` (Callable): a bare `${self}()` has no invoke -- override .__call__, errno=NOT_CALLABLE)
endef

define lang.proto.tmpl.materializable
${self}.__raw_body__ := 1
${self}.shape := $(value ${self})
${self}.__blockref__ = ${self}.shape
endef

define lang.proto.tmpl.feedable
${self}.feed ?= $(or $(call m5.ctx?,${1},feed),$(call m5.ctx?,$(value ${self}),feed),file)
${self}.feed_flag ?= $(or $(call m5.ctx?,${1},flag),$(call m5.ctx?,$(value ${self}),flag))
endef

define lang.proto.tmpl.directory
${self}.__children__ = $(call lang.proto.tmpl.directory.children,${self})
endef
lang.proto.tmpl.directory.childtest.default=$(call isinstance,$(m5[1]).$(m5[2]),$(call m5|,$(m5[1]).__class__,cmk.namespace))
lang.proto.tmpl.directory.children=$(foreach _p,$(sort $(foreach _l,$(call m5.select,$(patsubst $(m5[1]).%,%,$($(m5[1]).__all__)),$(m5[1]).%.__ctor__),$(if $(call $(if $(call m5.defined?,$($(m5[1]).__class__).__childtest__),$($(m5[1]).__class__).__childtest__,lang.proto.tmpl.directory.childtest.default),$(m5[1]),$(_l)),$($(m5[1]).$(_l).__line__):$(_l),))),$(lastword $(subst :, ,$(_p))))


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.banana :: The banana noun / reified (| .. |) bodies
##
## What the seed engine grows ONTO: a (| .. |) body reified to a fragment
## kind with a string algebra (fill @@holes@@, + concat, | pipe).
##
## * lang.banana.new! :: Gensym a define + run the ctor (raw = verbatim)
## * lang.banana.as :: Reify a banana as a named target (shape + ctor/clone)
## * lang.banana.clone.pipe :: Clone a pipe banana (stream / shape / pipe)
## * lang.banana.concat :: Concatenate two shapes into a new banana
## * lang.banana.fill :: Fill @@holes@@ from k=v args (over m5.quasi%)
## * lang.banana.__mod__ :: Fill the shape into a fresh __frag_N (render / %)
## * lang.banana.fragment! :: The fragment ctor (grown from the seed)
##
## * lang.banana.fragment :: The default reified kind.
##     Materializable + templatable; __ctor__, __add__ (concat), and fd / file
##     handles for shell redirection.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.banana.new! = $(eval lang.banana.seq += x)$(eval define __frag_$(words $(lang.banana.seq))$(nl)$(if $(filter raw,${3}),$(value $(m5[2])),$($(m5[2])))$(nl)endef)$(eval $(call $(m5[1]), def=__frag_$(words $(lang.banana.seq))))__frag_$(words $(lang.banana.seq))
lang.banana.as = $(call m5.def!,$(m5[1]),$(value $(m5[2]).shape))$(if $(call m5.defined?,$(m5[2]).__clone__),$(call $(m5[2]).__clone__,$(m5[1])),$(eval $(call $($(m5[2]).__ctor__), def=$(m5[1]))))
lang.banana.clone.pipe = $(call m5.self!,$(m5[__self__]))$(call m5.set.op,stream,=,$(value $(m5[2]).stream))$(eval $(m5[__self__]).shape = $$($(m5[1]).stream))$(call m5.set,__ctor__,code.pipe)$(eval $(m5[__self__]).__pipe__ = $$(call code.pipe,$(m5[1]),$$(strip $${__args__})))$(eval $(m5[__self__]).__clone__ = $$(call lang.banana.clone.pipe,$$(strip $${1}),$(m5[1])))
lang.banana.concat = $(call m5.def!,lang.banana.jtmp,$(value $(m5[1]).shape)$(nl)$(value $(m5[2]).shape))$(call lang.banana.new!,$($(m5[1]).__ctor__),lang.banana.jtmp,raw)

lang.banana.fill = $(if $(m5[2]),$(call lang.banana.fill,$(call m5.quasi%,${1},$(firstword $(subst =, ,$(firstword ${2}))),$(patsubst $(firstword $(subst =, ,$(firstword ${2})))=%,%,$(firstword ${2}))),$(wordlist 2,$(words ${2}),${2})),${1})
lang.banana.__mod__ = $(eval lang.banana.seq += x)$(eval define __frag_$(words $(lang.banana.seq))$(nl)$(call lang.banana.fill,$(value $(m5[1])),${2})$(nl)endef)__frag_$(words $(lang.banana.seq))

define lang.banana.fragment
$(eval _lsf_ns := $(or $(m5[1][def]),$(firstword ${1})))
$$(call lang.seed.materialize!, $(_lsf_ns), lang.proto.tmpl.materializable)
$$(call lang.seed.materialize!, $(_lsf_ns), lang.proto.tmpl.templatable)
$(_lsf_ns).__ctor__ := lang.banana.fragment!
$(_lsf_ns).__add__ = $$(call lang.banana.concat,$(_lsf_ns),$$(strip $${__args__}))
$(_lsf_ns).fd = <($$(call _mk.def.to.fd, $(_lsf_ns)))
$(_lsf_ns).file = $$(call _mk.def.tmpfile, $(_lsf_ns))
endef
$(call m5.def.!, lang.banana.fragment!, lang.banana.fragment)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: cmk.prelude :: The banana declaration keywords (the surface)
##
## One wrapper per engine face, bound bare by open cmk; each rejoins
## args via m5.__splat__ first, so a comma in bases= can't split it.
##
## * cmk.class / cmk.constructor / cmk.dsl :: kinds (dsl = metaclass)
## * cmk.import :: lowers the import directive (hard-errors on miss)
## * cmk.__all__ :: names bound bare by open / star-import
## * __args__ / __target__ :: instance ambient vars (args / target)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
cmk.class       = $(call lang.class!, $(m5.__splat__))
cmk.constructor = $(call lang.ctor!, $(m5.__splat__)$(if $(filter-out MKID_NONE,$(call m5.ctx?,$(m5.__splat__),umbrella)),$(if $(filter ns=%,$(m5.__splat__)),, ns=.)))
cmk.dsl         = $(call lang.dsl!, $(m5.__splat__))

__args__=$(m5[1]?)

__target__=$@

cmk.__all__ := class constructor container machine dsl namespace module protocol Dockerfile dockerfs Actor

cmk.import=$(foreach _imp,$(m5[1]),$(call lang.module.import.one,$(strip ${_imp})))
# __open__/__dir__ minting moved down, after all __all__ decls
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: tools :: Third-party CLI helpers (jq / yq / jb / glow)
##
## `jq`, `yq`, and `jb` (json.bash) for JSON/YAML, plus `glow` for rendering
## markdown.  Each prefers a local binary on PATH and falls back to a pinned,
## dockerized version otherwise, so recipes reach for them uniformly without a
## hard host dependency.  The docker fallback warns once per run
## (log.warn.once).  The `.run` forms are the resolved, memoized commands;
## bare handles are the conventional entrypoints.
##
## DOCS:
##  * `[1]:` [jq](https://github.com/jqlang/jq)
##  * `[2]:` [yq](https://github.com/mikefarah/yq)
##  * `[3]:` [json.bash / jb](https://github.com/h4l/json.bash)
##  * `[4]:` [glow](https://github.com/charmbracelet/glow)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# tools module: jq/yq/jb/glow, flat-importable (SSOT tools.*).
tools.__all__ := jq yq jb glow

# tools.warn.fallback <key> <msg> <cmd>: docker fallback that warns ONCE per run
# at exec-time (not when the handle is merely interpolated), then execs <cmd>.
# `exec` keeps it transparent to stdin/argv; the once-guard is resolved in-shell
# so the handle stays a stable string across processes.
tools.warn.fallback = sh -c 'M=".tmp.mk.super.$${MAKE_SUPER:-$$PPID}.once.$(strip $(1))"; [ -e "$$M" ] || { : >"$$M" && $(call log.warn,$(2)); }; exec $(3) "$$@"' cmk-$(strip $(1))

# jq/yq: local-first, memoized docker fallback (lazy, probed on use).
tools.jq.docker=${docker.run.base} -e key=$${key:-} ${IMG_JQ}
tools.yq.docker=${docker.run.base} -e key=$${key:-} ${IMG_YQ}
_tools.jq.run.detect=$(shell which jq 2>/dev/null || echo "${tools.jq.docker}")
_tools.yq.run.detect=$(shell which yq 2>/dev/null || echo "${tools.yq.docker}")
_tools.jq.run.pipe.detect=$(shell which jq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} ${IMG_JQ}")
_tools.yq.run.pipe.detect=$(shell which yq 2>/dev/null || echo "${docker.run.base} -i -e key=$${key:-} ${IMG_YQ}")
tools.jq.run=${bin[jq.run]}
tools.yq.run=${bin[yq.run]}
tools.jq.run.pipe=${bin[jq.run.pipe]}
tools.yq.run.pipe=${bin[yq.run.pipe]}
tools.jq=${tools.jq.run}
tools.yq=${tools.yq.run}
tools.jq.slurp.nonempty=${tools.jq.run} -s '[.[] | select(length > 0)]'

# jb: XDG bin before PATH; pure detector, warn attached at exec by tools.jb.run.
tools.jb.docker=docker container run $${docker_extra:-} --rm  ghcr.io/h4l/json.bash/jb:$${JB_CLI_VERSION:-0.2.2}
tools.jb.array=docker_extra="$${docker_extra:-} --entrypoint jb-array"; ${tools.jb.docker}
_tools.jb.run.detect=$(or $(wildcard ${CMK_XDG_CACHE}/bin/jb),$(shell which jb 2>/dev/null || echo "${tools.jb.docker}"))
tools.jb.run=$(if $(findstring ghcr.io/h4l/json.bash,${bin[jb.run]}),$(call tools.warn.fallback,jb,cmk: jb (json.bash) not on PATH; using the dockerized fallback (slower). Run: ${CMK_BIN} tools.init/jb to install.,${tools.jb.docker}),${bin[jb.run]})
tools.jb=${tools.jb.run}$(if $(filter-out undefined,$(origin 1)), $(1),)

# glow: local-first; pure detector, warn attached at exec by tools.glow.run.
GLOW_STYLE?=dracula
tools.glow.docker:=docker run -q -i ${IMG_GLOW} -s ${GLOW_STYLE}
_tools.glow.run.detect=$(or $(patsubst %,% -s ${GLOW_STYLE},$(wildcard ${CMK_XDG_CACHE}/bin/glow)),$(patsubst %,% -s ${GLOW_STYLE},$(shell which glow 2>/dev/null)),${tools.glow.docker})
tools.glow.run=$(if $(findstring ${IMG_GLOW},${bin[glow.run]}),$(call tools.warn.fallback,glow,cmk: glow not on PATH; using the dockerized fallback (slower). See https://github.com/charmbracelet/glow to install locally.,${tools.glow.docker}),${bin[glow.run]})
tools.glow=${tools.glow.run}

# bin[]: tool registry (2-arg detector ref, 3-arg detect/fallback).
$(call m5.mtable, bin)
$(call bin.update, jq.run, _tools.jq.run.detect)
$(call bin.update, yq.run, _tools.yq.run.detect)
$(call bin.update, jq.run.pipe, _tools.jq.run.pipe.detect)
$(call bin.update, yq.run.pipe, _tools.yq.run.pipe.detect)
$(call bin.update, jb.run, _tools.jb.run.detect)
$(call bin.update, glow.run, _tools.glow.run.detect)
$(call bin.update, compose, docker compose >/dev/null 2>&1 && echo docker compose, echo DOCKER-COMPOSE-MISSING)
$(call bin.update, gum.present, which gum >/dev/null 2>&1 && echo 1, 0)
$(call bin.update, curl, which curl, docker run --rm ${IMG_CURL})
$(call bin.update, cols, which tput >/dev/null 2>&1 && echo `tput cols 2>/dev/null`, 50)

# Flat-project the module onto bare names (like import tools flat=1).
$(eval $(call lang.module.bind,tools,$(tools.__all__)))

# Cross-namespace aliases onto the now-flat-bound handles.
stream.glow=${glow.run}
json.from=${jb}
io.json_builder=${jb}

# tools.init/<tool>: install a tool into the XDG bin (first on PATH).
tools.init/%:; @case "${*}" in \
	jb) set -x \
	  && d="${CMK_XDG_CACHE}/bin" && mkdir -p "$$d" && cd "$$d" \
	  && curl -fsSL -O "https://raw.githubusercontent.com/h4l/json.bash/HEAD/json.bash" \
	  && chmod +x json.bash && ln -sf json.bash jb && ln -sf json.bash jb-array \
	  && for name in jb-echo jb-cat jb-stream; do curl -fsSL -O "https://raw.githubusercontent.com/h4l/json.bash/HEAD/bin/$$name" && chmod +x "$$name"; done \
	  && { set +x; $(call log.io, ${green}jb installed${no_ansi_dim} to $$d ${sep} re-run cmk${no_ansi}); } ;; \
	*) $(call log.io, ${yellow}no local installer for ${*}${no_ansi}); exit 1 ;; \
	esac
# jb.init: back-compat alias onto tools.init/jb.
jb.init:; ${make} tools.init/jb


# stand-alone tool wrappers (bare yq/jq/jb/loadf), tool-mode only.
ifeq ($(CMK_STANDALONE),1)
export LOADF = $(value .sh.loadf)
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
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: compose.* :: Targets for docker compose, without the import macro
##
## Basic operations on compose files, like 'build' and 'clean'; scaffolded
## targets chain here in some cases.
##
## DOCS:
##  * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-compose)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# compose._quiet: drop compose's noisy Container/Network status lines.
define compose._quiet
2> >( grep -vE \
		'.*Container.*(Running|Recreate|Created|Starting|Started)' >&2 \
	  | grep -vE '.*Network.*(Creating|Created)' >&2 )
endef

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
# in exactly one place, so every caller (compose.dispatch.sh and all the tux.*
# container runs) stays consistent instead of hand-rolling its own `docker
# compose run`. Inputs (shell env): compose_file, svc, entrypoint (=bash),
# compose_env (extra `-e ..` flags), compose_run_flags (e.g. `-T`). Callers append
# their own tail (`-c "$cmd"` / `-i`) plus ${dash_x_maybe} and $(compose._quiet).
docker.compose.run=${docker.compose} $${COMPOSE_EXTRA_ARGS} -f $${compose_file} run $${compose_run_flags:-} --rm --remove-orphans ${docker.cmk.mount} ${docker.env.standard} $${compose_env:-} --entrypoint $${entrypoint:-bash} $${svc}
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
		-c "$${cmd:-true}" $(compose._quiet)

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
	&& fname=`printf "$${words}" | tr ' ' '\n' | tail -n +2 | head -1` \
	&& words=`printf "$${words}" | tr ' ' '\n' | tail -n +3 | xargs` \
	&& cmd_disp="${dim_cyan}$${words:-(No commands given.  Defaulting to opening UI..)}${no_ansi}" \
	&& header="${dim_green}${underline}$${fname}${no_ansi} ${sep}" \
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
			$(call log.io.part1, ${green}$${header} ${dim}Validating services) \
			&& validation=`$${tmpf} $${stem}.services` \
			&& count=`printf "$${validation}"|${stream.count.words}` \
			&& validation=`printf "$${validation}" \
				| xargs | fmt -w 60 \
				| ${stream.indent} | ${stream.indent}` \
			&& $(call log.base.part2, ${dim_green}ok${no_ansi_dim} ($${count} services total)) \
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
	header="" \
	&& $(call log.trace, $${header}  ${dim}extra="$${COMPOSE_EXTRA_ARGS}") \
	&& $(call log.io.part1, $${header} ${dim}$${label:-Validating compose file} ${sep} ${*}) \
	&& CMK_INTERNAL=1 ${make} compose.services/${*} ${all_devnull} \
	; case $$? in \
		0) $(call log.base.part2, ${GLYPH_CHECK} ok) && exit 0; ;; \
		*) $(call log.base.part2, ${red}failed) && exit 1; ;; \
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

compose.with_profile/%:
	@# Runs the given targets with the given COMPOSE_PROFILE.  
	@# Comma-separated profile-names is "and", not "intersection"!
	@#
	@# USAGE:
	@#   compose.with_profile/<profile>/<t1>,<t2>,..
	@#
	prof=$(call m5.__args__,1,/) \
	targets="`echo '$(call m5.__args__,2-,/)' | ${stream.comma.to.space}`" \
	&& $(call log,$${prof} ${cyan_flow_right} $${targets}) \
	&& COMPOSE_PROFILES=$${prof} ${make} $${targets}


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: docker.* :: Helpers for working with docker
##
## Deliberately minimal, favoring verbs like 'stop' and 'stat' over 'build' and
## 'run': containers managed by docker compose are preferred, but inlined
## Dockerfiles are supported for simple use-cases.  For an example see the
## implementation of `stream.pygmentize`.
##
## DOCS:
##  * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-docker)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# docker._quiet_flag: -q unless quiet=0.
docker._quiet_flag=-q
ifeq ($(quiet), 0)
docker._quiet_flag=
endif

jq.column.zipper=${jq} -R 'split(" ")' \
	| ${jq} '{(.[0]) : .[1]}' \
	| ${jq} -s 'reduce .[] as $$item ({}; . + $$item)' \
	| ${jq} 'to_entries | sort_by(.value) | from_entries' 

# Memoized-lazy: the `docker compose` availability probe runs at most once per
# process, and only when the compose command is actually expanded (a docker /
# compose / TUI target), never on the compile/interpret/flux hot path, which
# re-parses this file ~20x and used to pay this probe on every parse. The cached
# value is byte-identical to the old `:=` result (availability is process-stable).
docker.compose=${bin[compose]}

docker.containers.all:=docker ps --format json

docker.image.entrypoint: 
	@# Returns the current entrypoint for the given image.
	$(call assert.env, img)
	docker inspect $${img} --format='{{.Config.Entrypoint}}'

	
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
	$(if ${OS_MACOS},ipconfig getifaddr en0 || ipconfig getifaddr en1,ip addr show docker0 | grep -Po 'inet \K[\d.]+')
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

docker.build/% docker.from.file/% Dockerfile.from.fs/%:
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

# Live docker build-log filter: drop blanks, dim, indent, unbuffered.
docker.build.log.stream=awk -v pfx="  ${dim}" -v sfx="${no_ansi}" 'NF{print pfx $$0 sfx; fflush()}'

.docker.build/%:
	${trace_maybe} \
	&& case $${quiet:-1} in \
		0) quiet=;; \
		*) quiet=-q;; \
	esac \
	&& set -o pipefail \
	&& ( set -x; docker build $${quiet} $${build_args:-} -t $${tag} $${docker_args:-} -f ${*} . ) \
		2>&1 | ${docker.build.log.stream} 1>&2

docker.commander:
	@# TUI layout providing an overview for docker.
	@# This has 3 panes by default, where the main pane is lazydocker, 
	@# plus two utility panes. Automation also ensures that lazydocker 
	@# always starts with the "statistics" tab open.
	@#
	$(call log.docker, ${no_ansi_dim}Opening commander TUI for docker)
	tui_spec="flux.wrap/docker.stat:.tux.widget.ctop" \
	&& tui_spec="flux.loopf/$${tui_spec},.tux.widget.img.rotate" \
	&& tui_spec=".tux.widget.lazydocker,$${tui_spec}" \
	&& geometry="${GEO_DOCKER}" ${make} tux.open/$${tui_spec}

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

# Content hash (md5) of a Dockerfile define-block's rendered text, to bust the build cache when a def
# changes but its tag/name does not.  Arg 1 is the bare name; `docker.def.name` resolves it, preferring
# `Dockerfile.<name>` when that define exists, else the bare `<name>`.  It probes the prefixed name (not
# the bare one) to avoid a false hit on a same-named macro or target that shadows the bare def name.
# Callers must pass a parse-visible name (a make stem or literal, not a shell var): the choice is made
# at expand time by a definedness probe, blind to runtime values.
docker.def.name=$(if $(call m5.defined?,Dockerfile.$(m5[1])),Dockerfile.$(m5[1]),$(m5[1]))
docker.def.sha=${mk.def.read}/$(call docker.def.name,${1}) | md5sum | cut -d' ' -f1

assert.md5sum:
	@# Guards that `md5sum` is on PATH, since the docker def-cache keys on its output.
	@# Without the guard a missing binary yields an empty hash, which reads as a
	@# permanent cache miss rather than an error.
	$(call assert.tool.required,md5sum,on macOS install coreutils for md5sum)

docker.def.is.cached/%: assert.md5sum
	@# Answers whether the named define has an up-to-date cached docker image.
	@#
	@# "Up-to-date" means an image exists *and* its recorded def-content hash
	@# (the `compose.mk.def.sha` label, stamped by `Dockerfile.build`) matches the
	@# current text of `Dockerfile.<name>`, so editing the def busts the cache
	@# even though the tag is unchanged, and a stale same-named tag from an
	@# unrelated build never counts as cached.
	@#
	@# This never fails; it echoes "yes" or "no".  It honors 'force=1' (always
	@# "no").  The image tag inspected is ``tag`` if set, else `compose.mk:<name>`;
	@# the wanted hash is ``want`` if set, else computed from the def.
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

docker.dispatch=${make} docker.dispatch${_mk.forward.args}
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

docker.image.dispatch=${make} docker.image.dispatch${_mk.forward.args}
docker.image.dispatch/%:
	@# Similar to `docker.dispatch/<arg>`, but accepts both the image
	@# and the target as arguments instead of using environment variables.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk docker.image.dispatch/<img>/<target>
	tty=1 img=$(call m5.__args__,1,/) \
	${make} docker.dispatch/$(call m5.__args__,2-,/)

# NB: exit status does not work without grep..
docker.images.filter=docker images --filter reference=${1} \
	--format "{{.Repository}}:{{.Tag}}" | grep ${1}

docker.image.run=${make} docker.image.run${_mk.forward.args}
docker.image.run/%:
	@# Runs the named image, using the (optional) named entrypoint.
	@# Also available as a macro.
	@#
	@# USAGE:
	@#   ./compose.mk docker.image.run/<img>,<entrypoint>
	@# 
	export img="$(m5.__args__.first)" \
	&& entrypoint="$${entrypoint:-$(call m5.__args__,2-)}" \
	&& ${trace_maybe} \
	&& entrypoint="`[ -z "$${entrypoint:-}" ] \
	&& echo "none" || echo "$${entrypoint}"`" \
	${make} docker.run.sh

docker.init:
	@# Checks if docker is available, then displays version/context (no real setup)
	@#
	( dctx="`docker context show 2>/dev/null`" \
		; $(call log.docker, ${no_ansi_dim}context ${sep} ${ital}$${dctx}${no_ansi}) \
		&& dver="`docker --version`" \
		&& $(call log.docker, ${no_ansi_dim}version ${sep} ${ital}$${dver}${no_ansi})) \
	| ${stream.dim} | $(stream.to.stderr)
	${make} docker.init.compose
docker.init.compose:
	@# Ensures compose is available.  Note that
	@# build/run/etc cannot happen without a file,
	@# for that, see instead targets like '<compose_file_stem>.build'
	@#
	compose_version="`${docker.compose} version`" \
	; $(call log.docker, ${no_ansi_dim} version ${sep} ${ital}$${compose_version}${no_ansi})

docker.lambda/%:
	@# Similar to `docker.def.run`, but eschews usage of tags 
	@# and rebuilds implicitly on every single invocation. 
	@#
	@# Note that technically, this is still caching and 
	@# still actually  involves tags, but the tags are naked SHAs.
	@#
	entrypoint=`if [ -z "$${entrypoint:-}" ]; then echo ""; else echo "--entrypoint $${entrypoint:-}"; fi` \
	&& cmd=`if [ -z "$${cmd:-}" ]; then echo ""; else echo "$${cmd:-true}"; fi` \
	&& sha=`docker build -q $${docker_args:-} - <<< $$(${make} mk.def.read/$(call docker.def.name,${*}))` \
	&& docker run -i $${entrypoint} \
		${docker.env.standard} \
		-v $${workspace:-$${DOCKER_HOST_WORKSPACE:-$${PWD}}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		-w /workspace --rm $${docker_args:-} $${sha} $${cmd}

docker.logs/%:
	@# Tails logs for the given container ID.
	@# This is non-blocking.
	@#
	$(call log.docker,  tailing logs for ${*})
	docker logs ${*}
docker.logs.follow/%:
	@# Tails logs for the given container ID.
	@# This is blocking, and never exits.
	$(call log.docker,  reattaching to ${*})
	docker logs --follow  ${*} 
docker.logs.follow/:; $(call log.docker,  ${yellow}No container ID to get logs from.)
	@# Error handler, only called when `docker.ps` output was null
docker.logs.timeout/%:
	@# Like docker.logs.follow, but times out after the given number of seconds.
	@# USAGE: `docker.logs.timeout/<timeout_in_seconds>,<id>`
	timeout=$(call m5.__args__,1) \
	&& id=$(call m5.__args__,2,,$${id:-}) \
	quiet=1 CMK_INTERNAL=1 \
	cmd="docker logs -f $${id} 2>&1" timeout=3 ${make} flux.timeout.sh 

docker.from.def/% Dockerfile.build/%: assert.md5sum
	@# Builds a container, treating the given 'define' block as a Dockerfile.
	@# The 'Dockerfile.' prefix on the define is optional (resolved by name lookup):
	@# `Dockerfile.build/<n>` uses `define Dockerfile.<n>` when it exists, else the
	@# bare `define <n>`.  The prefix still aids naming/cleanup but is no longer
	@# required.  Container tags are determined by 'tag' var if provided, falling
	@# back to the name used for the define-block.  Tags are implicitly prefixed
	@# with 'compose.mk:', for the same reason as the other prefixes.
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
	&& def_name="$(call docker.def.name,$(patsubst compose.mk:%,%,${*}))" \
	&& tag="compose.mk:$${tag:-$${inp}}" \
	&& sha=`$(call docker.def.sha,$(patsubst compose.mk:%,%,${*}))` \
	&& header="${GLYPH.DOCKER} Dockerfile.build ${sep} ${dim_cyan}${ital}$${def_name}${no_ansi_dim}" \
	&& $(call log.trace, $${header} ) \
	&& $(trace_maybe) \
	&& case `tag=$${tag} want=$${sha} ${make} docker.def.is.cached/$${inp}` in \
		yes) true;; \
		no) ( $(call io.mktemp) && verbose=0 ${mk.def.to.file}/$${def_name},$${tmpf} \
			  && $(call log.docker, $(shell echo ${@}|cut -d/ -f1) \
					${sep} ${ital}${dim_cyan}$(shell echo ${@}|cut -d/ -f2) ${sep} ${dim}tag=${no_ansi}$${tag}${no_ansi_dim}) \
				&& cat $${tmpf} | ${stream.as.log} \
				&& $(call log.base, ${cyan_flow_right} ${bold}Building..) \
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
	$(call log.part1, ${dim_ital_cyan}$${tag})
	${docker.images} | grep -w "$${tag}" ${stream.obliviate} \
	&& ( $(call log.part2, already cached) &&  exit 0 )\
	|| ( $(call log.part2, ${yellow}not cached) \
		&& $(call log.part1, building) \
		&& $(call log.part2,\n${cyan_flow_right} ${dim_ital}$${url}) \
		&& ${trace_maybe} \
		&& docker build ${docker._quiet_flag} -t compose.mk:$${tag} $${url})

docker.panic: docker.stop.all docker.network.panic docker.volume.prune docker.system.prune; set -x && docker rm -f $$(docker ps -qa | tr '\n' ' ') 2>/dev/null || true
	@# Debugging only!  This is good for ensuring a clean environment,
	@# but running this from automation will nix your cache of downloaded
	@# images, and then you will probably quickly hit rate-limiting at dockerhub.
	@# It tears down volumes and networks also, so you do not want to run this in prod.
	@#

docker.reap:
	@# Force-removes cmk-launched containers, idempotently.  Run it by hand after a hard
	@# interrupt to clear strays that outlived their run.  Scoped by the 'cmk.run' label key
	@# (every container 'docker.run.sh' stamps), so it never touches non-cmk containers; pass
	@# run=<id> to limit it to a single run's supervisor.  Milder than 'docker.panic'.
	@#
	filter=`case "$${run:-}" in "") echo label=cmk.run;; *) echo label=cmk.run=$${run};; esac` \
	&& ids=$$(docker ps -aq --filter $${filter} 2>/dev/null) \
	&& case "$${ids:-}" in \
		"") $(call log.docker, ${dim}nothing to reap);; \
		*) $(call log.docker, ${dim}removing strays ${sep} ${no_ansi}`echo $${ids} | wc -w | tr -d ' '`) && docker rm -f $${ids} >/dev/null 2>&1 || true;; \
	esac

docker.prune docker.system.prune:; $(call log) && set -x && docker system prune --all --force
	@# Debugging only! Runs 'docker system prune' for the entire system.
	@#

docker.prune.old: flux.timer/.docker.prune.old
	@# Debugging only! Runs 'docker system prune --all --force --filter "until="'
.docker.prune.old:; docker system prune --all --force --filter "until=$${docker_max_age:-168h}"

docker.rmi:
	@# Removes images with `docker rmi`.  Must provide `img` in environment.
	force=`case $${force:-} in 1) echo '--force';; *) echo ;; esac` \
	&& set -x && docker rmi $${force} $${img} 2>/dev/null|| true

docker.run.def:
	@# Treats the named define-block as a script, then runs it inside the given container.
	@#
	@# USAGE:
	@#  entrypoint=<entry> def=<def_name> img=<image> ./compose.mk docker.run.def
	@#
	true \
	&& ( if [ -n "$${announce:-}" ]; then $(call log.docker.as,$${announce_as},$${announce}); \
		else $(call log.docker, ${dim_cyan}${ital}$${def}${no_ansi} ${sep} ${bold}${underline}$${img}); fi ) \
	&& case $${docker_args:-} in \
		"") true;; \
		*) quiet=$${quiet:-0};; \
	esac \
	&& $(call io.mktemp) \
	&& ${make} mk.def.to.file/$${def},$${tmpf} \
	&& (script_pre="$${cmd:-}" \
		&& unset cmd \
		&& case "$${feed:-file}" in \
			flag) script="$${script_pre} $${CMK_LAMBDA_ARGV:-} $${feed_flag} $${tmpf}";; \
			stdin) echo 'cmk: feed=stdin has no container path yet -- it must stream through docker.run.sh (which proxies stdin), not a materialized tmpfile; use feed=file/flag here or run on the host' >&2; exit 1;; \
			*) script="$${script_pre} $${tmpf} $${CMK_LAMBDA_ARGV:-}";; \
		esac \
		&& script="$${script}" img=$${img} ${make} docker.run.sh) \
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
	&& _cmk_run_id="$${MAKE_SUPER:-$${CMK_RUN_ID:-none}}-$${CMK_REAP_SALT:-0}" \
	&& entry=`[ "$${entrypoint:-}" == "none" ] && echo ||  echo "--entrypoint $${entrypoint:-bash}"` \
	&& net=`[ "$${net:-}" == "" ] && echo ||  echo "--net=$${net}"` \
	&& case "$${hostname:-}"  in \
		"") hostname="--hostname=$(shell echo $${img}| cut -d'@' -f1 | cut -d: -f1)";; \
		*) hostname="--hostname=$${hostname}";; \
	esac \
	&& cmd="$${cmd:-$${script:-}}" \
	&& disp_cmd="`echo $${cmd} | sed 's/${MAKE_FLAGS}//g'|${stream.lstrip}`" \
	&& ( \
		[ -z "$${quiet:-}" ] && [ "$${TRACE:-0}" = 1 ] \
		&& ( \
			$(call log.docker, docker.run ${sep} ${dim}img=${no_ansi}$${image_tag}) \
			&& case $${docker_args:-} in \
				"") true=;; \
				*) $(call log.docker, docker.run ${sep}${dim} docker_args=${no_ansi}${ital}$${docker_args:-});; \
			esac \
			&& $(call log.base, ${green_flow_right} ${dim_cyan}[${no_ansi}${bold}$${entrypoint:-}${no_ansi}${cyan}] ${no_ansi_dim}$${disp_cmd})  \
			) \
		|| true ) \
	&& extra_env=`[ -z $${env:-} ] && true || ${make} .docker.proxy.env/$${env}` \
	&& tty=`[ -z $${tty:-} ] && echo \`${io.tty.stdin} && echo "-t"|| true\` || echo "-t"` \
	&& cmd_args="\
		--rm --init -i $${tty} $${extra_env} \
		--label cmk.run=$${_cmk_run_id} \
		$${hostname} \
		-e CMK_INTERNAL=1 -e CMK_IN_CONTAINER=1 \
		${docker.env.standard} \
		-v $${workspace:-$${DOCKER_HOST_WORKSPACE:-$${PWD}}}:/workspace \
		-v $${DOCKER_SOCKET:-/var/run/docker.sock}:/var/run/docker.sock \
		${docker.cmk.mount} \
		${docker.hosted.mount} \
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
	&& printf '%s' '$(subst ${lang.comp.kwargs.sp},${space},$*)' | ${stream.comma.to.space} | ${stream.space.to.nl} \
	| xargs -I% bash -c "[[ -v % ]] && printf '%\n' || true " \
	| xargs -I% printf " -e %=\"\`echo \$${%}\`\""; printf '\n'


docker.run/% docker.start/%:; img="${*}" entrypoint=none ${make} docker.run.sh
	@# Starts the named docker image with the default entrypoint
	@# USAGE: 
	@#   ./compose.mk docker.start/<img>

docker.stat: 
	@# Show information about docker-status,
	@# Includes version details for docker, docker-compose, container-count, 
	@# docker socket, docker-related environment variables.
	@# No arguments. Pipe-friendly.
	@#
	which docker >/dev/null 2>/dev/null \
		&& CMK_INTERNAL=1 ${make} .docker.stat \
		|| ($(call log.warn, Docker is missing!); printf "{}\n")
.docker.stat:
	$(call io.mktemp) \
	&& ${make} docker.context/current > $${tmpf} \
	&& $(call log.docker) \
	&& export env="`${make} io.env.json/DOCKER`" \
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
		"env:raw=$${env}" \
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
			$(call log.docker, ${yellow}Nothing to stop) \
			&& exit 0;; \
	esac \
	&& $(call log.docker, docker.stop${no_ansi_dim} ${sep} ${green}$${id:-$${name}}) \
	&& ${trace_maybe} \
	&& export cid=`[ -z "$${id:-}" ] \
		&& docker ps --filter name=$${name} --format json \
			| ${jq.run} -r .ID || echo $${id}` \
	&& case "$${cid:-}" in \
		"") \
			$(call log.docker, ${yellow}No containers found); ;; \
		*) \
			${trace_maybe} \
			&& docker stop -t $${timeout:-1} $${cid} >/dev/null; ;; \
	esac $(shell [ "$${quiet:-0}" == "0" ] && echo '' || echo '> /dev/null 2>/dev/null' )

# Scaffolds dispatch/shell/run targets for the given docker image.  Accepts `file=<path>` (build from a
# Dockerfile path) or `def=<name>` (build from an inline `Dockerfile.<name>` define, routed to
# `_docker.import.def`); the $(if) is lazy so only the taken branch runs its parse-time $(eval)/unpack.
# Each branch also mints a real `container` instance for the namespace, so `<ns>` gains the
# `(| .. |) in <ns>` block-run surface on top of the build/dispatch/shell verbs.  The mint is cheap and
# sits above the CMK_INTERNAL guard (works at all make levels); the heavyweight verbs stay guarded to
# skip re-scaffolding on every nested sub-make.
docker.import=$(eval $(if $(findstring def=,${1}),$(call _docker.import.def,${1}),$(call _docker.import,${1})))

docker.stop.all:
	@# Non-graceful stop for all running containers.
	@#
	@# USAGE:
	@#   ./compose.mk docker.stop name=my-container timeout=99
	@#
	ids=`docker ps -q | tr '\n' ' '` \
	&& count=`printf "$${ids:-}" | ${stream.count.words}` \
	&& $(call log.part1, ) && $(call log.part2, ${yellow}$${count}${no_ansi_dim} containers total) \
	&& [ -z "$${ids}" ] && true || (set -x && docker stop -t $${timeout:-1} $${ids})

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: io.* :: Input/output helpers
##
## Misc helpers for input/output, including temp files and showing output to
## users.  User-facing output leverages charmbracelet utilities like gum[2] and
## glow[3], used directly when available and via containers otherwise.
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
ifdef OS_MACOS
col_b=LC_ALL=C col -b
io.mktemp=export tmpf=$$(mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
# Similar to io.mktemp, but returns a directory.
io.mktempd=export tmpd=$$(mktemp -u ./.tmp.XXXXXXXXX$${suffix:-}) && mkdir -p "$$tmpd" && trap 'rm -rf -- "$$tmpd"' EXIT
else
col_b=col
io.mktemp=export tmpf=$$(TMPDIR=`pwd` mktemp ./.tmp.XXXXXXXXX$${suffix:-}) && trap "rm -f $${tmpf}" EXIT
# Similar to io.mktemp, but returns a directory.
io.mktempd=export tmpd=$$(TMPDIR=`pwd` mktemp -d ./.tmp.XXXXXXXXX$${suffix:-}) && trap 'rm -rf -- "$$tmpd"' EXIT
endif

# Reap the shared run-scoped CMK_SCRATCH tmpfiles via CMK_POST.
io.scratch.reap:; rm -f -- ${CMK_SCRATCH}* 2>${devnull} || true
$(if $(wildcard ${CMK_SCRATCH}*),$(call __cmk_post__.append,io.scratch.reap))

# portable ns epoch; BSD/macOS date lacks ns, so use gdate or seconds.
io.time.ns=$$(_t=$$(date +%s%N); case $${_t} in *N*) command -v gdate >/dev/null 2>&1 && gdate +%s%N || echo "$$(date +%s)000000000";; *) echo $${_t};; esac)

# portable timeout binary; macOS or brew ships it as gtimeout.
io.timeout=$$(command -v timeout || command -v gtimeout)

# io.safe_rm(<path>) -- `rm -f` one path safely:
#   - `--` ends options, so a leading `-` can't become a flag,
#   - the double-quotes stop word-splitting and globbing,
#   - `-f` makes a missing path a no-op (so it is set-e safe).
# NB: for an UNTRUSTED path, pass a SHELL var -- `$(call
# io.safe_rm,$$f)` expands to `rm -f -- "$f"`, so the shell reads
# the value literally (no re-parse of an embedded `$(...)`/`;`).
# A make-interpolated value is only quote-safe (a literal
# `$(...)` inside it would still expand within the quotes).
# WARNING: not for globs -- the quotes make the pattern literal.
io.safe_rm=rm -f -- "$(1)"
define _io.mktemp
$(call mk.unpack.kwargs, $(m5[1]?), var, tmpf) 
${io.mktemp} && ${kwargs_var}=$${tmpf}
endef

# USAGE:
#   $(call mk.declare, K8S_PROJECT_LOCAL_CLUSTER)
mk.declare=$(call ${1})

# This is a hack because charmcli/gum is distroless, but the spinner needs to use "sleep", etc
# io.gum.alt.dumb=docker run -it -e TERM=dumb --entrypoint /usr/local/bin/gum --rm `docker build -q - <<< $$(printf "FROM alpine:${ALPINE_VERSION}\nRUN apk add -q --update --no-cache bash\nCOPY --from=charmcli/gum:${IMG_GUM} /usr/local/bin/gum /usr/local/bin/gum")`

io.awk=CMK_INTERNAL=1 ${make} io.awk${_mk.forward.args}

io.bash=CMK_INTERNAL=1 ${make} io.bash${_mk.forward.args}
io.bash/%:
	@# Treats the given define-block name as a bash script.
	@# Also available as a macro.
	@#
	@# USAGE: io.bash/<def_name>,<optional_args>
	is_pipe="`[ -p /dev/stdin ] && echo pipe || echo 'no input'`" \
	&& hdr="io.bash ${sep}${dim_cyan} ${*} ${sep}${dim}" \
	&& $(call log.io, $${hdr} Running script with ${no_ansi_dim}$${is_pipe}) \
	&& defname="$(m5.__args__.first)" \
	&& ${io.mktemp} && (${mk.def.read}/$${defname}) > $${tmpf} \
	&& args="`echo '$(call m5.__args__,2-)' | ${stream.comma.to.space}`" \
	&& sloc=`cat $${tmpf} | ${stream.count.lines}` \
	&& $(call log.io, $${hdr} sloc=$${sloc} args=$${args:-..}) \
	&& case $${verbose:-0} in \
		"1") $(call log.file.contents,$${tmpf});; \
	esac \
	&& (case $${is_pipe} in \
		"pipe") cat /dev/stdin ;; \
		*) echo ;; \
	esac) | bash -euo pipefail ${dash_x_maybe} $${tmpf} $${args}


IO_ENV_LOG?=DOCKER,MK,MAKE
# `io.curl` -- the curl command (host binary, else a dockerized fallback).  Dual-use: bare macro
# (`${io.curl} -s <url>`, back-compat) or a variadic callform (`cmk.io.curl(-s, <url>)` /
# `cmk.io.curl(-s <url>)`) that splats its comma-separated args, unquoted, after the command.  No
# args (a bare `${io.curl}`) appends nothing (origin-guarded, so it never grabs an enclosing frame).
io.curl=${bin[curl]}$(if $(filter undefined,$(origin 1)),, $(m5.__splat__))
_io.curl=${io.curl} ${1}
io.curl.stat=bash ${dash_x_maybe} -c '${io.curl} -s -o /dev/null $(if $(filter undefined,$(origin 1)),$${1},$(1)) > /dev/null' -- 
io.curl.quiet=$(call io.curl, -s $(m5[1]?))
io.log.curl=$(call io.curl.quiet, nginx-tcp:8080) | ${stream.as.log}

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
_io.env=tr ',' '\n' | xargs -I% sh -c "env | ${stream.grep.safe} | grep \"^%.*=\" || true"
io.env=bash -c 'echo $${1\#/} | ${_io.env}' -- 
io.env.filter.prefix=${io.env}
io.env.log: io.env.log/${IO_ENV_LOG}
	@# Filters environment variables starting with DOCKER, MAKE, MK, etc.
	@# Human-readable output sent to stderr.  Also available as a macro
io.env.log=${make} io.env.log

define io.env.log
	$(call log, prefixes ${sep} ${1}); 
	echo '${1}' | ${stream.comma.to.space} | ${stream.space.to.nl} | ${flux.each}/io.env | ${stream.as.log}
endef


# __locals__: JSON object of the shell vars this recipe defined -- "current vars minus the
# baseline snapshot taken at recipe entry".  The `target_locals` compile pragma injects that
# baseline (`_target_local_baseline`) as the first recipe line, but only into recipes that
# reference `__locals__`.  Surface: `cmk.__locals__()` lowers to the inline accessor; the
# `( )` subshell inherits the recipe's vars (exported and plain, so `<=` assignments show).
# Emits `{}` + a one-line stderr hint when the pragma is not enabled (no env dump, no crash).
__locals__ = ( if [ -z "$${_target_local_baseline:-}" ]; then printf '{}' ; printf '${yellow}✗ cmk: __locals__ used without the target_locals pragma${no_ansi}\n' >&2 ; \
	else _cmk_l_json="{}" \
	&& for _cmk_l_k in $$(printf '%s\n' "$$(compgen -v)" \
		| grep -vxF -f <(printf '%s\n' "$${_target_local_baseline}") \
		| grep -vE '^(_cmk_l_.*|_target_local_baseline|_|PIPESTATUS|FUNCNAME|BASH.*|LINENO|RANDOM|SECONDS|OPTIND|OPTARG|REPLY|EPOCHSECONDS|EPOCHREALTIME|SRANDOM|HISTCMD|GROUPS|DIRSTACK|COMP_.*)$$' || true); do \
		_cmk_l_json="$$(jq -c --arg k "$$_cmk_l_k" --arg v "$${!_cmk_l_k}" '. + {($$k):$$v}' <<<"$$_cmk_l_json")" ; \
	done \
	&& printf '%s' "$$_cmk_l_json" ; fi )

io.envp=CMK_INTERNAL=1 ${make} io.envp${_mk.forward.args}
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

io.file.select=header="Choose a file: (dir=$${dir:-.})"; \
	choices="`ls $${dir:-.}/$${pattern:-} | ${stream.nl.to.space}`" \
	&& $(call log.io,io.file.select ${sep} $${dir:-.} ${sep} $${choices}) \
	&& ${io.get.choice} 
# Creates file w/ the 2nd argument as a command, iff the file given by the 1st arg is older than
io.file.gen.maybe=[ -n "$$(find "${1}" -mmin +1 2>/dev/null)" ] \
	&& ($(call log.base,${dim} cached @ ${1} is old and will be recomputed fresh); eval "${2} > ${1}") \
	|| (true)

io.get.url=$(call io.mktemp) && curl -sL $${url} > $${tmpf}

io.gum.docker=${trace_maybe} && docker run $$(if ${io.tty.stdin}; then echo "-it"; else echo "-i"; fi) -e TERM=$${TERM:-xterm} --entrypoint /usr/local/bin/gum --rm `docker build -q - <<< $$(printf "FROM alpine:${ALPINE_VERSION}\nCOPY --from=charmcli/gum:${IMG_GUM} /usr/local/bin/gum /usr/local/bin/gum\nRUN apk add --update --no-cache bash\n")`

# USAGE: see html.cmk :// css.min
#   $(call io.factory.file_handler, ns=css.pretty handler=css.prettify root=$${css.root} name='*.css')
$(call m5.def.!, io.factory.file_handler, io.factory.file_handler.src)
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
		$$(call log, dispatching ${dim_cyan}${kwargs_handler} ${sep} path=${dim_ital}$${*}) \
		&& find $${*} -name '${kwargs_name}' \
		| $${stream.peek} | $${flux.each}/${kwargs_handler} \
	); else ( \
		$$(call log,$${*}) && ${make} ${kwargs_handler}/$${*} \
	); fi
${kwargs_ns}: ${kwargs_prereqs}
	@# Runs on given root or working directory
	$$(call log, handler=${bold_green}${kwargs_handler} ${sep} name=${dim_cyan}${kwargs_name}  ${sep} root=${dim_cyan}${kwargs_root})
	$${trace_maybe} && ${make} ${kwargs_ns}/${kwargs_root}
endef


# gum-presence probe, memoized to once-per-process (replaces a parse-time
# `ifeq ($(shell which gum ...))` that forked a `which` on every re-parse).
# the gum-dispatching callers then branch at call-time via `.$(_gum.present)`
# indirection ("1" -> on PATH, "0" -> dockerized), byte-identical to the old
# ifeq selection (verified against both branches), but no probe unless used.
_gum.present=${bin[gum.present]}
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

# Labels automatically go through 'gum format' before 'gum style', so templates are supported.
io.gum.style io.draw.banner io.banner:; label=$${label:-${io.timestamp}}; ${io.draw.banner}
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
	export label="$${label:-$@}" \
	&& export label="$${label:-${io.timestamp}}" \
	&& ${io.gum.run} style ${io.gum.style.default} ${io.gum.style.div} $${label} \
	; case $$? in \
		0) true;; \
		*) (${io.print.banner});; \
	esac
endef
io.banner=${io.draw.banner}


io.gum.div=label=${@} ${make} io.gum.div
io.gum.style/% io.draw.banner/% io.banner/%:; label="${*}"; ${io.draw.banner}
	@# Prints a divider with the given label. 
	@# Invocation must be a legal target (Do not use spaces, etc!)
	@# See also `io.draw.banner` and `io.print.banner` for something simpler.
	@#
	@# USAGE: ./compose.mk io.draw.banner/<label>

io.fs.watch: assert.tool.required/inotifywait
	@# Runs given command once, and again in a loop whenever the given path changes.
	@# A filesystem-change watcher (Linux-only, via inotifywait).
	@#
	@# USAGE: path='..' cmd='..' make io.fs.watch
	@#
	$(call log, ${dim}path=${no_ansi}$${path}) \
	&& export events="$${events:-modify,create,delete}" \
	&& $(call log, ${dim}events=${no_ansi}$${events}) \
	&& $(call log, ${cyan_flow_right} ${dim} $${cmd}) \
	&& bash -x -c 'set -e; $${cmd} & pid=$$!; trap "exit 0" SIGTERM SIGINT; \
	while inotifywait -q -r -e $${events} $${path}; do \
	    kill -KILL $${pid} 2>/dev/null || true; \
	    $${cmd} & \
	done'
io.fs.watch/%:; path="${*}" ${make} io.fs.watch
	@# Like `io.fs.watch`, but accepts path as argument.
	@#
	@# USAGE: cmd='..' make io.fs.watch/<path>

io.mkdir/% mk.require.dir/%:
	@# Runs `mkdir -p` for the named directory.
	@# Set `force=1` to use sudo.
	([ -z "$${force:-}" ] && sudo="" || sudo=sudo ) \
	&& $(call log.part1, ${*} ) \
	&& $${sudo} mkdir -p ${*} \
	&& $(call log.part2,${green}${GLYPH_CHECK})
io.preview.file=cat ${1} | ${stream.as.log}

io.print.banner:; label=$${label:-${io.timestamp}}; ${io.print.banner}
	@# Prints a divider on stdout, defaulting to the full
	@# term-width, with optional label. If label is not set, 
	@# a timestamp will be used.  Also available as a macro.
	@#
	@# USAGE:
	@#  label=".." filler=".." width="..." ./compose.mk io.print.banner 
define io.print.banner
	label=$${label:-$@} \
	&& label=$${label:-${io.timestamp}} \
	&& label=$${label/./-} \
	&& export width=$${width:-${io.terminal.cols}} \
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
io.log.part1=$(call log.base.part1,${GLYPH_IO} $(m5[1]))
io.log.part2=$(call log.base.part2, $(m5[1]))


io.quiet.stderr.sh:
	@# Runs the given target, surpressing stderr output, except in case of error.
	@#
	@# USAGE:
	@#  ./compose.mk io.quiet/<target_name>
	@#
	$(call io.mktemp) \
	&& cmd_disp=`printf "$${cmd}" | sed 's/make -s --warn-undefined-variables/make/'` \
	&& $(call log.io, ${green}$${cmd_disp}) \
	&& header="${_GLYPH_IO} io.quiet.stderr ${sep}" \
	&& $(call log.base, $${header} ${dim}( Quiet output, except in case of error. ))\
	&& start=$$(date +%s) \
	&& ([ -p ${stdin} ] && cmd="${stream.stdin} | ${cmd}" || true) \
	&& $${cmd} 2>&1 > $${tmpf} ; exit_status=$$? ; end=$$(date +%s) ; elapsed=$$(($${end}-$${start})) \
	; case $${exit_status} in \
		0) \
			$(call log.base, $${header} ${green}ok ${no_ansi_dim}(in ${bold}$${elapsed}s${no_ansi_dim})); ;; \
		*) \
			$(call log.base, $${header} ${red}failed ${no_ansi_dim} (error will be propagated)) \
			; cat $${tmpf} | awk '{print} END {fflush()}' > ${stderr} \
			; exit $${exit_status} ; \
		;; \
	esac

ifdef OS_MACOS
# https://www.unix.com/man_page/osx/1/script/
io.script.tmpf=$(call io.mktemp) && script -q -r $${tmpf} sh ${dash_x_maybe} -c "${1}"
io.script=script -q sh ${dash_x_maybe} -c "${1}"
else 
# https://www.unix.com/man_page/linux/1/script/
io.script.tmpf=$(call io.mktemp) && script -qefc --return --command "${1}" $${tmpf}
io.script=script -qefc --return --command "${1}" /dev/null
io.script.trace=sh -x -c "script -qefc --return --command \"${1}\" /dev/null"
endif

io.selector=choices=`${make} ${1} | ${stream.nl.to.space}` && ${io.get.choice} && ${make} ${2}/$${chosen}

io.shell.isolated=env -i TERM="$${TERM}" COLORTERM="$${COLORTERM}" PATH="$${PATH}" HOME="$${HOME}"
io.shell.iso=${io.shell.isolated}

# io.stack.cur: pick the stack-file (the arg if non-empty, else the default).
# The origin guard stays warning-clean and lets a bare argless call work inline
# (no sub-make); the inner fallback also covers a present-but-empty arg.
io.stack.cur = $(if $(filter-out undefined,$(origin 1)),$(or ${1},${CMK_IO_STACK}),${CMK_IO_STACK})

# io.stack! codegens a per-run-unique, origin-guarded stack-name var, frozen on first use so sub-makes share one file.
define _io.stack!
export $(1) := $(call m5|,$(1),.tmp.$(1).$(call m5|,MAKE_SUPER,${_cmk.pid}))
endef
# init_data kwarg: name of a JSON-array define to seed a stack from.
io.stack.init_data=$(call mk.kwargs.get,$(1),init_data)
# The bare stack name: def= kwarg, else namespace=, else leading word.
io.stack.name=$(strip $(or $(call mk.kwargs.get,$(1),def),$(call mk.kwargs.get,$(1),namespace),$(firstword $(1))))
# Seed source: the init_data kwarg if given, else the def body-define.
io.stack.seed=$(or $(call io.stack.init_data,$(1)),$(call mk.kwargs.get,$(1),def))
io.stack=(${io.stack.require} && cat ${io.stack.cur} | ${jq.run} .)

io.stack.pop/%:
	@# Pops first item off the given stack file.
	@# Not strict: popping an empty stack is allowed.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.pop/<fname>
	@#  {.. data ..}
	@#
	$(call log.io,   ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.pop, ${*})
# discard = pop without returning the value (it just trims the top off the
# file); pop is defined as "show the top, then discard it" so the trim lives in
# one place.
io.stack.discard=(stmp=$$(mktemp "${io.stack.cur}.tmp.XXXXXX") && ${io.stack} | ${jq.run} '.[:-1]' > "$${stmp}" && mv "$${stmp}" ${io.stack.cur})
io.stack.pop=(${io.stack} | ${jq.run} '.[-1]'; ${io.stack.discard})
# pop_word = pop, but emits the value raw (jq -r): an unquoted string instead of
# JSON.  Saves callers a trailing `| jq -r .`.  (`word` as in a bare scalar.)
io.stack.pop_word=(${io.stack} | ${jq.run} -r '.[-1]'; ${io.stack.discard})

io.stack.require=( ls ${io.stack.cur} >/dev/null 2>/dev/null || echo '[]' > ${io.stack.cur})
io.stack.push=(${io.stack.require} && obj=`${stream.stdin} | ${jq.run} -c .` && stmp=$$(mktemp "${io.stack.cur}.tmp.XXXXXX") && ${jq} --argjson obj "$${obj}" '. + [$$obj]' ${io.stack.cur} > "$${stmp}" && mv "$${stmp}" ${io.stack.cur})
io.stack.reset=echo '[]' > ${io.stack.cur}
# io.stack.initialize -- eager-seed a lazy stack: overwrite the file with a
# named define, then assert it parses as a JSON array (else error + exit).
# Tolerant: a no-op (logs a skip) when the def is empty/missing, so an optional
# seed is fine.  An existing-but-non-array def still errors.
io.stack.initialize=$(if $(m5[2]),( d=`${mk.def.read}/$(m5[2])` \
	&& if [ -z "$${d}" ]; then $(call log.io, ${dim}io.stack.initialize ${sep} no def ${ital}$(m5[2])${no_ansi_dim} ${sep} skipping seed) ; \
	else printf '%s\n' "$${d}" > ${io.stack.cur} \
		&& { cat ${io.stack.cur} | ${jq.run} -ce 'type=="array"' >${devnull} 2>${devnull} \
			|| { $(call log.io, ${red}io.stack.initialize${no_ansi_dim}: ${no_ansi}def ${ital}$(m5[2])${no_ansi} did not yield a JSON array); exit 1; } ; } ; fi ),true)
# io.stack.get.run -- read-only: apply the jq program in shell var jqp (default
# `.`) to the stack array as compact JSON, so callers can `<-` capture it.
# The caller builds jqp in-shell (comma-spec positional split) or from stdin.
io.stack.get.run=( ${io.stack.require} && cat ${io.stack.cur} | ${jq.run} -c "$${jqp:-.}" )
# io.stack.count: number of items on the stack.
io.stack.count=( ${io.stack.require} && cat ${io.stack.cur} | ${jq.run} length )
# io.stack.update.run: transform the whole array with the jq program in jqp
# (default `.`), then assert it's still a JSON array (else error + exit,
# original intact).  The Agent.update verb, mirroring io.stack.initialize.
io.stack.update.run=( ${io.stack.require} \
	&& stmp=$$(mktemp "${io.stack.cur}.tmp.XXXXXX") \
	&& cat ${io.stack.cur} | ${jq.run} "$${jqp:-.}" > "$${stmp}" 2>${devnull} \
	&& cat "$${stmp}" | ${jq.run} -ce 'type=="array"' >${devnull} 2>${devnull} \
	&& mv "$${stmp}" ${io.stack.cur} \
	|| { $(call log.io, ${red}io.stack.update${no_ansi_dim}: ${no_ansi}transform did not yield a JSON array); rm -f "$${stmp}" 2>${devnull}; exit 1; } )
io.stack.push/%:
	@# Pushes new JSON data onto the named stack-file
	@#
	@# USAGE:
	@#   echo '<json>' | ./compose.mk io.stack.push/<fname>
	@#
	${trace_maybe} \
	&& ([ "$${quiet:-0}" == "1" ] || $(call log.io,   ${dim}stack@${no_ansi}${*} ${cyan_flow_left})) \
	&& ${stream.peek} | $(call io.stack.push, ${*})
io.stack.update/%:
	@# Transform the named stack-file IN PLACE with the jq program on stdin (asserts the
	@# result stays a JSON array).  USAGE: echo '<jq>' | ./compose.mk io.stack.update/<fname>
	jqp=`${stream.stdin.maybe}` ; $(call io.stack.update.run, ${*})
io.stack.discard/%:
	@# Discards the top item of the given stack-file: like `io.stack.pop`, but
	@# removes the top without emitting it.  Not strict (empty stack is allowed).
	@# Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.discard/<fname>
	@#
	$(call log.io,   ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.discard, ${*})
io.stack.pop_word/%:
	@# Like `io.stack.pop`, but returns the top as a raw value (jq -r): an
	@# unquoted string instead of JSON.  Removes the top.  Also available as a macro.
	@#
	@# USAGE:
	@#  ./compose.mk io.stack.pop_word/<fname>
	@#
	$(call log.io,   ${dim}stack@${no_ansi}${*} ${cyan_flow_right})
	$(call io.stack.pop_word, ${*})

# io.stack.push_word: push a raw word read from stdin onto the default stack.  This is
# the stdin-input counterpart of the raw-word pop (which emits a raw word).  `jq -Rs .`
# slurps stdin into one JSON string, which the base push then appends.
io.stack.push_word=${jq} -Rs . | ${io.stack.push}
io.stack.push_word/:; printf '' | ${io.stack.push_word}

# Argless aliases over the default stack (${CMK_IO_STACK}), so you can use a
# stack without naming a file. The whole invocation's process tree shares it.
# Each is the no-arg form of the like-named macro (no `${make}` sub-make).
io.stack:;       @$(call io.stack)
	@# Show the default stack (`CMK_IO_STACK`).  See also io.stack/<fname>.
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
	@# (Re)initialize the default stack (`CMK_IO_STACK`) to empty.


io.string.hash=$(shell printf "${1}" | sed 's/ /_/g'|sed 's/[.]/_/g'|sed 's/\//_/g')

io.terminal.cols=${bin[cols]}

io.term.width=$(shell echo $$(( $${COLUMNS:-${io.terminal.cols}}-6)))

# Each succeeds iff that stream is a terminal (not redirected); prefer them over an inline bracket test, which clashes with the cmk-lang stream call-form.
$(call m5.declare, io.tty.stdout = [ -t 1 ], io.tty.stdin = [ -t 0 ], io.tty.stderr = [ -t 2 ])

io.timestamp=`date '+%T'`

io.user_exit=label="${1}" ${make} io.user_exit

io.wait io.time.wait: io.time.wait/1
	@# Pauses for 1 second.

io.wait/% io.time.wait/%:
	@# Pauses for the given amount of seconds.
	@#
	@# USAGE: ./compose.mk io.time.wait/<int>
	@#
	$(call log.io, ${dim}Waiting for ${*} seconds..) \
	&& sleep ${*}

io.xargs=xargs -I% sh ${dash_x_maybe} -c

# The `@io.pushd` decorator runs the whole target body from a given dir.  The compiler relocates the
# decorator to the recipe head and the joinbody pass `&&`-chains the body into one shell, so the
# directory change persists across every command (without it each recipe line is its own shell).  Uses
# bash `pushd` (not `cd`) so the body can `popd` back to the caller's dir; the stack listing is muted.
# Fails fast (nonzero) if the dir is missing, aborting the `&&`-chain.
io.pushd=pushd "$(m5[1])" >/dev/null
io.xargs.verbose=xargs -I% sh -x -c

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: assert.* :: Assertions with clear errors
##
## Each logs a clear error and exits nonzero on failure, covering environment
## variables, host tools, stdin streams, and plugin availability.  Most are
## macros (usable inline via `$(call assert.X, ...)`); the env + tool guards
## also expose `assert.X/%` target forms for use as prerequisites.
##
## Sibling guards that live in their own namespaces (not here): `__plugins__.assert`
## / `__modules__.assert` (parse-time registry asserts) and `_mk.assert.define`
## (the `import.module` define-exists guard).
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
assert.env.var=[[ -z "$${$(m5[1])}" ]] && { $(call mk.die, required variable $(m5[1]) is unset or empty, errno=ENVVAR_UNSET, var=$(m5[1])) ; } || true
assert.env=$(foreach var_name, ${1}, $(call assert.env.var, ${var_name});)
assert.env/%:; $(call assert.env,$(shell echo ${*}|${stream.comma.to.space}))
	@# Asserts that the (comma-delimited) environment variables are set and non-empty.
	@# Also available as a macro.

# --- Tool assertions ----------------------------------------------------------
# Assert a tool is on PATH, with optional failure hints. The `available` form probes on every call;
# the `required` form memoizes a success in an exported var, so it survives a recursive sub-make (the
# child skips the probe) -- but a `docker run` does not forward it, so the tool is re-probed inside a
# container. An optional 2nd arg is a hint line shown when the tool is missing (no backtick or comma:
# it lands in a printf and the comma is the macro-arg delimiter).
_assert.tool.hint=$(if $(filter undefined,$(origin 2)),,$(m5[2]))
_assert.tool.available=$(call log.base.part1,${GLYPH_MK} assert.tool ${sep} looking for ${ital}${dim_cyan}$(m5[1])); which ${1} >/dev/null && $(call log.base.part2,${green}${GLYPH_CHECK} ${no_ansi_dim}`which ${1}`) || ($(call log.base.part2,${red} missing!);$(call log.io,${no_ansi}${bold}Error:${no_ansi} Install tool and retry workflow.)$(if $(_assert.tool.hint),;$(call log.io,${yellow}hint:${no_ansi_dim} $(_assert.tool.hint)));exit 1)
assert.tool.available=${_assert.tool.available}
assert.tool.available/%:; $(call _assert.tool.available, ${*})
	@# Probes PATH for the given tool on every call, with no caching.
	@# Output is only on stderr, but this shows whereabouts if it is in PATH.
	@# If not found, this exits with an error.  Also available as a macro
	@# `cmk.assert.tool.available(foo, <hint>)` that takes an optional 2nd HINT
	@# arg and prints `hint: <hint>` on failure.

# The memo cell: a shell-valid name (only `[A-Za-z0-9_]`) so make can `export` it -- the tool name is
# sanitized (`.`/`-`/`/` -> `_`). A dotted name is silently not exported, so a recursive sub-make would
# re-probe every time.
_assert.tool.memo=_cmk_tool_ok_$(subst /,_,$(subst -,_,$(subst .,_,$(m5[1]))))
# Memo check is by definedness (`$(origin)` via m5.defined?), not by value: reading an
# as-yet-unset memo cell would trip `--warn-undefined-variables` on the first probe.
_assert.tool.required=$(if $(call m5.defined?,$(_assert.tool.memo)),true,$(eval export $(_assert.tool.memo):=1)$(_assert.tool.available))
assert.tool.required=${_assert.tool.required}
assert.tool.required/%:; $(call _assert.tool.required, ${*})
	@# Asserts that the given tool is available, memoizing success across the make
	@# process tree (the memo is exported, so a recursive `make` inherits it).
	@# Reinvocation for the same tool is a silent no-op (no probe, no logging); a
	@# docker run does not inherit the memo and re-probes.  Also available as a macro that
	@# takes an optional 2nd HINT arg shown on failure -- `cmk.assert.tool.required(foo, <hint>)`
	@# -- which the `/%` prereq form cannot carry (a prereq is one whitespace-split word).

# --- Stream assertions --------------------------------------------------------
# assert.stream.stdin.required -- guard: unless stdin is a stream, log (via the
# calling target, ${@}) and exit 1.
assert.stream.stdin.required=if ${io.tty.stdin}; then $(call log.error, needs a stream on stdin) ; exit 1 ; fi

# --- Plugin assertions --------------------------------------------------------
# assert.plugin(<name>): RECIPE guard -- passes if plugin <name> is already loaded (in __plugins__) or is
# AVAILABLE in CMK_PLUGINS_DIR, else logs + exits 1.  The availability fallback is what makes it usable by
# code that COMPILES a plugin rather than importing it (e.g. the repl harness in `lang.repl.launch`), where
# the plugin is never in the registry.  (Parse-time registry-only assert is `__plugins__.assert`.)
assert.plugin=$(if $(call __plugins__.has,$(m5[1])),true,{ [ -n "$(call cmk.plugin.find,${1})" ] || { $(call log.io, ${red}assert.plugin ${sep}${no_ansi} plugin not available${no_ansi_dim}: ${no_ansi}${bold}$(m5[1])${no_ansi} ${dim}(searched ${CMK_PLUGINS_DIR})) ; exit 1 ; } ; })

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: mk.* :: Meta-tooling and extensions to make itself
##
## Reflection and runtime changes, in several families:
##
## * mk.super.* :: Signals and supervisors
## * mk.def.* :: Tools for reading 'define' blocks
## * mk.parse.* :: Makefile parsing (used as part of generating help)
## * mk.help.* :: Help-generation
##
## DOCS:
## * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-mk)
## * `[2]:` [Signals & Supervisors](https://robot-wranglers.github.io/compose.mk/signals)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Real library files: MAKEFILE_LIST minus .mk-suffixed .tmp caches.
mk.__main__.libs = $(call twin.unmap,$(foreach _f,${MAKEFILE_LIST},$(if $(findstring .tmp.,$(_f)),$(if $(filter %.mk,$(_f)),,$(_f)),$(_f))))

mk.__main__:
	@# Runs the default goal, whatever it is.
	@# We need this for use with the supervisor because
	@# usage of `mk.super.enter/<pid>` is always present,
	@# and that overrides default that would run with an empty CLI.
	@# NB: count only real library files -- mk.__main__.libs drops the .mk-suffixed
	@# internal .tmp caches (hosted + builtins ns) but keeps user programs (no .mk).
	case `echo $(mk.__main__.libs)|${stream.count.words}` in \
		1) case `echo $(mk.__main__.libs) | xargs basename` in \
				compose.mk) (\
					$(call log.trace,empty invocation for compose.mk, returning help) \
					&& ${make} help);; \
				*) ${make} $(.DEFAULT_GOAL);; \
			esac ;; \
		0) $(call log.error, library list is empty);; \
		*) (\
			$(call log.trace, multiple library files; looking for a default goal..) \
			&& ${make} $(.DEFAULT_GOAL));; \
	esac

def.to.env=export $(m5[2])="$(shell ${make} mk.def.read/$(m5[1]))"
# Pure-make accessor: expands to a define block's raw text with no sub-make fork. Called with just a
# name it yields the raw text; with any 2nd arg it instead yields a single-line recipe-safe `printf`
# that reproduces the block verbatim on stdout (a heredoc can't be used in a recipe, since make splits
# on expansion-newlines). Newlines become `\n` and backslash/quote are escaped, so dollars, quotes, and
# parens survive both make and the shell. For shell-runtime streaming use the stream-reader form.
_mk.def.value=$(if $(m5[2]?),printf '%b' '$(subst ','\'',$(subst ${nl},\n,$(subst \,\\,$(value $(m5[1])))))',$(value $(m5[1])))
# `_mk.def.to.fd` is the recipe-safe `printf '%b'` form of a block -- the single seam for FD-material-
# ization, used by the stream glyph (wrapped in a process-sub) and by the tmpfile form. `_mk.def.tmpfile`
# is a shell command-substitution that writes the block to a fresh tmpfile under the run-id-keyed prefix
# and echoes its path (swept at end-of-run). A constructor-minted block shadows its own name with a
# callform macro, so prefer the raw ctor-source seed when present; a plain define has none and reads directly.
_mk.def.to.fd=$(call _mk.def.value, $(strip $(if $(call m5.undefined?,$(m5[1]).__ctor_src__),${1},${1}.__ctor_src__)), _)
_mk.def.tmpfile=$$(_brf=$$(mktemp ${CMK_BRF_PREFIX}.XXXXXXXX) && $(call _mk.def.to.fd, ${1}) > $$_brf && printf %s $$_brf)
mk.def.read=CMK_INTERNAL=1 ${make} mk.def.read${_mk.forward.args}
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

mk.def.to.file=${make} mk.def.to.file${_mk.forward.args}
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
		$(call log.base, $${header} ${dim_cyan}${ital}$${def_name} ${green_flow_right} ${dim}${bold}$${out_file}) \
		|| true) \
	&& ${mk.def.read}/$${def_name} > "$${out_file:-$${def_name}}"
mk.ifdef=echo "${.VARIABLES}" | grep -w ${1} ${all_devnull}
mk.ifdef/%:; $(call mk.ifdef, ${*})
	@# Answers whether the given variable is defined.
	@# This is silent, and only communicates via the exit code.
	
mk.ifndef=echo "${.VARIABLES}" | grep -v -w ${1} ${all_devnull}
mk.ifndef/%:; $(call mk.ifndef,${*})
	@# Flips the assertion for 'mk.ifdef'.

.mk.docker.dispatch/%:; img="compose.mk:$${img}" ${make} docker.dispatch/${*}
	@# PRIVATE/internal (leading `.`): like `docker.dispatch` but insists the image is
	@# "local" / internally managed by compose.mk -- auto-prefixes the "compose.mk:" tag.

mk.docker/% mk.docker.image/%:; ${make} docker.image.run/compose.mk:${*}
	@# Like `docker.image.run`, but automatically adds the `compose.mk:` prefix.
	@# This is used with "local" images that are managed by compose.mk itself, 
	@# e.g. embedded images that are built with `Dockerfile.build/..`, etc.
mk.docker.prune:
	@# Like `docker.prune` but only covers "local" images internally 
	@# managed by compose.mk, i.e. using the  "compose.mk:" prefix.
	docker images | grep -E '^(compose.mk|composemk)' | ${stream.peek} \
	| awk '{print $$3}' | ${io.xargs} "docker rmi -f %"
	

mk.docker.rmi/%:; CMK_INTERNAL=1 img="compose.mk:${*}" ${make} docker.rmi
	@# Removes images with `docker rmi`.  Uses the compose.mk prefix automatically.
mk.docker=${make} mk.docker${_mk.forward.args}
mk.docker:; ${mk.docker}/$${img}
	@# Like `mk.docker/..` but expects `img` argument is available from environment.

mk.docker.run.sh:; hostname="$${img}" img="compose.mk:$${img}" ${make} docker.run.sh
	@# Like docker.run.sh, but implicitly assumes the 'compose.mk:' prefix.

# mk.docker.* (collected): local-image clean + bind-script bridge
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

mk.docker.bind.script=$(call _mk.docker.bind.script,${1} build=Dockerfile.build)
define _mk.docker.bind.script
$(call docker.bind.script, $(strip $(shell printf "$(if $(findstring img=,$(1)),$(1),img=$(m5[1]))"| sed s'/img=/img=compose.mk:/')))
endef

mk.get/%:; $(info ${${*}})
	@# Returns the value of the given make-variable

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
		*) $(call log.error, expected format would be set in environment); exit 55;; \
	esac

_mk.help.o=parser_cache=".tmp.$(shell echo `basename ${1}`.parsed.json)" \
	&& $(call io.file.gen.maybe,$${parser_cache},${mkparse} ${1})
mk.help.target/%:; ${mkparse} ${MAKEFILE} --prefix ${*} --markdown --preview 
	@# Shows help docstring for the named target.
	@# By default, this previews the docstring as markdown, using charmbracelet/glow.
	@# Set `preview=0` in environment to override and get raw docstring.
	@# USAGE: ./compose.mk mk.help.target/<target_name>

# The sugar-dispatch table: each row's `__CALL__ d <ctor> <kwargs..>` spec DELEGATES to the
# generic banana lowering, rendered by the shared `build_call` in `.awk.sugarawk` (a `__WITH__`
# placeholder is filled from the block's `with` trailer).  The default table now carries only
# the generic banana; the layer is kept as the extension point for user-defined `cmk_sugar`
# rows (a raw `__NAME__`/`__WITH__`/`__REST__` template still works via the fallback path).
define lang.comp.sugar
[
	["(|", "|)", "__GENERIC__"]
]
endef

# The dialect table: ordered [pattern, replacement] rows, each a literal match (see
# .awk.preprocess.dialect: the pattern's regex metacharacters are auto-escaped before gsub, so
# `.` is a literal dot, never a wildcard -- `cmk.` matches `cmk.` only, never `cmk/`/`cmk)`).
# Patterns need no escaping here, which is why glyph keywords (ᐉ/...) and plain dotted ones
# (this.) both Just Work.  `this.` is the TARGET call-anchor.  The MACRO anchor `cmk.`->`؆`
# is not here: it is structural (the `cmkanchor` stage, not user-overridable) and banana-aware,
# so a qualified ctor head survives to sugar as a literal qualified callform.
define lang.comp.dialect
[
	["ᐉ", ".dispatch/"],
	["🡆", "${stream.stdin} | ${jq} -r"],
	["🡄", "${jb}"],
	["this.", "${make} "]
]
endef

# `_cmk.target.doc` -- the docstring reader behind the `.docs`/`.__doc__` members of the `__target__`
# reflection family (normalized in the callform stage; the family mirrors the make-var dunders
# `${__doc__}`/`${<kls>.__bases__}`).  Recursive `=` so `$@` binds at recipe time; it is a recipe-shell
# command-sub (make's `$(shell)` would not inherit the exported extractor), so it resolves only in a
# raw-shell recipe position (`echo "${__target__.docs}"`), not when passed as a make callform argument.
# It runs only where the token is written, so targets that never reference it pay nothing.
_cmk.target.doc = $$(awk -v t="$@" -v bin="$${__file__:-$${CMK_BIN}}" "$${_awklang_target_doc}" $${__interpreting__:-} $(call twin.unmap,${MAKEFILE_LIST}) 2>/dev/null)

mk.clean:
	@# Cleans `.tmp.*` scratch (files and dirs) from the cwd, PLUS the staged
	@# `.tmp.module.*`/native/hosted artifacts from wherever CMK_STAGE_DIR resolved
	@# (the `./.cmk` seed and the XDG fallback -- both swept, since either may hold a
	@# run's staging).  User-invoked + best-effort (deliberately not an at-exit hook --
	@# see import.module): a non-root `rm` cannot remove files a ROOT docker submake may
	@# have left on a mounted dir.
	rm -rf -- .tmp.* 2>/dev/null || true
	$(if $(filter-out . ./,$(strip ${CMK_MODULES_DIR})),( cd "$(strip ${CMK_MODULES_DIR})" 2>/dev/null && rm -rf -- .tmp.module.* .tmp.hosted.*.mk native ) 2>/dev/null || true)
	( cd "${CMK_XDG_CACHE}" 2>/dev/null && rm -rf -- .tmp.module.* .tmp.hosted.*.mk native ) 2>/dev/null || true

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
_awkv="`awk --version 2>&1 | head -1`" \
&& case "$${_awkv}" in \
	"GNU Awk"*|"mawk"*|"awk version"*) true;; \
	""|*) _awkv="$${_awkv}; `awk 2>&1 | head -1`" ; case "$${_awkv}" in \
		*"BusyBox"*) true;; \
		""|*) printf 'cmk: the CMK compiler supports GNU awk, mawk, busybox awk, and one-true-awk, but PATH awk answered: %s\nInstall one of those (macOS: brew install gawk, then gnubin-first PATH or an awk symlink; alpine: apk add gawk; debian/ubuntu: apt install gawk).\n' "$${_awkv}" >&2; exit 78;; \
	esac;; \
esac \
&& export LC_ALL=C LC_CTYPE=C \
&& $(call log.trace, __file__=$${__file__} \
	__interpreter__=${__interpreter__} \
	__interpreting__="$${__interpreting__:-None}" \
	__script__=$${__script__}) \
&& case $${quiet:-1} in \
	*) runner=flux.pipeline;; \
	0) runner=flux.pipeline;; \
esac \
&& ${io.mktemp} && export inputf=$${tmpf} \
&& ${stream.stdin} > $${inputf} \
&& cmk_pragma=$$(cat $${inputf} | ${lang.parse.pragma.hint}) && export cmk_pragma && cmk_pragma_lines= && cmk_join= \
&& { if [ -n "$${cmk_pragma}" ]; then \
		_pout=$$(printf '%s' "$${cmk_pragma}" | ${jq.run.pipe} -r 'to_entries[]? | (if .key!=(.key|ascii_downcase) then "#WARN \(.key)" else empty end), "export CMK_PRAGMA_\(.key|ascii_upcase|gsub("[.-]";"_")) := \(if (.value|type)=="array" then (.value|join(" ")) else (.value|tostring) end)"' 2>/dev/null || true) ; \
		cmk_pragma_lines=$$(printf '%s\n' "$${_pout}" | grep '^export ' || true) ; \
		while IFS= read -r _pl; do case "$$_pl" in "export CMK_PRAGMA_"*) _k="$${_pl#export }"; _k="$${_k%% := *}"; export "$$_k=$${_pl#* := }";; esac; done < <(printf '%s\n' "$${cmk_pragma_lines}") ; \
		_pwarn=$$(printf '%s\n' "$${_pout}" | sed -n 's/^#WARN //p' | tr '\n' ' ') ; \
		[ -z "$${_pwarn}" ] || $(call log.compiler, ${yellow}mk.compile ${sep}${no_ansi_dim} pragma ${sep} prefer lowercase keys ${sep} ${no_ansi}$${_pwarn}) ; \
		cmk_join=$$(printf '%s\n' "$${cmk_pragma_lines}" | $(call __pragma__.sh,RECIPE_JOIN)) ; \
		export CMK_COMPILER_VERBOSE="$$(printf '%s\n' "$${cmk_pragma_lines}" | $(call __pragma__.sh,COMPILER_VERBOSE) | grep . || printf '%s' "$${CMK_COMPILER_VERBOSE}")" ; \
		export CMK_COMPILER_STEPWISE="$$(printf '%s\n' "$${cmk_pragma_lines}" | $(call __pragma__.sh,COMPILER_STEPWISE) | grep . || printf '%s' "$${CMK_COMPILER_STEPWISE:-}")" ; \
		_pnames=$$(printf '%s\n' "$${cmk_pragma_lines}" | sed -E 's/ :=.*//;s/^export //' | tr '\n' ' ') ; \
		[ -z "$${cmk_pragma_lines}" ] || $(call log.compiler, ${dim}mk.compile ${sep} pragma ${sep} ${ital}$${_pnames}${no_ansi}) ; \
	fi ; true ; } \
&& { if [ "$${CMK_IMPORT_DISCOVER:-0}" != 1 ]; then case "$${CMK_PRAGMA_PLUGIN_PRAGMA_ALLOWED:-}" in \
		""|0|false|no) : ;; \
		*) $(call io.mktemp) && _ppf=$${tmpf} && cat $${inputf} | ${make} __pragma__.resolve > $${_ppf} \
			&& cmk_pragma_lines=$$(cat $${_ppf}) \
			&& while IFS= read -r _pl; do case "$$_pl" in "export CMK_PRAGMA_"*) _k="$${_pl#export }"; _k="$${_k%% := *}"; export "$$_k=$${_pl#* := }";; esac; done < <(printf '%s\n' "$${cmk_pragma_lines}") \
			&& cmk_join=$$(printf '%s\n' "$${cmk_pragma_lines}" | $(call __pragma__.sh,RECIPE_JOIN)) \
			&& $(call log.compiler, ${yellow}mk.compile ${sep}${dim} two-pass ${sep} stacked plugin pragmas ${sep}${ital} plugin_pragma_allowed${no_ansi}) ;; \
	esac ; fi ; } \
&& export CMK_INTERNAL=1 \
&& printf "#!/usr/bin/env -S __interpreting__=$${__interpreting__:-stdin} ${__interpreter__} mk.interpret\nMAKEFILE_LIST+=${CMK_SRC}\n" \
&& { [ -z "$${cmk_pragma_lines}" ] || printf '%s\n' "$${cmk_pragma_lines}" ; } \
&& __interpreting__=$${__interpreting__:-stdin} \
	${make} mk.src \
&& case $${CMK_COMPILER_STEPWISE:-0} in \
	1) cat $${inputf} | style=monokai lexer=makefile ${make} $${runner}/lang.comp.pipeline.head,io.awk/.awk.dispatch,io.awk/.awk.joinbody,io.awk/.awk.cmk.unsentinel,lang.comp.pipeline.tail ;; \
	*) cat $${inputf} | ${lang.comp.pipeline} ;; \
	esac
endef

mk.compile! mk.compiler!:
	@# Like `mk.compile`, but also embeds the result thus removing the include
	@# for `compose.mk` to produce a completely stand-alone file.  See also: `lang.src.fork.guest`
	${flux.pipeline}/mk.compile,lang.comp.pipeline.minify | sed "\|^MAKEFILE_LIST+=${CMK_SRC}|d" | ${make} lang.src.fork.guest

lang.transpile:; ${lang.transpile}
	@# Transpiles CMK-lang on stdin to a bare, includable Makefile fragment on stdout.
	@# Unlike `mk.compile`, it emits no shebang, no `MAKEFILE_LIST+=` line, and no
	@# `mk.src` context embedding -- so the output is safe to `include`/`-f`.  This is
	@# the shared primitive under `native_target`/`cmk.cook` and the hosted cache.
	@#
	@# It is exactly the fused transpile chain `mk.compile` runs internally (preprocess
	@# -> dispatch -> joinbody -> imports) minus the stand-alone wrapper preamble.  The
	@# `joinbody` stage is load-bearing: without it each transpiled recipe line runs in
	@# its own shell (a var set on one line is empty by the next).
	@#
	@# USAGE:
	@#  printf 'foo:\n  cmk.log(hi)\n' | ./compose.mk lang.transpile

# lang.transpile (macro form): stdin CMK-lang -> bare Makefile fragment on stdout.  Streams
# directly (the pipeline buffers its own stdin), so no pragma-hint pre-scan happens here.
define lang.transpile
${stream.stdin} | ${lang.comp.pipeline}
endef

# mk.cache.ensure: shared cache gate; build on miss.
mk.cache.ensure = if $(2); then $(call log.io, $(m5[1]) ${sep} ${dim_green}cache HIT${no_ansi}); else $(call log.io, $(m5[1]) ${sep} ${yellow}cache MISS${no_ansi}); $(3); fi

# native_target / cmk.cook -- JIT-compile a CMK-lang `define` on first call. Make expands recipes
# lazily, so a target that uses one but is never built costs nothing; the named define is transpiled and
# content-cached on first call, reused after. native_target freezes one side-effecting target to a bash
# script (no make subprocess when warm); cmk.cook re-execs make for a fragment of many targets/vars.

# cmk.cook / _cmk.cook.frag -- the seed-level cook-and-run primitive: lower a raw cmk-lang define to
# code (lang.transpile), content-cache it, re-exec the entry in a child make.  Stripping the def name
# is load-bearing (a called arg carries a leading space, which would misname the value lookup).
# `_cmk.cook.frag` is the inline single-line twin for a complete fragment carrying its own entry: it
# materializes the value to a file (a printf-hole would break on a newline), then transpiles and runs it.
define cmk.cook
@$(call log.io, ${bold}$(m5[2])${no_ansi} ${sep}${dim} cmk.cook ${sep} JIT compile + run)
$(call mk.native.stage,${CMK_NATIVE_CACHE}/$(m5[1]).raw,$(value $(m5[1])))
@raw=${CMK_NATIVE_CACHE}/$(m5[1]).raw; \
key=`cksum < $$raw | awk '{printf "%07x",$$1%268435456}'`; \
out=${CMK_NATIVE_CACHE}/$(m5[1]).$$key.mk; \
$(call mk.cache.ensure, native ${sep}${dim} $(m5[1]), [ -s "$$out" ], ${make} lang.transpile < $$raw 2>/dev/null > "$$out.tmp" && mv "$$out.tmp" "$$out"); \
$(MAKE) ${MAKE_FLAGS} -f $(cmk.self) -f "$$out" $(m5[2])
endef
_cmk.cook.frag = $(call mk.native.stage,${CMK_NATIVE_CACHE}/cf.$(m5[1]).raw,$(value $(m5[1])))_cfr=${CMK_NATIVE_CACHE}/cf.$(m5[1]).raw && _cfo=${CMK_NATIVE_CACHE}/cf.`cksum < $$_cfr | awk '{printf "%07x",$$1}'`.mk && { [ -s "$$_cfo" ] || ${make} lang.transpile < $$_cfr 2>${devnull} > "$$_cfo" ; } && $(MAKE) ${MAKE_FLAGS} -f $(cmk.self) -f "$$_cfo" __main__

# native_target(<def-name>,<entry-target>): lower once, then freeze the fully-expanded
# recipe to a pure-shell script with `make -n` (resolves every `$(call ..)`/`${@}` at
# freeze time).  Warm path never touches make -- just `bash <script>`.  Must be `bash`
# (frozen recipe uses `[ "0" == "1" ]`), not `sh`.  Fits a single side-effecting target.
define native_target
@$(call log.io, ${bold}$(m5[2])${no_ansi} ${sep}${dim} native_target ${sep} JIT compile + freeze)
$(call mk.native.stage,${CMK_NATIVE_CACHE}/$(m5[1]).raw,$(value $(m5[1])))
@raw=${CMK_NATIVE_CACHE}/$(m5[1]).raw; \
key=`cksum < $$raw | awk '{printf "%07x",$$1%268435456}'`; \
sh=${CMK_NATIVE_CACHE}/$(m5[1]).$$key.sh; \
$(call mk.cache.ensure, native ${sep}${dim} $(m5[1]) ${dim} bash, [ -s "$$sh" ], frag=$$sh.frag.mk; ${make} lang.transpile < $$raw 2>/dev/null > $$frag && $(MAKE) ${MAKE_FLAGS} -f $(cmk.self) -f $$frag -n $(m5[2]) 2>/dev/null > $$sh.tmp && mv $$sh.tmp $$sh); \
bash $$sh
endef


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
	@#  echo flux.ok | ./compose.mk mk.kernel
	@#  echo flux.and/flux.ok,flux.ok | ./compose.mk mk.kernel
	@#
	instructions="`${stream.stdin} | ${stream.nl.to.space}`" \
	&& count=`printf "$${instructions}" | ${stream.count.words}` \
	&& $(call log.part1, parsing input stream as instructions ) \
	&& $(call log.part2, ${yellow}$${count}${no_ansi_dim} total) \
	&& ${trace_maybe} && ${make} $${instructions}

mk.kernel.each:
	@# Iterative sibling of the kernel runner: runs each non-empty line of the input
	@# stream as its own instruction, in order, each in a SEPARATE recursive
	@# `make` (so a line may carry an argument, e.g. `target/arg`).  Fails fast.
	@#
	@# Where the base kernel collapses the whole stream to whitespace and runs it as
	@# one `make instr1 instr2 ..` invocation, this re-enters make per line.  That
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

mk.src:
	@# Returns source-code for this make-context (excluding compose.mk).
	@# This effectively flattens includes, basically concatenating 
	@# MAKEFILE_LIST in reverse order, and is used internally as part 
	@# of mk.compile.  This has a different meaning if called from extensions
	@# 
	$(call assert.env,__script__)
	$(call log.compiler,${@} ${sep}${dim} Generating source code for context)
	[ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] || printf '\n# generated from context:\n'
	[ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] || ${jb} \
		MAKEFILE_LIST='${MAKEFILE_LIST}' \
		MAKEFILE=${MAKEFILE} \
		make='${make}' \
		__script__='$${__script__}' \
		__file__=$${__file__} \
		__interpreter__=$${__interpreter__} \
		__interpreting__='$${__interpreting__}' \
	 | ${jq} . | awk '{print "#  " $$0}'
	src_list="$(subst ${CMK_SRC},,${MAKEFILE_LIST})" \
	&& case "$${__script__}" in \
		""|None|"${__file__}") $(call log.trace, ${@} ${sep} no separate script was found);; \
		*) ( \
				$(call log.mk, compiling with script ${__script__}) \
				&& $(call log.mk, ${yellow}script will be included!) \
				&& cat $${__script__} && printf '\n'; \
			) \
	esac \
	&& case "$${src_list}" in \
		"") $(call log.trace, ${@} ${sep} no other sources to include);; \
		*) $(call log.trace, ${@} ${sep} ${yellow}possible extra source to include: $${src_list});; \
	esac

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.comp :: The CMK compiler pipeline (awk preprocess -> Makefile)
##
## head|body|tail pipeline (mk.compile / lang.transpile): head fuses
## the pragma stages, body the fixed passes, tail resolves imports.
##
## * lang.comp.pipeline[.body/.tail] :: the three composed tiers
## * lang.comp.stages[.all/.core/.pre/.post] :: stage list + pragma knobs
## * lang.comp.pipeline.<stage> :: per-stage debug targets (stepwise mode)
## * lang.comp.stats :: size / partition metrics for compose.mk
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Three tiers; stream flows head -> body -> tail (inline macro).
lang.comp.pipeline.body = awk "$${_awklang_dispatch}" | awk -v JOIN="$${cmk_join:-$${CMK_RECIPE_JOIN:-&&}}" "$${_awklang_joinbody}" | awk "$${_awklang_unsentinel}"
lang.comp.pipeline = ${make} lang.comp.pipeline.head | ${lang.comp.pipeline.body} | ${make} lang.comp.pipeline.tail
# kwargs sentinel: an in-quote space kept as one make word.
lang.comp.kwargs.sp := ␟
export CMK_KWARGS_SP := ${lang.comp.kwargs.sp}

lang.comp.pipeline.tail:
	@# CMK compile stage (stdin->stdout): replaces each
	@# `import.{target,targets,def,defs}` callform line with the resolved blocks
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

lang.comp.pipeline.dialect:; ${lang.comp.stage.dialect}
	@# Runs dialect preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	@# (body lives in the `lang.comp.stage.dialect` macro, shared with the fused fast path.)

lang.comp.pipeline.sugar:; ${lang.comp.stage.sugar}
	@# Runs sugar-preprocessor on stdin.
	@# Part of the CMK->Makefile transpilation process.
	@# (body lives in the `lang.comp.stage.sugar` macro, shared with the fused fast path.)

# The preprocess stages, in pipeline order (single source of truth).
lang.comp.stages=minify dedent decorators dialect cmkanchor m5wrap moduledoc sugar lambdalift nslint acquire fluent receivers tagged callform blockref triplequote indent imports call capture

# compiler_pre/post: extra stages spliced around the chain via pragma.
lang.comp.stages.pre=$(strip $(call __pragma__.append, compiler_pre))
lang.comp.stages.post=$(strip $(call __pragma__.append, compiler_post))
lang.comp.stages.all=$(strip $(lang.comp.stages.pre) $(lang.comp.stages) $(lang.comp.stages.post))
# core: stages backed by a lang.comp.stage macro.  lifted: the rest, resolved from plugin blocks.
lang.comp.stages.core=$(call m5.select,$(lang.comp.stages.all),lang.comp.stage.%)
lang.comp.stages.lifted=$(filter-out $(lang.comp.stages.core),$(lang.comp.stages.all))

# _cmk.stage.lift: resolve a non-core stage from a plugin block.
_cmk.stage.lift=_lsp= ; _lifs=$$IFS ; IFS=: ; for _ld in $${CMK_PLUGINS_DIR}; do for _lf in "$$_ld"/*.cmk; do { [ -f "$$_lf" ] && grep -q "^define _cmk_blk_$(m5[1])$$" "$$_lf" ; } && { _lsp="$$_lf" ; break 2 ; } ; done ; done ; IFS=$$_lifs ; if [ -n "$$_lsp" ]; then $(call io.mktemp) && sed -n "/^define _cmk_blk_$(m5[1])$$/,/^endef/{/^define/d;/^endef/d;p;}" "$$_lsp" > $${tmpf} && _cmklift_$(m5[1])="$${tmpf}" && $(call log.compiler, lang.comp.pipeline ${sep}${dim} lifted plugin stage ${ital}$(m5[1])${no_ansi}) ; else _cmklift_$(m5[1])= ; $(call log.compiler, lang.comp.pipeline ${sep}${dim} stage ${ital}$(m5[1])${no_ansi} not found (no core lang.comp.stage. macro, no plugin _cmk_blk_) ${sep} skipped) ; fi

# Drop the timer wrapper (bare pipeline) when CMK_COMPILER_VERBOSE=0.
lang.comp.pipeline.head: $(if $(filter 0,${CMK_COMPILER_VERBOSE}),.lang.comp.pipeline,flux.timer/.lang.comp.pipeline)
.lang.comp.pipeline:
	@# Runs the CMK input preprocessor on stdin.
	@# Default: a fused single-process pipeline (the four stages composed via
	@# their macros, no make-per-stage). CMK_COMPILER_STEPWISE=1 keeps the
	@# step-wise flux.pipeline of the stage *targets* (per-stage previews) for
	@# debugging. Both compose the same stage logic, so output is identical.
	@# Requires source on stdin; called with no pipe, it logs the stage order and fails.
	@[ -p ${stdin} ] || { \
		$(call log.warn, stages) \
		; printf '%b\n' "${dim}${ital}${lang.comp.stages.all}${no_ansi}" | fmt -w 64 | ${stream.indent.to.stderr} \
		; $(call log.error, expected an input pipe!) \
		; exit 1 ; }
	export LC_ALL=C LC_CTYPE=C \
	&& $(call io.mktemp) && export inputf=$${tmpf} && export _CMK_CERR=$${tmpf}.cerr && rm -f $${_CMK_CERR} \
	&& ${stream.stdin} > $${inputf} \
	&& export cmk_dialect=$$(cat $${inputf} | ${lang.parse.dialect.hint}) \
	&& export cmk_sugar=$$(cat $${inputf} | ${lang.parse.sugar.hint}) \
	&& export RECEIVERS=$$(cat $${inputf} | ${lang.parse.scan.receivers}) \
	&& export JUNCTIONS=$$(cat $${inputf} | ${lang.parse.scan.junctions}) \
	&& case "$${RECEIVERS// }" in *[![:space:]]*) $(call log.compiler.fmt, lang.comp.pipeline.receivers ${sep}${dim} declared, ${dim}${ital}$${RECEIVERS}${no_ansi}) ;; esac \
	&& { : $(foreach _s,$(lang.comp.stages.lifted),; $(call _cmk.stage.lift,$(_s))) ; } \
	&& case $${CMK_COMPILER_STEPWISE:-0} in \
		1) cat $${inputf} $(foreach _s,$(lang.comp.stages.lifted), | { [ -n "$${_cmklift_$(_s)}" ] && awk -f "$${_cmklift_$(_s)}" || cat ; }) \
			| ${make} flux.pipeline/$(subst $(space),$(comma),$(addprefix lang.comp.pipeline.,$(lang.comp.stages.core))) ;; \
		*) $(call log.trace.compiler.fmt, lang.comp.pipeline ${sep}${dim} fused pipeline, ${dim}${ital}$(lang.comp.stages.all)${no_ansi}) \
			&& cat $${inputf} $(foreach _s,$(lang.comp.stages.all),$(if $(call m5.defined?,lang.comp.stage.$(_s)), | $(lang.comp.stage.$(_s)), | { [ -n "$${_cmklift_$(_s)}" ] && awk -f "$${_cmklift_$(_s)}" || cat ; })) ;; \
	esac \
	| ${stream.nl.compress} \
	&& printf '\n' \
	&& { [ -s $${_CMK_CERR} ] && printf '%s\n' '$$(error cmk-fault errno=GRAMMAR code=65 :: compile-stage error -- see the stderr above)' || true ; } ; rm -f $${_CMK_CERR} 2>/dev/null || true

lang.comp.pipeline/%:
	@# A version of `lang.comp.pipeline` (the full head|body|tail) that accepts a file-arg.
	@#
	@# USAGE: ./compose.mk lang.comp.pipeline/<fname>
	@#
	fname=${*} && case ${*} in -) fname=/dev/stdin;; esac \
	&& cat $${fname} | ${lang.comp.pipeline}

# Size/partition scanner: run-only hosted awklang (compiler_stats).
lang.comp.stats:
	@# Size metrics for compose.mk, one LC_ALL=C awk pass (byte-counting).  SLOC =
	@# non-blank / non-comment lines.  `compiler_sloc` counts lines inside the
	@# `define .awk.*` compiler blocks; `hosted_sloc` those inside the `define
	@# __hosted__` partition (depth-tracked past nested defines).  `core_sloc` =
	@# total SLOC minus the compiler; `seed_sloc` = core minus hosted (the
	@# hand-written seed).  So `total_sloc` = compiler + core, and core = seed +
	@# hosted.  `compiler_ratio` = non-comment core *chars* per non-comment awk
	@# *char*.  Partition boundary lines (the `.awk.*` / `__hosted__` define+endef)
	@# and all comment / blank lines are excluded from every figure.  JSON on stdout
	@# (logs to stderr); feeds the docs/stats renderer -- keep the two awks in sync.
	@#
	@# USAGE: ./compose.mk lang.comp.stats
	$(call log.compiler, ${@} ${sep}${dim} size/partition metrics for ${no_ansi}${CMK_SRC})
	cat ${CMK_SRC} | LC_ALL=C awk "$${_awklang_compiler_stats}" | ${jq} .

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# The composable `.cmk.<stage>` pipe-fragment macros (one per stage) are minted alongside their
# `_awklang_*` exports by `lang.awk.stage`.  The `lang.comp.pipeline.*` targets wrap them for
# standalone/debug use; the fused fast path chains them in one process (no make-per-stage).
# `lang.comp.stage.dialect`/`lang.comp.stage.sugar` below stay hand-written (shell recipes, not `awk "..."` fragments).
# --- DECLARATION / BINDING-FORM GRAMMAR (living spec; keep in sync) -------------------
# `lang.parse.scan.receivers` is the single place that enumerates every cmk-lang form which
# INTRODUCES a bindable name -- a receiver namespace scaffolding a `<name>.<method>`
# target family.  It is a compile-time pre-scan of raw source, not a pipeline stage:
# the `receivers` stage runs early (before `imports`, and before imported files are
# pulled in), so only an upfront source scan sees every namespace before sends are
# rewritten.  That independence makes it a THIRD hand-synced copy of the declaration
# grammar (compiler stages + this scanner + prism-cmk.js/cmk.tmLanguage.json).
#   SYNC RULE: a new binding form => add a `lang.rex.recv.*` row below, and teach the stage that
#   lowers it, and (if lexically visible) both highlighter grammars.  Over-registration
#   is harmless (receivers only fires on `NAME.method<call-suffix>` in recipe content);
#   under-registration silently drops a family.  (Fluent-style chaining `foo().bar()` is a
#   send SHAPE handled inside the receivers stage, NOT a binding form -- it introduces no
#   name, so it deliberately has no `lang.rex.recv.*` row.)  Multi-service compose keeps the
#   `ᐉ`/`.dispatch` send -- its service names are dynamic (from the compose file), so a
#   compile-time scan cannot know them.
#
#   One ROW per form (grep pattern -> the `sed` extractor that yields the bare name):
#     lang.rex.recv.banana    `NAME[(kw)](|`/`[|`/`{|` banana block name    strip kwargs+open digraph
#     lang.rex.recv.kwarg     `namespace=NAME`         declare.*/*.import    strip `namespace=`
#     lang.rex.recv.def       `..def=NAME` (code/  container/image      strip `def=`,`Dockerfile.`
#                     container/docker tokens)
#     lang.rex.recv.importas  `import .. as NAME[,..]` aliased import        strip `.. as `, split `,`
#     lang.rex.recv.openlist  `open|import NAME[,..]`  open/import list      strip kw, split `,`
#     lang.rex.recv.star      `* NAME[,..]`            ambient open (flat)   strip `* `, split `,`
#     lang.rex.recv.goal      `goal NAME = <expr>`     named-lift goal       strip `goal `, drop `= ..`
#     lang.rex.recv.capture   `[&]NAME <- <expr>`      capture/handle LHS    drop `&`, keep NAME, drop `<- ..`
# -------------------------------------------------------------------------------------

# lang.main.* -- entrypoint tooling (distinct from the goal registry, which owns no entry concern). `re`
# detects a col-0 `__main__:` target header (not a variable); `has`/`.has.stream` probe it in a file or
# pipe; the stub bodies are inject-stubs as data; `ensure/<policy>` (below) appends the chosen stub when
# a source declares no entrypoint.
lang.main.re = ^__main__[[:blank:]]*:([^=]|$$)
_lang.main.has = $(shell grep -qsE '$(lang.main.re)' "$(m5[1])" 2>/dev/null && echo __main__)
lang.main.has = $(call m5.memoize.fn, _lmh, _lang.main.has, $(m5[1]))
lang.main.has.stream = grep -qsE '$(lang.main.re)' && echo __main__
lang.main.stub.error := __main__:; echo __main__ wasnt set
lang.main.stub.help  := __main__: help
lang.main.stub.noop  := __main__:; @true
lang.main.ensure/%:
	@# Ensure the piped source declares a __main__ entrypoint; if absent, append the <%> policy
	@# stub (error|help|noop).  The single seam behind the former per-site inject stubs.
	src=`cat` \
	; printf '%s\n' "$${src}" \
	; [ -n "`printf '%s' "$${src}" | ${lang.main.has.stream}`" ] || printf '%s\n' '$(lang.main.stub.$*)'

# The `dsl.*` wrapper over the awk-export minter: it names the export via `as` (defaulting to `def`
# minus `.awk.`, dots to `_`) and delegates the compile to that minter (which injects the pipeline-
# spliced body into `_awklang_<as>`), then adds an optional stdin runner. The safe env-var shape rides
# `$(value)` untouched, so awk's fields never meet a make frame. A constructor kind, usable raw in the
# seed or as a banana, alongside the jqlang fragment kind.
define dsl.awklang
$(call lang.awk.export, main=${self} pipeline=$(call mk.kwargs.get,${1},pipeline) as=$(or $(call mk.kwargs.get,${1},as),$(subst .,_,$(patsubst .awk.%,%,${self}))))
$(if $(call mk.kwargs.get,${1},run),$(call mk.kwargs.get,${1},run)/%:; @$${stream.stdin} | awk -v $(call mk.kwargs.get,${1},stem)='$${*}' "$$$${_awklang_$(_asexport)}")
endef
$(call lang.ctor!, def=dsl.awklang)

# awk-block minters -- a 3-level hierarchy, each reuses the one below.

# lang.awk.export(main=<block> [pipeline=<a:b:c>]) -- exports `_awklang_<name>` only (name = main's last
# dotted segment; pipeline = colon-joined helpers, nearest-main-first, reversed
# before the nl-join + placeholder injection).
lang.awk.export=$(eval _asmain:=$(call mk.kwargs.get,${1},main))$(eval _asexport:=$(or $(call mk.kwargs.get,${1},as),$(lastword $(subst ., ,$(_asmain)))))$(eval export _awklang_$(_asexport) := $$(call lang.grammar.ctx.fill,$$(call m5.splice!,$(call m5.lex.rev,$(subst :, ,$(call mk.kwargs.get,${1},pipeline))) $(_asmain))))

# lang.awk.comp(.. [stage_name=<s>], [<awk-cli-extra>]) -- + the `.cmk.<name>=awk [extra] ".."` pipe-
# fragment (`stage_name` renames it, default = export name; the positional extra rides verbatim).
lang.awk.comp=$(call lang.awk.export,${1})$(eval _asstage:=$(or $(call mk.kwargs.get,${1},stage_name),$(_asexport)))$(eval lang.comp.stage.$(_asstage)=awk $(if $(filter-out undefined,$(origin 2)),$(if $(m5[2]),$(m5[2]) ))"$$$${_awklang_$(_asexport)}")

# lang.awk.stage(..) -- + its `lang.comp.pipeline.<name>` standalone/debug stage target.
lang.awk.stage=$(call lang.awk.comp,${1},$(if $(filter-out undefined,$(origin 2)),$(2)))$(eval lang.comp.pipeline.$(_asstage):; $${stream.stdin} | $${lang.comp.stage.$(_asstage)})

# The reflective-tower kind: a compile stage AS a fragment.  A seed minter, cf. the pure string
# fragment, whose materialize-with-grammar fill reproduces the pass-composer's export -- so the
# composer's own inject-over-spliced-sources IS the fragment substrate.  Takes def=<awk-block>.
$(call m5.def.!, lang.awk.stage.fragment, _lang.awk.stage.fragment)
define _lang.awk.stage.fragment
$(eval _asf := $(or $(call mk.kwargs.get,${1},def),$(firstword ${1})))
$$(call lang.seed.materialize!, $(_asf), lang.proto.tmpl.materializable)
$(_asf).__sources__ ?= $(_asf)
$(_asf).shape = $$(call m5.splice!,$$($(_asf).__sources__))
$(_asf).__mod__ = $$(call lang.grammar.ctx.fill,$$($(_asf).shape))
endef
# lang.awk.stage.frag -- like lang.awk.stage but the export is sourced from a stage-fragment: its source
# list (`.__sources__` = reversed pipeline + main) is spliced then grammar-filled by `.__mod__`, directly
# (no define round-trip).  Handles single AND multi-source; the positional awk-cli-extra rides as before.
lang.awk.stage.frag = $(eval _asmain:=$(call mk.kwargs.get,${1},main))$(eval _asexport:=$(or $(call mk.kwargs.get,${1},as),$(lastword $(subst ., ,$(_asmain)))))$(eval _asstage:=$(or $(call mk.kwargs.get,${1},stage_name),$(_asexport)))$(eval $(_asmain).__sources__ := $(call m5.lex.rev,$(subst :, ,$(call mk.kwargs.get,${1},pipeline))) $(_asmain))$(eval $(call lang.awk.stage.fragment, def=$(_asmain)))$(eval export _awklang_$(_asexport) := $$($(_asmain).__mod__))$(eval lang.comp.stage.$(_asstage)=awk $(if $(filter-out undefined,$(origin 2)),$(if $(m5[2]),$(m5[2]) ))"$$$${_awklang_$(_asexport)}")$(eval lang.comp.pipeline.$(_asstage):; $${stream.stdin} | $${lang.comp.stage.$(_asstage)})
# lang.awk.export.frag -- the export-only twin (no comp/stage wrappers), for the fixed terminal stages.
lang.awk.export.frag = $(eval _asmain:=$(call mk.kwargs.get,${1},main))$(eval _asexport:=$(or $(call mk.kwargs.get,${1},as),$(lastword $(subst ., ,$(_asmain)))))$(eval $(_asmain).__sources__ := $(call m5.lex.rev,$(subst :, ,$(call mk.kwargs.get,${1},pipeline))) $(_asmain))$(eval $(call lang.awk.stage.fragment, def=$(_asmain)))$(eval export _awklang_$(_asexport) := $$($(_asmain).__mod__))

# Dialect/sugar as pipe-stage macros (verbatim transcription of the target bodies below; only
# `${@}` -> literal name and `#` -> `\#` for the make-variable comment trap).  Wrapped in (...) so
# they compose in the fused pipeline; each reads stdin at its eval and writes stdout.  (A literal
# `#` inside a make *variable* starts a comment, hence the `\#`.)

# _cmk.gen.dialect / _cmk.gen.sugar -- jq-free readers for the [pattern,replacement,..] rule tables:
# parse the array-of-arrays JSON with awk (already a hard dep) and emit the same per-row `| awk ..`
# pipeline the stage evals -- byte-equivalent to the old `${jq} -r ".[] | .."`, so compiling CMK
# (incl. the hosted block cold) no longer needs jq.  Field values never contain " or ' (q=' , b=\ ,
# built via %c to keep the source clean).
_cmk.gen.dialect=awk -v prog='${.awk.preprocess.dialect}' 'BEGIN{q=sprintf("%c",39);b=sprintf("%c",92)}{line=$$0;n=0;while(match(line,/"[^"]*"/)){f[++n]=substr(line,RSTART+1,RLENGTH-2);line=substr(line,RSTART+RLENGTH)}for(i=1;i+1<=n;i+=2)printf " | awk -v bs=%s -v amp=%s -v old=%s -v new=%s %s\n",q b b q,q "&" q,q f[i] q,q f[i+1] q,q prog q}'
_cmk.gen.sugar=awk -v sa="$${sugar_awk}" 'BEGIN{q=sprintf("%c",39)}{line=$$0;n=0;while(match(line,/"[^"]*"/)){f[++n]=substr(line,RSTART+1,RLENGTH-2);line=substr(line,RSTART+RLENGTH)}for(i=1;i+2<=n;i+=3)printf " | awk -f %s -v pid=$$$$ %s %s %s \n",sa,q f[i] q,q f[i+1] q,q f[i+2] q}'

lang.comp.stage.dialect=( $(call io.mktemp) && hint_file=$${tmpf} && case $${cmk_dialect} in "") ( dialect=$${dialect:-lang.comp.dialect} && $(call log.compiler, lang.comp.pipeline.dialect ${sep}${dim} using ${ital}$${dialect}) && if [ "$${dialect}" = lang.comp.dialect ]; then printf '%s' "$${_cmk_blk_dialect}" > $${hint_file}; else ${mk.def.read}/$${dialect} > $${hint_file}; fi );; *) ( $(call log.compiler, lang.comp.pipeline.dialect ${sep}${dim} using dialect from file) && printf "$${cmk_dialect}" > $${hint_file} && printf "\# cmk_dialect ::: $${cmk_dialect} :::\n" );; esac && $(call io.mktemp) && parser_file=$${tmpf} && cat $${hint_file} | ${_cmk.gen.dialect} > $${parser_file} && printf '\n' && ${stream.stdin} | eval ${stream.stdin} `cat $${parser_file}` )

lang.comp.stage.sugar=( $(call io.mktemp) && hint_file=$${tmpf} && case $${cmk_sugar} in "") ( sugar=$${sugar:-lang.comp.sugar} && $(call log.compiler, lang.comp.pipeline.sugar ${sep}${dim} using ${ital}$${sugar}) && if [ "$${sugar}" = lang.comp.sugar ]; then printf '%s' "$${_cmk_blk_sugar}" > $${hint_file}; else ${mk.def.read}/$${sugar} > $${hint_file}; fi );; *) ( $(call log.compiler, lang.comp.pipeline.sugar ${sep}${dim} using sugar from file) && printf "$${cmk_sugar}" > $${hint_file} && printf "\# cmk_sugar ::: $${cmk_sugar} :::\n" );; esac && $(call io.mktemp) && parser_file=$${tmpf} && $(call io.mktemp) && sugar_awk=$${tmpf} && printf '%s' "$${_awklang_sugarawk}" > $${sugar_awk} && cat $${hint_file} | ${_cmk.gen.sugar} > $${parser_file} && eval cat /dev/stdin `cat $${parser_file}` )

# lang.runtime.classify_fault -- the run-time fault classifier used by the mk.validate / cli.cmk error branches.
# The awk program lives in `__hosted__` (`dsl.awklang classify_fault`, exported `_awklang_classify_fault`).
lang.runtime.classify_fault=awk "$${_awklang_classify_fault}"
# _cmk.host.machine: out=navigate outward; else dispatch by own name.
_cmk.host.machine = $(if $(filter out,$(m5[1])),outwards,$(m5[1]))

# host.native <x>: mint the host.native.<x> singleton (idempotent).
host.native = $(if $(filter undefined,$(origin 1)),,$(if $(call m5.defined?,host.native.$(m5[1]).run),,$(eval $(call cmk.host, def=host.native.$(m5[1]) entrypoint=$(m5[1])))))
# host.native is a module: manifest = native host interpreters
host.native.__all__ := bash sh python
# mint each module's __open__/__dir__ (after all __all__ declared)
$(foreach _m,$(lang.module.core),$(eval $(_m).__open__ = $$(call lang.module.bind,$(_m),$$(or $$(strip $${1}),$$($(_m).__all__))))$(eval $(_m).__dir__ = $$(sort $$(patsubst $(_m).%,%,$$(filter $(_m).%,$$(.VARIABLES))))))

# Host vs container is discriminated by img-presence: an empty `img` runs on the host subkind, a set
# `img` runs in a container. The ambient dissolve seam opens a boundary by dispatching to the subkind's
# dissolve method (the module/path variants are plain deferred macros below), defaulting to the base
# inline dissolve. (machine/container are the run-side subkinds, built as classes in the hosted partition.)
export __ambients__ ?=


# The BASE ambient dissolve (kind empty / inline): the body is make code, so eval it flat.
ambient.dissolve.inline = $(call _mk.assert.define,$(m5[1]))$(eval $(value $(m5[1])))

# _ambient.pathsrc(<src>) -- resolve an import source: a `/`-bearing token is a verbatim path, a
# bare name is found on CMK_PLUGINS_DIR.  An extensionless bare name falls back to `<name>.cmk` then
# `<name>.mk`, so the kwargs directive resolves the same file the bare form would (kwarg-forwarding).
_ambient.pathsrc = $(if $(findstring /,${1}),${1},$(or $(call cmk.plugin.find,${1}),$(call cmk.plugin.find,${1}.cmk),$(call cmk.plugin.find,${1}.mk)))

# _ambient.fwd(<kwargs>) -- the import kwargs to pass through to the loader: every token except the
# ambient's own control keys `kind=`/`def=` (so namespace=/flat=/preprocs=/targets=/defs= ride along).
_ambient.fwd = $(foreach _kv,${1},$(if $(filter kind def,$(firstword $(subst =, ,${_kv}))),,${_kv}))

# module / path -- the load subkinds for open/import, the `Openable` protocol's `.__open__` method per
# kind (structural conformers). Plain deferred macros: the route calls the kind's `.__open__` with the
# payload def-name and the pass-through kwargs; each treats the def as data (a plugin name or a file),
# resolves-and-loads it, and forwards the kwargs, rather than eval-ing it as code. So every open/import
# form -- bare, `as <ns>`, and `kw=v` -- lands on this one seam, and the kwargs carry flat-vs-namespace through.
module.__open__ = $(call include.plugins, strict=0 $(foreach _n,$(value $(m5[1])),$(_n).cmk $(_n).mk))
path.__open__ = $(call import.module, file=$(call _ambient.pathsrc,$(strip $(value $(m5[1])))) $(call _ambient.fwd,${2}))

# lang.module.from mod names -- from-import / open dispatcher: the module's kind is decided here at import time, never by the compiler.
lang.module.from = $(if $(call m5.defined?,$(m5[1]).__open__),$(call _lang.module.from.core,$(m5[1]),$(m5[2])),$(call _lang.module.from.path,$(m5[1]),$(m5[2])))
# in-core prelude: bind members through the module's own open method; a star takes the whole roster, minus any except-list.
_lang.module.from.core = $(if $(filter *,$(m5[2][1])),$(if $(word 3,$(m5[2])),$(call $(m5[1]).__open__,$(filter-out $(wordlist 3,999,$(m5[2])),$($(m5[1]).__all__))),$(call $(m5[1]).__open__)),$(call $(m5[1]).__open__,$(m5[2])))
# disk plugin: the whole module loads flat either way (bodies are not rewritten, so members need their siblings), then the listed names bind bare.
_lang.module.from.path = $(if $(filter *,$(m5[2][1])),$(call include.plugins, strict=0 $(m5[1]).cmk $(m5[1]).mk),$(call _lang.module.from.file,$(m5[1]),$(m5[2]),$(or $(call _ambient.pathsrc,$(m5[1])),$(call mk.error, from-import: no module named `$(m5[1])`, errno=MODULE_MISSING))))
# the staged path is recomputed from the source, since nested imports clobber the staging globals.
_lang.module.from.file = $(call import.module, file=${3} flat=1)$(eval _lang_from_staged:=${CMK_STAGE_DIR}/.tmp.module.$(call _mk.module.key,$(basename $(notdir ${3})),$(basename $(notdir ${3})))-$(call _mk.hash.file,${3}).mk)$(call _lang.module.from.bind,${1},${2})
# a qualified member aliases to its bare name; one the module already declares bare passes through; anything else is a fault.
_lang.module.from.bind = $(foreach _n,$(m5[2]),$(if $(filter $(m5[1]).%,$(_n)),$(call _lang.module.from.check,$(m5[1]),$(_n)),$(if $(call _lang.module.qmember?,$(m5[1]),$(_n)),$(call lang.module.bind,$(m5[1]),$(_n)),$(if $(call _lang.module.target?,$(m5[1]).$(_n)),$(eval $(_n): $(m5[1]).$(_n)),$(call _lang.module.from.check,$(m5[1]),$(_n))))))
_lang.module.from.check = $(if $(or $(call m5.defined?,${2}),$(filter ${2}.%,$(.VARIABLES)),$(call _lang.module.target?,${2})),,$(if ${__hosted__.loaded},$(call mk.error, cmk: `$(strip ${2})` is not a member of module `$(m5[1])`, errno=MODULE_MEMBER),))
_lang.module.qmember? = $(or $(call m5.defined?,${1}.${2}),$(filter ${1}.${2}.%,$(.VARIABLES)))
# target-only members are invisible to the variable roster, so probe the just-staged module file.
_lang.module.target? = $(shell grep -Em1 '^$(subst .,\.,$(strip ${1}))[:/%]' ${_lang_from_staged} 2>/dev/null)

# ambient.dissolve <def> [kind=..] [kw=v..] -- dispatch to the kind's own `.__open__` method, passing
# the def payload plus the pass-through kwargs, defaulting to the base inline dissolve. A kind with no
# `.__open__` method (and an empty kind) both fall back to inline dissolve -- an unknown kind is not
# applied as a ctor. This is the one open seam; each subkind defines `.__open__` to change how it opens.
ambient.dissolve = $(call _ambient.dissolve.route,$(strip $(call mk.kwargs.get,${1},kind)),$(strip $(call mk.kwargs.get,${1},def)),${1})
_ambient.dissolve.route = $(if ${1},$(if $(call m5.defined?,${1}.__open__),$(call ${1}.__open__,${2},${3}),$(call ambient.dissolve.inline,${2})),$(call ambient.dissolve.inline,${2}))

# ambient.enter <name>: env-prefix moving the chain one level in; dual of ambient.exit.  The stack rides the env comma-joined, staying one shell word across the docker run quoting seams.
_ambient.stack? = $(subst ${comma},${space},$(__ambient_stack__))
_ambient.stack.enc = $(subst ${space},${comma},$(strip ${1}))
_ambient.frame = $(or $(__ambient__),$($(strip ${1}).__ambient_parent__))
ambient.enter = __ambient_stack__="$(call _ambient.stack.enc,$(call m5.stack.push,$(call _ambient.frame,${1}),$(_ambient.stack?)))" __ambient__="$(strip ${1})" __ambient_parent__="$(call _ambient.frame,${1})"

# ambient.exit: env-prefix moving the chain one level out.  A pop that empties the stack refills it from the destination's declared parent, so the parent link is always the stack top and an outward climb can keep going.
_ambient.dest? = $(call m5.stack.top,$(_ambient.stack?))
_ambient.rest? = $(or $(call m5.rest,$(_ambient.stack?)),$(call m5.stack.push,$($(_ambient.dest?).__ambient_parent__),))
ambient.exit = __ambient__="$(_ambient.dest?)" __ambient_stack__="$(call _ambient.stack.enc,$(_ambient.rest?))" __ambient_parent__="$(call m5.stack.top,$(_ambient.rest?))"

# ambient.root <name>: env-prefix landing at a root, where the chain is fully unwound and nothing encloses you.  An empty parent is the sentinel a further outward move faults on.
ambient.root = __ambient__="$(or $(strip ${1}),host.local)" __ambient_stack__="" __ambient_parent__=""

# ambient.out.<x>: the outward move a kind performs, selected by its `.__out__` hook.  `default` lands on the host, `escape` is what a container can reach through the socket, `unavailable` is the refusal from a kind with no channel back.
ambient.out.inward = ${ambient.exit} ${make} $${P}.reenter/${1}
ambient.out.default = if [ "$$P" = host.local ]; then $(call ambient.root) ${make} host.local.reenter/${1}; else $(call ambient.out.inward,${1}); fi
ambient.out.escape = if [ "$$P" = host.local ]; then $(call ambient.out.socket,${1}); else $(call ambient.out.inward,${1}); fi
ambient.out.socket = if [ ! -S "$${DOCKER_SOCKET:-/var/run/docker.sock}" ]; then echo 'cmk: out denied -- no host channel (mount the docker socket to grant escape)' >&2; exit 1; fi; ${io.mktemp} && ${mk.def.to.file}/${1},$${tmpf} && $(call ambient.root,host.daemon) img="$${img:-debian:bookworm-slim}" entrypoint=bash cmd="/workspace/$$(basename $${tmpf}) $${CMK_LAMBDA_ARGV:-}" ${make} docker.run.sh
ambient.out.unavailable = echo 'cmk: OutwardsUnavailable: $(strip ${1}) offers no channel back to its enclosing ambient' >&2; exit 1

# cmk.ambient.host/<def> (run a machine DEF) + cmk.host.exec (run a prebuilt `cmd=..`) -- THE
# irreducible base ambient: raw host exec, never lowered through `in`; everything nests over these.
# if/then/else (not `A && B || C`) so a failing body propagates its exit code.
cmk.ambient.host/%:
	$(call io.mktemp) \
	&& ${mk.def.to.file}/${*},$${tmpf} \
	&& if [ -p ${stdin} ]; then ${stream.stdin} | bash ${dash_x_maybe} $${tmpf}; else bash ${dash_x_maybe} $${tmpf}; fi
cmk.host.exec:; @if [ -p ${stdin} ]; then ${stream.stdin} | bash ${dash_x_maybe} -c "$${cmd}"; else bash ${dash_x_maybe} -c "$${cmd}"; fi

# literal (not regex) substitution of `old`->`new` outside define-blocks. `old`/`new` arrive via `-v`
# (per rule); BEGIN regex-escapes the pattern's ERE metacharacters so the gsub matches them as plain
# text -- a `.` in a dialect keyword is a literal dot, never a wildcard. `bs` (a backslash) and `amp`
# come in via `-v` too: this awk source can hold no string literal (its `"` would close the embedding
# jq string), no `$`, and no literal `\`, so it uses implicit-$0 gsub plus param-fed escapes.
.awk.preprocess.dialect=\
	BEGIN{ block=0; gsub(/[].*+?(){}|[]/, bs bs amp, old); gsub(/[&]/, bs bs amp, new) } /^define/{block=1} /^endef/{block=0} !block{gsub(old,new)} 1

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.parse :: Read-only extraction from CMK source
##
## Runs before the compile pipeline (lang.comp) to hand it the
## metadata it needs via env: the `*.hint` parsers pull the `:::`-delimited JSON out of a header comment
## (`cmk_pragma`/`cmk_dialect`/`cmk_sugar`), and the `scan.*` macros grep the raw source for declared
## receivers (`-v RECEIVERS`) and junction overrides (`-v JUNCTIONS`). Distinct from lang.comp (which
## transforms source) and from mk.parse (which reflects over a finished makefile).
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# Header-hint parsers as single-source macros: extract the `:::`-delimited JSON
# from a `# cmk_dialect/sugar ::: ... :::` header comment. The targets below wrap
# these (kept standalone/debug-invocable + tested); `.lang.comp.pipeline` expands them
# inline (no make-per-hint re-parse). NB: a literal `#` in a make *variable*
# starts a comment, hence the `\#` throughout (cf. `.cmk.minify`).
lang.parse.pragma.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/ && NF {exit}'` && lc=`printf '%s' "$${tmp}" | tr 'A-Z' 'a-z'` && case "$${lc}" in *"cmk_pragma :::"*) pre="$${lc%%cmk_pragma :::*}cmk_pragma :::" && rest="$${tmp:$${\#pre}}" && ( echo "$${rest%%:::*}" | sed 's/^\#//g' | ${lang.comp.stage.json5} | ${jq.run.pipe} -c . || ( $(call log, ${red}failed parsing pragma hint -- not valid JSON (trailing commas + // comments are tolerated, but it must otherwise be valid)); exit 79 ) ) ;; esac )
lang.parse.sugar.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/{exit}'` && rest="$${tmp\#*cmk_sugar :::}" && if [ "$${rest}" = "$${tmp}" ]; then true ; else echo "$${rest//:::*}" | sed 's/^\#//g' | ${jq.run.pipe} -c ; fi ) 2>/dev/null || true
lang.parse.dialect.hint=( tmp=`${stream.stdin} | awk 'NR==1 && /^\#!/{next} /^\#/{print} !/\#/{exit}'` && rest="$${tmp\#*cmk_dialect :::}" && if [ "$${rest}" = "$${tmp}" ]; then $(call log.trace, no dialect hint in file) ; else ( echo "$${rest//:::*}" | sed 's/^\#//g' | ${jq.run.pipe} -c . || ($(call log, ${red}failed parsing dialect hint!); exit 79) ) ; fi )

# `lang.parse.scan.*` -- compile-time pre-scans of raw source (grep the alternation, reduce each match to bare
# name(s), dedupe).  `.receivers` extracts every bound name (the `lang.rex.recv.*` rows above, in that row order
# -- the sed extractors assume it) for -v RECEIVERS.  `.junctions` extracts `<name>.__junction__ := <op>`
# overrides as `name=op` pairs for -v JUNCTIONS (none in source -> nothing, so chains keep the ` | ` pipe).
lang.parse.scan.receivers=( grep -aoE '$(lang.rex.recv.kwarg)|$(lang.rex.recv.def)|$(lang.rex.recv.importas)|$(lang.rex.recv.fromimport)|$(lang.rex.recv.openlist)|$(lang.rex.recv.star)|$(lang.rex.recv.goal)|$(lang.rex.recv.capture)|$(lang.rex.recv.banana)' || true ) | sed -E 's/^[[:space:]]*from[[:space:]]+(${lang.rex.name}+)[[:space:]]+import[[:space:]]+\*.*$$/\1/; s/^[[:space:]]*from[[:space:]]+${lang.rex.name}+[[:space:]]+import[[:space:]]+//; s/.*[[:space:]]as[[:space:]]+//; s/.*(namespace=|def=)//; s/^[[:space:]]*(open|import)[[:space:]]+//; s/^[[:space:]]*goal[[:space:]]+//; s/^[[:space:]]*&?(${lang.rex.name}+)[[:space:]]*<-.*/\1/; s/^[[:space:]]*\*[[:space:]]+//; s/[[:space:]]*,[[:space:]]*/ /g; s/(\([^()|]*\))?[([{]\|$$//; s/^Dockerfile\.//' | sort -u | tr '\n' ' '
lang.parse.scan.junctions=( grep -aoE '${lang.rex.name}+\.__junction__[[:space:]]*:?=[[:space:]]*[^[:space:]]+' || true ) | sed -E 's/\.__junction__[[:space:]]*:?=[[:space:]]*/=/' | sort -u | tr '\n' ' '
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: __pragma__ :: Compiler pragmas
##
## A pragma is a per-program knob, declared as a JSON object in a header comment
## (`# cmk_pragma ::: { "recipe_join": ";" } :::`; case-insensitive, JSON5-lite).  Each key
## folds (upcase, `.`/`-` -> `_`) into the compiler-only `CMK_PRAGMA_*` namespace (never
## clobbers an internal `CMK_*`); resolution is pragma > env > default (scalars replace +
## warn, lists accumulate like `+=`).  `__pragma__` has three surfaces: the `CMK_PRAGMA_*`
## env wire-format (compiler-written), the `${__pragma__}` JSON manifest (lazy observer,
## `${make} __pragma__`), and the `__pragma__.*` resolvers.  This section owns the parser,
## resolvers, manifest, and stacking target; the knob catalog is in `docs/cmk/pragmas.md`.
##
## Resolvers: `.key` folds a name to its `CMK_PRAGMA_` form; `.envvar` maps a folded key to its env
## var (a `CMK_*` knob names its var directly, else `CMK_`-prefixed); `.get`/`.scalar` do the replace-
## with-warn scalar resolution; `.append`/`.list` do the accumulate (env + pragma both contribute,
## like `+=`); `.sh` is the shell-time reader for the compile/boot phases where the value is stored
## text, not a make-var. `${__pragma__}` renders the resolved manifest as one JSON object (lower-cased
## knobs -> stored strings), lazily; `__pragma__.resolve` does the two-pass plugin-pragma stacking
## (additive-only, conflict = hard error).
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
__pragma__.key=$(subst -,_,$(subst .,_,$(call m5.lex.upper,$(m5[1]))))
__pragma__.envvar=$(if $(filter CMK_%,${1}),${1},CMK_${1})
__pragma__.get=$(call __pragma__.scalar,$(call __pragma__.key,${1}),$(if $(filter-out undefined,$(origin 2)),${2}))
__pragma__.warn=$(if $(and $(call m5.defined?,CMK_PRAGMA_${1}),$(call m5.given?,$(call __pragma__.envvar,${1})),$(filter-out $($(call __pragma__.envvar,${1})),$(CMK_PRAGMA_${1}))),$(warning pragma ${1}=$(CMK_PRAGMA_${1}) supersedes env $(call __pragma__.envvar,${1})=$($(call __pragma__.envvar,${1}))))
__pragma__.scalar=$(call __pragma__.warn,${1})$(or $(call m5|,CMK_PRAGMA_${1},),$(call m5|,$(call __pragma__.envvar,${1}),),$(m5[2]))
__pragma__.append=$(call __pragma__.list,$(call __pragma__.key,${1}),$(if $(filter-out undefined,$(origin 2)),${2}))
__pragma__.list=$(or $(strip $(call m5|,$(call __pragma__.envvar,${1}),) $(call m5|,CMK_PRAGMA_${1},)),$(m5[2]))
__pragma__.sh=sed -n 's/^export CMK_PRAGMA_$(m5[1]) := //p' | head -1
__pragma__=$(shell env | grep -a '^CMK_PRAGMA_' | ${jq.run.pipe} -c -R -s 'split("\n")|map(select(length>0))|map(split("=")|{((.[0]|sub("^CMK_PRAGMA_";"")|ascii_downcase)):(.[1:]|join("="))})|add // {}')
$(call m5.marm, __pragma__)
__pragma__:; @printf '%s\n' '${__pragma__}'
__pragma__.resolve:
	@# Reads an ENTRY on stdin.  DISCOVER = compile it (register-only imports) then re-parse the compiled
	@# make so real `include.plugins` populate `__plugins__.paths`, then STRICTLY (additive-only, conflict =
	@# hard error) merge the entry's pragma with each discovered plugin's -> merged `export CMK_PRAGMA_*`.
	set -o pipefail ; src="$$(cat)" \
	&& ent="$$(printf '%s\n' "$$src" | ${lang.parse.pragma.hint})" ; [ -n "$${ent}" ] || ent='{}' \
	&& paths="$$( { printf 'include %s\n' '${CMK_SRC}' ; printf '%s\n' "$$src" | CMK_IMPORT_DISCOVER=1 CMK_INTERNAL=1 CMK_COMPILER_VERBOSE=0 ${make} mk.compile ; } | CMK_IMPORT_DISCOVER=1 CMK_INTERNAL=1 ${MAKE} -f - __plugins__.paths )" \
	&& { printf '%s\n' "$$ent" ; for _pf in $$paths; do [ -f "$$_pf" ] || continue ; _pp="$$(cat "$$_pf" | ${lang.parse.pragma.hint})" ; [ -z "$$_pp" ] || printf '%s\n' "$$_pp" ; done ; } \
		| ${jq.run.pipe} -s '(map(keys)|add) as $$a | ($$a|group_by(.)|map(select(length>1))|map(.[0])|unique) as $$d | if ($$d|length)>0 then error("cmk pragma merge conflict (additive-only, no updates) on keys: "+($$d|join(", "))) else (reduce .[] as $$o ({};.+$$o)) end' \
		| ${jq.run.pipe} -r 'to_entries[] | "export CMK_PRAGMA_\(.key|ascii_upcase|gsub("[.-]";"_")) := \(if (.value|type)=="array" then (.value|join(" ")) else (.value|tostring) end)"'
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

.mk.parse.sugar.hint:
	$(call log.trace, ${@} ${sep} parsing sugar hint..)
	${lang.parse.sugar.hint}
.mk.parse.dialect.hint:
	$(call log.trace, ${@} ${sep} parsing dialect hint..)
	${lang.parse.dialect.hint}

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

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: import/include :: The importer (def/target) + include wrappers
##
## The def/target importer copies `define` block(s) or whole targets verbatim out
## of another file into this namespace (def=/defs=/as=/namespace=, globs allowed;
## a target never overrides a local).  Parse-time only, top-level.  _import.emit
## is the compile-time inliner (bakes imports in via lang.comp.pipeline.tail).
##
## The file/plugin include family: thin wrappers over the module importer's copy-free fast path, so
## an `include.*` is just that importer with an empty pipeline. `include.file`/`include.files` include
## one-or-many cwd-relative (or absolute) makefiles with import-logging and a clean missing-file error;
## `include.dir` bulk-loads every `*.mk`/`*.cmk` directly under a directory (hard-erroring when none
## match); `include.def` is the positional convenience over the def importer. `strict=0` is lenient
## (log + continue) throughout; `_include.set` is the shared driver.
##
## `include.plugin`/`include.plugins` load one-or-many plugins from CMK_PLUGINS_DIR: a `*.mk` is a
## verbatim include, a `*.cmk`/`*.cmk.mk` is JIT-compiled then imported (via `_include.cmk.one`), and
## each imported namespace gets an auto `<ns>.help` target. `_include` is the one guarded-`include`
## primitive behind the whole family (and the module bind): it resolves `<prefix>/<file>` (an absolute
## file used as-is), honors `strict`, and is include-once, skipping a path already in MAKEFILE_LIST,
## the cycle-breaker for a file or module that imports itself.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# import.def / import.defs -- copy define block(s) verbatim (see header).
#
# Verbatim-preserving per block: a `define .. endef` wrapper keeps `$`/`$$`/indentation, and a
# tmpfile read via `$(file <)` (not `$(shell)`) keeps newlines; fetch/read/cleanup run in textual order.
#
# USAGE:
#   $(call import.def, file=<path> def=<name>)
#   $(call import.def, file=<path> def=<name> as=<local_name>)
#   $(call import.def, file=<path> defs="<name> <name> ...")
#   $(call import.def, file=<path> defs="<glob> ...")    # e.g. 'underload_*'
#   $(call import.def, file=<path> def=<name> namespace=<ns>)  # binds <ns>.<name>
# Compile-time inlining: with `_mk_emit` set to a file path, imports append resolved block text to it
# instead of `$(eval)`ing into the live namespace (and `_mk_exclude_from` overrides the never-override
# source).  Both empty by default (runtime path unchanged), set via env only in the compile stage.
$(call m5.declare, _mk_emit ?=, _mk_exclude_from ?=)
# Consume one resolved define block ${1}=file ${2}=name ${3}=local-name: append its
# text to `_mk_emit` (compile-time) or `$(eval)` it into the namespace (runtime).
_mk.emit.or.eval.def=$(if ${_mk_emit},$(file >> ${_mk_emit},$(call _import.def.one,${1},${2},${3})),$(eval $(call _import.def.one,${1},${2},${3})))
import.def=$(call _import.def, ${1})
# Plural-name alias (identical signature/behavior); reads naturally with `defs=`.
import.defs=$(call _import.def, ${1})

# Names of `define`s in file ${1} whose name matches glob spec ${2} (shell `case`,
# so `*`/`?`/`[..]` are native globs); scans the file's own `define` lines only.
_mk.def.match=$(shell grep -E '^define[[:space:]]' '${1}' 2>/dev/null | awk '{print $$2}' | while read n; do case "$$n" in (${2}) printf '%s\n' "$$n";; esac; done)

# Import one define by exact name ${2} from file ${1}, under local name ${3}: read
# verbatim (via `$(value)`), error if absent, wrap in a fresh `define`.
# Invoke it wrapped in `$(eval …)` so the minted `define` is parsed.
define _import.def.one
$(shell make -f ${1} mk.def.read/${2} > .tmp.import.def.${3} 2>/dev/null)
$(if $(strip $(file < .tmp.import.def.${3})),,$(call mk.error, import.def: def `${2}` not found in `${1}`, errno=IMPORT_DEF))
define ${3}
$(file < .tmp.import.def.${3})
endef
$(shell rm -f .tmp.import.def.${3})
endef

# Resolve one `defs=` spec: a glob expands to every matching define name (error if
# none), an exact name imports directly.  ${3} is the (possibly empty) namespace
# prefix applied to the LOCAL bind name -- the source name (read from the file) is
# unchanged, so `namespace=N` binds `define N.<name>` (top-level header only).
_import.def.spec=$(if $(call m5.lex.glob?,${2}),$(eval _mk_id_names:=$(call _mk.def.match,${1},${2}))$(if ${_mk_id_names},$(foreach _n,${_mk_id_names},$(call _mk.emit.or.eval.def,${1},${_n},${3}${_n})),$(call mk.error, import.def: no def matching `${2}` in `${1}`, errno=IMPORT_DEF)),$(call _mk.emit.or.eval.def,${1},${2},${3}${2}))

define _import.def
$(eval _mk_id_args:=$(subst %,%%,$(subst ",',${1})))
$(call mk.unpack.kwargs, ${_mk_id_args}, file def=MKID_NONE defs=MKID_NONE as=MKID_NONE namespace=MKID_NONE)
$(eval _mk_id_ns:=$(if $(filter-out MKID_NONE,${kwargs_namespace}),$(strip ${kwargs_namespace}).))
$(if $(wildcard ${kwargs_file}),,$(call mk.error, import.def: file not found: `${kwargs_file}`, errno=IMPORT_DEF))
$(if $(filter-out MKID_NONE,${kwargs_def} ${kwargs_defs}),,$(call mk.error, import.def: give def=<name> or defs="<a b c>". Input: `${1}`, errno=IMPORT_DEF))
$(if $(filter-out MKID_NONE,${kwargs_def}),$(call _mk.emit.or.eval.def,${kwargs_file},${kwargs_def},${_mk_id_ns}$(if $(filter-out MKID_NONE,${kwargs_as}),${kwargs_as},${kwargs_def})))
$(foreach _s,$(filter-out MKID_NONE,${kwargs_defs}),$(call _import.def.spec,${kwargs_file},${_s},${_mk_id_ns}))
endef

# Every `define .awk.*` carries `#:phase <P> seed=<0|1> awklang=<yes|no>` (audited by
# `lint.self.phase` in .automation.cmk).  P = the strictest phase the block is used in: SUPERVISOR (raw-extracted
# pre-parse, no `@@`), SEED-PARSE (`$(value)` / awklang export at parse), COMPILE (feeds a `.cmk.*`
# stage), RUN (recipe-only).  seed=1 = pinned to seed, can never move into `__hosted__` (the
# quarantine); seed=0 = run-only, free.  awklang=yes iff seed=0 (only these can become hosted awklang).

# Pipeline-stage SELECTors (stdin->stdout): emit the subset of a makefile stream
# named by the stem (a glob with `*`/`?`, else an exact name).  These are the
# composable form of `import.{def,target}`'s extraction, usable inside a
# `flux.column` staging pipeline (e.g. partial module imports).  The awk is read
# from an exported `_cmk_blk_*` var so make does not mangle its `$0`/`$$`.
mk.select.def/% mk.select.defs/%:; @${stream.stdin} | awk -v pat='${*}' "$${_awklang_select_def}"
	@# Emit define block(s) from stdin whose name matches <spec> (glob: `*` `?`).
mk.select.target/% mk.select.targets/%:; @${stream.stdin} | awk -v t='${*}' "$${_cmk_blk_target_extract}"
	@# Emit target block(s) from stdin whose name matches <spec> (glob: `*` `?`).

# Target names defined textually in file ${1} (`^name:` headers, split on
# multi-target rules; the `([^=]|$)` guard skips `:=`/`?=` assignments).  Skips
# `define ... endef` bodies, whose content (e.g. an awk block or a literal with
# `:`) must not be mistaken for target headers.
_mk.target.names=$(shell awk '$(value .awk.target.names)' '${1}' 2>/dev/null | sort -u)

# Subset of the space-list ${2} that is also a target in file ${1}.  Scans ${1}
# once but emits only the intersection, so this stays cheap even when ${1} is a big
# (e.g. interpreter-inlined) file, and used as the never-override set.  Skips
# `define ... endef` bodies for the same reason as `_mk.target.names`.
_mk.local.of=$(shell awk -v want='${2}' '$(value .awk.target.names)' '${1}' 2>/dev/null | sort -u)

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

# Resolve one spec to source target names (glob or exact), error if it matches nothing, then import
# each except names the destination already defines: a local target is never overridden, silently.
# An optional namespace prefix renames each imported target `<ns>.<target>` (so it can't collide with
# a local) and bypasses the local-skip.
define _import.target.spec
$(eval _mk_it_hits:=$(call _mk.glob.filter,${2},${_mk_it_src}))
$(if ${_mk_it_hits},,$(call mk.error, import.target: no target matching `${2}` in `${1}`, errno=IMPORT_TARGET))
$(foreach _n,${_mk_it_hits},$(if $(if $(strip ${3}),,$(findstring <${_n}>,${_mk_it_localb})),,$(eval $(call _import.target.one,${1},${_n},$(strip ${3})))))
endef

# The target-flavoured sibling of the def importer: copies whole target(s) -- header (with prereqs)
# and recipe -- verbatim out of another makefile into this one, to share targets between a `.cmk` port
# and its plain-make twin. Parse-time only; call it at top-level. A spec with `*`/`?` is a glob, else an
# exact name; it errors if the file or any spec matches nothing, and never overrides a local target. A
# `namespace=` renames each import so it can't collide (bypassing the local-skip); it scans the file textually only.
import.target=$(call _import.target, ${1})
# Plural-name alias (identical signature/behavior); reads naturally with `targets=`.
import.targets=$(call _import.target, ${1})

define _import.target
$(eval _mk_it_args:=$(subst %,%%,$(subst ",',${1})))
$(call mk.unpack.kwargs, ${_mk_it_args}, file target=MKIT_NONE targets=MKIT_NONE namespace=MKIT_NONE)
$(if $(wildcard ${kwargs_file}),,$(call mk.error, import.target: file not found: `${kwargs_file}`, errno=IMPORT_TARGET))
$(eval _mk_it_src:=$(call _mk.target.names,${kwargs_file}))
$(eval _mk_it_localb:=$(foreach _l,$(call _mk.local.of,$(or ${_mk_exclude_from},$(firstword ${MAKEFILE_LIST})),${_mk_it_src}),<${_l}>))
$(eval _mk_it_specs:=$(subst %%,%,$(strip $(filter-out MKIT_NONE,${kwargs_target} ${kwargs_targets}))))
$(if ${_mk_it_specs},,$(call mk.error, import.target: give target=<name> or targets="<a b c>". Input: `${1}`, errno=IMPORT_TARGET))
$(foreach _s,${_mk_it_specs},$(call _import.target.spec,${kwargs_file},${_s},$(filter-out MKIT_NONE,${kwargs_namespace})))
endef

_import.emit:
	@# Compile-time inliner for one `import.*` callform, driven by env vars:
	@# `ekind` (target|targets|def|defs), `eargs` (the arg-string), and
	@# `_mk_exclude_from` (the source being compiled, so locals aren't overridden).
	@# Reuses the normal import machinery, but because `_mk_emit` is set the resolved
	@# blocks are APPENDED to a tmp instead of eval'd; the tmp is printed to
	@# stdout.  Used by `lang.comp.pipeline.tail` to bake imports in at compile-time.
	$(eval _mk_emit:=$(shell TMPDIR=. mktemp ./.tmp.mk.emit.XXXXXXXX))
	$(if $(filter target targets,${ekind}),$(call import.target,${eargs}),$(call import.def,${eargs}))
	@cat ${_mk_emit}; $(call io.safe_rm,${_mk_emit})

define _include.set
$(call mk.unpack.kwargs, ${1}, prefix, .)
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(foreach _incf,$(filter-out strict=% prefix=%,$(patsubst file=%,%,$(shell echo "$(m5[1])"))),$(call import.module, file=${_incf} flat=1 preprocs=stream.echo prefix=$(strip ${kwargs_prefix}) strict=${kwargs_strict}))
endef
include.file=$(eval $(call _include.set, prefix=. ${1}))
# Plural-name alias (identical signature/behavior); reads naturally with a file list.
include.files=$(call include.file, ${1})

include.def=$(call import.def, file=$(m5[2]) def=$(m5[1]))
include.dir=$(if $(strip $(wildcard ${1}/*.mk ${1}/*.cmk)),$(call _include.dir.load,${1}),$(call log.module.fail, include.dir ${sep}${no_ansi} no ${bold}*.mk/*.cmk${no_ansi} under ${bold}${1}${no_ansi}$(if $(wildcard ${1}),,${dim} (no such directory)${no_ansi}), CMK_INCLUDE_DIR_EMPTY))
_include.dir.load=$(call log.module, ${dim}include.dir ${sep}${no_ansi} ${1} ${dim}($(words $(wildcard ${1}/*.mk ${1}/*.cmk)) files)${no_ansi})$(call include.files, $(wildcard ${1}/*.mk ${1}/*.cmk))

$(call m5.def.!, include.plugin, _include.plugins)
$(call m5.def.!, include.plugins, _include.plugins)
define _include.plugins
$(call mk.unpack.kwargs, ${1}, prefix, ${CMK_PLUGINS_DIR})
$(call mk.unpack.kwargs, ${1}, strict, 1)
$(eval _mkip_prefix:=$(strip ${kwargs_prefix}))
$(eval _mkip_strict:=$(strip ${kwargs_strict}))
$(eval _mkip_files:=$(filter-out strict=% prefix=%,$(patsubst file=%,%,$(shell echo "$(m5[1])"))))
# Discovery mode registers names only, so all three load actions share one gate.
$(eval _mkip_load:=$(if $(filter 1,${CMK_IMPORT_DISCOVER}),,1))
$(if ${_mkip_load},$(foreach _mkip_a,${_mkip_files},$(call _mk.plugin.autohelp,${_mkip_a},$(call _mk.path.resolve,${_mkip_prefix},${_mkip_a}))))
$(if ${_mkip_load},$(if $(filter-out ${_mk.cmk.exts},${_mkip_files}),$(call _include.set, prefix=${_mkip_prefix} strict=${_mkip_strict} $(filter-out ${_mk.cmk.exts},${_mkip_files}))))
$(if ${_mkip_load},$(foreach _mkip_c,$(filter ${_mk.cmk.exts},${_mkip_files}),$(call _include.cmk.one,$(call _mk.path.resolve,${_mkip_prefix},${_mkip_c}),${_mkip_strict},${_mkip_c})))
$(if ${_mkip_files},$(eval __plugins__:=$(sort ${__plugins__} ${_mkip_files}))$(eval __plugins__.paths:=$(sort ${__plugins__.paths} $(foreach _mkip_f,${_mkip_files},$(call _mk.path.resolve,${_mkip_prefix},${_mkip_f})))))
endef

define _include.cmk.one
$(if $(wildcard ${1}),$(call import.module, file=${1} flat=1)$(call log.import.part1, include ${sep} ${dim}strict=${ital}${2} ${sep} ${dim_ital}${3} )$(call log.import.part2, ${GLYPH_CHECK} ${dim}(cmk lowered)),$(call log.import.part1, include ${sep} ${dim}strict=${ital}${2} ${sep} ${dim_ital}${3} )$(if $(filter 0,$(strip ${2})),$(call log.import.part2, ${dim}${1}${no_ansi} ${GLYPH_XXX} (missing -- skipping)),$(call log.import.part2, ${GLYPH_XXX}${1}${no_ansi} (missing))$(call log.import.error, ${red}Declared cmk-plugin missing: ${bold}${3})$(error cmk-fault errno=INCLUDE_MISSING code=66 ::cmk-plugin $(strip ${3}) not found (use strict=0 for conditional include))))
endef

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
$(shell d=$(firstword $(call m5.lex.split,${kwargs_prefix})); ls $$d 2>/dev/null > /dev/null || mkdir -p $$d)
ifeq ($(shell ${trace_maybe} && ls ${_mk_plug} 2>/dev/null >/dev/null && echo 0 || echo 1),1)
ifeq (${kwargs_strict},1)
$(call log.import.part2, ${GLYPH_XXX}${_mk_plug}${no_ansi} (missing))
$(call log.import.error, ${red}Declared import missing: ${bold}${kwargs_file})
$(call log.import.error, Consider ${bold}strict=0${no_ansi} for conditional inclusion)
$$(error cmk-fault errno=INCLUDE_MISSING code=66 ::import $(strip ${kwargs_file}) not found (use strict=0 for conditional include))
else
$(call log.import.part2, ${dim}${_mk_plug}${no_ansi} ${GLYPH_XXX})
endif
else
include ${_mk_plug}
$(call log.import.part2, ${GLYPH_CHECK})
endif
endif
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Root-namespace dunders -- the registries and self-model registers the runtime keeps at file scope.
# Four `Registry`-protocol carriers (plugins/modules/ambients/goals) are by-name sets with a uniform
# has/require/assert interface; plugins and modules are exported so a re-parsing child inherits what the
# parent loaded. The trampoline's CEK/scheduler registers are exported read-only on the dispatch hop and
# defaulted empty here (so a bare reference never warns). `__main__` is the default-goal noun, exposed bare.
export __plugins__ ?=
__plugins__.paths ?=
export __modules__ ?=
export __goals__ ?=
$(call m5.declare, \
	__ip__ ?=, __alt__ ?=, __yielded__ ?=, __step__ ?=, __step_budget__ ?=, \
	__posix_code__ ?=, __exit_code__ ?=)

__plugins__.paths:; @echo ${__plugins__.paths}
__ip__:; @echo '${__ip__}'
__step__:; @echo '${__step__}'
__posix_code__:; @echo '${__posix_code__}'
__exit_code__:; @echo '${__exit_code__}'

# One membership test over all four carriers; only the require-action differs.
$(foreach _reg,__plugins__ __modules__ __ambients__ __goals__,$(eval $(_reg).has=$$(strip $$(filter $$(firstword $${1}),$${$(_reg)}))))
__plugins__.require=$(if $(call __plugins__.has,${1}),,$(call include.plugins,${1}))
__modules__.require=$(if $(call __modules__.has,$(call _mk.module.name,${1})),,$(call import.module,${1}))
__ambients__.require=$(if $(call __ambients__.has,${1}),,$(call __ambients__.declare,${1}))
__goals__.require=$(if $(call __goals__.has,${1}),,$(call _registry.assert.fail,goal,$(firstword ${1})))
__goals__.assert=$(call __goals__.require,${1})
__main__ = $(.DEFAULT_GOAL)

# Idempotent registry writers.  io.stack!: pushdef/popdef stack (m4).

# __ambients__.declare drops a trailing `=value` before appending.

# __goals__.declare adds a bare goal; goal.bind lifts a goal-expr.
__ambients__.declare=$(eval export __ambients__ += $(firstword $(subst =, ,$(m5[1]))))
io.stack! = $(eval $(call _io.stack!,$(call io.stack.name,$(1))))$(eval $(call io.stack.name,$(1))._INIT_DEF ?=)$(if $(call io.stack.seed,$(1)),$(eval $(call io.stack.name,$(1))._INIT_DEF := $(call io.stack.seed,$(1))))
__goals__.declare=$(if $(call __goals__.has,${1}),,$(eval export __goals__ += $(m5[1])))
goal.bind=$(eval $(m5[1]) := $(m5[2]))$(call __goals__.declare,${1})$(eval $(m5[1]):; @$${make} $$($(m5[1])))$(eval $(m5[1])/%:; @$${make} $$($(m5[1]))/$$*)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.repl :: REPL as an execution mode
##
## The core-to-plugin bridge that turns a compiled program into an interactive
## tux.repl session over its target namespace. Core cannot import the tux.repl plugin (the harness and
## launch logic live there), so this layer builds the tux.repl kwarg string, auto-imports any vm regions
## the session needs, applies the start-by-default enter, and compiles+runs the plugin. It backs both the
## `cmk run` repl-pragma branch and `cmk repl`.
##
## `lang.repl.kwargs` builds the kwarg string from the `repl` pragma: a truthy value is a bare `eval`, an
## object yields its read/eval/print/exit_after/minimap/events/complete/enter keys, each resolved pragma-
## key > `CMK_REPL_*` env > empty (`lang.repl.objkey` reads one key via jq). `lang.repl.enter.default` is
## the `cmk repl` start-by-default (auto-submit `__main__` on entry unless CMK_REPL_ENTER=none).
## `lang.repl.vm.ensure` flat-imports virtual-machine.cmk when a `__vm__` region or vm-trace is requested.
## `lang.repl.launch` is the bridge: it exports the `CMK_REPL_*` vars, compiles the plugin (with a
## `__main__: tux.repl.run` line appended) into a second temp, and runs it.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lang.repl.launch=$(call assert.plugin, tux.repl.cmk) && export CMK_REPL_RUNNER="$${tmpf}" CMK_REPL_SOURCE="$(m5[2])" CMK_REPL_KWARGS="$(1)" CMK_REPL_CLI="$${MAKE_CLI}" && tmpf2=$$(TMPDIR=`pwd` mktemp ./.tmp.cmk.repl.XXXXXXXXX) && trap "rm -f $${tmpf} $${tmpf2}" EXIT && $(call log.io, ${dim}cmk ${sep}${no_ansi} repl ${sep}${dim} launching harness ${sep} ${no_ansi}$(1)) && { cat "$(call cmk.plugin.find,tux.repl.cmk)" ; printf '\n__main__: tux.repl.run\n' ; } | ${_cli.subcommands.make} mk.compile > $${tmpf2} && chmod +x $${tmpf2} && CMK_INTERNAL=0 CMK_SUPERVISOR=1 ${make} mk.interpret/$${tmpf2}

lang.repl.objkey=printf '%s' "$${_bp_repl}" | ${jq.run.pipe} -r '.$(1) // $(2)' 2>/dev/null
lang.repl.kwargs={ case "$${_bp_repl}" in \
	true|1|on|yes|TRUE|ON|YES) _re= ; _rr= ; _rp= ; _rx= ; _rm= ; _rev= ; _rco= ; _ren= ;; \
	*) _re=$$($(call lang.repl.objkey,eval,empty)) ; _rr=$$($(call lang.repl.objkey,read,empty)) ; _rp=$$($(call lang.repl.objkey,print,empty)) ; _rx=$$($(call lang.repl.objkey,exit_after,empty)) ; _rm=$$($(call lang.repl.objkey,minimap,empty)) ; _rev=$$($(call lang.repl.objkey,events,empty)) ; _rco=$$($(call lang.repl.objkey,complete,empty)) ; _ren=$$($(call lang.repl.objkey,enter,empty)) ;; \
	esac ; \
	[ -n "$${_re}" ] || _re="$${CMK_REPL_EVAL:-tux.repl.kernel}" ; \
	[ -n "$${_rr}" ] || _rr="$${CMK_REPL_READ:-}" ; \
	[ -n "$${_rp}" ] || _rp="$${CMK_REPL_PRINT:-}" ; \
	[ -n "$${_rx}" ] || _rx="$${CMK_REPL_EXIT_AFTER:-}" ; \
	[ -n "$${_rm}" ] || _rm="$${CMK_REPL_MINIMAP:-}" ; \
	[ -n "$${_rev}" ] || _rev="$${CMK_REPL_EVENTS:-}" ; \
	[ -n "$${_rco}" ] || _rco="$${CMK_REPL_COMPLETE:-}" ; \
	[ -n "$${_ren}" ] || _ren="$${CMK_REPL_ENTER:-}" ; \
	case "$${_ren}" in none|off|-|0) _ren= ;; esac ; \
	_rk="eval=$${_re}" ; \
	[ -z "$${_rr}" ] || _rk="$${_rk} read=$${_rr}" ; \
	[ -z "$${_rp}" ] || _rk="$${_rk} print=$${_rp}" ; \
	[ -z "$${_rx}" ] || _rk="$${_rk} exit_after=$${_rx}" ; \
	[ -z "$${_rm}" ] || _rk="$${_rk} minimap=$${_rm}" ; \
	[ -z "$${_rev}" ] || _rk="$${_rk} events=$${_rev}" ; \
	[ -z "$${_rco}" ] || _rk="$${_rk} complete=$${_rco}" ; \
	[ -z "$${_ren}" ] || _rk="$${_rk} enter=$${_ren}" ; \
	}

lang.repl.enter.default=case " $${_rk} " in \
	*" enter="*) : ;; \
	*) case "$${CMK_REPL_ENTER:-}" in \
		none|off|-|0) : ;; \
		*) grep -qE '^__main__[[:space:]]*:' $${tmpf} 2>/dev/null \
			&& { _rk="$${_rk} enter=__main__" ; $(call log.io, ${dim}cmk repl ${sep}${no_ansi_dim} start-by-default ${sep} running ${no_ansi}__main__${no_ansi_dim} on entry ${sep}${dim} opt out with CMK_REPL_ENTER=none) ; } \
			|| true ;; \
	   esac ;; \
	esac

lang.repl.vm.ensure=case "$${_rk} vt=$${CMK_PRAGMA_VM_TRACE:-}" in \
	*__vm__*|*" vt=1"*|*" vt=true"*|*" vt=yes"*|*" vt=on"*|*" vt=TRUE"*) \
		grep -q 'virtual-machine\.cmk' $${tmpf} 2>/dev/null \
		|| { $(call log.io, ${dim}cmk repl ${sep}${no_ansi_dim} vm region requested ${sep} auto-importing virtual-machine.cmk into the runner) ; \
		     printf '\n$$(call import.module, file=$$(call cmk.plugin.find,virtual-machine.cmk) flat=1)\n' >> $${tmpf} ; } ;; \
	esac
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# present = at least one `ns.*` macro already in scope (core namespaces + earlier-defined members).
lang.module.import.one=$(if $(or $(call cmk.plugin.find,${1}.cmk),$(call cmk.plugin.find,${1}.mk),$(call __plugins__.has,${1}.cmk),$(call __plugins__.has,${1}.mk),$(call __modules__.has,${1}),$(filter ${1}.%,$(.VARIABLES))),,$(call lang.module.import.missing,${1}))
lang.module.import.missing=$(call log.import.error,${red}import ${sep}${no_ansi} ${bold}${1}${no_ansi} resolves to nothing ${dim}(no CMK_PLUGINS_DIR file, not loaded, no ${1}.* in scope)${no_ansi} -- did you mean ${bold}open ${1}${no_ansi} (to modify)?)$(call mk.error, import ${1} resolves to nothing, errno=IMPORT_NOT_FOUND)
_registry.assert.fail=$(call log.import.error,${red}$(1) not loaded: ${bold}$(2)${no_ansi})$(call mk.error, $(1) not loaded: $(2), errno=REGISTRY_ASSERT)
__plugins__.assert=$(if $(call __plugins__.has,${1}),,$(call _registry.assert.fail,plugin,$(firstword ${1})))
__modules__.assert=$(if $(call __modules__.has,${1}),,$(call _registry.assert.fail,module,$(firstword ${1})))

# compose.mk puts files in exactly two categories (no `CMK_TMP_DIR`): (A) container-visible scratch
# -> the cwd, via `.tmp.*` names (TMPDIR=`pwd`), so a dispatched container reads it
# by the same relative path under its cwd->/workspace bind-mount; (B) host-only cache/staging ->
# CMK_STAGE_DIR (below), which never needs to cross into a container.

# _mk.path.resolve(<prefix>,<file>) -- resolve <file> against a (possibly ':'-path) <prefix> to
# one path: absolute <file> used as-is; single-element <prefix> -> <prefix>/<file> with no
# $(wildcard) probe (so a just-staged file re-includes by literal path); multi-element -> first
# existing <dir>/<file> across the path, else a <first-element>/<file> fallback.  Pure make, no
# fork.
_mk.path.resolve=$(strip $(if $(filter /%,$(m5[2])),$(m5[2]),$(if $(filter 1,$(words $(call m5.lex.split,$(1)))),$(m5[1])/$(m5[2]),$(firstword $(wildcard $(foreach d,$(call m5.lex.split,$(1)),$(strip $(d))/$(m5[2]))) $(firstword $(call m5.lex.split,$(1)))/$(m5[2])))))
# cmk.plugin.find(<name>) -- RECIPE-time bash: echo the first <dir>/<name> on the
# CMK_PLUGINS_DIR search path that exists (empty if none).  IFS=: is subshell-local +
# POSIX-portable (busybox/macOS).  Use this anywhere bash needs to locate a plugin file
# (the raw ${CMK_PLUGINS_DIR}/<name> breaks once the value holds a colon).
_cmk.plugin.find=$(shell n='$(m5[1])'; p="$$CMK_PLUGINS_DIR"; IFS=:; for d in $$p; do [ -f "$$d/$$n" ] && { printf '%s' "$$d/$$n"; break; }; done)
cmk.plugin.find=$(call m5.memoize.fn, _cpf, _cmk.plugin.find, $(m5[1]))
# File extensions that mark a plugin as cmk-lang (the JIT-compile path): the `.cmk`/`.CMK` spellings
# plus the `.cmk.mk`/`.CMK.mk` double-extension (a `.mk` tail so tooling treats it as a makefile, the
# inner `.cmk` marking the dialect). Used by both the filter and filter-out sides so the partition can't drift.
_mk.cmk.exts:=%.cmk %.CMK %.cmk.mk %.CMK.mk
# _cmk.autohelp -- namespace roots already given an auto `<ns>.help` (dedups across re-imports).
_cmk.autohelp:=
# _mk.gen.help(<ns>) -- eval `<ns>.help: mk.namespace.filter/<ns>.` once (dedup via _cmk.autohelp).
# Prereq form (like the core help targets): a real, discoverable explicit target.  The shared
# generator behind both the plugin auto-help and the core-namespace auto-help.
_mk.gen.help=$(if $(filter ${1},${_cmk.autohelp}),,$(eval _cmk.autohelp+=${1})$(eval ${1}.help: mk.namespace.filter/${1}.))
# _mk.plugin.autohelp(<file-token>,<resolved-path>) -- give an imported plugin a `<ns>.help`
# target (ns = filename minus .cmk/.mk, per the `<name>.{cmk,mk}` -> `<name>.*` convention) so
# `make <ns>.help` lists its namespace with zero boilerplate.  Skipped when the plugin source
# already defines `<ns>.help` (grep-checked -> the "if one is not present" clause).
_mk.plugin.autohelp=$(if $(wildcard ${2}),$(eval _ah_ns:=$(patsubst %.CMK,%,$(patsubst %.cmk,%,$(basename $(notdir ${1})))))$(if $(filter ${_ah_ns},${_cmk.autohelp}),,$(if $(shell grep -sqE '^$(subst .,[.],${_ah_ns})[.]help[ :]' ${2} && echo 1),$(eval _cmk.autohelp+=${_ah_ns}),$(call _mk.gen.help,${_ah_ns}))))

# import.module(def=<name> | file=<path> [namespace=<ns>] [preprocs=...]) -- stage a module into
# CMK_MODULES_DIR as `.tmp.module.<ns>` and import it (strict, prefix=that dir), like any plugin.
# `def` and `file` are mutually exclusive (exactly one): def=<name> materializes the in-scope
# `define <name>` (via $(value)/$(file)); file=<path> copies an existing makefile.  The namespace
# (prefix on every module-level LHS) is `namespace=` else the def name else the file basename; the
# staged file is keyed <source>-<dest> so distinct sources coexist (same identity still collides ->
# use `namespace=`).  `preprocs=` is a colon-delimited stage pipeline (default
# `mk.compile`, or `stream.echo` for verbatim).  A partial import adds `targets=`/`defs=` (a
# select stage keeps only matches). `flat=1` is a root import (namespace + header stages omitted, body
# lands global); flat + verbatim + unselected file is the copy-free fast path (correct self-referential
# MAKEFILE_LIST) that the `include.*` verbs lower to.
# NB: dispatch uses lazy $(if), not `ifeq` (whose branches' mkdir/$(file)/cp would all run).

# `__name__` -- the current namespace path, threaded by the `namespace` ctor (empty at
# module scope); also the anticipated identity for `${__name__}.__doc__` (moduledoc).
$(call m5.declare, __name__ :=, __name__stack :=, self :=, self_stack :=)

# The dynamic containment chain; lazy so a value inherited from an enclosing dispatch survives.
$(call m5.declare, __ambient__ ?=, __ambient_stack__ ?=)

# `_mk.module.namespace/%` -- prefix every module-level assignment/target LHS on stdin with
# `<ns>.` (the destination namespace taken literally from the stem; pure, no header).  The
# target + its `_awklang_module_ns` export are both minted by the `awklang` call at the awk-block
# export cluster (search `awklang, def=.awk.module.namespace`).  See also _mk.module.stage.

# Pipeline stage: prepend the `export CMK_MODULE := <source>` module-identity header. The stem is the
# source module (def name / file basename) -- a module's own identity, independent of the destination
# namespace it is imported under -- so a `def=M` imported `as Alias` still reads `CMK_MODULE=M`. Kept
# separate from namespacing so a flat/root import can omit it. `self` is bound to the source name too,
# so a body docstring lowered to the self-docstring reifies as `<source>.__doc__`.
_mk.module.header/%:; @{ echo 'export CMK_MODULE := ${*}'; echo 'self := ${*}'; ${stream.stdin}; }
	@# Prepend `export CMK_MODULE := <source>` (stdin->stdout); see _mk.module.stage.

_mk.module.name=$(or $(strip $(call mk.kwargs.get,${1},def)),$(basename $(notdir $(strip $(call mk.kwargs.get,${1},file)))))

# Pipeline stage: demote a module's `__main__` entrypoint to the namespace-root target (the stem). This
# is the Pythonic `if __name__=="__main__"` guard: a plugin's __main__ runs when the file is executed
# directly, but on import it is rebound to a plain `<root>:` target so it can't collide with the
# importer's own __main__. Header-only rename (prereqs preserved); a plugin-level `.DEFAULT_GOAL` is
# dropped (the importer owns the goal); define bodies and recipe lines pass through verbatim.
_mk.demote.main/%:; @${stream.stdin} | awk -v root='${*}' "$${_awklang_demote_main}"
	@# Rebind `__main__` -> `<root>:` on import (stdin->stdout); see _mk.module.stage.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Module staging :: The engine behind import.module
##
## The `_mk.module.*` helpers turn a module source (an in-scope `define`, or a file) into a
## namespaced, header-injected, main-demoted staged makefile under CMK_STAGE_DIR, then include
## it into the importer's scope.  Both `import.module` paths (def= and file=) funnel through it;
## the pipeline stages driven (namespace, header, main-demote) are defined just above.  A staged
## module carries its own identity as `export CMK_MODULE := <source>` (independent of the
## destination namespace, read at run time as CMK_MODULE), with every module-level assignment /
## target LHS prefixed `<dest>.`, so `var`/`tgt` become `<dest>.var`/`<dest>.tgt`.
##
## `_mk.module.key` is the staging key for `.tmp.module.<key>.mk`: just `<dest>` when source ==
## destination (the tidy common case), else `<src>-<dest>` so two sources imported to one namespace
## get distinct files instead of colliding.  `_mk.hash.file` adds a short cksum digest (7 hex,
## POSIX-portable) to a file-import's key so it is content-addressed: two files sharing a basename
## stay distinct, and an edited source changes the key, so a failed recompile finds the new key's
## file simply absent (a clean error) rather than falling back to stale output.  `_mk.module.stage`
## runs the source through the memoized pipeline (select -> main-demote -> namespace -> header ->
## compile; flat=1 omits the namespace + header stages), regenerating only when the output is absent,
## empty, or older than its source.
##
## `_mk.assert.define` is the parse-time guard (errors unless the named `define` is in scope).
## `_mk.module.from_def` / `_mk.module.from_file` are the entrypoints: each stages its source then
## includes the result from CMK_STAGE_DIR.  from_def writes the def value to a `.raw` idempotently
## (a `.raw.new` promoted via POSIX `cmp` only when it differs), so an unchanged re-import leaves the
## mtime untouched and the stage step's `-nt` memoization can skip the recompile (an unconditional
## write would bump the mtime every parse and defeat the cache; from_file's content-hash key avoids
## this by design).  `_mk.module.from_def_flat` is the def analogue of the file fast path: a flat +
## verbatim + unselected import whose staged output would be byte-identical to its body, so it skips
## staging and binds the value directly.  With no sub-make or temp file, it is also the only
## def-import that works when compose.mk has been inlined into one image (the interpret shebang),
## where the staging sub-make cannot find a standalone compose.mk in MAKEFILE_LIST.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
_mk.module.key=$(if $(filter $(m5[1]),$(m5[2])),$(m5[2]),$(m5[1])-$(m5[2]))
_mk.hash.file=$(shell cksum < "$(1)" | awk '{printf "%07x",$$1%268435456}')
_mk.module.stage=$(shell mkdir -p ${CMK_STAGE_DIR})$(shell _o=${CMK_STAGE_DIR}/.tmp.module.${1}.mk; if [ -s "$$_o" ] && [ "$$_o" -nt "${2}" ]; then true; else cat ${2} | CMK_INTERNAL=1 MAKEFLAGS= make -f $(firstword $(filter %compose.mk,${MAKEFILE_LIST}) ${MAKEFILE}) flux.column/$(if $(m5[4]),$(m5[4]):)_mk.demote.main/$(strip $(if $(filter 1,$(strip ${5})),${6},${7})):$(if $(filter 1,$(strip ${5})),,_mk.module.namespace/${7}:_mk.module.header/${6}:)$(or $(m5[3]),mk.compile) > $$_o.$$$$.out && mv $$_o.$$$$.out $$_o 2>/dev/null; fi; true)
_mk.assert.define=$(if $(call m5.undefined?,${1}),$(call mk.error, import.module: no such define: $(m5[1]), errno=MODULE_MISSING))
_mk.module.from_def=$(call _mk.assert.define,${1})$(shell mkdir -p ${CMK_STAGE_DIR})$(eval _mk_mod_k:=$(call _mk.module.key,${1},${2}))$(file > ${CMK_STAGE_DIR}/.tmp.module.${_mk_mod_k}.raw.new,$(value ${1}))$(shell _r=${CMK_STAGE_DIR}/.tmp.module.${_mk_mod_k}.raw; if cmp -s "$$_r.new" "$$_r"; then rm -f "$$_r.new"; else mv "$$_r.new" "$$_r"; fi)$(call _mk.module.stage,${_mk_mod_k},${CMK_STAGE_DIR}/.tmp.module.${_mk_mod_k}.raw,${3},${4},${5},${1},${2})$(call _include, prefix=${CMK_STAGE_DIR} strict=1 file=.tmp.module.${_mk_mod_k}.mk)
_mk.module.from_file=$(if $(wildcard ${1}),,$(call mk.error, import.module: no such file: ${1}, errno=MODULE_MISSING))$(eval _mk_mod_k:=$(call _mk.module.key,$(basename $(notdir ${1})),${2})-$(call _mk.hash.file,${1}))$(call _mk.module.stage,${_mk_mod_k},${1},${3},${4},${5},$(basename $(notdir ${1})),${2})$(call _include, prefix=${CMK_STAGE_DIR} strict=1 file=.tmp.module.${_mk_mod_k}.mk)
_mk.module.from_def_flat=$(call _mk.assert.define,${1})$(eval $(value ${1}))
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
$(call m5.def.!, import.module, _import.module)
# A partial/star module import: `defs=`/`targets=` (mutually exclusive) prepend a
# select stage so only the matching defines/targets are namespaced+compiled
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
$(call mk.unpack.kwargs, ${1}, plugin, 0)
# plugin=1 -- also register this file into __plugins__ (basename-with-ext token, like include.plugins;
# the plugin-registry gates match that exact token).  Captured here, before the from_file/
# _include expansion below re-unpacks `kwargs_file` to a staged temp and clobbers the global.
$(eval _mk_mod_plugtok:=$(if $(filter 1,$(strip ${kwargs_plugin})),$(notdir $(strip ${kwargs_file}))))
$(eval _mk_mod_plugpath:=$(if ${_mk_mod_plugtok},$(call _mk.path.resolve,$(strip ${kwargs_prefix}),$(strip ${kwargs_file}))))
$(if $(and $(strip ${kwargs_def}),$(strip ${kwargs_file})),$(call mk.error, import.module: def= and file= are mutually exclusive, errno=MODULE_ARGS))
$(if $(strip ${kwargs_def}${kwargs_file}),,$(call mk.error, import.module: requires def=<name> or file=<path>, errno=MODULE_ARGS))
$(if $(and $(strip ${kwargs_defs}),$(strip ${kwargs_targets})),$(call mk.error, import.module: defs= and targets= are mutually exclusive, errno=MODULE_ARGS))
$(eval _mk_mod_sel:=$(if $(strip ${kwargs_targets}),mk.select.targets/$(strip ${kwargs_targets}),$(if $(strip ${kwargs_defs}),mk.select.defs/$(strip ${kwargs_defs}))))
# A flat (root) + verbatim (stream.echo) + un-selected import is the fast-PATH: its
# staged output is byte-identical to the source, so it skips staging.  For a FILE that
# means binding it directly (copy-free include); for a DEF, eval-ing the value in place.
# EXCEPT a file carrying a `__main__` entrypoint: it must be routed THROUGH staging so
# `_mk.demote.main` can rebind __main__ -> <root> (else a verbatim include would leak the
# plugin's __main__ into the importer's scope and collide).  The grep runs only for a
# fast-path file candidate, so the copy-free path is preserved for the __main__-less norm.
$(eval _mk_mod_flatverb:=$(if $(filter 1,$(strip ${kwargs_flat})),$(if $(filter stream.echo,$(strip ${kwargs_preprocs})),$(if $(strip ${kwargs_defs}${kwargs_targets}),,1))))
$(eval _mk_mod_hasmain:=$(if $(and ${_mk_mod_flatverb},$(strip ${kwargs_file})),$(call lang.main.has,$(call _mk.path.resolve,$(strip ${kwargs_prefix}),$(strip ${kwargs_file})))))
$(eval _mk_mod_fast:=$(if ${_mk_mod_flatverb},$(if $(strip ${kwargs_file}),$(if ${_mk_mod_hasmain},,FAST))))
$(eval _mk_mod_fast_def:=$(if ${_mk_mod_flatverb},$(if $(strip ${kwargs_def}),FAST)))
$(if ${_mk_mod_fast},$(call _include, prefix=$(strip ${kwargs_prefix}) strict=$(strip ${kwargs_strict}) file=$(strip ${kwargs_file})),$(if ${_mk_mod_fast_def},$(call _mk.module.from_def_flat,$(strip ${kwargs_def})),$(if $(strip ${kwargs_def}),$(call _mk.module.from_def,$(strip ${kwargs_def}),$(or $(strip ${kwargs_namespace}),$(strip ${kwargs_def})),$(strip ${kwargs_preprocs}),${_mk_mod_sel},$(strip ${kwargs_flat})),$(call _mk.module.from_file,$(call _mk.path.resolve,$(strip ${kwargs_prefix}),$(strip ${kwargs_file})),$(or $(strip ${kwargs_namespace}),$(basename $(notdir $(strip ${kwargs_file})))),$(strip ${kwargs_preprocs}),${_mk_mod_sel},$(strip ${kwargs_flat})))))$(eval __modules__:=$(sort ${__modules__} $(call _mk.module.name,def=$(strip ${kwargs_def}) file=$(strip ${kwargs_file}))))$(if ${_mk_mod_plugtok},$(eval __plugins__:=$(sort ${__plugins__} ${_mk_mod_plugtok}))$(eval __plugins__.paths:=$(sort ${__plugins__.paths} ${_mk_mod_plugpath})))
endef

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: __hosted__ :: The hosted partition
##
## `define __hosted__` is a region of compose.mk authored in CMK-lang, parked in an
## opaque make `define` (never expanded as a var).  It is lowered to a content-addressed
## cache and bound via GNU make's makefile-remaking, so a plain `include compose.mk` (no
## bash/supervisor) transparently gets it: on a cold cache make builds it here and
## restarts once; warm parses are a hash + `-include`.  The seed must not reference
## `__hosted__` symbols at parse time (all references are run-time targets/prereqs); a
## hosted target may freely reference seed symbols.
##
## Placed here, right after the module-import and transpile machinery it depends on.
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
# The CMK-lang source of truth.  Extracted (by sed, from the file) + lowered by the rule
# below; the make `define` itself is inert (never `$(__hosted__)`-expanded).
define __hosted__
  hosted.selftest:
    '''A trivial, non-docker proof target authored in the hosted region.'''
    cmk.log(hosted partition is live)
    echo ok

  # flux (hosted): background-job + retry helpers.  flux.bg backgrounds+reaps a
  # target by pidfile; flux.retry loops a shell command until it succeeds.
  flux.bg.pidfile=.tmp.flux.bg.$(subst /,_,$(m5[1])).pid
  flux.bg=${make} $(m5[1]) & echo $$! > $(call flux.bg.pidfile,$(1))
  flux.bg.wait=wait `cat $(call flux.bg.pidfile,$(1)) 2>${devnull}` 2>${devnull} || true; rm -f $(call flux.bg.pidfile,$(1))
  flux.bg/%:; $(call flux.bg,${*})
  flux.retry=_n=$(or $(m5[2]?),${FLUX_RETRY_N}); _r=0; _rc=1; while [ $$_r -lt $$_n ]; do { $(1); } && { _rc=0; break; }; _r=$$(($$_r+1)); [ $$_r -lt $$_n ] && sleep $${interval:-${FLUX_RETRY_DELAY}}; done; ( exit $$_rc )

  cmk.class cmk.protocol(|
    '''
    The ABC metaclass for cmk's dunders.  One declaration form: `NAME(kwargs)(| body |)`, where
    the kwargs (abstract/dunder, bases) always ride the call-args and the body is the OPTIONAL
    default -- empty for a pure structural interface, docstring-only for a documented one, or a
    real impl for a mixin.  Structural checks (provided_by/register) come for free; __bases__/__mro__
    publish so issubclass works across KINDs; deriving a base unions its abstract into this one;
    minting self-registers into lang.proto.registry (bare `protocols` after `open cmk`).

    Body vs surface: the body is the MIXIN -- it is stamped onto conformers via `bases=<Proto>`, so
    it holds only members every conformer should inherit.  Protocol query/reader tooling (`.get`,
    `.provided_by`, `.register`) lives on the protocol OBJECT (set outside the body, subject passed
    as an arg) and is never stamped onto a conformer -- so a name like `.get` stays free downstream.
    '''
    $(call lang.proto.__new__, self, ${1})
    $(call lang.proto.__init__, self, ${1})
    self.registry  ?=
    self.provided_by = $(call lang.proto.provided_by,self,$1)
    self.register = $(eval self.registry += $1)
    $(eval lang.proto.registry += self)
  |)
  cmk.protocol Documented(dunder=__doc__)(|
    '''
    The documentation-string capability: the interface every documented module, class, and target
    satisfies.  A bare triple-quoted literal at the top of a body reifies here; a target's own text
    is read back from source at recipe time by a registered runtime reader.
    '''
  |)
  Documented.get = $(if $(call Documented.provided_by,$(m5[1])),$($(m5[1]).__doc__),)
  $(call Documented.register,_cmk.target.doc)

  cmk.protocol Registry(abstract=has:require)(|
    '''
    The registry capability: a named collection you can query membership of and demand a member
    from.  The plugin, module, ambient, and lifted-goal tables all satisfy it structurally -- one
    interface over four collections.
    '''
  |)

  cmk.protocol Named(dunder=__name__)(|
    '''
    The naming capability: a qualified identity.  A namespace instance satisfies it structurally.
    '''
  |)

  cmk.protocol Loggable(bases=Named)[|
    '''
    The logging capability: a name-bound logger.  A conformer logs under its own identity without
    re-deriving it.  Bare `.log` is the info line; `.log.warn`, `.log.error`, and `.log.debug` are
    the severity ladder.  Each delegates to the themed core loggers, which supply the running-target
    header, while this mixin supplies the conformer name.  Anything Named can carry it.
    '''
    self.log.__call__ = cmk.log(self ${sep} ${__args__})
    self.log.warn.__call__ = cmk.log.warn(self ${sep} ${__args__})
    self.log.error.__call__ = cmk.log.error(self ${sep} ${__args__})
    self.log.debug.__call__ = cmk.log.trace(self ${sep} ${__args__})
  |]

  cmk.protocol Directory(abstract=__all__:__dir__, ifaces=lang.proto.tmpl.directory)(|
    '''
    The reflection capability, python's pair: a curated public-export manifest (the intent) and the
    live computed member listing (the contents).  Contract only -- both providers already exist
    structurally: every instance is stamped with its member listing, and the core namespaces carry
    a curated export manifest.
    '''
  |)

  cmk.protocol Program(abstract=__main__)(|
    '''
    The entrypoint capability.  The default reports that no entrypoint was declared and fails; a
    program kind overrides it with a real entry.
    '''
    self.__nomain__ = $(call log.module.fail, self declares no __main__ entrypoint, CMK_NO_MAIN)
    self.__main__ = $(self.__nomain__)
  |)

  cmk.protocol Openable(abstract=__open__)(|
    '''
    The open capability: dissolve a module into scope.  The default reports it is unimplemented and
    fails; the module, path, and core-module kinds override it.
    '''
    self.__noopen__ = $(call log.module.fail, self does not implement __open__, CMK_NOT_IMPLEMENTED)
    self.__open__ = $(self.__noopen__)
  |)

  cmk.protocol Callable(dunder=__call__, ifaces=lang.proto.tmpl.callable)(|
    '''
    The call capability: a bare invocation routes here.  Some interfaces name a contract only
    (structural conformance, no default); this one ships a default that errors, and conformers
    override it -- the fragment mixin routes every language instance.  The default lives in the seed
    prelude and is prepended to the mixin below, so it is shared with any seed-resident carrier.
    '''
  |)
  
  cmk.protocol Templatable(abstract=__mod__, ifaces=lang.proto.tmpl.templatable)(|
    '''
    Compile-time symbol injection: fill the holes in the quoted body and mint a fresh fragment of
    the same kind.  The working default (`.__mod__`/`.render`) lives in the seed prelude and is
    prepended to the mixin below, so a seed code-object and this protocol share one body.
    '''
  |)

  cmk.protocol Materializable(dunder=__blockref__, ifaces=lang.proto.tmpl.materializable)[|
    '''
    The materialization capability: hold a quoted body and expose it as a process-substitution FD
    or a real tempfile, so an external tool reads it as a file argument.  The dunder names the
    materializable representation -- here the body itself -- and the blockref operator dispatches
    through it.  A concretized mixin: a kind carries this to become referenceable as a file.
    The glyph-free core (raw-body, shape, blockref) lives in the seed prelude and is prepended to
    the mixin below; only the block-reference glyph members stay here, cooked (`[|`) so they lower.
    '''
    ${self}.fd = ⬦${self}
    ${self}.file = ⬥${self}
  |]

  cmk.protocol Feedable(abstract=feed, ifaces=lang.proto.tmpl.feedable)(|
    '''
    The program-feed capability: how a run's materialized program file reaches its entrypoint -- a
    trailing file argument (the default), piped on stdin, or after a flag (which the flag names).
    A concretized mixin whose members are read from the declaration keywords or the instance body;
    the machine hierarchy carries it so a host or container interpreter picks the discipline its
    tool expects.  The run paths consult it when assembling the interpreter command.
    '''
  |)

  cmk.class cmk.Fragment(bases=Callable,Materializable)[|
    '''
    The fragment mixin: a materializable body PLUS a bare invocation.  The materialization surface
    (shape, fd, file) arrives from Materializable; the call capability from Callable, with the
    router overriding the erroring default.  The language metaclass mints every kind with this as a
    base, so a language declaration is just a class declaration carrying this mixin.  When the kind
    is machine-backed (a `dsl` declaration carrying entrypoint/img/machine), the invoke instead
    delegates to that machine, running the body through its entrypoint: the fragment has-a machine.
    '''
    self.__machine__ = $(call m5|,$(self.__class__).__machine__,)
    self.stream = $(if $(self.__machine__),$(call lang.dsl.machine.proxy,$(self.__machine__),,self),$(if $(filter file override,$(origin self)),$(call self,),${make} self))
    self.__call__ = $(if $(self.__machine__),$(call lang.dsl.machine.proxy,$(self.__machine__),${__args__},self),$(if $(filter file override,$(origin self)),$(call self,${__args__}),${make} self))
    self.__eval__ = $(call m5.def!,lang.banana.jtmp,${__args__})$(call lang.banana.new!,$(self.__class__),lang.banana.jtmp,raw)
    ${self}.__concat__ = $(call lang.banana.concat,${self},$(strip ${__args__}))
  |]

  cmk.class blockref(bases=Materializable)[|
    '''
    Capture a raw block and expose it as a materializable handle: its body materializes as a
    process-substitution FD or a real tempfile.  Materialization only -- referencing the block is
    the use, there is no base call.  The constructor-form dual of the recipe-line block-reference
    glyphs, and the route for a module-level block the glyph stage cannot reach.
    '''
  |]

  cmk.dsl dsl.jqlang(docstrings=1)[|
    '''
    A core sub-language kind: an instance is a callable JSON builder over a quoted jq shape (bare
    after opening the language namespace).  The base call runs jq with the shape as a script over
    stdin plus any trailing CLI args; the locals variant feeds the recipe's captured target-locals
    instead of stdin.  Triple-quoted docstrings are enabled per instance.
    '''
    self.__flags__ := $(patsubst MKID_NONE,,$(call _mk.kwargs.getd,${1},__args__))
    ${self} = ${jq} $(strip $(${self}.__flags__) ${__args__}) -f ${self}.fd()
    self.locals = $(__locals__) | $(call self,)
    ${self}.__concat__ = $(call ${self}.__eval__,$(${self}.shape)$($(strip ${__args__}).shape))
    ${self}.__add__ = $(call ${self}.__concat__,${__args__})
    ${self}.__pipe__ = $(call ${self}.__eval__,$(${self}.shape) | $($(strip ${__args__}).shape))
  |]

  dsl.jqlang mk.stat.shape(|
    '''
    mk.stat report shape.  It reads its input from `.` (not `__locals__` -- core
    can't assume the target_locals pragma), so `mk.stat` builds a typed JSON with
    `jb` (`:number`/`:raw` keep level + pragma unstringified) and streams it through
    the shape.  `words` folds a space-separated registry string to a token array.
    '''
    def words: split(" ") | map(select(length > 0));
    { make_version: .mv, version: .ver, "compose.mk": .hash, bin: .bin, makelevel: .lvl,
      plugins: ((.plugins // "") | words), modules: ((.modules // "") | words),
      n_plugins: ((.plugins // "") | words | length), n_modules: ((.modules // "") | words | length),
      pragma: .pragma }
  |)

  dsl.awklang compiler_stats(|
    '''Run-only size and partition scanner backing the compiler stats report.'''
    { raw=$0; t=raw; sub(/^[[:space:]]+/,"",t); is_c=(t ~ /^#/ || t ~ /^@#/); is_b=(t=="") }
    /^define \.awk\./    { inb=1; next }
    inb && /^endef/      { inb=0; next }
    /^define __hosted__/ { inh=1; hd=0; next }
    inh && /^define /    { hd++ }
    inh && /^endef/      { if (hd==0) { inh=0; next } hd-- }
    { if (!is_c && !is_b) { total++; cc+=length(raw)
        if (inb) { compiler++; ac+=length(raw) }
        if (inh) hosted++ } }
    END { core=total-compiler; seed=core-hosted; r = ac>0 ? cc/ac : 0
      printf "{\"total_sloc\":%d,\"compiler_sloc\":%d,\"core_sloc\":%d,\"hosted_sloc\":%d,\"seed_sloc\":%d,\"core_chars\":%d,\"awk_chars\":%d,\"compiler_ratio\":%.2f}\n", total, compiler, core, hosted, seed, cc, ac, r }
  |)

  dsl.awklang fork_section(|
    '''
    Run-only: replace a guest or payload section in a forked copy of the source, driven by the
    environment (the section name, a prefix, the guest data, a postfix, and a post-hook).
    '''
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
  |)

  dsl.awklang target_doc(|
    '''
    Emit a target's leading recipe-comment docstring block (the silent comment lines right under
    its rule), prefix-stripped, for surfacing in subcommand usage.  Run-only; powers the runtime
    docstring reader and subcommand usage, and degrades to empty on a cold cache.  A docstring
    writes the invocation as the literal token ${CMK_BIN}; the `bin` var rewrites it to the path
    this process was actually invoked as, so examples never hardcode one entrypoint spelling.
    '''
    BEGIN{_o="";for(_i=1;_i<=length(t);_i++){_c=substr(t,_i,1);if(index(".+*?^$()[]{}|/\\",_c))_o=_o "\\" _c;else _o=_o _c};pat="^" _o "[ \t]*:"} FNR==1{c=0} !c&&$0~pat{c=1;next} c&&/^\t@#/{l=$0;sub(/^\t@#[ ]?/,"",l);if(bin!="")gsub(/\$\{CMK_BIN\}/,bin,l);print l;next} c{c=0}
  |)

  dsl.awklang subcmd_docs(|
    '''
    Emit `<name>|<summary>` for each target named in `names`, where the summary is the first line
    of its docstring (the `${CMK_BIN}` token rewritten from `bin`, as in target_doc).  One pass for
    a whole subcommand namespace, so a usage listing costs one awk instead of one per subcommand.
    '''
    BEGIN{n=split(names,A," ");for(i=1;i<=n;i++){_o="";for(j=1;j<=length(A[i]);j++){_c=substr(A[i],j,1);if(index(".+*?^$()[]{}|/\\",_c))_o=_o "\\" _c;else _o=_o _c};P[i]="^" _o "(/%)?[ \t]*:"}}
    /^[^ \t#]/{c=0;for(i=1;i<=n;i++)if(!(A[i] in D)&&$0~P[i]){c=i;break};next}
    /^\t@#/{if(c){l=$0;sub(/^\t@#[ ]?/,"",l);if(bin!="")gsub(/\$\{CMK_BIN\}/,bin,l);D[A[c]]=l;print A[c] "|" l;c=0};next}
    {c=0}
  |)

  dsl.awklang select_def(|
    '''
    Select whole define blocks from a makefile stream whose name matches a glob (an exact name when
    it has no glob character), passing nested inner defines through verbatim and skipping the
    non-matching blocks.  Run-only.
    '''
    function g2r(s,  r,i,c){ r="";
      for(i=1;i<=length(s);i++){ c=substr(s,i,1);
        if(c=="*") r=r ".*";
        else if(c=="?") r=r ".";
        else if(c ~ /[][(){}.^$+|\\]/) r=r "\\" c;
        else r=r c };
      return r }
    BEGIN { rx = "^(" g2r(pat) ")$"; depth=0; cap=0 }
    depth==0 && /@@SYM_DEFINE@@ / { if ($2 ~ rx) { cap=1; depth=1; print } else { cap=0; depth=1 }; next }
    depth==0 { next }
    /@@SYM_DEFINE@@ / { depth++; if (cap) print; next }
    /^endef[ \t]*$/ { if (cap) print; depth--; if (depth==0) cap=0; next }
    { if (cap) print }
  |)

  dsl.awklang demote_main(|
    '''
    Rename a module's top-level entrypoint target to the module root (Pythonic import demotion) and
    drop any default-goal, leaving nested defines and recipes untouched.  Run-only.
    '''
    /^[ ]*define[ ]/ { depth++; print; next }
    /^[ ]*endef[ ]*$/ { if (depth>0) depth--; print; next }
    depth > 0 { print; next }
    /^\t/ { print; next }
    /^__main__[ \t]*:/ { sub(/^__main__/, root); print; next }
    /^[ \t]*\.DEFAULT_GOAL[ \t]*:?=/ { next }
    { print }
  |)

  dsl.awklang classify_fault(|
    '''
    Run-only: classify a dry-run failure into one CamelCase fault-type on stdout, or nothing.  Backs
    the validate and run error branches; degrades to no fault-header on a cold cache (the raw
    traceback still prints).
    '''
    !h && match($0, /cmk-fault errno=[A-Za-z_]+/) { s=substr($0, RSTART, RLENGTH); sub(/.*errno=/, "", s); print s; h=1; next }
    !h && match($0, /NotImplemented\/Grammar\/[A-Za-z0-9._-]+/) { print substr($0, RSTART, RLENGTH); h=1; next }
    !h && /No rule to make target/ { print "RuleMissing"; h=1; next }
    !h && /missing separator/ { print "SyntaxError"; h=1; next }
    !h && /commences before first target/ { print "SyntaxError"; h=1; next }
  |)

  cmk.protocol Runnable(dunder=__in__)(|
    '''
    The execute capability, dual to the call capability and keyed to the `in` operator (its dunder,
    the structural dual of `__call__`).  A code-object conforms only when bound; distinct from the
    entrypoint capability.  A machine reads its own `.run` helper to pick a dispatch target, then
    `.__in__` wraps it feed-aware; the plain `.run` name is a machine detail, not this slot.
    '''
    self.__in__ = $(call mk.error, cmk: .__in__ not implemented on `self` (Runnable): nothing to execute -- override .__in__$(comma) or bind to a machine, errno=NOT_RUNNABLE)
  |)
  
  cmk.protocol Ambient(bases=Directory:Named, abstract=__ambient_parent__)(|
    '''
    Ambient membership, the mobility-algebra root: a conformer is a named place a block moves
    between.  Working default: registers as a named ambient and carries its parent link for outward
    navigation.  The machine kind mixes it in; a namespace conforms structurally.  Per-operator
    refinements are separate capabilities (the execute and open interfaces).
    '''
    $(if $(call m5.defined?,${self}.__isprotocol__),,$(if $(call __ambients__.has,${self}),,$(call __ambients__.declare,${self})))
    self.__ambient_parent__ ?= host.local
  |)

  # the ambient run-side subkinds, grouped in an ENCAPSULATION AMBIENT -- `*[| .. |]`, an indented
  # anonymous module dissolved-in-place in the same scope that declares it (a small contiguous namespace).
  # `cmk.machine` is a KIND (class): each instance (sh/bash/python/out) grows a `${self}/%:` target
  # routing through a `.run` hook (host command dispatch by default), reached by the `NAME[block]` callform.
  # `cmk.container` IS-A machine (`using bases=cmk.machine`): inherits that target, overrides `.run` to
  # the docker dispatch (`_crun`), reads img/entrypoint from the instance body -- after `open cmk`,
  # `container box(img=..)(| |)` then `(| .. |) in box` runs in the image.  (The KINDs are minted qualified
  # so bare `machine`/`container` stay free until `open cmk`; `jq` is NOT a machine -- use `dsl jqlang`.)
  # container.exec(inst,def) / `_crun/<inst>,<def>` -- a container instance's RUN hook: run the lifted
  # block <def> in the instance's image (cmd/img/entrypoint from its own vars).  A container's `.run` is
  # `_crun/${self}`, and the machine dispatch appends `,<def>`, which `_crun` splits back out.
  mk.expand = $(eval _mk.expand.tmp := $(1))$(_mk.expand.tmp)
  container.exec = def=$(2) img=$($(1).img) cmd="$($(1).cmd)" entrypoint=$(or $($(1).entrypoint),none) feed=$(or $($(1).feed),file) feed_flag="$($(1).feed_flag)" ${make} docker.run.def
  # container.owner names the builder of an instance's image: itself, else whoever registered that tag at mint; the run, call, and dispatch seams all ensure it.
  container.owner.key = $(subst /,__,$(subst :,__,$(1)))
  container.buildable = $(or $($(1).src),$($(1).file))
  # An unregistered tag (any public image) has no cell, so the lookup is by definedness first.
  container.owner.registered = $(if $(call m5.defined?,container.owner.$(1)),$(container.owner.$(1)))
  container.owner = $(if $(call container.buildable,$(1)),$(1),$(call container.owner.registered,$(call container.owner.key,$($(1).img))))
  # an image is keyed on all that shapes it: kwargs, recipe, and each bound file's body and placement
  container.content = $(1)$(nl)$(value $($(1).src))$(nl)$(value $($(1).file))$(foreach _f,$($(1).__files__),$(nl)$(_f) $($(_f).__path__) $($(_f).__mode__)$(nl)$(value $(_f).shape))
  container.content.tmp = .tmp.cmk.cimg.${_cmk.pid}
  container.content.key = $(file > ${container.content.tmp},$(call container.content,$(1)))$(shell set -- `cksum < ${container.content.tmp}`; rm -f ${container.content.tmp}; echo $$1)
  # read on demand, not at mint, since a file can bind itself to an instance that already minted
  container.tag = $(if $(call container.buildable,$(1)),$($(1).img)-$(call container.content.key,$(1)),$($(1).img))
  container.ensure = $(if $(call container.owner,$(1)),docker image inspect $(call container.tag,$(call container.owner,$(1))) >/dev/null 2>&1 || ${make} $(call container.owner,$(1)).build &&)
  _crun/%:; @$(call container.ensure,$(firstword $(subst $(comma), ,${*}))) $(call container.exec,$(firstword $(subst $(comma), ,${*})),$(lastword $(subst $(comma), ,${*})))
  *[|
    cmk.class cmk.container.capabilities[|
      '''
      The container-capabilities mixin: the configuration surface for the machine hierarchy (folded
      into the base machine, so container, host, and polyglot inherit it).  A namespace or module is
      an ambient too but carries none of this.  Image, entrypoint, command, source, and file are read
      from the declaration keywords first, else the instance body; it provides the image-build hook
      (ambient registration belongs to the ambient capability, not this mixin, and the program-feed
      discipline to the Feedable capability).  One command concept: the entrypoint -- a word overrides
      the baked image entrypoint, a target reference routes a make target, unset honors the baked
      entrypoint -- and the command is the args appended after it.
      '''
      self.img ?= $(call mk.expand,$(or $(call _mk.kwargs.getd,${1},img),$(call _mk.kwargs.getd,$(value self),img)))
      self._entrypoint ?= $(call mk.expand,$(or $(call _mk.kwargs.getd,${1},entrypoint),$(call _mk.kwargs.getd,$(value self),entrypoint)))
      self.cmd ?= $(call mk.expand,$(or $(call _mk.kwargs.getd,${1},cmd),$(call _mk.kwargs.getd,$(value self),cmd)))
      self.src ?= $(or $(call _mk.kwargs.getd,${1},src),$(call _mk.kwargs.getd,$(value self),src))
      self.file ?= $(or $(call _mk.kwargs.getd,${1},file),$(call _mk.kwargs.getd,$(value self),file))
      self.__files__ ?=
      self.build:
      	if [ -n "$(strip $(${self}.__files__))" ]; then \
      		cmk.log.docker.part1(${dim}(with files=${no_ansi}$(strip $(${self}.__files__))${dim}) ${sep} ${cyan_flow_right}) \
      		&& img="$(${self}.img)" ${make} ${self}.build.files \
      		&& cmk.log.docker.part2(${bold}${green}${GLYPH_CHECK}); \
      	else case "$(${self}.file)" in \
      		''|undefined|Undefined) case "$(${self}.src)" in \
      			''|undefined|Undefined) cmk.log.docker(${dim}no src=/file= ${sep} noop);; \
      			*) cmk.log.docker.part1(${cyan_flow_right}) \
      				&& case `tag=$(${self}.img) ${make} docker.def.is.cached/$(${self}.src)` in \
      					yes) tag=$(strip $(patsubst compose.mk:%,%,$(${self}.img))) ${make} Dockerfile.build/$(${self}.src) \
      						&& cmk.log.docker.part2(${bold}${green}${GLYPH_CHECK});; \
      					*) cmk.log.docker.part2(${yellow}not cached) \
      						&& tag=$(strip $(patsubst compose.mk:%,%,$(${self}.img))) ${make} Dockerfile.build/$(${self}.src) \
      						&& cmk.log(${bold}${green}${GLYPH_CHECK});; \
      				esac;; \
      		esac;; \
      		*) cmk.log.docker(${dim}(via file=${no_ansi}$(${self}.file)${dim}) ${sep} ${cyan_flow_right}) \
      			&& tag=$(${self}.img) ${make} docker.build/$(${self}.file) \
      			&& cmk.log(${bold}${green}${GLYPH_CHECK});; \
      	esac; fi
      	$(if $(call container.buildable,${self}),docker tag $(${self}.img) $(call container.tag,${self}),true)
    |)

    cmk.class cmk.machine(bases=cmk.container.capabilities,Runnable,Ambient,Feedable)[|
      '''
      The base ambient, an execution context.  The image is optional: empty runs on the host (the
      host subkind), a real image runs in that container.  Holds the configuration surface, ambient
      registration, the in-dispatch execute hook, the universal call dispatch, and a hook to mint a
      code-object bound here.  The container and host kinds refine it.  The call dispatch combines
      the entrypoint and command: a target reference routes a make target, a real image routes to the
      container runtime, the host prepends the entrypoint.  Running a file here is a call with it.
      '''
      self.__raw_body__ := 1
      self.__all__ ?= $(call mk.error, cmk: .__all__ not implemented on `self` (Directory): a machine's member manifest is undefined for now -- override .__all__, errno=NOT_IMPLEMENTED)
      self.__name__ ?= self
      self.entrypoint = $(or $(self._entrypoint),$(if $(self.img),,self))
      self.run = $(if $(self.img),_crun/self,host.dispatch/$(self.entrypoint))
      # the run helpers speak in the ambient's voice, given this line, and stage the block silently
      self.__announce__ = $(if $(self.img),${bold}${underline}$(self.img),${dim}$(self.entrypoint))
      self.__run__ = announce="$(self.__announce__)" announce_as="${self}" verbose=0 feed="$(self.feed)" feed_flag="$(self.feed_flag)" ${make} $(self.run),${__args__}
      self.__in__ = $(call ambient.enter,${self}) $(call ${self}.__run__,${__args__})
      ${self}/%:; @$(call ${self}.__in__,${*})
      ${self}.reenter/%:; @$(call ${self}.__run__,${*})
      self.__call__ = $(if $(filter @%,$(self.entrypoint)),${make} $(patsubst @%,%,$(self.entrypoint))/$(strip $(self.cmd) ${__args__}),$(if $(self.img),$(call container.ensure,self) img=$(self.img) entrypoint=$(or $(self.entrypoint),none) cmd="$(strip $(self.cmd) ${__args__}) $${CMK_LAMBDA_ARGV:-}" ${make} docker.run.sh,cmd="$(strip $(self.entrypoint) $(self.cmd) ${__args__}) $${CMK_LAMBDA_ARGV:-}" ${make} cmk.host.exec))
      self.polyglot = $(call code.unbound, ${__args__} bind=self)
    |)

    cmk.class cmk.container(bases=cmk.machine)(|
      '''
      A machine whose execute hook is fixed to the container-runtime dispatch: always a container, an
      image is expected.  The call dispatch is inherited from the base machine; the refinement pins the
      execute hook so a block run in an instance always uses the container, and the dispatch hook runs
      a make target inside the image.  A buildable instance registers its tag at mint, so an instance
      that merely points at that tag builds it on first dispatch instead of needing a manual build.
      '''
      self.run := _crun/self
      self.__out__ = $(call ambient.out.escape,${__args__})
      ${self}.dispatch/%:; @$(call container.ensure,${self}) img=$(${self}.img) ${make} docker.dispatch/${*}
      self.__buildable := $(if $(strip $(foreach _w,$(value self),$(if $(call m5.lex.kwarg?,$(_w)),,$(_w)))),1)
      self.src := $(or $(self.src),$(if $(self.__buildable),self))
      self.img := $(or $(self.img),$(if $(self.__buildable),compose.mk:self))
      self.__minted__ = $(if $(call container.buildable,${self}),$(if $(${self}.img),$(eval container.owner.$(call container.owner.key,$(${self}.img)) ?= ${self})))
      ${self}.__dot__ = $(eval _op := $(strip ${__args__}))$(eval $(_op).__call__ := ${make} ${self}.build && def=$(_op) img=$(${self}.img) entrypoint=sh ${make} docker.run.def)$(_op)
    |)
    cmk.class cmk.host(bases=cmk.machine)(|
      '''
      The symmetric twin of the container kind: a machine whose execute hook is fixed to the host
      dispatch, the entrypoint run on the local host, never a container.  Host and container are the
      explicit subkinds -- a host carries no sentinel, it just is-a host.
      '''
      self.run = host.dispatch/$(self.entrypoint)
    |)

    # `host.local` -- the always-present local-host singleton ambient: the default recipe shell,
    # the canonical `out` target, and the home for host capabilities.  Its `__ambient_parent__`
    # is empty -- nothing encloses the host (see `outwards/%` below).
    cmk.host host.local(entrypoint=bash)(| |)
    $(eval host.local.__ambient_parent__ :=)

    # `host.daemon` -- what a mounted socket confers, the right to build containers rather than to run on the host; a root, since nothing encloses the daemon either.
    cmk.host host.daemon(entrypoint=bash)(| |)
    $(eval host.daemon.__ambient_parent__ :=)

    # `host.native.*` -- the native host interpreters as host singletons, each minted through the
    # `host.native` factory (a `host.native.<x>` cmk.host whose entrypoint is `<x>`).  Reached by
    # their FULL instance name (`in host.native.sh`, `in host.native.python`): there is no bare
    # `in sh`/`in python` alias -- `_cmk.host.machine` dispatches any non-`out` name by its own
    # value, so a bare `in python` is an ordinary (undefined) ambient, not a runner.  `out` (the
    # host escape) is its own singleton below.
    $(call host.native,sh)
    $(call host.native,bash)
    $(call host.native,python)
    cmk.host out(entrypoint=bash)(| |)

    # `outwards/%` -- the `out` keyword's target (the `out` trailer resolves to it via
    # `_cmk.host.machine`).  It navigates to the DYNAMIC `__ambient_parent__` inherited from the
    # enclosing `X/%` dispatch (`out == in __ambient_parent__`).  UNSET means a top-level recipe,
    # whose enclosing ambient is `host.local` (so `out` there = escape to the host, the existing
    # behavior).  EXPLICITLY EMPTY means you are IN `host.local` (its parent is unset) -> there is
    # nowhere further out -> a hard, named fault.  A named parent -> navigate into it.
    outwards/%:; @P="$${__ambient_parent__-host.local}"; if [ -n "$${__ambient_expect__:-}" ] && [ "$${__ambient_expect__}" != "$${__ambient__:-}" ]; then echo "cmk: OutwardsUnexpected: asked to leave $${__ambient_expect__}, but this block is in $${__ambient__:-the top}" >&2; exit 1; fi; if [ -n "$${__ambient_parent__+x}" ] && [ -n "$$P" ] && [ "$$P" != "$(_ambient.dest?)" ]; then echo "cmk: AmbientChainMismatch: the parent link says $$P but the chain stack says $(_ambient.dest?)" >&2; exit 1; fi; if [ -z "$$P" ]; then echo 'cmk: OutwardsUndefined: this is the top (nothing encloses this ambient to move out to)' >&2; exit 1; fi; $(if $(call m5.defined?,$(__ambient__).__out__),$(call $(__ambient__).__out__,${*}),$(call ambient.out.default,${*}))
    cmk.class cmk.Dockerfile(bases=cmk.container)(|
      '''
      Thin alias of container: a container whose non-empty body is the image recipe builds it identically (img=compose.mk:self, src=self, fluent chain), so Dockerfile just names that intent -- all behavior is inherited.  When files are bound to it (see dockerfs), the build folds them into a private context, injecting a copy plus a chmod after the first base line; render shows that injected recipe without building.
      '''
      self.dockerfs = $(call cmk.dockerfs, ${__args__} bind=self)
      ${self}.render:
      	@d=$$(mktemp -d) && touch $$d/ins \
      	&& ${make} mk.def.to.file/$(or $(${self}.src),${self}),$$d/df \
      	$(foreach _f,$(${self}.__files__), && echo "COPY $(_f) $($(_f).__path__)" >> $$d/ins && echo "RUN chmod $($(_f).__mode__) $($(_f).__path__)" >> $$d/ins) \
      	&& awk -v inf=$$d/ins 'FILENAME==inf{b=b $$0 ORS;next}{print}/^FROM /&&!s{printf "%s",b;s=1}' $$d/ins $$d/df; rm -rf $$d
      ${self}.build.files:
      	@d=$$(mktemp -d) \
      	$(foreach _f,$(${self}.__files__), && verbose=0 ${make} mk.def.to.file/$(_f).shape,$$d/$(_f)) \
      	&& verbose=0 ${make} ${self}.render > $$d/Dockerfile \
      	&& docker build -q -f $$d/Dockerfile -t $${img} $$d >/dev/null && rm -rf $$d
    |)

    cmk.class cmk.dockerfs(bases=cmk.Fragment)(|
      '''
      A file bound to an image build.  The body is captured verbatim; bind= registers it on the image eagerly, path= is where it lands, mode= is its chmod.  At build the image copies each bound file in after its first base line, so the Dockerfile body stays free of scripts and copy lines.
      '''
      self.__minted__ = $(eval $(call m5.ctx?,${1},bind).__files__ += $(call m5.ctx?,${1},def))$(eval $(call m5.ctx?,${1},def).__path__ := $(call m5.ctx?,${1},path))$(eval $(call m5.ctx?,${1},def).__mode__ := $(call m5.ctx?,${1},mode))
    |)

    cmk.class compose.machine(bases=cmk.machine)(|
      '''
      The compose analog of a container: a machine backed by a scaffolded compose
      service, so the run, call, and build hooks are pinned to the service dispatch
      rather than falling through to the host.
      '''
      self.__exec__ = $(addsuffix .exec,self.__im_self__)
      self.run = self.stem/self.__im_self__
      self.__in__ = ${make} self.__exec__/$(strip ${__args__})
      self.__call__ = cmd="$(strip ${__args__}) $${CMK_LAMBDA_ARGV:-}" ${make} self.run
      self.build: $(addsuffix .build,self.stem)/self.__im_self__
      self.exec/%:
        cmk.io.mktemp() && this.mk.def.to.file(${*},$${tmpf}) && cmd=$${tmpf} env=$${env:-} this.self.run()
    |)

    cmk.class compose.group(|
      '''
      A compose file as a kind (the compose analog of Dockerfile): embed a spec,
      scaffold its classical service targets, and mint each service a machine.
      '''
      self.__raw_body__ = 1
      self.compose = $(addsuffix .yml,$(addprefix .tmp.,self.__im_self__))
      self.stem = $(addprefix .tmp.,self.__im_self__)
      self.content = $(value self)
      self.__all__ = $(shell awk '/^services:/{s=1;next} s&&/^  [A-Za-z0-9_]+:/{gsub(/:.*/,"");gsub(/^ +/,"");print} s&&/^[^ ]/{s=0}' self.compose 2>/dev/null)
      self.__minted__ = $(if $(filter-out 1,${CMK_INTERNAL}),$(file > self.compose,self.content))$(eval $(call compose.import.generic, self.__im_self__, FALSE, self.compose))$(foreach _svc,self.__all__,$(eval $(_svc).stem = self.stem)$(eval $(call compose.machine, def=$(_svc))))
    |)

    cmk.class compose.service(bases=compose.group,compose.machine)(|
      '''
      A degenerate compose.group that is itself the one service (and its machine): the
      raw body is a single service body, wrapped into a one-service compose file
      (services, self, body) when it materializes.
      '''
      self.content = services:$(nl)  $(addsuffix :,self.__im_self__)$(nl)    working_dir: /workspace$(nl)    volumes: [$(PWD):/workspace]$(nl)    $(subst $(nl),$(nl)    ,$(value self))
      self.__all__ =
    |)

    # compose.svc: a true alias of compose.service (same class).
    compose.svc = $(call compose.service,$(m5[1]))
  |]

  cmk.constructor cmk.namespace(bases=Ambient)(|
    '''
    A kind for names: a constructor with a per-instance body (unlike the machine classes above).  A
    declaration qualifies the body's heads under the instance's fully-qualified name, threading the
    enclosing name so nested blocks compose.  Working envelope: pure nesting with uniformly-indented
    leaves.  Currently a runtime shim; a compiler-stage replacement that dedents nested bodies before
    hoisting is planned.  Satisfies Named, Ambient, and Directory structurally: the name, parent
    link, and export manifest are stamped per instance (the manifest defaults empty, overridable),
    and the member listing is stamped by the constructor template.
    '''
    $(eval __fqn__ := $(if $(__name__),$(if $(filter $(__name__).%,${self}),${self},$(__name__).${self}),${self}))
    $(eval self.__raw_body__ := 1)
    $(eval $(__fqn__).__name__ := $(__fqn__))
    $(call m5.def!,$(__fqn__).shape,$(value ${body1}))
    $(eval $(__fqn__).__ambient_parent__ ?= host.local)
    $(eval $(__fqn__).__all__ ?=)
    $(if $(__name__),$(eval $(__fqn__) := $(__fqn__))$(eval $(__name__).__all__ += $(patsubst $(__name__).%,%,${self}))$(if $(call m5.defined?,${self}.__class__),$(eval $(__fqn__).__class__ := $(${self}.__class__)))$(eval $(__fqn__).__ctor__ := $(${self}.__ctor__)))
    $(eval __name__stack := $(call m5.stack.push,$(__name__),$(__name__stack)))
    $(eval __name__ := $(__fqn__))
    # an empty body has no heads to dedent/hoist, so skip the file+awk+include entirely -- this also
    # keeps a pure container (an identity-only namespace) from adding a temp to MAKEFILE_LIST.
    $(if $(strip $(value $(__fqn__).shape)),$(eval __ns_base.$(__fqn__) := $(filter $(__fqn__).%,$(.VARIABLES)))$(eval __ns_tmp := .tmp.ns.$(__fqn__).${_cmk.pid})$(file >$(__ns_tmp).raw,$(value $(__fqn__).shape))$(eval __ns_mk := $(shell set -- `cksum < $(__ns_tmp).raw`; o=.tmp.ns.$(__fqn__).${HOSTED_HASH}$(firstword $(subst ., ,$(notdir ${CMK_TWIN_PATH}))).$$1-$$2.mk; [ -f "$$o" ] || { awk "$${_awklang_ns_dedent}" $(__ns_tmp).raw | awk "$${_awklang_indent}" | awk -v ns='$(__fqn__)' -v dunders=1 -v frags=1 "$${_awklang_module_ns}" > $(__ns_tmp).mk && mv -f $(__ns_tmp).mk "$$o"; }; rm -f $(__ns_tmp).raw; echo "$$o"))$(eval include $(__ns_mk)))
    $(eval __name__ := $(call m5.stack.top,$(__name__stack)))$(eval __name__stack := $(call m5.rest,$(__name__stack)))
    $(eval __fqn__ := $(if $(__name__),$(if $(filter $(__name__).%,${self}),${self},$(__name__).${self}),${self}))
    # the member manifest is collected here, once the name is this instance's again: a nested body leaves it pointing at the nested one
    $(if $(call m5.defined?,__ns_base.$(__fqn__)),$(eval $(__fqn__).__all__ += $(sort $(foreach _m,$(patsubst $(__fqn__).%,%,$(filter-out $(__ns_base.$(__fqn__)),$(filter $(__fqn__).%,$(.VARIABLES)))),$(if $(findstring .,$(_m)),,$(_m))))))
    $(eval $(__fqn__).__all__ := $(sort $($(__fqn__).__all__)))
    $(if $(strip $(value ${body1})),$(if $(strip $(call mk.native.stage,${CMK_NATIVE_CACHE}/$(__fqn__).hm,$(value $(__fqn__).shape))$(call lang.main.has,${CMK_NATIVE_CACHE}/$(__fqn__).hm)),$(eval $(__fqn__).__call__ = ${make} $(__fqn__).__main__)))
    $(call lang.seed.materialize!,$(__fqn__),lang.proto.tmpl.directory)
    # the ambient half a bare namespace lacked: registry membership, a parent link on each member, and the two doors
    $(call __ambients__.require,$(__fqn__))
    # a member arrives bare or already qualified, and only the ones already carrying a parent link are ambients
    $(foreach _k,$(patsubst $(__fqn__).%,%,$($(__fqn__).__all__)),$(if $(call m5.defined?,$(__fqn__).$(_k).__ambient_parent__),$(eval $(__fqn__).$(_k).__ambient_parent__ := $(__fqn__))))
    $(eval $(__fqn__)/%:; @$$(call ambient.enter,$(__fqn__)) $${make} host.dispatch/bash,$$*)
    $(eval $(__fqn__).reenter/%:; @$${make} host.dispatch/bash,$$*)
  |)

  cmk.class dsl.cmklang(bases=cmk.Fragment,Program)[|
    '''
    The CMK-lang fragment kind: a fragment that HOLDS its raw quoted body (no construction, so a body
    entrypoint never leaks to the top level) and is also a program.  Use raw bodies, cooked on demand.
    Cooking re-execs the body's entrypoint; a bare call cooks it, or reports no entrypoint; adding two
    bodies yields a fresh fragment of the same kind.  Resident target construction belongs to the
    module kind, not this one.
    '''
    ${self}.__add__ = $(call ${self}.__concat__,${__args__})
    ${self}.__has_main__ = $(call mk.native.stage,${CMK_NATIVE_CACHE}/${self}.hasmain,$(value ${self}.shape))$(call lang.main.has,${CMK_NATIVE_CACHE}/${self}.hasmain)
    ${self}.__cook__ = $(call cmk.cook,${self}.shape,__main__)
    ${self}.__main__ = $(if $(${self}.__has_main__),$(if $(call m5.defined?,${self}.__name__),${make} ${self}.__main__,$(${self}.__cook__)),$(${self}.__nomain__))
    ${self}.__call__ = $(call ${self}.__main__)
    self.__cook_here__ = mkdir -p ${CMK_NATIVE_CACHE} && _chr="$$(printf '%s\n' "$(value self)")" && _chf=${CMK_NATIVE_CACHE}/ch.$$(printf '%s' "$$_chr" | cksum | awk '{printf "%07x",$$1}').mk && { [ -s "$$_chf" ] || printf '%s\n' "$$_chr" | ${make} lang.transpile 2>${devnull} > "$$_chf" ; } && $(MAKE) ${MAKE_FLAGS} -f $(cmk.self) -f "$$_chf" __main__
    ${self}.__exec__ = $(eval define _cmk.exec.body$(nl)$(value ${self}.shape)$(nl)$(value $(strip ${__args__}))$(nl)endef)$(call _cmk.cook.frag,_cmk.exec.body)
    ${self}.__in__ = $(eval define _cmk.in.main$(nl)__main__:$(nl)  $(subst $(nl),$(nl)  ,$(value $(strip ${__args__})))$(nl)endef)$(call ${self}.__exec__,_cmk.in.main)
  |]
  cmk.class cmk.module(bases=dsl.cmklang,cmk.namespace)(|
    '''
    Is-a CMK-lang fragment (the fragment surface, algebra, and entrypoint) plus a namespace, so it
    CONSTRUCTS: a declaration builds resident qualified targets.  The fragment kind alone only holds
    its body, so a body entrypoint never leaks to the top level; construction is this kind's job.
    '''
    ${self}/%:; @$(call ${self}.__in__,${*})
    self.import = $(call import.module, def=self ${__args__})
  |)
  # (module / path dissolve subkinds are plain deferred macros in the seed -- see `module.dissolve`.)

  # __builtins__: reflection predicates, auto-bound bare below.
  cmk.module __builtins__(|
    issubclass = $(if $(filter $(strip ${2}),$($(strip ${1}).__mro__)),1,)
    isinstance = $(call __builtins__.issubclass,$(call m5|,$(strip ${1}).__class__,$($(strip ${1}).__ctor__)),$(strip ${2}))
  |)

  cmk.kernel:
  	'''
  	The CMK-lang analog of the kernel: compile the CMK source read on stdin, then run it.  The
  	stdin fills the program hole of an anonymous quote, whose cook-here step materializes,
  	transpiles, and runs its entrypoint in a child make -- no tempfile, no direct compile or
  	interpret.  The eval subcommand is the public front-end.
  	
  	USAGE:
  	  echo 'this.flux.ok' | ./compose.mk cmk.kernel
  	  echo 'this.flux.or(flux.ok, flux.fail)' | ./compose.mk cmk eval
  	'''
  	prog="$$(printf '__main__:\n'; ${stream.stdin} | awk '{print "\t"$$0}')"
  	dsl.cmklang(| ${prog} |).__cook_here__()
  mk.def.dispatch/% host.dispatch/%:
  	'''
  	Host command dispatch: materialize the named block, then run the entrypoint over the file on
  	the host (a target-reference entrypoint dispatches to that make target).
  	USAGE: ./compose.mk host.dispatch/<entrypoint>,<def_name>
  	'''
  	cmk.io.mktemp()
  	entrypoint <- printf "${*}" | cut -d, -f1
  	def_name <- printf "${*}" | cut -d, -f2-
  	${mk.def.to.file}/$${def_name},$${tmpf}
  	if [ -n "$${preview:-}" ]; then ${make} io.preview.file/$${tmpf}; fi
  	if [ -n "$${announce:-}" ]; then cmk.log.mk.as($${announce_as},$${announce}); else cmk.log.mk($${entrypoint} ${sep} $${tmpf}); fi
  	case "$${entrypoint}" in @*) ${make} "$${entrypoint:1}/$${tmpf}";; *) which $${entrypoint} > ${devnull} || exit 1 && case "$${feed:-file}" in stdin) cmd="$${entrypoint} $${CMK_LAMBDA_ARGV:-} < $${tmpf}";; flag) cmd="$${entrypoint} $${CMK_LAMBDA_ARGV:-} $${feed_flag} $${tmpf}";; *) cmd="$${entrypoint} $${tmpf} $${CMK_LAMBDA_ARGV:-}";; esac && cmd="$${cmd}" ${make} cmk.host.exec;; esac
  mk.stat:
  	'''
  	Cheap runtime self-report for make and the tool.  Beyond version and identity it folds in the
  	program self-model: the imported plugin and module registries (as token arrays plus counts)
  	and the resolved pragma manifest.  Every field is cheap to gather: the registries are plain
  	exported strings and the pragma is one environment grep; no reflection snapshot is spawned.
  	
  	USAGE: ./compose.mk mk.stat
  	'''
  	cmk.log.base(${GLYPH_MK} mk.stat${no_ansi_dim}:)
  	_version <- make --version | awk 'NR==1{print $$3}'
  	_hash <- cat ${CMK_BIN} | md5sum | cut -d' ' -f1
  	${jb} mv="$$_version" ver="${CMK_VERSION}" hash="$$_hash" \
  	  bin="`basename $${CMK_BIN:-compose.mk}`" lvl:number="$${MAKELEVEL:-0}" \
  	  plugins:string??="${__plugins__}" modules:string??="${__modules__}" pragma:raw='${__pragma__}' \
  	  | mk.stat.shape(-c)

  tux.require: ${CMK_COMPOSE_FILE}
  	'''
  	Require the embedded-TUI stack to finish bootstrap.  This is time-consuming, so call it
  	strategically and only when needed.  It may be required for tools like 'gum' and for anything
  	depending on the base image, so strictly speaking it is not just for TUIs.  It tries to take
  	advantage of caching, but each service in the build order must be visited, and even that is slow.
  	'''
  	case $${force:-0} in \
  		1) ${make} tux.purge;; \
  	esac \
  	&& header="${GLYPH_TUI} tux.require ${sep}" \
   	&& cmk.log.trace($${header} ${dim}Ensuring TUI containers are ready: "${TUI_SVC_BUILD_ORDER}") \
  	&& (true \
  		&& ([ -z "$${TUX_BOOTSTRAPPED:-}" ] || $(call log.base, $${header}${red}bootstrapped already); exit 0) \
  		&& (local_images=`${docker.images} | xargs` \
  			&& cmk.log.trace.fmt($${header} ${dim}local-images ${sep}, ${dim}$${local_images}) \
  			&& items=`printf "${TUI_SVC_BUILD_ORDER}" | ${stream.comma.to.space}` \
  			&& count=`printf "$${items}"|${stream.count.words}` \
  			&& cmk.log.trace.loop.top($${header} ${yellow}$${count}${no_ansi_dim} items) \
  			&& for item in $${items}; do \
  				(cmk.log.trace.loop.item(${dim}$${item}) \
  				&& printf "$${local_images}" | grep -w $${item} > /dev/null \
  					|| ( \
  						cmk.log.tux(${@} ${no_ansi_dim}Container ${no_ansi}${bold}$${item}${no_ansi}${no_ansi_dim} not cached yet.${no_ansi}${bold} Building..) \
  						&& quiet=$${quiet:-1} svc=$${item} ${make} compose.build/${TUI_COMPOSE_FILE}) \
  			); done \
  			&& exit 0 ) \
  		)

  tux.purge:
  	'''Force removal of the base containers for the TUI.'''
  	cmk.log.flux(${@} ${sep}${no_ansi_dim} Purging the TUI base images..)
  	printf ${TUI_SVC_BUILD_ORDER} | ${stream.comma.to.nl} | xargs -I% docker rmi -f compose.mk:%
  	# docker rmi -f compose.mk:tux && docker rmi -f compose.mk:dind_base

  # flux.* control/composition primitives, ported from core into the hosted
  # region so a plain `include compose.mk` gets them via the lowered cache (not
  # just the bash/supervisor path).  Kept ALPHABETICAL -- see the hosted-porting memory.
  # Encapsulated in an anonymous module (`*[| .. |]`) that dissolves in place: a
  # contiguous flux.* namespace boundary inside the hosted region.
  *[|
    flux.after/%:; $(call flux.after,${*})
      '''Blocking delayed apply of N comma-listed targets after <seconds> (sync sibling of `flux.delay`).  USAGE: `flux.after/2,build,test`'''

    # flux.and(<t1>,..,<tN>): sequential fail-fast AND, the canonical impl -- a macro-first
    # twin (like flux.delay/flux.pool) so cmk.flux.and(..) is an inline callform with no
    # dispatcher fork.  Pure make-subst: the comma list becomes ` && ${make} `-joined.
    flux.and=${make} $(subst $(comma), && ${make} ,$(m5.__nargs__))
    flux.all=$(call flux.and,$(m5.__nargs__))
    flux.all/% flux.and/%:; $(call flux.and,${*})
      '''
      AND over the named comma-delimited targets: equivalent to running them in sequence.  Mostly a
      wrapper for the unary-argument case, with different semantics than plain make (which treats
      duplicate targets as already satisfied).
      
      USAGE:
        ./compose.mk flux.and/<t1>,<t2>
      '''

    flux.apply/%:
      '''
      Applies the given target to the given argument, comma-delimited.  If no argument is
      given, the target is assumed nullary.

      USAGE:
        ./compose.mk flux.apply/<target>,<arg>
        ./compose.mk flux.apply/<target>
        ./compose.mk make flux.apply/flux.echo,THUNK
      '''
      ${trace_maybe}
      export target="$(m5.__args__.first)"
      export arg="cmk.mk.unpack.arg(2-)"
      case $${arg} in \
      "") ${make} $${target}; ;; \
      *) ${make} $${target}/$${arg} ; ;; \
      esac

    flux.column/%:
      '''Exactly `flux.pipeline`, but assumes `:` delimiter instead of comma.'''
      delim=':' ${make} flux.pipeline/${*}

    flux.delay/%:; $(call flux.delay,${*})
      '''Non-blocking delayed apply of N comma-listed targets after <seconds> (async sibling of `flux.after`).  USAGE: `flux.delay/5,build,test`'''

    # flux.do.unless(<umbrella>,<dry>): run <umbrella> iff <dry> fails -- macro-first (defers to
    # `flux.do.when` over a negated <dry>), so cmk.flux.do.unless(..) is inline.
    flux.do.unless=( spec="$(m5.__nargs__)" \
      && ${make} flux.do.when/`printf '%s' "$${spec}"|cut -d, -f1`,flux.negate/`printf '%s' "$${spec}"|cut -s -d, -f2-` )
    flux.do.unless/%:
      '''
      Runs the 1st target iff the 2nd target fails.  Thin wrapper over the `flux.do.unless` macro
      (also `cmk.flux.do.unless(..)`).  A reversed `flux.if.then` -- see those docs for details.

      USAGE:
        ./compose.mk flux.do.unless/<umbrella>,<dry>
        ./compose.mk flux.do.unless/flux.ok,flux.fail
      '''
      $(call flux.do.unless,${*})

    # flux.do.when(<umbrella>,<raining>): reversed-arg `flux.if.then` -- run <umbrella> iff
    # <raining> succeeds; macro-first (defers to the `flux.if.then` macro) so cmk.flux.do.when(..)
    # is inline.  Nicer than flux.if.then when the "then" target carries its own commas.
    flux.do.when=( spec="$(m5.__nargs__)" \
      && _then=`printf '%s' "$${spec}"|cut -d, -f1` \
      && _if=`printf '%s' "$${spec}"|cut -s -d, -f2-` \
      && ${make} flux.if.then/$${_if},$${_then} )
    flux.do.when/%:
      '''
      Runs the 1st given target iff the 2nd target is successful.  Thin wrapper over the
      `flux.do.when` macro (also `cmk.flux.do.when(..)`).  A version of `flux.if.then`, nicer when
      the "then" target has multiple commas.

      USAGE:
        ./compose.mk flux.do.when/<umbrella>,<raining>
      '''
      $(call flux.do.when,${*})

    flux.echo/%:
      '''echoes the argument'''
      echo "${*}"

    flux.fail:
      '''
      Alias for `exit 1` (POSIX failure); mostly for testing other pipelines.
      See also the `flux.ok` target.
      '''
      cmk.log.flux(flux.fail ${sep} ${red}failing${no_ansi} as requested!) \
      && exit 1

    flux.fold/%:
      '''
      Left-fold over stdin lines (reduce with an explicit initial value).  The accumulator is
      threaded through the <reducer> target's stdin; the current line is passed as the `val`
      env-var; the reducer prints the new accumulator.  Seeded by the `acc` env-var, else the
      <init> arg (default empty).  Same shape as the `stream.*` reducers, so they drop in directly.

      USAGE: bundle a stream into a JSON array, reusing a stdlib reducer
        printf 'a\nb\nc\n' | ./compose.mk flux.fold/stream.json.array.append,[]  -> ["a","b","c"]
      '''
      reducer="$(m5.__args__.first)"
      acc="$${acc:-cmk.mk.unpack.arg(2-)}"
      while IFS= read -r val; do \
      acc="`printf '%s' "$${acc}" | val="$${val}" ${make} $${reducer}`" \
      ; done
      printf '%s\n' "$${acc}"

    # flux.if.then(<test>,<then>): run <then> iff <test> succeeds -- macro-first (keeps the
    # part1/part2 flux logging inline), so cmk.flux.if.then(..) runs with no dispatcher fork.
    # Args normalize via m5.__nargs__; the "if" failure is swallowed (quiet), not propagated.
    flux.if.then=( spec="$(m5.__nargs__)" \
      && _if=`printf '%s' "$${spec}" | cut -d, -f1` \
      && _then=`printf '%s' "$${spec}" | cut -s -d, -f2-` \
      && $(call log.base.part1,${GLYPH_FLUX} flux.${bold.underline}if${no_ansi}${dim_green}.then ${sep}${dim} ${ital}$${_if}${no_ansi} ) \
      && ( case $${quiet:-1} in \
             1) ${make} $${_if} 2>/dev/null; st=$$?; ;; \
             *) ${make} $${_if}; st=$$?; ;; \
           esac \
         ; case $${st} in \
             0) ( $(call log.base.part2,${dim_green}true${no_ansi_dim}) \
                ; $(call log.base,${GLYPH_FLUX} flux.if.${bold.underline}then${no_ansi} ${sep} ${dim_ital}$${_then} ${cyan_flow_right}); ${make} $${_then} ); ;; \
             *) $(call log.base.part2,${yellow}false${no_ansi_dim}); ;; \
           esac ) )
    flux.if.then/%:
      '''
      Runs the 2nd given target iff the 1st one is successful.  Thin wrapper over the `flux.if.then`
      macro (also `cmk.flux.if.then(..)`).  The "if" failure is not distinguished from a crash and
      does not propagate.  Only the 2nd argument may contain commas.  For the reversed form, see
      `flux.do.when`.

      USAGE:
        ./compose.mk flux.if.then/<test_target>,<then_target>
        ./compose.mk flux.if.then/flux.fail,flux.ok
      '''
      $(call flux.if.then,${*})

    # flux.if.then.else(<test>,<then>,<else>): standard if/then/else over targets -- macro-first
    # (keeps the part1/part2 logging inline), so cmk.flux.if.then.else(..) has no dispatcher fork.
    flux.if.then.else=( spec="$(m5.__nargs__)" \
      && _if=`printf '%s' "$${spec}" | cut -d, -f1` \
      && _then=`printf '%s' "$${spec}" | cut -d, -f2` \
      && _else=`printf '%s' "$${spec}" | cut -s -d, -f3-` \
      && $(call log.base.part1,${GLYPH_FLUX} flux.if.then.else ${sep}${dim} testing ${dim_ital}$${_if}) \
      && ( ${make} $${_if} ${all_devnull} ; st=$$? \
         ; case $${st} in \
             0) $(call log.base.part2,${dim_green}true${no_ansi_dim} - dispatching ${dim_cyan}$${_then}) ; ${make} $${_then};; \
             *) $(call log.base.part2,${yellow}false${no_ansi_dim} - dispatching ${dim_cyan}$${_else}); ${make} $${_else};; \
           esac ) )
    flux.if.then.else/%:
      '''
      Standard if/then/else control flow for make targets.  Thin wrapper over the
      `flux.if.then.else` macro (also `cmk.flux.if.then.else(..)`).

      USAGE:
        ./compose.mk flux.if.then.else/<test_target>,<then_target>,<else_target>
      '''
      $(call flux.if.then.else,${*})

    flux.indent/%:; ${make} flux.indent.sh cmd="${make} ${*}"
      '''Run the given target, indenting both its stdout and stderr.  See also `stream.indent`.  USAGE: `flux.indent/<target>`'''
    flux.indent.sh:; $${cmd}  1> >(sed 's/^/  /') 2> >(sed 's/^/  /')
      '''Like `flux.indent`, but for any shell command in the `cmd` env-var.'''

    flux.loop/%:
      '''
      Repeatedly run the named target a given number of times.  Requires `pv` for the progress
      bar (bundled in the k8s-tools containers); target stdout is suppressed (it corrupts the
      bar) while stderr is left alone.  NB: only "flat" targets with no `/` in the name.

      USAGE:
        ./compose.mk flux.loop/<times>/<target>
      '''
      times=$(call m5.__args__,1,/) \
      && target=$(call m5.__args__,2-,/) \
      && cmk.log.flux(flux.loop${no_ansi_dim} ${sep} ${green}$${target}${no_ansi} ($${times}x)) \
      && (for i in `seq $${times}`; do ${make} $${target} > ${devnull}; echo $${i}; done) \
        | eval `which pv||echo cat` > ${devnull}

    flux.loop.until/%:
      '''
      Loop the given target until it succeeds.  stderr is suppressed by default (set `verbose=1`
      to keep it); reports the elapsed time once the target passes.
      '''
      header="${GLYPH_FLUX} flux.loop.until${no_ansi_dim} ${sep} ${green}${*}${no_ansi}" \
      && start_time=${io.time.ns} \
      && cmk.log.base($${header} (until success)) \
      && ${make} ${*} 2>/dev/null || (sleep $${interval:-1}; ${make} flux.loop.until/${*}) \
      && end_time=${io.time.ns} \
      && time_diff_ns=$$((end_time - start_time)) \
      && delta=$$(awk -v ns="$$time_diff_ns" 'BEGIN {printf "%.9f", ns / 1000000000}') \
      && cmk.log.base($${header} ${no_ansi_dim}(succeeded after ${no_ansi}${yellow}$${delta}s${no_ansi_dim}))

    flux.loop.watch/%: assert.tool.required/watch
      '''Loop the given target forever via `watch` (requires `watch` on the host).'''
      watch --interval $${interval:-2} --color ${make} ${*}
    flux.loopf/%:; verbose=1 ${make} flux.loopf.quiet/${*}
      '''Loop the given target forever (verbose).'''
    flux.loopf.quiet/%:
      '''
      Loop the given target forever.  To reduce noise, stderr goes to null but stdout is preserved;
      set `verbose=1` to keep stderr, or `quiet=1` to trim even more logging.
      '''
      header="flux.loopf${no_ansi_dim}" \
      && header+=" ${sep} ${green}${*}${no_ansi}" \
      && interval=$${interval:-1} \
      && ([ -z "$${quiet:-}" ] \
        && tmp="`\
          [ -z "$${clear:-}" ] \
          && true \
          || echo ", clearing screen between runs" \
           `" \
        && cmk.log.flux($${header} ${dim}( looping forever at ${yellow}$${interval}s${no_ansi_dim} interval$${tmp})) || true ) \
      && while true; do ( \
        ([ -z "$${verbose:-}" ] && ${make} ${*} 2>/dev/null || ${make} ${*} ) \
        || ([ -z "$${quiet:-}" ] && true || printf "$${header} ($${failure_msg:-failed})\n" > ${stderr}) \
        ; sleep $${interval} \
        ; ([ -z "$${clear:-}" ] && true || clear) \
      ) ;  done
    flux.loopf.quiet.quiet/%:; quiet=yes ${make} flux.loopf/${*}
      '''Like `flux.loopf`, but even more quiet.'''

    flux.progress/%:
      '''
      Observed serial iterator: read work items on stdin, run <target>/<item> for each.
      With progress=0 (the default) each item is narrated and its output flows through; any
      other value shows a determinate bar (via tux.progress) and, being serial, keeps just the
      last command output, replaying it on failure.  A requested bar is honored only on a
      controlling terminal (see tux.progress.terminal) and otherwise silently downgrades to
      narration -- so CI and piped runs stay clean.  Contrast the fire-and-forget `flux.loop`.
      '''
      _items <- cat
      _n <- printf '%s\n' "$${_items}" | grep -c . || true
      if [ "$${_n}" -eq 0 ]; then exit 0; fi
      if [ "$${progress:-0}" = 0 ] || ! { ${tux.progress.terminal} ; }; then \
        _i=0; \
        for _x in $${_items}; do \
          _i=$$(( _i + 1 )); \
          cmk.log.io(${dim}${*} ${sep}${dim_ital} $${_i} / $${_n} ${sep} $${_x}); \
          ${make} ${*}/$${_x} || exit 255; \
        done; \
      else \
        cmk.io.mktemp(); \
        set -o pipefail; \
        { _i=0; for _x in $${_items}; do \
            ${make} ${*}/$${_x} > $${tmpf} 2>&1 || { _rc=$$?; printf '{"index":%s,"total":%s,"output":"%s","status":"error"}\n' "$$(( _i + 1 ))" "$${_n}" "$${_x}"; exit $${_rc}; }; \
            _i=$$(( _i + 1 )); printf '{"index":%s,"total":%s,"output":"%s"}\n' "$${_i}" "$${_n}" "$${_x}"; \
          done; } | ${stream.progress} >${devnull}; \
        _rc=$$?; \
        if [ "$${_rc}" -ne 0 ]; then cmk.log.io(${red}${*} ${sep}${no_ansi} aborted ${sep} replaying failed output); cat $${tmpf} >&2; exit $${_rc}; fi; \
        cmk.log.io(${dim}${*} ${sep}${dim_green} ok ${sep} $${_n} items); \
      fi

    flux.each.dir/%:
      '''Map a directory onto a target: find files matching the glob env-var, then hand them to
      `flux.progress` (which renders the bar via tux.progress).  Stem is <target>/<dir>; honours
      the glob and progress env-vars (progress defaults to 1 here, so a directory run bars).'''
      _target <- printf "${*}" | cut -d/ -f1
      _dir <- printf "${*}" | cut -d/ -f2-
      find "$${_dir}" -type f -name "$${glob:-*}" | sort | progress="$${progress:-1}" ${make} flux.progress/$${_target}

    # The `@io.dirhandler(glob=.., progress=..)` decorator gives a single-file parametric target
    # optional directory support.  The delegator guards the optional positionals; the body, when
    # the stem is a directory, reads glob/progress by name and hands the fan-out to flux.each.dir.
    io.dirhandler=$(call io.dirhandler.body,$(m5[1]?) $(m5[2]?))
    io.dirhandler.body=if [ -d "${*}" ]; then _dh_full='${__target__}'; _dh_base="$${_dh_full%/${*}}"; glob='$(or $(strip $(call mk.kwargs.get, ${1}, glob)),*)' progress='$(or $(strip $(call mk.kwargs.get, ${1}, progress)),1)' ${make} flux.each.dir/$$_dh_base/${*}; exit $$?; fi

    flux.map/% flux.for.each/%:
      '''
      Like `flux.each`, but accepts the iterable as an argument instead of on stdin: apply the
      leading <target> once per remaining comma-arg.

      USAGE:
        ./compose.mk flux.map/flux.echo,hello,world
        ./compose.mk flux.for.each/flux.echo,hello,world
      '''
      ${io.mktemp}
      printf "cmk.mk.unpack.arg(2-)" | ${stream.comma.to.nl} \
        | xargs -I% echo "${make} cmk.mk.unpack.arg(1)/%" > $${tmpf}
      bash ${dash_x_maybe} $${tmpf}

    # flux.negate(<target>): status inversion, macro-first so cmk.flux.negate(..) runs inline.
    flux.negate=! ${make} $(m5.__nargs__)
    flux.negate/%:
      '''
      Negates the status for the given target.  Thin wrapper over the `flux.negate` macro
      (also `cmk.flux.negate(..)`).

      USAGE:
        ./compose.mk flux.negate/flux.fail
      '''
      $(call flux.negate,${*})

    flux.noop:
      '''
      No-op, mostly used for testing.  Similar to `flux.ok` but without logging.

      USAGE:
        ./compose.mk flux.noop
      '''
      exit 0

    flux.parallel/%:
      '''
      Jobserver parallelism over comma-listed targets, with the job count from the `jobs` env-var
      (default 2).  Thin alias of `flux.pool.bounded` (which takes the count as a leading positional
      arg) -- see there for the recursion-budget semantics and caveats (concurrency may affect more
      than the named top-level targets; not stream-safe).

      USAGE:
        ./compose.mk flux.parallel/t1,t2,t3          # jobs=2 (default)
        jobs=8 ./compose.mk flux.parallel/t1,t2,t3

      REFS:
        [1] https://www.gnu.org/software/make/manual/html_node/Parallel-Disable.html
        [2] https://www.gnu.org/software/make/manual/html_node/Parallel-Input.html
      '''
      ${trace_maybe} && ${make} flux.pool.bounded/$${jobs:-2},${*}

    flux.pipeline.quiet/%:; quiet=1 ${make} flux.pipeline/${*}
    flux.pipeline.verbose/%:; quiet=0 verbose=1 ${make} flux.pipeline/${*}

    flux.pool/%:; $(call flux.pool,${*})
      '''Bounded streaming worker-pool: run comma-listed targets with at most <size> concurrent xargs workers, fail-fast.  USAGE: `flux.pool/<size>,<t1>,<t2>`'''
    flux.pool.bounded/%:; $(call flux.pool.bounded,${*})
      '''Jobserver-bounded variant of `flux.pool` (runs under `make --jobs <n>`; bounds the global recursion budget, not <n> workers).  USAGE: `flux.pool.bounded/<n>,<t1>,<t2>`'''

    flux.reduce/%:
      '''
      Reduce over stdin lines, seeded by the first line (no initial value).  Implemented via
      `flux.fold`: seed `acc` from the head, fold the tail.  Fails on empty input.  See `flux.fold`
      for the reducer contract.

      USAGE:
        printf '3\n1\n4\n1\n5\n' | ./compose.mk flux.reduce/<reducer>
      '''
      ${io.mktemp}
      ${stream.stdin} > $${tmpf}
      ( [ -s $${tmpf} ] || ( cmk.log(${red}flux.reduce: empty input) ; exit 1 ) )
      tail -n +2 $${tmpf} | acc="`head -n1 $${tmpf}`" ${make} flux.fold/${*}

    flux.retry/%:
      '''
      Retries the given target a certain number of times.

      USAGE: default interval of FLUX_POLL_DELTA
        ./compose.mk flux.retry/<times>/<target>
      USAGE: explicit interval in seconds
        interval=3 ./compose.mk flux.retry/<times>/<target>
      '''
      times=$(call m5.__args__,1,/) \
      && target=$(call m5.__args__,2-,/) \
      && header="flux.retry ${sep} ${dim_cyan}${underline}$${target}${no_ansi} (${yellow}$${times}x${no_ansi}) ${sep}" \
      && cmk.log.flux($${header}  ${dim_green}starting..) \
      && interval=$${interval:-${FLUX_POLL_DELTA}} \
      && $(call flux.retry, ${make} $${target}, $${times})

    flux.star/% flux.match/%:
      '''
      Run every target in the local namespace matching the given pattern.

      USAGE: (run all the test targets)
        make -f project.mk flux.star/test.
      '''
      matches="`${make} mk.namespace.filter/${*} | ${stream.nl.to.space}`" \
      && count=`printf "$${matches}" | ${stream.count.words}` \
      && cmk.log(${bold}$${count}${no_ansi_dim} matches for pattern ${dim_cyan}${*}) \
      && printf "$${matches}" | ${stream.fold} | sed 's/ /, /g' | ${stream.as.log} \
      && printf "$${matches}" | ${make} flux.each/flux.apply

    flux.starmap/%:
      '''
      Based on `itertools.starmap` from python: accepts two targets, the "function" and the
      "iterable".  The iterable is nullary and the function is unary; the function target is
      called once per result of the iterable, which must emit newline-separated data (usually
      one word per line).

      USAGE:
        ./compose.mk flux.starmap/<fn>,<iterable>
      '''
      target="cmk.mk.unpack.arg(1)" \
      && iterable="cmk.mk.unpack.arg(2-)" \
      && ${make} $${iterable} | ${make} flux.each/$${target}

    flux.stream.obliviate/%:; $(call _sh, ${make} ${*})
      '''Run the given target, consigning all output (stdout and stderr) to oblivion.'''

    flux.try.finally/%:
      '''
      A try/finally with the named targets: `flux.try.except.finally` with `except` = `flux.noop`.

      USAGE:
        ./compose.mk flux.try.finally/<try_target>,<finally_target>
      '''
      ${make} flux.try.except.finally/cmk.mk.unpack.arg(1),flux.noop,cmk.mk.unpack.arg(2)

    # flux.wrap(<t1>[:,]<t2>..): colon-or-comma AND -- normalize `:`->`,` then defer to the
    # `flux.and` macro, so cmk.flux.wrap(..) is inline too.
    flux.wrap=$(call flux.and,$(subst :,$(comma),$(m5.__nargs__)))
    flux.wrap/%:
      '''
      Same as `flux.and` except it accepts commas or colon-delimited args (use it to disambiguate
      targets that need to reserve `,`).  Thin wrapper over the `flux.wrap` macro (also
      `cmk.flux.wrap(..)`).  Performs an "and" over the named targets, equivalent to the default
      behaviour of `make t1 t2 .. tN`; mostly used as a wrapper in case targets are unary.
      '''
      $(call flux.wrap,${*})
  |]

  # io.* leaf targets ported from the seed, grouped in an ENCAPSULATION AMBIENT
  # (`*(| .. |)`, an inline anonymous module dissolved in place).  ALPHABETICAL.
  *(|
    io.awk/%:; ${stream.stdin} | awk -f <(${mk.def.read}/${*}) $${awk_args:-}
      '''
      Treat the given define-block name as an awk script, always run on stdin.  Silent, no args.
      Also available as a macro.  USAGE: io.awk/<def_name>
      '''
    io.bash:; bash
      '''Start an interactive shell with the same environment as this Makefile.'''
    io.browser/%:; url="`CMK_INTERNAL=1 this.mk.get/${*}`" this.io.browser
      '''
      Like the base browser target, but takes a variable name: it is dereferenced and stored as the
      url before chaining.  Requires python on the host; cannot run from a container.
      '''
    io.echo:; ${stream.stdin}
      '''Echo data from the input stream.'''
    io.env.log/%:; cmk.io.env.log(${*})
      '''Human-readable description of the given subset of environment variables.  Multiple inputs
      are comma-separated.'''
    io.force/%:; force=1 ${make} ${*}
      '''Context-manager: set force, then run the given target.'''
    io.gum.div:; label=$${label:-${io.timestamp}}; ${io.draw.banner}
      '''
      Draw a horizontal divider with gum.  If a label is not provided, it defaults to a timestamp.
      
      USAGE: label=".." ./compose.mk io.gum.div
      '''
    io.preview.img/%:; cat ${*} | ${stream.img} 
      '''
      Console-friendly image preview for the given file.
      
      USAGE: ./compose.mk io.preview.img/<path_to_img>
      '''
    io.preview.markdown/%:; cat ${*} | ${stream.markdown} 
      '''Console-friendly markdown preview for the given file.'''
    io.preview.pygmentize/%:; fname="${*}" this.stream.pygmentize
      '''
      Syntax highlighting for the given file.  The lexer is autodetected unless overridden; the
      style defaults to 'trac', which works best with dark backgrounds.
      
      USAGE:
        ./compose.mk io.preview.pygmentize/<fname>
        lexer=.. ./compose.mk io.preview.pygmentize/<fname>
        lexer=.. style=.. ./compose.mk io.preview.pygmentize/<fname>
      
      REFS: https://pygments.org/
      '''
    io.env.json/%:
      '''Like `io.env/<prefix>` but returns JSON.'''
      env="`${make} io.env/${*} | ${stream.nl.to.space}`" && ${jb} $${env}
    io.figlet:
      '''Pull `label` from the env and render it with figlet.  Also a macro; needs the embedded tui built.'''
      ${io.figlet}
    io.figlet/%:
      '''Render the argument as a label with figlet.  Needs the embedded tui built.'''
      label="${*}"; ${io.figlet}
    io.selector/%:
      '''Use the given targets to generate then handle choices.  1st arg nullary, 2nd unary.'''
      cmk.io.selector($(m5.__args__.first),$(call m5.__args__.cut,2-))
    io.preview.file/%:
      '''
      Output syntax-highlighting + line-numbers for the given filename to stderr.
      USAGE: ./compose.mk io.preview.file/<fname>
      '''
      cmk.log.io(io.preview.file ${sep} ${dim}${bold}${*}) \
      && style=monokai ${make} io.preview.pygmentize/${*} \
      | ${stream.nl.enum} | ${stream.indent.to.stderr}
    io.quiet.stderr/%:
      '''Run the given target, suppressing stderr except on error.  USAGE: io.quiet.stderr/<target>'''
      cmd="${make} ${*}" ${make} io.quiet.stderr.sh
      true && header="${GLYPH_IO} io.quiet.stderr ${sep}" \
      && $(call log.base,  $${header} ${green}$${*})
    io.shell:
      '''Start an interactive shell with the parent environment plus this Makefile's context.'''
      cmk.log.io(${@} ${sep} ${ital}${bold}Interactive)
      cmk.log.io(${@} ${sep} ${dim}${GLYPH_CHECK}.. environment will match make-context)
      bash -i </dev/tty >/dev/tty 2>&1
    io.tail/%:; $(trace_maybe) && touch ${*} && tail -f ${*} 2>/dev/null
      '''
      Tail the named file; blocking.  Creates the file first if necessary.
      
      USAGE: ./compose.mk io.tail/<fname>
      '''
    io.browser:
      '''Open the URL in the `url` env-var in a browser.  Host-only (needs python; not from docker).'''
      cmk.log(${red}opening $${url})
      python3 -c"import webbrowser; webbrowser.open(\"$${url}\")" \
        || cmk.log.error(browser failed to open or was killed)
    io.gum.spin:
      '''Run `gum spin` with the `cmd`/`label`/`spinner`/`color` env-vars (charmbracelet gum).'''
      ${trace_maybe} \
      && ${io.gum.docker} spin \
        --spinner $${spinner:-meter} \
        --spinner.foreground $${color:-39} \
        --title "$${label:-?}" -- $${cmd:-sleep 2};
    io.user_exit:
      '''Wait for user input (enter), then exit cleanly via `mk.super.exit` (honors CMK_POST).'''
      cmk.log.io(${@} ${sep} $${label:-Waiting for user input} ${sep} ${yellow} Press enter to exit...)
      read -p "" _ignored \
      ; CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${make} mk.super.exit/0
    io.with.file/%:
      '''
      Context manager: write the named define-block to a temp-file, then run the given
      unary target with that file as its argument.  USAGE: `io.with.file/<def>/<target>`
      '''
      cmk.io.mktemp() && def_name=$(call m5.__args__,1,/) \
      && target=$(call m5.__args__,2-,/) \
      && ${mk.def.read}/$${def_name} > $${tmpf} \
      && CMK_INTERNAL=1 ${make} $${target}/$${tmpf}
    io.with.color/%:
      '''
      Context manager: paint the given target's (stderr) output in the given color.
      USAGE (banner in red): `io.with.color/red,io.figlet/banner`
      '''
      color="$(m5.__args__.first)" \
      && target=$(call m5.__args__.cut,2-) \
      && cmk.io.mktemp() && ${make} $${target} 2>$${tmpf} \
      && printf "$(value $(m5.__args__.first))`cat $${tmpf}`${no_ansi}\n" >/dev/stderr
    io.stack/%:; cmk.io.stack(${*})
      '''Return all data in the named stack-file.  USAGE: `io.stack/<fname>`'''
    io.stack.reset/%:; @cmk.io.stack.reset(${*})
      '''(Re)initialize the named stack-file to empty.'''
    io.stack.count/%:; @cmk.io.stack.count(${*})
      '''Number of items in the named stack-file.  USAGE: `io.stack.count/<fname>`'''
    io.stack.get/%:
      '''Read-only jq query of the named stack-file (program on stdin, or `.`); emits compact JSON.'''
      jqp=`${stream.stdin.maybe}` ; cmk.io.stack.get.run(${*})
    io.stack.push_word/%:; printf '%s' "${*}" | ${io.stack.push_word}
      '''Push the (raw, literal) stem as a word onto the default stack.'''
  |)

  *(|
    cmk.class cmk.Actor(bases=Loggable)[|
      '''
      Actor: identity (a socket address) plus an opaque mainloop that moves
      bytes and never reads them.  The base transport is inproc; a subclass
      leaves the process by overriding the verbs, and the mailbox and store
      belong to the agent layer mixed in at the leaf.  A stop verb runs at
      exit, so a subclass releases its resources by overriding stop, not by
      re-registering teardown.  Its logger is the Loggable mixin, specialized
      here to tag the line with an actor prefix; each verb's own docstring
      gives its contract.
      '''
      ${self}.get_sock.__call__ = echo .tmp.actor.${self}.sock
      self.log.__call__ = cmk.log(${dim}actor:self ${sep} ${__args__})
      ${self}.__minted__ = $(call __cmk_post__.append,${self}.stop)

      self.deliver: self.recv
        '''
        Transmits one framed message.
        (Without a truly concurrent actor, this hands directly to recv)
        '''

      self.serve:
        '''
        Runs the receive loop; the inproc base has none
        '''
        ${self}.log(inproc ${sep} no serve loop)

      self.stop:
        '''
        Teardown at exit: __minted__ registers this, so a subclass that
        overrides deliver/serve gets its cleanup called just by overriding
        this verb (no separate registration).  The inproc base frees its
        socket handle; idempotent, so a manual mid-run call stays safe.
        '''
        cmk.io.safe_rm(.tmp.actor.${self}.sock)

      ${self}: ${self}.deliver
        '''
        A bare poke transmits stdin as one message.
        '''
    |]
  |)

  *(|
    cmk.class channel(|
      '''
      An event channel: a newest-first JSON stack with an operator suite.  Mint one with
      `channel NAME(| ..seed.. |)`; it self-provisions the backing stack and its at-exit teardown.
      Operators (push, pop, dump, emit, filter, dispatch, and friends) live under the dot; the slash
      namespace holds the user's event handlers.  The block body seeds the initial stack; an optional
      at-exit op drains it before the auto-purge.
      '''
      # the block body is a raw seed payload (init JSON), read at mint -- not an
      # instance scope to apply.
      self.__raw_body__ := 1
      # backing store: a declared stack, its var namespaced (events__) so it can't
      # collide with the channel's own name.  __stackvar__ is the make var, __stack__
      # the file it points at.
      ${self}.__stackvar__ = events__${self}
      self.__stack__ = $($(self.__stackvar__))
      # provision once at mint: declare the stack (seeded from init_data / the body
      # def), then register at-exit hooks -- the at_exit op BEFORE the auto-purge so
      # the stack drains before it is dropped (CMK_POST runs in append order).
      ${self}.__minted__ = $(eval $(call io.stack!,$(${self}.__stackvar__) $(if $(or $(call mk.kwargs.get,${__args__},init_data),$(call mk.kwargs.get,${__args__},def)),init_data=$(or $(call mk.kwargs.get,${__args__},init_data),$(call mk.kwargs.get,${__args__},def)))))$(if $(call mk.kwargs.get,${__args__},at_exit),$(eval $(call __cmk_post__.append,${self}.$(call mk.kwargs.get,${__args__},at_exit))))$(if $(findstring match=,${__args__}),$(eval $(call mk.unpack.kwargs,${__args__},match))$(eval kwargs_match := $(subst ${lang.comp.kwargs.sp},${space},$(kwargs_match)))$(eval ${self}._QUERIES += $(or $(call mk.kwargs.get,$(kwargs_match),test),field_equal):$(call mk.kwargs.get,$(kwargs_match),key):$(call mk.kwargs.get,$(kwargs_match),value)))$(eval $(call __cmk_post__.append,${self}.purge))
      self.push = $(call io.stack.push,$(self.__stack__))
      self.push:; cmk.log.trace(${@}) ; $(self.push)
      self.pop:; cmk.log.trace(${@}) ; cmk.io.stack.pop($(self.__stack__))
      self.count:; cmk.log.trace(${@}) ; cmk.io.stack.count($(self.__stack__))
      self.dump:; cmk.log.trace(${@}) ; _dn=`cmk.io.stack.count($(self.__stack__))` ; cmk.log.io(self ${sep} $${_dn} records${comma} arrival order) ; cmk.io.stack($(self.__stack__)) | ${jq.run} -c '.[]'
      ${self}.filter.field_equal/%:; cmk.log.trace(${@}) ; $(call bind.posargs) && cmk.io.stack($(${self}.__stack__)) | ${jq.run} -c --arg f "$${_1st}" --arg v "$${_2nd}" 'reverse[] | select((.[$$f]|tostring)==$$v)'
      ${self}.first.match.field_equal/%:; cmk.log.trace(${@}) ; $(call bind.posargs) && cmk.io.stack($(${self}.__stack__)) | ${jq.run} -c --arg f "$${_1st}" --arg v "$${_2nd}" 'first(reverse[] | select((.[$$f]|tostring)==$$v)) // empty'
      self.filter:; cmk.log.trace(${@}) ; jqp=`${stream.stdin.maybe}` ; cmk.io.stack.get.run($(self.__stack__))
      self.filter/%:
      	cmk.log.trace(${@}) ; $(call bind.posargs) \
      	&& if [ "$${_1st}" = jqlang ]; then jqp=`${mk.def.read}/$${_2nd}` ; \
      	elif [ -n "$${_1st}" ]; then jqp="map(select((.$${_1st}|tostring)==\"$${_2nd}\"))" ; \
      	else jqp=. ; fi \
      	&& cmk.io.stack.get.run($(self.__stack__))
      ${self}.filter.jq/% ${self}.jq/%:; cmk.log.trace(${@}) ; jqp=`${mk.def.read}/${*}` ; cmk.io.stack.get.run($(${self}.__stack__))
      ${self}.update ${self}.filter.in_place:; cmk.log.trace(${@}) ; jqp=`${stream.stdin.maybe}` ; cmk.io.stack.update.run($(${self}.__stack__))
      self.filter.in_place/% self.update/%:
      	cmk.log.trace(${@}) ; $(call bind.posargs) \
      	&& if [ "$${_1st}" = jqlang ]; then jqp=`${mk.def.read}/$${_2nd}` ; \
      	elif [ -n "$${_1st}" ]; then jqp="map(select((.$${_1st}|tostring)==\"$${_2nd}\"))" ; \
      	else jqp=. ; fi \
      	&& cmk.io.stack.update.run($(self.__stack__))
      self.emit = $(if $(strip $(if $(filter-out undefined,$(origin 1)),$(1))),${jb.run} $(m5[1]),${jb.run} `${stream.stdin.maybe}`) | $(self.push)
      self.emit:; $(call ${self}.emit, `${stream.stdin.maybe}`)
      ${self}.emit.type/%:; cmk.log.trace(${@}) ; $(call ${self}.emit, type=${*} `${stream.stdin.maybe}`)
      self.dispatch.drain/%:
      	cmk.log(${*})
      	while obj=`cmk.io.stack.pop($(${self}.__stack__))` \
      	&& [ -n "$${obj}" ] && [ "$${obj}" != null ]; do \
      	t=`echo "$${obj}" | ${jq.run} -r .$(strip ${*})` ; \
      	echo "$${obj}" | ${jq.run} . | ${stream.as.log} ; \
      	CMK_EVENT="$${obj}" ${make} "${self}/$${t}" </dev/null || true ; \
      	done
      self.dispatch.by_type: self.dispatch.drain/type
      self.drain: self.dispatch.by_type
      self.initialize = $(eval $(self.__stackvar__)._INIT_DEF := $(call mk.kwargs.get,$(1),def))
      self.initialize:; cmk.log.trace(${@}) ; cmk.io.stack.initialize($(self.__stack__),$($(self.__stackvar__)._INIT_DEF))
      self._QUERIES ?=
      self.match = $(eval self._QUERIES += $(or $(call mk.kwargs.get,$(1),test),field_equal):$(call mk.kwargs.get,$(1),key):$(call mk.kwargs.get,$(1),value))
      self.match:
      	cmk.log.trace(${@})
      	for q in $(${self}._QUERIES); do \
      	t=`echo "$${q}" | cut -d: -f1` ; \
      	k=`echo "$${q}" | cut -d: -f2` ; \
      	v=`echo "$${q}" | cut -d: -f3` ; \
      	${make} ${self}.filter.$${t}/$${k},$${v} | ${make} ${self}.match/$${v} ; \
      	done
      self.purge:; cmk.log.trace(${@}) ; cmk.io.safe_rm($(self.__stack__)) ; rm -f -- $(self.__stack__).tmp.* 2>/dev/null || true
    |)
  |)

  # docker.* leaf targets ported from the seed (no parse-time refs).  ALPHABETICAL.
  docker.context:; docker context inspect
  	'''Returns all available docker context; JSON output, pipe-friendly.'''
  docker.image.sizes:; ${make} docker.size.summary | ${jq.column.zipper}
  	'''Shows disk-size summaries for all images; returns JSON mapping each image to a human-friendly size.'''
  docker.network.connect/%:; cmk.bind.posargs() && ${trace_maybe} && docker network connect $${_1st} $${_2nd}
  	'''Connect a container to networks.  USAGE: ./compose.mk docker.network.connect/net1,net2'''
  docker.network.panic:; docker network prune -f
  	'''Prune all unused docker networks for the entire system.'''
  docker.ps:; docker ps --format json | ${jq} .
  	'''Like 'docker ps', but always returns JSON.'''
  docker.rmi/%:; img=${*} this.docker.rmi
  	'''Shortcut to remove an image.  USAGE: ./compose.mk docker.rmi/<image>'''
  docker.socket:; ${make} docker.context/current | ${jq.run} -r .Endpoints.docker.Host
  	'''Returns the docker socket in use for the current docker context.  No arguments; pipe-friendly.'''
  docker.start:; ${make} docker.start/$${img}
  	'''Run the image with its default entrypoint.  USAGE: img=.. ./compose.mk docker.start'''
  docker.start.tty:; tty=1 ${make} docker.start
  	'''Run the image with a TTY allocated (tty=1).'''
  docker.start.tty/%:; tty=1 ${make} docker.start/${*}
  	'''Run the named image with a TTY allocated.  USAGE: ./compose.mk docker.start.tty/<img>'''
  docker.volume.prune:; set -x && docker volume prune -f
  	'''Prune all unused docker volumes for the entire system.'''

  cmk.Dockerfile makeself(|
    FROM debian:bookworm
    RUN apt-get update && apt-get install -y bash make makeself
  |)
  mk.self: makeself.build
    '''
    A dockerized interface to the `makeself` tool: build self-extracting executables.
    All arguments are passed as environment variables:
      archive  a space-separated list of files/dirs to bundle
      script   the script that runs inside the archive
      bin      the name of the executable to create
      label    optional; shown at runtime after rehydration, before the script runs
    USAGE: archive=<dir> label=<label> bin=<name> script="pwd; ls" ./compose.mk mk.self
    REFS: makeself, at https://makeself.io
    '''
    header="${@}${no_ansi} ${sep}${dim}" \
    && cmk.log.io($${header} Archive for ${no_ansi}${ital}$${archive}${no_ansi_dim} will be released as ${no_ansi}${bold}./$${bin}) \
    && (ls $${archive} >/dev/null || exit 1) \
    && cmk.io.mktempd() \
    && cp -rf $${archive} $${tmpd} \
    ; archive_dir=$${tmpd} \
    && file_count=`find $${archive_dir}|${stream.count.lines}` \
    && cmk.log.io($${header} Total files: ${no_ansi}$${file_count}) \
    && cmk.log.io($${header} Entrypoint: ${no_ansi}$${script}) \
    && cmd="--noprogress --quiet --nomd5 --nox11 --notemp $${archive_dir} $${bin} \"$${label:-archive}\" $${script} $${script_args:-}" \
    img=compose.mk:makeself entrypoint=makeself ${make} docker.run.sh
    sed -i.bak -e 's/quiet="n"/quiet="y"/' $${bin} && rm -f $${bin}.bak

  cmk.Dockerfile pygmentize(|
    FROM ${IMG_ALPINE_BASE:-alpine:3.21.2}
    RUN apk add -q --update py3-pygments
  |)
  stream.pygmentize=CMK_INTERNAL=1 ${make} stream.pygmentize
  stream.pygmentize: pygmentize.build
    '''
    Syntax highlighting for the input stream.  The lexer is autodetected unless
    overridden; the style defaults to 'monokai', which works best with dark
    backgrounds.  Also available as a macro.
    USAGE: ( using the JSON lexer )
      echo {} | lexer=json ./compose.mk stream.pygmentize
    REFS: https://pygments.org/ ; https://pygments.org/styles/
    '''
    lexer=`[ -z $${lexer:-} ] && echo '-g' || echo -l $${lexer}` \
    && style="-Ostyle=$${style:-monokai}" \
    && src="entrypoint=pygmentize" \
    && src="$${src} cmd=\"$${style} $${lexer} -f terminal256 $${fname:-}\"" \
    && src="$${src} img=compose.mk:pygmentize ${make} docker.run.sh" \
    && ([ -p ${stdin} ] && ${stream.stdin} | eval $${src} || eval $${src}) >/dev/stderr

  # code.compiled: the language-agnostic compiled-code skeleton (the Go and Rust
  # shims delegate here); dissolved in place as an encapsulation ambient.
  *(|
    # cache: one dir per source-hash; GC prunes to the newest N dirs.
    _CMK_COMPILE_CACHE_KEEP?=10

    # _code.compiled.* helpers: source defs, cache path, name, memo key.
    _code.compiled.srcdef=$(or $(call mk.kwargs.get,${1},$(strip ${2})),$(if $(call m5.defined?,$(call mk.kwargs.get,${1},lang).default.$(strip ${2})),$(call mk.kwargs.get,${1},lang).default.$(strip ${2})))
    _code.compiled.defs=$(foreach _p,$($(call mk.kwargs.get,${1},lang).srcmap),$(call _code.compiled.srcdef,${1},$(word 1,$(subst :,${space},${_p}))))
    _code.compiled.bin=${CMK_XDG_CACHE}/$(firstword $(shell printf '%s' '$(subst ','\'',$(foreach _d,${1},$(value $(strip ${_d}))))' | cksum))/$(strip ${2})
    _code.compiled.name=$(or $(call mk.kwargs.get,${1},name),$(call mk.kwargs.get,${1},src),bin)
    _code.compiled.memo=$(call mk.kwargs.get,${1},lang).$(call _code.compiled.name,${1})
    _code.compiled.bin.get=$(if $(call m5.defined?,_cce.bin.$(call _code.compiled.memo,${1})),,$(eval _cce.bin.$(call _code.compiled.memo,${1}) := $(call _code.compiled.bin,$(call _code.compiled.defs,${1}),$(call _code.compiled.name,${1}))))$(_cce.bin.$(call _code.compiled.memo,${1}))
    _code.compiled.materialize=$(foreach _p,$($(call mk.kwargs.get,${1},lang).srcmap),&& mkdir -p "$$dir/$$(dirname $(word 2,$(subst :,${space},${_p})))" && ${mk.def.to.file}/$(call _code.compiled.srcdef,${1},$(word 1,$(subst :,${space},${_p}))),$$dir/$(word 2,$(subst :,${space},${_p})))
    _code.compiled.dockerargs=-w /build -e HOST_UID=`id -u` -e HOST_GID=`id -g` -e OUT=$(call _code.compiled.name,${1}) -v $$dir:/build $($(call mk.kwargs.get,${1},lang).env) $($(call mk.kwargs.get,${1},lang).mounts)

    # materialize + cross-build in the toolchain.
    _code.compiled.build(|
      $(eval _ccb_lang := $(call mk.kwargs.get,${1},lang)) \
      $(eval _ccb_base := $(or $(call mk.kwargs.get,${1},base),$(${_ccb_lang}.base))) \
      bin="$(call _code.compiled.bin.get,${1})" ; dir=`dirname "$$bin"` ; _t0=`date +%s 2>/dev/null || echo 0` \
      && mkdir -p "$$dir" \
      $(call _code.compiled.materialize,${1}) \
      && ${mk.def.to.file}/$(${_ccb_lang}.buildsh),$$dir/build.sh \
      && { docker image inspect ${_ccb_base} >/dev/null 2>&1 \
           || { $(call log.io, ${dim}${_ccb_lang} ${sep} pulling ${no_ansi}${_ccb_base}${dim} (one-time)${no_ansi}) ; docker pull ${_ccb_base} 2>&1 | cat ; } } \
      && entrypoint=sh img=${_ccb_base} cmd=/build/build.sh docker_args="$(call _code.compiled.dockerargs,${1})" ${make} docker.run.sh \
      && $(call log.io, ${dim}${_ccb_lang} ${sep} built ${no_ansi}$$bin${dim} in $$(( `date +%s 2>/dev/null || echo 0` - $${_t0:-0} ))s${no_ansi})
    |)

    # set bin, then probe/build once per process.
    code.compiled.ensure(|
      $(eval _cce := $(call _code.compiled.memo,${1})) \
      bin="$(call _code.compiled.bin.get,${1})" ; \
      $(if $(call m5.defined?,_cce.done.${_cce}),:,$(eval _cce.done.${_cce} := 1) \
          $(call log.io.part1, $(call mk.kwargs.get,${1},lang) ${sep} ${dim}checking for cache) ; \
          if [ -x "$$bin" ]; then \
              $(call log.io.part2, ${dim}$(patsubst $(HOME)%,~%,${_cce.bin.${_cce}}) ${green}${GLYPH_CHECK}${no_ansi}) ; \
          else \
              $(call log.io.part2, ${yellow}not found${no_ansi}) ; \
              $(call _code.compiled.build,${1}) && ${make} code.compiled.cache.gc ; \
          fi)
    |)

    # build-if-needed then exec; args is comma-argv (a darwin host runs a linux-only binary inside the lang's image).
    code.compiled.lambda(|
      $(call code.compiled.ensure, ${1}) \
      && $(if ${OS_MACOS},if [ "`head -c 4 "$${bin}" | tail -c 3`" = "ELF" ]; then d=`dirname "$${bin}"` ; quiet=1 img=$($(call mk.kwargs.get,${1},lang).base) entrypoint="/cmk-bin/`basename "$${bin}"`" cmd="$(subst ${comma},${space},$(or $(call mk.kwargs.get,${1},args),${space}))" docker_args="-v $$d:/cmk-bin:ro" ${make} docker.run.sh ; else exec "$${bin}" $(subst ${comma},${space},$(or $(call mk.kwargs.get,${1},args),${space})) ; fi,exec "$${bin}" $(subst ${comma},${space},$(or $(call mk.kwargs.get,${1},args),${space})))
    |)

    code.compiled.cache.gc:
      '''Prune the cache to the newest _CMK_COMPILE_CACHE_KEEP entries.'''
      ( keep=$${_CMK_COMPILE_CACHE_KEEP:-10} ; case "$$keep" in ''|*[!0-9]*) keep=10 ;; esac ; \
        cd "${CMK_XDG_CACHE}" 2>/dev/null || exit 0 ; \
        old=$$(ls -1dt */ 2>/dev/null | sed 's:/$$::' | while IFS= read -r d; do case "$$d" in ''|*[!0-9]*) continue ;; *) echo "$$d" ;; esac ; done | awk -v k="$$keep" 'NR>k') ; \
        [ -n "$$old" ] || exit 0 ; \
        ${io.mktempd} && mkdir -p "$$tmpd" ; \
        printf '%s\n' "$$old" | while IFS= read -r d; do case "$$d" in ''|*[!0-9]*) ;; *) mv -- "./$$d" "$$tmpd/" ;; esac ; done ; \
        cmk.log.io(${dim}code.compiled ${sep} cache gc ${sep} pruned ${no_ansi}$$(printf '%s\n' "$$old" | grep -c .)${dim} old${no_ansi}) )
    code.compiled.cache.list:
      '''List cache entries (newest first) with size and the built binary.'''
      cd "${CMK_XDG_CACHE}" 2>/dev/null \
      && { \
        tot=0 ; \
        for d in $$(ls -1dt */ 2>/dev/null | sed 's:/$$::'); do \
          case "$$d" in ''|*[!0-9]*) continue ;; esac ; \
          sz=$$(du -sh "$$d" 2>/dev/null | cut -f1) ; \
          b=$$(ls -1 "$$d" 2>/dev/null | grep -v '[.]' | head -1) ; \
          printf '  %-12s %7s  %s\n' "$$d" "$$sz" "$$b" ; tot=$$((tot+1)) ; done ; \
        printf '  (%s cksum entries in %s)\n' "$$tot" "${CMK_XDG_CACHE}" ; } \
      || cmk.log.io(no cache at ${CMK_XDG_CACHE})
    code.compiled.cache.clean:
      '''Clear all cksum dirs (a full reset; leaves non-cksum dirs).'''
      cd "${CMK_XDG_CACHE}" 2>/dev/null \
      && { \
        ${io.mktempd} && mkdir -p "$$tmpd" ; \
        for d in $$(ls -1d */ 2>/dev/null | sed 's:/$$::'); do \
          case "$$d" in ''|*[!0-9]*) continue ;; *) mv -- "./$$d" "$$tmpd/" ;; esac ; \
        done ; \
        cmk.log.io(${green}code.compiled cache cleared${no_ansi}) ; \
      } || true
    # code.compiled.fmt: format stdin via the lang formatter (or error).
    code.compiled.fmt:
      '''Stream stdin through the lang toolchain formatter (errors if none).'''
      $(if $(and $(call m5.defined?,$(lang).fmtentry),$($(lang).fmtentry)),,$(call mk.error, cmk: no formatter (fmtentry) for '$(lang)', errno=NO_FORMATTER))quiet=1 img=$($(lang).base) entrypoint=$($(lang).fmtentry) ${make} docker.run.sh

    # base compiled-code kind; a subclass fixes one language.
    cmk.class code.compiled(|
      self.__raw_body__ := 1
      self.__args__ = src=self lang=$(self.__class__) $(filter-out def=% src=% namespace=% bases=%,${1})
      self.lambda = $(call code.compiled.lambda, $(self.__args__))
      self.__call__ = $(call code.compiled.lambda, $(self.__args__) ${__args__})
      self:; ${self.lambda}
      self/%:; $(call code.compiled.lambda, $(self.__args__) args=${*})
      self.fmt:
        ${mk.def.read}/$(call _code.compiled.srcdef,$(${self}.__args__),src) \
        | lang=$(self.__class__) ${make} code.compiled.fmt
    |)
  |)

  # lang.parser + Language: structural reflection (exploding ambient).
  *(|
    IMG_COMBY?=comby/comby:alpine-3.14-1.8.2
    lang.parser.cli=entrypoint=comby img=${IMG_COMBY} ${make} docker.run.sh 2>/dev/null
    lang.parser.flags=-matcher $${matcher:-.generic} -stdin
    lang.parser=$(call lang.parser.$(m5[1]),$(m5[2]?))
    # A grammar family (arg 2 of the parser call) selects the comby pattern per kind:
    # core ships the default `braces` family (Go/C/Rust); a dsl plugin registers its own
    # `lang.parser.pat.<kind>.<grammar>` and sets `__grammar__` to opt into it.
    lang.parser.grammar=$(or $(m5[1]?),braces)
    lang.parser.pat.symbols.braces=:[[name]](:[args]) :[ret~[^{}();\n]*]{:[body]}
    lang.parser.pat.blocks.braces={:[body]}
    lang.parser.symbols=cmd="'$(lang.parser.pat.symbols.$(lang.parser.grammar))' '' ${lang.parser.flags} -match-only -json-lines" ${lang.parser.cli} | ${jq} -r '.matches[]|[(.environment[]|select(.variable=="name")|.value),(.environment[]|select(.variable=="args")|.value)]|"\(.[0])(\(.[1]))"'
    lang.parser.blocks=cmd="'$(lang.parser.pat.blocks.$(lang.parser.grammar))' '' ${lang.parser.flags} -match-only -json-lines" ${lang.parser.cli} | ${jq} -r '.matches[].matched'
    lang.parser.tokens=cmd="'{:[body]}' ';' ${lang.parser.flags} -stdout" ${lang.parser.cli} | ${jq} -Rsr '[scan("[A-Za-z_][A-Za-z0-9_]*")]|unique|join(" ")'
    cmk.protocol Language(dunder=__symbols__ classvars='__lang__')[|
      '''Language: a dsl exposing symbols/blocks/tokens via comby.  __lang__ is the
         comby matcher (.go/.py); __grammar__ picks the pattern family (braces default).'''
      self.__grammar__ ?= braces
      self.__symbols__:
        cmk.lang.parser(symbols,$(self.__grammar__))[⬥self]{matcher=self.__lang__}
      self.__blocks__:
        cmk.lang.parser(blocks,$(self.__grammar__))[⬥self]{matcher=self.__lang__}
      self.__tokens__:
        cmk.lang.parser(tokens)[⬥self]{matcher=self.__lang__}
    |]
  |)
endef

# __hosted__.loaded: is the hosted cache loaded (in MAKEFILE_LIST)?
# Guards module.bind cold-miss; empty until load = defer.
__hosted__.loaded =$(strip $(filter ${HOSTED_CACHE},${MAKEFILE_LIST}))
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: partition.* :: The parametric staging engine
##
## A partition is a `define __<name>__` region authored in CMK-lang; the staging template
## lowers any such region to a content-addressed cache and binds it via make's makefile-remaking,
## so a plain include transparently gets its targets (cold: build and restart once; warm: a hash
## and an `-include`).  The region name is the only structural variable, so one template drives
## both the load-bearing `hosted` partition and the opt-in `sandbox` lab bench; running it against
## `sandbox` as well as `hosted` is what proves the mechanism parametric.  This zone also holds the
## built-in prewarm loader, which materializes the hosted cache once before the supervised makes run.
##
## Contents, top to bottom:
##
## * __sandbox__ :: The sandbox region.
##     A lab bench for the dedent/cook/docstring hazards, run through the real
##     transpile pipeline but depended on by nothing.
## * _CMK_HOSTED_BUILDING :: Re-entrancy guard so the cache-build sub-make skips this whole block
## * partition.stage :: The staging template.
##     Positional args: name, prefix, min-count, phony, failmsg;
##     `CMK_<PREFIX>_SRC` overrides the body as a per-test injection hook.
## * partition.*.failmsg :: The per-partition cold-build failure messages
## * HOSTED_SRC :: The file that carries the regions plus the transpiler
## * hosted instance :: Plus the whole-file `.PHONY` collision guard and core-namespace auto-help
## * sandbox instance :: The same template, gated off unless opted in
## * _cmk.prewarm.hosted :: The built-in loader that warms the hosted cache before the run
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Home for experimental forms before they earn a stable name; the early ones have all graduated to
# their stable homes.  No forms live here now; `__future__.help` keeps the namespace registered.
__future__.help: mk.namespace.filter/__future__.

# The SANDBOX partition: a parallel of `define __hosted__` above, keyed on `define __sandbox__`.
# Purpose: a lab bench for the recurring dedent/cook/docstring hazards.  Experimental CMK-lang
# content dropped in here is driven through the REAL transpile pipeline (so it reproduces hosted
# behavior exactly), but nothing depends on it and its build never touches normal operation --
# so an unstable experiment cannot halt bootstrap the way an unstable `__hosted__` does.  The
# staging (below, in the `ifndef _CMK_HOSTED_BUILDING` block) activates only when opted in.
define __sandbox__
  sandbox.selftest:
    '''
    The isolated twin of `hosted.selftest`: a trivial, non-docker proof target authored in the
    SANDBOX region.  Add experimental content around it to exercise the compiler off the
    load-bearing hosted partition.
    '''
    cmk.log(sandbox partition is live)
    echo ok
endef

# _CMK_HOSTED_BUILDING guards re-entrancy: the cache-build sub-make (below) re-parses
# compose.mk and would otherwise re-trigger the remaking rule -> infinite recursion.
# Each build recipe exports _CMK_HOSTED_BUILDING=1, so that sub-make skips this whole
# block.  (Internal only -- the leading `_` marks it private, not a user-facing knob.)
ifndef _CMK_HOSTED_BUILDING

# partition.stage: the parametric staging template (see the section doc-block).  Args (positional):
#   1 lower-case partition name   -> the `define __<1>__` marker, `.tmp.<1>.` cache, prewarm hook
#   2 UPPER prefix                -> the <2>_CACHE / <2>_HASH / CMK_<2>_SRC public symbols
#   3 minimum target count        -> a short/truncated (cold-fail) build is warned + never promoted
#   4 phony-manifest source (opt) -> when set, its shell value seeds a `.PHONY` line for the build
#   5 failure-message source      -> a macro name (indirected so its commas don't split the log call)
# The body source is a per-partition override CMK_<2>_SRC (empty default = extract from the file,
# balancing nested define/endef); it is the per-test injection hook and feeds both the hash
# (content-addressing each injection to its own cache) and the transpile verbatim.
# Two hard-won invariants live in the recipe, do not "simplify" them away:
#   - the hash folds in CMK_VERSION so a pure-seed edit that adds a new namespace root still busts
#     an upgrader's warm cache (the region alone would not change); guarded by test_phony_collisions.
#   - the build is concurrency-safe + validated: a PID-keyed scratch file lets racing cold builds
#     not corrupt each other, and only a temp with >= <3> targets is promoted onto the shared
#     .PRECIOUS cache (a short/truncated build is warned + dropped, never promoted -- what once
#     surfaced as a phantom `not a member`); guarded by test_hosted_cmk.
define partition.stage
$(m5[2])_CACHE_DIR ?= $${CMK_STAGE_DIR}
CMK_$(m5[2])_SRC ?=
partition.$(m5[1]).body = $$(if $${CMK_$(m5[2])_SRC},cat $${CMK_$(m5[2])_SRC},awk '/^define __$(m5[1])__$$$$/{f=1;d=0;next} f{ line=$$$$0; sub(/^  /,"",line); if(line ~ /^endef[ \t]*$$$$/){ if(d==0){f=0;next} d--; print line; next } if(line ~ /^define /)d++; print line }' $${HOSTED_SRC})
# one hash probe per run, not per boot: a child reuses the exported hash while the exported key still matches its own inputs, and any mismatch (container, assembled program, injection override) recomputes.
$(m5[2])_HASH :=
ifeq ($$(value _CMK_$(m5[2])_HASH_KEY),$${HOSTED_SRC}|$${CMK_$(m5[2])_SRC}|$${CMK_VERSION})
$(m5[2])_HASH := $$(_CMK_$(m5[2])_HASH)
endif
ifeq ($$($(m5[2])_HASH),)
$(m5[2])_HASH := $$(shell { echo "$${CMK_VERSION}"; $${partition.$(m5[1]).body}; } | cksum | awk '{printf "%07x",$$$$1%268435456}')
endif
export _CMK_$(m5[2])_HASH_KEY := $${HOSTED_SRC}|$${CMK_$(m5[2])_SRC}|$${CMK_VERSION}
export _CMK_$(m5[2])_HASH := $$($(m5[2])_HASH)
$(m5[2])_CACHE := $${$(m5[2])_CACHE_DIR}/.tmp.$(m5[1]).$${$(m5[2])_HASH}.mk
.PRECIOUS: $${$(m5[2])_CACHE}
ifneq ($$(__$(m5[1])__.enabled),0)
-include $${$(m5[2])_CACHE}
endif
$${$(m5[2])_CACHE}:
	@mkdir -p $${$(m5[2])_CACHE_DIR} \
	&& _mf="$${MAKE_FLAGS}" \
	&& case "$$$$_mf" in --*) ;; -*) _rest="$$$${_mf#"$$$${_mf%% *}"}" ; _w1=`printf %s "$$$${_mf%% *}" | tr -d n` ; [ "$$$$_w1" = - ] && _w1="" ; _mf="$$$$_w1$$$$_rest" ;; esac \
	&& _t=$${@}.$$$$$$$$.build \
	&& { $${partition.$(m5[1]).body} \
	     | CMK_INTERNAL=1 _CMK_HOSTED_BUILDING=1 MAKEFLAGS= $$(MAKE) $$$$_mf -f $${HOSTED_SRC} lang.transpile > $$$$_t$(if $(m5[4]), \
	     && printf '\n.PHONY: %s\n' "`$${$(m5[4])}`" >> $$$$_t) ; } ; \
	if [ -s "$$$$_t" ] && [ "$$$$(grep -cE '^[A-Za-z_][A-Za-z0-9._/%-]*:' $$$$_t)" -ge $(m5[3]) ]; then \
	  mv $$$$_t $${@} ; \
	else \
	  $$(call log.mk, $${yellow}$${$(strip $5)}$${no_ansi}) ; \
	  rm -f $$$$_t ; \
	fi
mk.$(m5[1]).prewarm: $${$(m5[2])_CACHE}
	@true
endef

# The two partition failure messages (macro-indirected so their commas don't split the log call).
partition.hosted.failmsg = hosted partition failed to compile ${sep} hosted-only targets will be missing. The cold compiler needs GNU awk (busybox awk is not enough). Install gawk or provide a prebuilt cache (see scratch/TODO-hosted-needs-gawk.md)
partition.sandbox.failmsg = sandbox partition failed to compile ${sep} sandbox-only targets will be missing (the cold compiler needs GNU awk)

# The file holding both the partition regions and the transpiler.  Normally compose.mk
# itself; when compose.mk is inlined into a stand-alone program the running makefile
# carries the copy, so fall back to the first entry of MAKEFILE_LIST.
HOSTED_SRC := $(or ${cmk.self},$(abspath $(firstword ${MAKEFILE_LIST})))

$(eval $(call partition.stage,hosted,HOSTED,5,_cmk.phony.bare,partition.hosted.failmsg))

# Bind __builtins__ bare at load (floor precedence: guest read last).
$(if $(filter 1,$(__hosted__.enabled)),$(call lang.module.bind,__builtins__,$(__builtins__.__all__)))

# Hosted-only whole-file bookkeeping (NOT partition mechanics): the `.PHONY` collision guard and
# the core-namespace auto-help.  compose.mk ships no .PHONY and runs under `-s`, so a client
# file/dir named like a bare target would silently shadow it; we phony only the bare (dotless)
# core heads.  `_cmk.phony.roots` (first-segment of every head) also feeds the auto-help below,
# which is gated on a `.help` goal so the enumeration shell runs only when help is requested.
_cmk.seed.heads = sed '/^define /,/^endef/d' ${HOSTED_SRC} | grep -oE '^[A-Za-z_][A-Za-z0-9._/%-]*:([^=]|$$)'
_cmk.hosted.heads = ${partition.hosted.body} | grep -oE '^[A-Za-z_][A-Za-z0-9._/%-]*:([^=]|$$)'
_cmk.phony.roots = { ${_cmk.seed.heads}; ${_cmk.hosted.heads}; } | sed -E 's/:.*//; s/[./%].*//' | sort -u | tr '\n' ' '
_cmk.phony.bare = ${__builtins__} | grep -vE '[./%]' | tr '\n' ' '
_cmk.help.auto.roots = for r in $$(${_cmk.phony.roots}); do case "$$r" in _*) continue;; esac; grep -qE "^$$r[.]help[ :]" ${CMK_SRC} || printf '%s ' "$$r"; done
$(if $(filter %.help,$(call m5|,MAKECMDGOALS,)),$(foreach _hr,$(shell ${_cmk.help.auto.roots}),$(call _mk.gen.help,${_hr})))

# The SANDBOX instance: the same template, gated OFF by default.  Active only when opted in
# (`CMK_SANDBOX` truthy, `CMK_SANDBOX_SRC` set, or a `sandbox.*`/`mk.sandbox.*` goal), so a normal
# build never parses or builds it and a broken experiment is recovered by not asking for it.
_cmk.sandbox.active := $(if $(filter-out 0 false no off,${CMK_SANDBOX}),1,)$(if ${CMK_SANDBOX_SRC},1,)$(if $(filter sandbox.% mk.sandbox.%,$(call m5|,MAKECMDGOALS,)),1,)
ifneq (,${_cmk.sandbox.active})
$(eval $(call partition.stage,sandbox,SANDBOX,1,,partition.sandbox.failmsg))
endif
endif

# _cmk.prewarm.hosted: a built-in loader that materializes the hosted partition cache once,
# before the supervised makes run, keeping make's cold makefile-remaking restart out of them
# (its own restart is swallowed).  The `mk.hosted.prewarm` target owns the build.  Fires at
# most once per run (only the top-level `./compose.mk` header runs it); opt out with
# CMK_HOSTED_PREWARM=0.
define _cmk.prewarm.hosted
_hosted_warm=""
if [ -z "${CMK_HOSTED_SRC:-}" ]; then
  for _hf in "${CMK_MODULES_DIR:-.cmk}"/.tmp.hosted.*.mk "${XDG_CACHE_HOME:-$HOME/.cache}/compose.mk"/.tmp.hosted.*.mk; do
    [ -s "${_hf}" ] && _hosted_warm=1 && break
  done
fi
case "${CMK_HOSTED_PREWARM:-1}" in 0|false|no|off) ;; *) [ -n "${_hosted_warm}" ] || CMK_INTERNAL=1 ${_make_} mk.hosted.prewarm 2>&1 >/dev/null | grep -a 'hosted partition failed to compile' >&2 || true ;; esac
endef
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: mk.interpret.* :: compose.mk as a makefile interpreter
##
## These targets turn compose.mk into a makefile interpreter, so a
## `.mk` or `.cmk` file can run itself via a `compose.mk` shebang and inherit not
## just the framework's targets but its signals and supervisor.  `mk.interpret`
## reads a makefile and re-execs it against compose.mk; `mk.interpret!` runs the
## CMK preprocessing/transpile step first; `mk.interpret/<file>` is the file-arg
## engine both dispatch to (it deduplicates the self-include, validates, and execs
## the assembled makefile).
##
## DOCS:
## * `[1]:` [Signals](https://robot-wranglers.github.io/compose.mk/signals/)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

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
	&& $(call _cmk.compile,$${fname}) \
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
	&& $(call log.mk,  ${dim}starting interpreter ${sep} ${dim}timestamp=${yellow}${io.timestamp}) \
	&& continuation="$${rest}" __interpreting__=$${__interpreting__:-$${fname}} ${make} mk.interpret/$${fname}
	$(call mk.yield, true)

# the interpret engine as a macro, so cli.cmk.run assembles and execs the program in-process instead of paying another boot; the target below remains the direct entrypoint.
define _mk.interpret.file
case $(1) in \
		-) fname=/dev/stdin ;;\
		*) fname="$(1)" ;; \
	esac \
	&& $(call log.trace, \
		__input__=$${fname} \
		__file__=${__file__} \
		__script__=${__script__} \
		__interpreter__=${__interpreter__} \
		__interpreting__="$${__interpreting__:-None}" ) \
	&& $(call io.mktemp) \
	&& $(call log.trace.compiler.part1, mk.interpret) \
	&& ( cat ${CMK_SRC} \
			| sed -e '$$d' \
			| awk '/^define __hosted__$$/{h=1;d=0;print;next} h{if(/^endef[ \t]*$$/){if(d==0)h=0;else d--;print;next} if(/^define /)d++; print;next} /^# /{next} {print}' \
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
	&& $(call log.trace.compiler.part2, ${dim}deduplicated includes from ${ital}$${fname}) \
	&& { [ -n "`cat $${tmpf} | ${lang.main.has.stream}`" ] || printf '%s\n' '$(lang.main.stub.error)' >> $${tmpf} ; } ; \
	( export CMK_INTERNAL=0 goals="$${continuation%% *}" ; $(call mk.validate,$${tmpf}) ) \
		|| { rc=$$? ; { [ -z "$${MAKE_SUPER}" ] || [ -s .tmp.mk.super.$${MAKE_SUPER} ] || echo $${rc} > .tmp.mk.super.$${MAKE_SUPER} ; } ; exit $${rc} ; } \
	; chmod +x $${tmpf} \
	&& $(call log.trace, ${dim_ital}$${continuation:-(no additional arguments passed)}) \
	&& export __interpreting__=$${__interpreting__:-$(1)} \
	&& { _sb= ; command -v stdbuf >/dev/null 2>&1 && _sb="stdbuf -o0 -e0" ; \
		__script__=${__script__} MAKEFILE=$${tmpf} $${_sb} $${tmpf} $${continuation:-} ; } ; rc=$$? \
	; { [ -z "$${MAKE_SUPER}" ] || [ $${rc} -eq 0 ] || echo $${rc} > .tmp.mk.super.$${MAKE_SUPER} ; } \
	; exit $${rc}
endef

mk.interpret/%:
	@# A version of `mk.interpret` that accepts file-args.
	@#
	@# USAGE: ./compose.mk mk.interpret/<fname>
	@#
	$(call _mk.interpret.file,${*})

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Fast, define-aware enumeration of a makefile's public target base-names -- the single source of truth
# behind the shell-completion helpers and the repl's local-target banner.  A pure single-pass POSIX-awk scan (no
# make re-exec, so cheap enough for tab-completion; runs under gawk/BSD-awk/busybox): skips `define..endef`
# bodies, matches `^<names>:` (rejecting `:=`/`::`/recipe/comment lines), splits multi-target lines, drops
# private (`.`/`_`) and `%` names.  Parametric `foo/%` collapses to base `foo` (`-v param=keep` emits
# `foo/%` for the repl's arg-hint); `-v emit=jsonl` switches to a shallow one-record-per-name JSON.
# Stays in seed (not hosted awklang): it powers `cmk` completion/help, which must run cold on
# busybox/make+bash -- hosting would need gawk to build the partition first, breaking that cold path.
# See scratch/TODO-hosted-needs-gawk.md.
#:phase RUN seed=0 awklang=yes
define .awk.completion.scan
  function jrep(s, fs, rep,   n, p, i, r) { n = split(s, p, fs); r = p[1]; for (i = 2; i <= n; i++) r = r rep p[i]; return r }
  function jesc(s) { s = jrep(s, "\\\\", "\\\\"); s = jrep(s, "\"", "\\\""); s = jrep(s, "\t", "\\t"); s = jrep(s, "\r", "\\r"); return "\"" s "\"" }
  # `define __hosted__` is the hosted partition -- real makefile targets, not the
  # embedded Dockerfile/awk/heredoc bodies the ind-skip exists to ignore.  Scan it.
  /^define[ \t]+__hosted__([ \t]|$)/ { ind=0; next }
  /^define[ \t]/      { ind=1; next }
  /^endef([ \t]|$)/   { ind=0; next }
  # A col-0 triple-quote is a module docstring (raw `.cmk`; it lowers to `define __doc__`,
  # which the compiled path already skips).  Skip the block so its prose -- lines that happen
  # to hold a colon -- is not misread as multi-target rules.  Toggled on the bare fence line.
  /^('''|""")[ \t]*$/ { tq=!tq; next }
  ind                 { next }
  tq                  { next }
  /^[ \t#]/           { next }
  {
    ci=index($0,":"); if (ci==0) next
    head=substr($0,1,ci-1); rest=substr($0,ci)
    if (rest ~ /^:[=:]/) next
    if (head !~ /^[A-Za-z0-9._%\/! -]+$/) next
    n=split(head,toks,/[ \t]+/)
    for (i=1;i<=n;i++){ t=toks[i]; if(t=="") continue
      if (emit=="jsonl") {
        printf "{\"name\":%s,\"file\":%s,\"lineno\":%d,\"header\":%s,\"prereqs\":\"\",\"docs\":\"\",\"type\":\"file\"}\n", jesc(t), jesc(FILENAME), FNR, jesc($0)
        continue }
      s=index(t,"/"); base=(s>0)?substr(t,1,s-1):t
      c=substr(base,1,1); if(c=="."||c=="_"||c=="-") continue
      if(index(base,"%")>0||base=="") continue
      out=(param=="keep")?t:base
      if(!(seen[out]++)) print out }
  }
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: native mk.parse :: The awk+jq Makefile-to-JSON engine (the `mkparse` seam)
##
## awk extracts scalar-only JSONL (docs joined by a 0x1f sentinel); jq reshapes,
## derives booleans, filters, and renders.  The shallow path reuses
## `.awk.completion.scan -v emit=jsonl` (one scanner for help + completion).
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
define _mkp.awk.jesc
function jrep(s, fs, rep,   n, p, i, r) {
  n = split(s, p, fs); r = p[1]
  for (i = 2; i <= n; i++) r = r rep p[i]
  return r }
function jesc(s) {
  s = jrep(s, "\\\\", "\\\\"); s = jrep(s, "\"", "\\\"")
  s = jrep(s, "\t", "\\t"); s = jrep(s, "\r", "\\r")
  s = jrep(s, SEP, "\\u001f")
  return "\"" s "\"" }
BEGIN{ SEP=sprintf("%c",31) }
endef

# full parse of `make -pRrq` output.  Paragraph mode (RS="", FS="\n") so $1 is the
# stanza header; both rule sections are scanned (`# Implicit Rules` = pattern
# targets, `# Files` = explicit).
define _mkp.awk.full
BEGIN{ RS=""; FS="\n"; Q=sprintf("%c",39) }
/(^|\n)# Implicit Rules(\n|$)/          { infiles=1; next }
/(^|\n)# Files(\n|$)/                   { infiles=1; next }
/(^|\n)# Finished Make data base/       { infiles=0; next }
!infiles { next }
{
  line1=$1
  ci=index(line1,":"); if(ci==0) next
  head=substr(line1,1,ci-1)
  if(substr(line1,ci+1,1)=="=" || substr(line1,ci+1,1)==":") next
  if(head !~ /^[A-Za-z0-9._%\/!][A-Za-z0-9._%\/! -]*$/) next
  prereqs=substr(line1,ci+1); gsub(/^[ \t]+/,"",prereqs); gsub(/[ \t]+$/,"",prereqs)
  file=""; lineno=0; typ="file"; docs=""; hasrecipe=0
  for(i=2;i<=NF;i++){ l=$i
    if(l ~ /^#  recipe to execute \(from /){
      hasrecipe=1
      if(match(l,/line [0-9]+/)){ ln=substr(l,RSTART); sub(/line /,"",ln); lineno=ln+0 }
      q1=index(l,Q); if(q1>0){ r=substr(l,q1+1); q2=index(r,Q); if(q2>0) file=substr(r,1,q2-1) }
      continue }
    if(l ~ /^#  Phony target/){ typ="phony"; continue }
    if(substr(l,1,3)=="\t@#"){ d=substr(l,4); sub(/^ /,"",d); docs=(docs==""?d:docs SEP d) }
  }
  if(!hasrecipe && prereqs=="" && typ!="phony") next
  n=split(head,toks,/[ \t]+/)
  for(i=1;i<=n;i++){ t=toks[i]; if(t=="") continue
    printf "{\"name\":%s,\"file\":%s,\"lineno\":%d,\"header\":%s,\"prereqs\":%s,\"docs\":%s,\"type\":%s}\n", jesc(t), jesc(file), lineno, jesc(line1), jesc(prereqs), jesc(docs), jesc(typ) }
}
endef

define _mkp.awk.cblocks
/^## BEGIN:/ {
  s=$0; sub(/^## BEGIN:[ \t]*/,"",s)
  ci=index(s,":")
  if(ci>0){ label=substr(s,1,ci-1); tail=substr(s,ci+1) } else { label=s; tail="" }
  gsub(/^[ \t]+|[ \t]+$/,"",label); gsub(/^[ \t]+|[ \t]+$/,"",tail)
  inblk=1
  if(tail!="") printf "{\"label\":%s,\"text\":%s}\n", jesc(label), jesc(tail)
  next }
/^## END:/ { inblk=0; next }
inblk && /^##/ {
  t=$0; sub(/^##[ ]?/,"",t)
  printf "{\"label\":%s,\"text\":%s}\n", jesc(label), jesc(t); next }
endef

# JSONL array -> object|names|markdown.  Flag args are "" when unset.  `private`
# is a leading `.` only (matches the container, keeps `_`).  alias/primary group
# a multi-target line (same file,lineno); primary = shortest name.
define _mkp.jq.targets
def bn: (. // "") | split("/") | last;
def arr($s): if ($s // "")=="" then [] else ($s|split("\u001f")) end;
map( . + {
  docs:    arr(.docs),
  prereqs: (if (.prereqs // "")=="" then [] else (.prereqs|split(" ")|map(select(length>0))) end),
  private: (.name|test("^[.]")),
  parametric: (.name|test("%")),
  local:   (((.file // "")|bn)==$localfile or ((.file // "")|test($hosted)))
})
| ( group_by([.file, .lineno])
    | map( if ((length > 1) and (.[0].file != "") and ((.[0].lineno // 0) != 0))
           then ( (sort_by([(.name|length), .name]) | .[0].name) as $prim
                  | map(.primary = $prim | .alias = (.name != $prim)) )
           else map(.primary = .name | .alias = false) end )
    | add )
| map(select( ($public=="")      or (.private|not) ))
| map(select( ($private=="")     or (.private) ))
| map(select( ($local=="")       or (.local) ))
| map(select( ($parametrics=="") or (.parametric) ))
| map(select( ($prefix=="")      or (.name|startswith($prefix)) ))
| map(select( ($target=="")      or (.name==$target) ))
| if   $output=="names"    then .[].name
  elif $output=="markdown" then
    ( reduce .[] as $t ({seen:{},out:""};
        ($t.name|gsub("%";"")) as $k
        | if .seen[$k] then . else
            .seen[$k]=true
            | .out += "\n[**`\($k)`**](#\($k))\n\n"
                + (($t.docs // [])|map(gsub("^\\s+|\\s+$";""))|join("\n"))
                + "\n\n---------\n"
          end) | .out )
  else ( map({(.name): .}) | add // {} )
  end
endef

define _mkp.jq.cblocks
( group_by(.label) | map({key:.[0].label, value:[.[].text]}) | from_entries )
| if $pattern=="" then . else with_entries(select(.key|test($pattern))) end
endef

define _mkp.jq.graph.edges
[ to_entries[] as $t | $t.value.prereqs[]? | {from:$t.key, to:.} ]
endef

define _mkp.jq.graph.dot
"digraph make {",
( to_entries[] as $t | $t.value.prereqs[]? | "  \"\($t.key)\" -> \"\(.)\";" ),
"}"
endef

# `_mkp.dispatch` -- the container-compatible CLI front-end (POSIX sh).  Reads the
# awk/jq programs from MKP_* env (materialized by `_mkp.native`), so the engine
# lives once in the defines above.  Presents `targets`/`cblocks`/`graph` + the
# container flags; bare `--shallow` emits a JSON ARRAY of names (__targets__
# pipes `jq -r '.[]'`).  jq programs go via argv so a dockerized ${jq} still works.
define _mkp.dispatch
set -eu
sub=targets
case "${1:-}" in targets|cblocks|graph) sub=$1; shift ;; esac
PUBLIC= PRIVATE= LOCAL= SHALLOW= NAMES= PARAMETRICS= MARKDOWN= PREVIEW= DOT= PREFIX= PATTERN= TARGET= file=
while [ $# -gt 0 ]; do case "$1" in
  --public) PUBLIC=1;; --private) PRIVATE=1;; --local) LOCAL=1;; --shallow) SHALLOW=1;;
  --names-only) NAMES=1;; --parametrics) PARAMETRICS=1;; --markdown) MARKDOWN=1;;
  --preview) PREVIEW=1; MARKDOWN=1;; --dot) DOT=1;;
  --prefix) shift; PREFIX="${1:-}";; --prefix=*) PREFIX="${1#--prefix=}";;
  --pattern) shift; PATTERN="${1:-}";; --pattern=*) PATTERN="${1#--pattern=}";;
  --target) shift; TARGET="${1:-}";; --target=*) TARGET="${1#--target=}";;
  --*) : ;;
  *) file="$1";;
esac; shift; done
file="${file:-${MAKEFILE:-Makefile}}"
[ -f "$file" ] || { printf 'mk.parse: no such file: %s\n' "$file" >&2; exit 2; }
base=$(basename "$file"); HOSTED='\.tmp\.hosted\.'
jsonl(){ if [ -n "$SHALLOW" ]; then awk -v emit=jsonl "$MKP_SCAN" "$file"
  else { env -u MAKEFILE -u __file__ -u MAKEFILE_LIST MAKEFLAGS= LC_ALL=C make -pRrq -f "$file" : 2>/dev/null || true; } | awk "$MKP_JESC
$MKP_FULL"; fi; }
tjq(){ $MKP_JQ -rs --arg prefix "$PREFIX" --arg localfile "$base" --arg hosted "$HOSTED" \
  --arg target "$TARGET" --arg output "$1" --arg public "$PUBLIC" --arg private "$PRIVATE" \
  --arg local "$LOCAL" --arg parametrics "$PARAMETRICS" "$MKP_JQ_TARGETS"; }
preview(){ if [ -n "$PREVIEW" ] && command -v glow >/dev/null 2>&1; then glow -; else cat; fi; }
case "$sub" in
targets)
  if   [ -n "$NAMES" ];    then jsonl | tjq names
  elif [ -n "$MARKDOWN" ]; then jsonl | tjq markdown | preview
  elif [ -n "$SHALLOW" ];  then PUBLIC=1; jsonl | tjq names | $MKP_JQ -Rs 'split("\n")|map(select(length>0))'
  else jsonl | tjq json; fi ;;
cblocks) awk "$MKP_JESC
$MKP_CBLOCKS" "$file" | $MKP_JQ -s --arg pattern "$PATTERN" "$MKP_JQ_CBLOCKS" ;;
graph) obj=$(jsonl | tjq json)
  if [ -n "$DOT" ]; then printf '%s' "$obj" | $MKP_JQ -r "$MKP_JQ_GDOT"
  else printf '%s' "$obj" | $MKP_JQ "$MKP_JQ_GEDGES"; fi ;;
*) printf 'mk.parse: unknown subcommand: %s\n' "$sub" >&2; exit 1 ;;
esac
endef

# Makefile-metadata parser (targets/help/cblocks -> JSON).  Native awk+jq backend,
# no container: the native backend (below), which shares the completion-scan awk for shallow mode.
# Callers append `[<subcommand>] <flags> <file>`.
mkparse=$(trace_maybe) && ${_mkp.native} $${subcommand:-targets} $${mkparse_args:-}

# `_mkp.native` -- the native backend entrypoint for the parser seam.  Bakes the
# engine programs into MKP_* env (via _mk.def.to.fd, in-process) and runs the
# dispatcher; the caller appends `<subcommand> <flags> <file>` as argv.
_mkp.native=MKP_JQ="${jq}" \
  MKP_JESC="$$($(call _mk.def.to.fd,_mkp.awk.jesc))" \
  MKP_FULL="$$($(call _mk.def.to.fd,_mkp.awk.full))" \
  MKP_SCAN="$$($(call _mk.def.to.fd,.awk.completion.scan))" \
  MKP_CBLOCKS="$$($(call _mk.def.to.fd,_mkp.awk.cblocks))" \
  MKP_JQ_TARGETS="$$($(call _mk.def.to.fd,_mkp.jq.targets))" \
  MKP_JQ_CBLOCKS="$$($(call _mk.def.to.fd,_mkp.jq.cblocks))" \
  MKP_JQ_GEDGES="$$($(call _mk.def.to.fd,_mkp.jq.graph.edges))" \
  MKP_JQ_GDOT="$$($(call _mk.def.to.fd,_mkp.jq.graph.dot))" \
  sh <($(call _mk.def.to.fd,_mkp.dispatch))

mk.parse/%:; ${mkparse} ${*}
	@# Parses the given Makefile, returning JSON output that describes the targets, docs, etc.

MKPARSE_ARGV?=
mk.parse.exec:; ${_mkp.native} ${MKPARSE_ARGV}
	@# Runs the native mk.parse backend on container-style argv in `MKPARSE_ARGV`
	@# (e.g. `targets --names-only --prefix X <file>`).  A CLI shim for callers that
	@# expect a `mk.parse` binary -- notably the docs image (see `.cmk/docs.mk`).

mk.parse:
	@# Parse / merge for each Makefile in MAKEFILE_LIST
	echo "${MAKEFILE_LIST}" | ${stream.space.to.nl} \
	| ${flux.each}/mk.parse | ${jq} -s '.[0] * .[1]'

mk.parse.targets/%:; ${mkparse} ${*} --public --names-only
	@# Parses the given Makefile, returning target-names only. Simple, pipe-friendly output. 
	@# Also available as a macro.  
	@# WARNING: Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"

mk.parse.doc_block/%:; ${trace_maybe}; subcommand=cblocks; ${mkparse} --pattern "$${pattern:-}" ${*}
	@# Pulls out documentation blocks that match the given pattern.
	@#
	@# USAGE:
	@#  pattern=.. ./compose.mk mk.parse.doc_block/<makefile>
	@#
	@# EXAMPLE:
	@#   pattern='TUI' make mk.parse.doc_block/compose.mk

mkparse:
	@#
	prefix=`case $${prefix:-} in "") echo;; *) echo "--prefix $${prefix}";; esac` \
	&& local=`case $${local:-} in "") echo;; *) echo "--local";; esac` \
	&& preview=`case $${preview:-} in "") echo;; *) echo "--preview";; esac` \
	&& ${trace_maybe} && ${mkparse} $${path:-${MAKEFILE}} $${prefix} $${local} $${preview} --public 

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: cli.subcommands :: The reusable subcommand / CLI engine
##
## Turns any target namespace into a `compose.mk <ns> <sub> <args>` dispatcher in
## one line; kwargs are optional/auto-detected (namespace defaults to the target,
## subs reflect the `.<ns>.<sub>` handlers in source order, default is the first).
## Clients: cli.cmk (below), demos/subcommands.mk.
##
## * _cli.subcommands.doc :: Group docstring header-block (glow to /dev/tty, else log).
##
## * subcommands.tail :: A dispatcher's CLI tail recovered from `MAKE_CLI`.
##     One `sed` drops the make-invocation prefix through the supervisor-enter word
##     (empty if absent); make then strips the `flux.pre`/`flux.post` hook decorations
##     and the leading namespace token (helper `m5.rest` drops that word).
## * _cli.subcommands.make :: Internal-recursion prefix for dispatch sub-makes.
##     Marks internal, skips re-installing the target-rewrite/at-exit hooks and the
##     SIGINT supervisor. The client keeps the real supervisor at top level; a handler
##     that execs a program re-enables `CMK_SUPERVISOR` (see `cli.cmk.run/%`).
## * _cli.subcommands.argv0 :: Sets `_inv`, the invocation as the user spelled it.
##     A wrapper exports `CMK_ARGV0` when it stands for `<program> <namespace>`, and
##     the namespace token it consumed is then dropped from the rendered prefix.
##     Otherwise the program path is used, shortened to its basename when that
##     basename resolves to the same file on PATH.
## * _cli.subcommands.usage :: Generic multi-line usage from subcmd_ns + subcmd_subs.
##     A header then one tree-line per subcommand (stderr): parametric subs annotated
##     `<arg> [args..]`, opt-in `subcmd_optional` subs `[<arg>]`, the rest bare, each
##     followed by the first line of that handler's docstring (one `subcmd_docs` awk
##     pass over the namespace, not one per subcommand).
## * _cli.subcommands.error :: Dispatch error (arg 1 = message tail).
##     A red error line plus the generated usage, then the `CMK_UNKNOWN_SUBCOMMAND`
##     token and a nonzero exit. A runtime recipe (no parse-time error), so the token
##     reaches stderr.
## * cli.subcommands.enter :: The entrypoint body for a subcommand CLI.
##     All kwargs optional/auto-detected (searched namespaces first-match-wins, the
##     sep, the reflected sub list, the bare-form default, which subs take an optional
##     arg). Handler `<ns><sep><sub>[/%]`; single-quote space-bearing values. Captures
##     the CLI tail then yields once. Nesting: a non-parametric handler may be a
##     sub-group; a dispatched handler reads argv, a top-level entry parses `MAKE_CLI`.
## * cli.subcommands :: CMK-lang decorator form of cli.subcommands.enter.
##     `@cli.subcommands` above a target turns it into a subcommand CLI; bare (no
##     kwargs) defaults to the tree-glyph namespaces (handlers `├─<sub>`/`╰─<sub>`),
##     pass kwargs to override.
##
##  * `[1]:` [Subcommands](https://robot-wranglers.github.io/compose.mk/subcommands)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

subcommands.tail = $(call m5.rest,$(filter-out flux.pre/% flux.post/%,$(shell printf '%s' '${MAKE_CLI}' | sed -E 's|^.*mk\.super\.enter/[0-9]+ *||;t;s|.*||')))

_cli.subcommands.make=CMK_INTERNAL=1 CMK_DISABLE_HOOKS=1 CMK_SUPERVISOR=0 ${make}

# Sets `_inv`, the invocation as the user spelled it.
_cli.subcommands.argv0=_a="$${CMK_ARGV0:-}" ; _s="$${subcmd_name}" ; \
	if [ -n "$${_a}" ]; then _s=`printf '%s' "$${_s}" | sed -E 's|^(cli\.)?cmk\.?||' | tr . ' '` ; \
	else _a="$${__file__:-$${CMK_BIN}}" ; _b="$${_a\#\#*/}" ; [ "`command -v "$${_b}" 2>/dev/null`" != "$${_a}" ] || _a="$${_b}" ; fi ; \
	_inv=`printf '%s %s' "$${_a}" "$${_s}" | sed -E 's/ +$$//'`

_cli.subcommands.doc=doc=`awk -v t="$${subcmd_name}" -v bin="$${_a:-$${__file__:-$${CMK_BIN}}}" "$${_awklang_target_doc}" $${__interpreting__:-} $(call twin.unmap,${MAKEFILE_LIST}) 2>/dev/null` ; \
	_glow_tty=0 ; { true >/dev/tty; } 2>/dev/null && [ "$${GITHUB_ACTIONS:-false}" != true ] && [ "$${CI:-}" != true ] && _glow_tty=1 ; \
	[ -z "$${doc}" ] || if [ "$${CMK_HELP_GLOW:-1}" != 0 ] && { [ "$${_glow_tty}" = 1 ] || [ "$${CMK_HELP_GLOW:-}" = 1 ]; } ; then \
		_glow_sink=/dev/stderr ; [ "$${_glow_tty}" = 1 ] && _glow_sink=/dev/tty ; \
		printf '%s\n' "$${doc}" | ${stream.glow} > $${_glow_sink} 2>/dev/null ; \
	else \
		printf '%s\n' "$${doc}" | while IFS= read -r dl; do $(call log.io, ${dim}$${subcmd_name} ${sep}${no_ansi_dim} $${dl}${no_ansi}); done ; \
	fi

_cli.subcommands.usage=( ${_cli.subcommands.argv0} ; ${_cli.subcommands.doc} ; \
	$(call log.loop.top, ${dim}$${subcmd_name} ${sep}${no_ansi} USAGE${no_ansi_dim}: ${no_ansi}$${_inv} ${bold}<subcommand>${no_ansi}${dim} [args..]) \
	&& nsalt=`echo "$${subcmd_ns}" | tr ' ' '|'` \
	&& last=`echo "$${subcmd_subs}" | awk '{print $$NF}'` \
	&& names="" \
	&& for s in $${subcmd_subs}; do for ns in $${subcmd_ns}; do \
		if grep -qE "^$${ns}[$${subcmd_sep}]$${s}(/%|:)" ${MAKEFILE_LIST} 2>/dev/null; then names="$${names} $${ns}$${subcmd_sep}$${s}"; break; fi; \
	done; done \
	&& docs=`awk -v names="$${names}" -v bin="$${_a}" "$${_awklang_subcmd_docs}" $${__interpreting__:-} $(call twin.unmap,${MAKEFILE_LIST}) 2>/dev/null` \
	&& for s in $${subcmd_subs}; do \
		if grep -qE "^($${nsalt})[$${subcmd_sep}]$${s}/%" ${MAKEFILE_LIST} 2>/dev/null; then args=" <arg> [args..]"; \
		elif case " $${subcmd_optional:-} " in *" $${s} "*) true;; *) false;; esac; then args=" [<arg>]"; \
		else args=""; fi ; \
		doc=`printf '%s\n' "$${docs}" | while IFS='|' read -r n d; do case "$${n}" in *$${subcmd_sep}$${s}) printf '%s' "$${d}"; break;; esac; done | tr -d '\`%$$"' | cut -c1-64` ; \
		pad=$$(( 28 - $${\#s} - $${\#args} )) ; [ $${pad} -gt 0 ] || pad=1 ; \
		lbl="${bold_cyan}$${s}${no_ansi}${dim_ital}$${args}${no_ansi}`printf '%*s' $${pad} ''`${dim}$${doc}" ; \
		if [ "$${s}" = "$${last}" ]; then $(call log.loop.item.last, $${lbl}); else $(call log.loop.item, $${lbl}); fi; \
	done )

_cli.subcommands.error=( $(call log.io, ${red}$${subcmd_name} ${sep}${no_ansi} $(1)) ; ${_cli.subcommands.usage} ; $(call log.io, ${red}${bold}CMK_UNKNOWN_SUBCOMMAND${no_ansi}) ; exit 1 )

define cli.subcommands.enter
$(eval _subcmd_args:=$(m5[1]?))$(call mk.unpack.kwargs, ${_subcmd_args}, namespace, .${@})$(call mk.unpack.kwargs, ${_subcmd_args}, sep, .)$(call mk.unpack.kwargs, ${_subcmd_args}, subs,)$(call mk.unpack.kwargs, ${_subcmd_args}, default,)$(call mk.unpack.kwargs, ${_subcmd_args}, optional,)tail=`if [ "$${CMK_INTERNAL:-0}" = 1 ] && [ -n "$${argv:-}" ]; then echo "$${argv:-}"; else case "$${MAKE_CLI}" in \
		*mk.super.enter/*) echo '$(subcommands.tail)' ;; \
		*) _t="$${MAKE_CLI#*${@}}"; [ "$${_t}" = "$${MAKE_CLI}" ] && echo "" || echo "$${_t}" ;; \
	esac; fi | xargs` \
	&& _fns="$(strip ${kwargs_namespace})" && _fsep="$(strip ${kwargs_sep})" && _fh="" \
	&& if [ -n "$${tail}" ] && [ "$${_fns#* }" = "$${_fns}" ] && [ -z "$(strip ${kwargs_subs})" ]; then \
		_fsub="`echo "$${tail}" | cut -d' ' -f1`" && _frest="`echo "$${tail}" | cut -d' ' -f2- -s`" ; \
		case "$${_fsub}" in help|-h|--help) _fsub="";; esac ; \
		case "$${tail}" in *[\`\"\'$$\;\|\&]*) _fsub="";; esac ; \
		if [ -n "$${_fsub}" ]; then \
			if grep -qE "^$${_fns}[$${_fsep}]$${_fsub}/%" ${MAKEFILE_LIST} 2>${devnull}; then _fh="$${_fns}$${_fsep}$${_fsub}/`echo "$${_frest}" | cut -d' ' -f1`" && _fargs="`echo "$${_frest}" | cut -d' ' -f2- -s`" ; \
			elif grep -qE "^$${_fns}[$${_fsep}]$${_fsub}:" ${MAKEFILE_LIST} 2>${devnull}; then _fh="$${_fns}$${_fsep}$${_fsub}" && _fargs="$${_frest}" ; \
			elif [ -n "$(strip ${kwargs_default})" ] && grep -qE "^$${_fns}[$${_fsep}]$(strip ${kwargs_default})/%" ${MAKEFILE_LIST} 2>${devnull}; then _fh="$${_fns}$${_fsep}$(strip ${kwargs_default})/$${_fsub}" && _fargs="$${_frest}" ; fi ; \
		fi ; \
	fi \
	&& if [ -n "$${_fh}" ]; then \
		_froute="argv=\"$${_fargs}\" subcmd_name=${@} ${_cli.subcommands.make} $${_fh}" && $(call mk.yield, $${_froute}) ; \
	else \
		$(call mk.yield, subcmd_name=${@} subcmd_ns=\"$(strip ${kwargs_namespace})\" subcmd_sep=$(strip ${kwargs_sep}) subcmd_default=$(strip ${kwargs_default}) subcmd_subs=\"$(strip ${kwargs_subs})\" subcmd_optional=\"$(strip ${kwargs_optional})\" subcmd_tail=\"$${tail}\" ${_cli.subcommands.make} cli.subcommands) ; \
	fi
endef

cli.subcommands:
	@# Shared subcommand-dispatch engine (reusable; see `cli.subcommands.enter`).
	@# Reads subcmd_name/subcmd_ns/subcmd_sep/subcmd_subs/subcmd_default/subcmd_tail from
	@# the env and routes the first tail word to its handler.  A parametric handler
	@# `<ns><sep><sub>/%` gets the next word as its stem (the rest in `argv`); a
	@# non-parametric `<ns><sep><sub>` gets all the remaining args in `argv`.  An
	@# unrecognized first word routes to the default sub only when the default is
	@# parametric (the word becomes its arg, e.g. `cmk <file>` -> `cmk run <file>`); when
	@# the default is non-parametric, an unrecognized first word is an unknown-subcommand
	@# error.  empty/help/-h/--help prints usage.  Never yields.
	@#
	@# subcmd_ns may be a SPACE-SEPARATED list of namespaces, searched in order like an
	@# MRO (the first namespace that defines a handler for the sub wins).  subcmd_subs (the
	@# union across namespaces) and subcmd_default are auto-detected when empty by reflecting
	@# the `<ns><sep><sub>` handler targets in `MAKEFILE_LIST` (parametric or not).
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

cli.subcommands=$(call cli.subcommands.enter,$(or $(strip $(if $(filter-out undefined,$(origin 1)),${1})),namespace='├ ╰' sep=─))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

## BEGIN: tux.progress :: The dockerized NDJSON progress renderer
##
## From github.com/mattvonrocketstein/tux.progress.  `stream.progress` is a pipe filter: a producer
## emits `{index,total,output}` NDJSON, pipes it through, the bar is drawn on the terminal and
## stdout passes through unchanged.  When a controlling terminal exists and it is not CI, the bar
## is forced on and routed straight to /dev/tty; `[ -t 2 ]` is unreliable here because the cmk
## CLI wraps recipe stderr.  Any set `tux_progress_*` env vars are forwarded into the container.
## terminal = a controlling tty exists (not CI)
tux.progress.terminal={ true >/dev/tty; } 2>/dev/null && [ "$${GITHUB_ACTIONS:-false}" != true ] && [ "$${CI:-}" != true ]
tux.progress.env=-e TERM=$${TERM:-xterm} $$(env | grep '^tux_progress_' | sed 's/=.*//;s/^/-e /' | tr '\n' ' ')
## names = the tux_progress_* namespace for docker.run.sh env=
tux.progress.names=tux_progress_force,tux_progress_width,tux_progress_bar_width,tux_progress_color,tux_progress_track_color,tux_progress_check_color,tux_progress_fill_chars,tux_progress_spinner,tux_progress_unit,tux_progress_done,tux_progress_checks,tux_progress_prefix,tux_progress_eta,tux_progress_tick,tux_progress_hz,tux_progress_clear,tux_progress_template,tux_progress_gradient
tux.progress.run=if ${tux.progress.terminal}; then docker run --rm -i -e tux_progress_force=1 ${tux.progress.env} ${IMG_TUX_PROGRESS} 2>/dev/tty; else docker run --rm -i ${tux.progress.env} ${IMG_TUX_PROGRESS}; fi
stream.progress=${tux.progress.run}
tux.progress:
	@# Filter stdin NDJSON progress events through the dockerized tux.progress renderer.
	@# USAGE:  <producer emitting {index,total,output} NDJSON> | ./compose.mk tux.progress
	${stream.progress}

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: cli.cmk :: The cmk CLI client
##
## A public subcommand front-end (`cmk` is the short alias for `cli.cmk`,
## both dispatching to the `cli.cmk.*` handlers) built as a thin client of the subcommand engine
## above. Subcommands: `build`/`compile`/`transpile`/`eval`/`run`/`repl`/`doc`/`lint`, plus the
## nested `cli.cmk.cli` group (`complete`/`init`/`targets`) for bash-completion integration. A bare
## `cmk <file>` means `cmk run <file>`; source piped on stdin with no subcommand is compiled (or run),
## via the `_cmk.stdin.compile.maybe` shortcut that acts on the pipe then interrupts the supervisor.
##
## The heavy lifting is delegated to existing internals; the private `_cmk.*` helpers here compose the
## run path: `_cmk.compile` lowers a source to an executable temp, `_cmk.compile.checked` adds a
## validate pass for the non-executing front-ends (lint/doc), and `_cmk.interpret.self` re-execs the
## compiled program self-supervised with any extra CLI words as the make continuation. `cmk run`
## forces `CMK_COMPILER_VERBOSE=0` (quiet unless a compile actually fails) and honors a program's
## `repl` pragma as an execution mode; `cmk repl` forces that interactive mode explicitly. Boot
## pragmas (hooks / bootloader_disabled / bootloaders), read pre-make by the bash header, are threaded
## into the re-exec by the `mk.super.boot.*` helpers just below the section.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

_cmk.stdin.compile.maybe=_ct=`echo '$(subcommands.tail)' | xargs` ; case "$${_ct}" in ''|compile) _pv=mk.compiler; _std='mk.compiler!' ;; transpile) _pv=lang.transpile; _std=lang.transpile ;; run) _pv=RUN ;; *) _pv= ;; esac ; if [ -p ${stdin} ] && [ -n "$${_pv}" ]; then if [ "$${_pv}" = RUN ]; then $(call log.io, ${dim}cmk run ${sep}${dim} stdin) ; ${make} cli.cmk.run/- ; elif ${io.tty.stdout}; then { [ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] || $(call log.io, ${dim}cmk $${_ct:-compile} ${sep}${dim} stdin) ; } && errto=$$( [ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] && echo /dev/null || echo /dev/stderr ) && ${stream.stdin} | ${_cli.subcommands.make} $${_pv} 2>$${errto} | style=monokai lexer=makefile ${make} stream.pygmentize ; else ${stream.stdin} | ${_cli.subcommands.make} $${_std} ; fi ; rc=$$? ; { [ -z "$${MAKE_SUPER}" ] || echo "$${rc}" > .tmp.mk.super.$${MAKE_SUPER} ; } ; ${mk.interrupt} ; fi

# Keep the docstring leading (the `docstring` stage reads it there) and `cli.subcommands.enter` sole-final.
cli.cmk:
	@# Compile, run, package, and inspect CMK programs (`.cmk` files).
	@# A bare `<file>` means `run <file>`; source piped on stdin is compiled.
	@${_cmk.stdin.compile.maybe}
	$(call cli.subcommands.enter, namespace=cli.cmk default=run optional='repl lint')
cmk:
	@# Compile, run, package, and inspect CMK programs (`.cmk` files).
	@# A bare `<file>` means `run <file>`; source piped on stdin is compiled.
	@${_cmk.stdin.compile.maybe}
	$(call cli.subcommands.enter, namespace=cli.cmk default=run optional='repl lint')

cli.cmk.cli:; $(call cli.subcommands.enter, namespace=cli.cmk.cli default=complete optional='complete init targets')
	@# Shell integration: tab-completion scripts and target listings.

cli.cmk.cli.complete:
	@# Emit a bash tab-completion script on stdout; eval it:
	@#   ./compose.mk cmk cli complete   -- eval its output; registers compose.mk, ./compose.mk, cmk
	@#   ./your.cmk   cmk cli complete   -- a cmk-run program (inherited; registers itself)
	@# Optional first arg = a makefile to complete (default: interpreted program else CMK_SRC).
	@# Bakes a stdlib target snapshot + embeds the scanner for a live scan of the typed file, so
	@# one function (keyed on `COMP_WORDS`[0]) serves every registered command.  zsh: first run
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
	@# Install bash completion for a program, idempotently.
	@# Writes one file into the user's bash-completion dir; no shell-rc
	@# edits.  Optional first arg = makefile (default: interpreted program
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
	@# Print a makefile's public target base-names.
	@# Debug primitive: define/endef-aware.
	@# Optional first arg = file (default: interpreted program else CMK_SRC).
	@#   ./compose.mk cmk cli targets   |   ./your.cmk cmk cli targets
	f="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& f="$${f:-$${__interpreting__:-${CMK_SRC}}}" \
	&& awk -f <(${mk.def.read}/.awk.completion.scan) "$${f}" 2>/dev/null | sort -u

cli.cmk.build/%:
	@# Package a program into a self-extracting executable.
	bin="$${argv:-$$(basename ${*} .cmk)}" \
	&& $(call log.io, ${dim}cmk build ${sep}${no_ansi} ${underline}${*}${no_ansi} ${dim}-> ${no_ansi}$${bin}) \
	&& $(call lang.lint.source,${*}) \
	&& $(call lang.lint.output,$${bin}) \
	&& bin="$${bin}" ${_cli.subcommands.make} lang.pkg/${*}

# omni bundle: CMK_PLUGINS_DIR + CMK_MODULES_DIR dirs, deduped.
_cmk.omni.dirs=$(call m5.lex.uniq,$(strip $(foreach _d,$(call m5.lex.split,${CMK_PLUGINS_DIR}) ${CMK_MODULES_DIR},$(wildcard ${_d}))))

cli.cmk.omni:
	@# Package a program plus its plugin dirs into one executable.
	@# `cmk omni [<app>.cmk]` helper: package an omnibus self-extracting executable that also
	@# bundles the host's CMK_PLUGINS_DIR / CMK_MODULES_DIR so the frozen binary carries its
	@# plugins/modules.  Thin wrapper over `cmk build` / `lang.pkg.root`: it just forwards the
	@# existing plugin dirs as extra `archive` entries.
	@#   ./compose.mk cmk omni <app>.cmk    # freeze an app + its plugins
	@#   ./compose.mk cmk omni              # freeze the compose.mk root + plugins
	@# Output defaults to ./omnibus (override with bin=<name>).  Dirs are bundled by basename
	@# (see `mk.self`); resolution is automatic for the default `.cmk` layout (runtime cwd =
	@# extraction dir).  Absolute or non-`.cmk`-basename search dirs are still bundled but
	@# need a runtime CMK_PLUGINS_DIR to be found.
	f="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& bin="$${bin:-omnibus}" \
	&& archive="$(_cmk.omni.dirs) $${archive:-}" \
	&& if [ -n "$${f}" ]; then \
		$(call lang.lint.source,$${f}) \
		&& $(call lang.lint.output,$${bin}) \
		&& $(call log.io, ${dim}cmk omni ${sep}${no_ansi} ${underline}$${f}${no_ansi} ${dim}-> ${no_ansi}$${bin} ${dim}(+ $(_cmk.omni.dirs))) \
		&& bin="$${bin}" archive="$${archive}" ${_cli.subcommands.make} lang.pkg/$${f} ; \
	else \
		$(call log.io, ${dim}cmk omni ${sep}${no_ansi} ${underline}root${no_ansi} ${dim}-> ${no_ansi}$${bin} ${dim}(+ $(_cmk.omni.dirs))) \
		&& bin="$${bin}" archive="$${archive}" ${_cli.subcommands.make} lang.pkg/$${bin} ; \
	fi

cli.cmk.compile/%:
	@# Compile a program to a standalone Makefile.
	@# Highlighted preview on a tty, else the full standalone output.
	$(call lang.lint.source,${*}) \
	&& if [ -n "$${argv:-}" ]; then \
		$(call lang.lint.output,$${argv}) \
		&& $(call log.io, ${dim}cmk compile ${sep}${no_ansi} ${underline}${*}${no_ansi} ${dim}-> ${no_ansi}$${argv}) \
		&& cat ${*} | ${_cli.subcommands.make} mk.compiler! > $${argv} ; \
	elif ${io.tty.stdout}; then \
		$(call log.io, ${dim}cmk compile ${sep}${dim} preview ${sep} ${no_ansi}${underline}${*}) \
		&& errto=$$( [ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] && echo /dev/null || echo /dev/stderr ) \
		&& ${_cli.subcommands.make} mk.compiler/${*} 2>$${errto} | style=monokai lexer=makefile ${make} stream.pygmentize ; \
	else \
		cat ${*} | ${_cli.subcommands.make} mk.compiler! ; \
	fi

cli.cmk.transpile/%:
	@# Show the bare Makefile fragment the CMK sugar lowers to.
	@# `cmk transpile` helper: emit the bare Makefile fragment (no shebang/payload
	@# wrapper) so you can see how the CMK sugar lowers.  Highlighted preview on a tty;
	@# `<out>` writes the fragment to a file.  Contrast `cmk compile` (full standalone).
	$(call lang.lint.source,${*}) \
	&& if [ -n "$${argv:-}" ]; then \
		$(call log.io, ${dim}cmk transpile ${sep}${no_ansi} ${underline}${*}${no_ansi} ${dim}-> ${no_ansi}$${argv}) \
		&& export __interpreting__=${*} && cat ${*} | ${_cli.subcommands.make} lang.transpile > $${argv} ; \
	elif ${io.tty.stdout}; then \
		$(call log.io, ${dim}cmk transpile ${sep}${dim} preview ${sep} ${no_ansi}${underline}${*}) \
		&& errto=$$( [ "$${CMK_COMPILER_VERBOSE:-1}" = 0 ] && echo /dev/null || echo /dev/stderr ) \
		&& export __interpreting__=${*} && cat ${*} | ${_cli.subcommands.make} lang.transpile 2>$${errto} | style=monokai lexer=makefile ${make} stream.pygmentize ; \
	else \
		export __interpreting__=${*} && cat ${*} | ${_cli.subcommands.make} lang.transpile ; \
	fi

cli.cmk.eval:
	@# Compile and run CMK source read from stdin.
	@# `cmk eval` helper: read CMK-lang source on stdin, compile it, and run it.  A thin
	@# front-end for `cmk.kernel` (the CMK analog of the make-side kernel).
	@# USAGE:  echo 'this.flux.or(flux.ok, flux.fail)' | ./compose.mk cmk eval
	${stream.stdin} | ${make} cmk.kernel


# content-addressed compile cache: key is source plus every compile input (env knobs, plugin dirs, hosted hash, twin id); a hit skips the whole compile sub-make ladder, stdin and misses take the old path, and only a non-empty result is stored (pid temp, atomic rename).
_cmk.compile=if [ -f "$(strip $(1))" ]; then \
	_cs=`{ cat "$(strip $(1))"; printf '%s' "$${CMK_LANG:-}|$${dialect:-}|$${sugar:-}|$${cmk_dialect:-}|$${cmk_sugar:-}"; _pifs=$$IFS; IFS=:; for _pd in $${CMK_PLUGINS_DIR:-}; do cat "$$_pd"/*.cmk 2>${devnull}; done; IFS=$$_pifs; } | cksum | tr ' ' '-'` \
	&& _co=${CMK_STAGE_DIR}/.tmp.cmkc.${HOSTED_HASH}$(firstword $(subst ., ,$(notdir ${CMK_TWIN_PATH}))).$$_cs.mk \
	&& if [ -f "$$_co" ]; then cat "$$_co" > $${tmpf} && chmod +x $${tmpf}; \
	else cat "$(strip $(1))" | ${_cli.subcommands.make} mk.compile > $${tmpf} && chmod +x $${tmpf} \
		&& if [ -s $${tmpf} ]; then mkdir -p ${CMK_STAGE_DIR} && cp $${tmpf} "$$_co.${_cmk.pid}" && mv -f "$$_co.${_cmk.pid}" "$$_co"; fi; fi; \
else cat $(1) | ${_cli.subcommands.make} mk.compile > $${tmpf} && chmod +x $${tmpf}; fi

_cmk.compile.checked=$(call io.mktemp) \
	&& ( export CMK_COMPILER_VERBOSE=0 && $(call _cmk.compile,$(1)) ) \
	&& ( export CMK_COMPILER_VERBOSE=0 CMK_INTERNAL=0 ; $(call mk.validate,$${tmpf}) )

_cmk.interpret.self=export CMK_INTERNAL=0 CMK_SUPERVISOR=1 continuation="$${argv:-}" __interpreting__=$(m5[1]) && $(call _mk.interpret.file,$${tmpf})


cli.cmk.run/%: CMK_COMPILER_VERBOSE := 0
cli.cmk.run/%:
	@# Compile and run a program.
	@# `cmk run` helper: compile then exec (no yield; the program self-supervises).  The compile +
	@# pragma-threading is factored into the `_cmk.*` helpers above; see those for the boot/repl details.
	@# REPL PRAGMA: a `repl` pragma (true, or a {read,eval,print,exit_after} object) makes the DEFAULT
	@# action (no target args) launch the interactive tux.repl harness over the program's targets instead
	@# of running __main__ -- REPL-as-execution-mode.  An explicit `cmk run <file> <target>` bypasses it
	@# and runs the target (like `python script.py` vs bare `python`); `cmk repl <file>` forces the mode.
	$(call lang.lint.source,${*}) \
	&& $(call io.mktemp) \
	&& export __interpreting__=${*} \
	&& export CMK_LANG="$${CMK_LANG:-$$( { [ -f "${*}" ] && cat ${*} | $(lang.parse.pragma.hint) 2>${devnull} | ${jq.run.pipe} -r '.cmk_lang // empty' 2>${devnull} ; } | grep . || echo 1 )}" \
	&& $(call _cmk.compile, ${*}) \
	&& $(call mk.super.boot.thread) \
	&& _bp_repl=$$(cat $${tmpf} | $(call __pragma__.sh,REPL)) \
	&& if [ -n "$${_bp_repl}" ] && [ -z "$${argv:-}" ]; then \
			$(call lang.repl.kwargs) \
			&& $(call log.io, ${yellow}cmk run ${sep}${no_ansi} pragma repl ${sep} entering REPL execution mode${no_ansi}) \
			&& $(call lang.repl.launch, $${_rk}, ${*}) ; \
		else \
			export CMK_TRAMPOLINE="$${CMK_TRAMPOLINE:-$$(cat $${tmpf} | $(call __pragma__.sh,TRAMPOLINE))}" && $(call _cmk.interpret.self, ${*}) ; \
		fi

cli.cmk.repl:
	@# Open an interactive shell over a program's target namespace.
	@# `cmk repl [<file>]` helper: launch the interactive REPL over a program's target namespace, even
	@# one with no `repl` pragma (the explicit form of what that pragma opts a program into). With a file
	@# it compiles it and wires the kernel dispatcher over the file's targets (type a target name to run
	@# it; ctrl-d exits). No file drops to a shell over the core namespace: interactive with a tty, else
	@# stdin streams line-by-line into the core eval kernel (so `echo flux.ok | cmk repl` runs flux.ok).
	@# An explicit `cmk repl -` instead makes the piped stream the program. Regions default to the kernel
	@# eval but honor a `repl` pragma, falling back per-region to CMK_REPL_* env vars. The file arrives via
	@# `argv`, so all forms share one handler; interactive use needs a tty.
	f="`echo "$${argv:-}" | cut -d' ' -f1`" \
	&& $(call io.mktemp) \
	&& export __interpreting__=$${tmpf} \
	&& if [ -n "$${f}" ]; then \
		{ [ "$${f}" = - ] && src="<stdin>" || src="$${f}" ; } \
		&& $(call log.io, ${dim}cmk repl ${sep}${no_ansi} ${underline}$${src}) \
		&& $(call lang.lint.source,$${f}) \
		&& $(call _cmk.compile, $${f}) ; \
	else \
		$(call log.io, ${dim}cmk repl ${sep}${no_ansi_dim} no file ${sep} simple shell over the core namespace) \
		&& printf '%s\n' '$(lang.main.stub.noop)' | $(call _cmk.compile, -) ; \
	fi \
	&& _bp_repl=$$(cat $${tmpf} | $(call __pragma__.sh,REPL)) \
	&& $(call lang.repl.kwargs) \
	&& { $(call lang.repl.enter.default) ; } \
	&& { $(call lang.repl.vm.ensure) ; } \
	&& $(call lang.repl.launch, $${_rk}, $${f})

cli.cmk.doc/%:
	@# Make a program directly executable: shebang, chmod, check.
	$(call lang.lint.source,${*}) \
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

cli.cmk.lint:
	@# Lint programs, or source piped on stdin.
	@# Lints each given .cmk program (or piped source on stdin) -- source hygiene
	@# (`lang.lint.source`), a compile pass surfacing the namespace/shadow warnings, then the deep
	@# tier.  Multiple files are linted independently: one failure does not stop the rest, and the
	@# exit is nonzero if any failed.  With no file and no pipe it prints a usage hint (compose.mk's
	@# own audit is the separate project target `lint.self` in .automation.cmk).  Files arrive via `argv`; a
	@# bare `.. | cmk lint` (or `cmk lint -`) lints stdin, like `cmk eval` runs it.
	files="$${argv:-}" \
	&& { [ -n "$${files}" ] || ! [ -p ${stdin} ] || files=- ; } \
	&& if [ -n "$${files}" ]; then \
		rc=0 ; \
		for f in $${files}; do \
			( { [ "$${f}" = - ] && src="<stdin>" || src="$${f}" ; } \
				&& $(call log.io, ${dim}cmk lint ${sep}${dim} checking ${sep} ${no_ansi}${underline}$${src}) \
				&& $(call lang.lint.source,$${f}) \
				&& ( export CMK_NS_LINT=1 && $(call _cmk.compile.checked,$${f}) ) \
				&& ${make} lang.lint.deep/$${f} \
				&& $(call log.io, ${dim}cmk lint ${sep} ${green}ok) ) \
			|| rc=1 ; \
		done ; \
		exit $${rc} ; \
	else \
		$(call log.io, ${dim}cmk lint ${sep}${no_ansi_dim} needs a .cmk file or piped source ${sep} framework self-audit is ${no_ansi}make lint.self) ; \
	fi

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
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
	header="${dim_cyan}${*} ${sep}" \
	&& $(call log.mk.part1, $${header} ${dim}Generating code) \
	&& $(call io.mktemp) \
	&& src="$(call m5.__args__.first,:): $(call m5.__args__.cut,2-,:)" \
	&& printf "$${src}" >  $${tmpf} ; cp $${tmpf} tmpf \
	&& $(call log.base.part2, ${no_ansi_dim}$${tmpf}) \
	&& cmd="${make} -f $${tmpf} $${MAKE_CLI#*mk.let/${*}}" \
	&& $(call log,$${cmd}) \
	&& $(call mk.yield,$${cmd})

# lang.mk.dir: the always-available primitive (not the make builtin).
lang.mk.dir = $(if $(m5[1]),${mkparse} --prefix $(m5[1]) --names-only $${path:-${MAKEFILE}},$(call _help_gen) | cut -d. -f1 | cut -d/ -f1 | uniq | grep -v ^all$$)

# dir(<prefix>): member listing, python dir() -- now a builtin.
# With no argument it emits the top-level namespaces (flux, io, stream, ..); with a
# prefix it emits the targets inside that namespace.  Newline-delimited, pipe-friendly,
# and fork-free -- the primitive behind the namespace-listing helpers.
# USAGE:  bare `dir` -- no arg = top namespaces; prefix = members.
dir:
	@# Reflective listing of the top-level namespaces (cf. python's `dir()`).
	@# Pipe-friendly; stdout is newline-delimited namespace prefixes.
	$(call lang.mk.dir)
dir/%:
	@# Reflective listing of the members of the given namespace (cf. `dir(obj)`).
	@# WARNING: callers must anticipate parametric targets with percent-signs (foo.bar/%).
	@# USAGE: ./compose.mk dir/flux.
	$(call lang.mk.dir, ${*})

# __builtins__: reflective listing of the core targets compose.mk itself ships -- the
# always-available stdlib namespace (cf. python's `__builtins__`), distinct from a guest
# program's own targets (`mk.targets`) and from the whole loaded namespace (`__dir__`).
# Names come from `${HOSTED_SRC}` (the seed heads plus the `__hosted__` partition), sorted
# and deduped, newline-delimited and pipe-friendly.  This is the single enumerator behind
# the `.PHONY` guard: `_cmk.phony.bare` filters it down to the bare (dotless) heads.
# USAGE:  $(call __builtins__)   ||   ./compose.mk __builtins__
__builtins__={ ${_cmk.seed.heads}; ${_cmk.hosted.heads}; } | sed 's/:.*//' | sort -u

__builtins__:
	@# Reflective listing of the core targets compose.mk ships (cf. python's `__builtins__`).
	@# The always-available stdlib namespace; cf. `__dir__` (whole loaded namespace) and
	@# `mk.targets` (this file's own targets).  Pipe-friendly, newline-delimited.
	$(call __builtins__)

mk.namespace.list help.namespaces:
	@# Returns only the top-level target namespaces
	@# Pipe-friendly; stdout is newline-delimited target prefixes.
	@#
	tmp="`$(call lang.mk.dir)`" \
	&& count=`printf "$${tmp}"| ${stream.count.lines}` \
	&& $(call log.base, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} ) \
	&& printf "$${tmp}\n" \
	&& $(call log.base, ${no_ansi}${GLYPH_MK} help.namespaces ${sep} ${dim}count=${no_ansi}$${count} )

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.pkg :: Packaging as a self-extracting executable
##
## Freeze a CMK app, a `.mk` file, or a make-target into a single-file, dependency-free
## self-extracting executable (via `makeself`), bundling `compose.mk` plus whatever is packaged so the
## result runs on a host with no compose.mk/source present. `lang.pkg/<input>` dispatches by suffix
## (`.cmk` re-interprets the bundled app, `.mk` runs its default goal, a bare name packages a target);
## `bin`/`archive` tune the output name and extra bundled files. `lang.pkg` is the `mk.self` variant
## that also embeds the source; `lang.pkg.root` (conditional on interpret mode) packages the app root.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lang.pkg:; set -x && archive="$${archive} ${CMK_SRC}" ${make} mk.self
	@# Like `mk.self`, but includes `compose.mk` source also.

lang.pkg/%:
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
	@#  ./compose.mk lang.pkg/<target_name>           # e.g. lang.pkg/flux.ok
	@#  ./compose.mk lang.pkg/path/to/app.cmk         # freeze a CMK app
	@#  ./compose.mk lang.pkg/path/to/app.mk          # freeze a makefile
	@#  archive="file1 dir1" ./compose.mk lang.pkg/path/to/app.cmk
	@#
	pkg_in="${*}" && case "$${pkg_in}" in \
	  *.cmk) base=`basename "$${pkg_in}"` \
	    && bin="$${bin:-$${base%.cmk}}" archive="$${pkg_in} $${archive:-}" script=bash \
	       script_args="$(notdir ${CMK_SRC}) mk.interpret! $${base}" ${make} lang.pkg ;; \
	  *.mk)  base=`basename "$${pkg_in}"` \
	    && bin="$${bin:-$${base%.mk}}" archive="$${pkg_in} $${archive:-}" script=make \
	       script_args="${MAKE_FLAGS} -f $${base}" ${make} lang.pkg ;; \
	  *)     ${make} .lang.pkg/$${pkg_in} ;; \
	esac

ifeq (${__interpreting__},) 
.lang.pkg/%:; cmd=${*} bin=$${bin:-${*}} label=$${label:-${*}} ${make} lang.pkg.root
lang.pkg.root:
	@# Packages the application root, or the given command if provided.
	label=$${label:-${*}} bin=$${bin:-${*}} script=make \
	script_args="${MAKE_FLAGS} -f ${MAKEFILE} $${cmd:-}" \
	${make} lang.pkg
else 
lang.pkg.root:
	@# Packages the application root, or the given command if provided.
	@# `lang.pkg` bundles `CMK_SRC`, which `mk.self` lands at the archive root by
	@# basename, so run that copy via `bash` (compose.mk's shebang interpreter):
	@# no `./compose.mk`-at-cwd assumption and no executable-bit requirement (an
	@# `include`d compose.mk often isn't chmod +x), while keeping the shebang's
	@# supervisor trampoline that `mk.interpret!` relies on.
	label=$${label:-${*}} bin=$${bin:-${*}} script=bash \
	script_args="$(notdir ${CMK_SRC}) mk.interpret! ${__interpreting__} $${cmd:-}" \
	${make} lang.pkg
.lang.pkg/%:; cmd=${*} bin=$${bin:-${*}} label=$${label:-${*}} ${make} lang.pkg.root
endif

# .lang.src.fork.section/<SECTION>/<file> -- rewrite one named section (guest, services, or payload) of a
# forked copy of the source, injecting the prefix, guest data, postfix, and post-hook from the environment
# via the section-rewriting awk program. Section is the first stem field; the source file (or `-` for
# stdin) is the rest. Consumed by the lang.src.fork.* verbs.
.lang.src.fork.section/%:
	section=$(call m5.__args__,1,/) \
	&& fname=$(call m5.__args__,2-,/) \
	&& case $${fname} in -) fname=/dev/stdin;; esac \
	&& fdata=$$(cat $${fname}) \
	&& $(call log.mk,lang.src.fork.section ${sep} ${dim}section=${dim_cyan}$${section} ${sep} ${dim}loading ${bold}$${fname}) \
	&& { [ -z "$${shebang:-}" ] || printf "$${shebang}\n" ; } \
	&& cat ${CMK_BIN} \
	  | TARGET_SECTION=$${section} PREFIX='$(shell echo "$${PREFIX:-}")' POSTFIX="$${POSTFIX:-}" POSTHOOK=$${POSTHOOK:-} GUEST_DATA="$${fdata}" \
	  awk "$${_awklang_fork_section}"

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
mk.namespace.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Newline-delimited output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.namespace.filter/<prefix>
	@#
	$(call lang.mk.dir, ${*})

mk.run/%:; ${io.shell.isolated} make -f ${*} 
	@# A target that runs the given makefile.
	@# This uses `make` directly and naively, not using the current context.

mk.select mk.select.local: mk.select/${MAKEFILE}
	@# Interactive target selection / runner for the local Makefile

mk.select/%:
	@# Interactive target-selector for the given Makefile.
	@# This uses `gum choose` for user-input.
	@#
	choices=`${make} mk.targets.simple/${*} | ${stream.nl.to.space}` \
	&& header="Choose a target:" && ${io.get.choice} \
	&& ${io.shell.isolated} bash ${dash_x_maybe} -c "make -f ${*} $${chosen}"

# __targets__(<file>): reflective listing of a file's own (shallow) target-names, no
# includes -- python's `vars(module)` to __dir__'s whole-namespace `dir()` and __builtins__'s
# core namespace.  The cheap name-list primitive the `mk.targets.*` family shares (a macro,
# so no sub-make re-parse); full include-aware parsing is `mkparse`/`mk.parse`.  `.parametric`
# keeps only the `foo/%` targets, stem-stripped to `foo`.
__targets__=${mkparse} --shallow $(1) | ${jq} -r '.[]'
__targets__.parametric=$(call __targets__,$(1)) | grep '%' | sed 's/\/%//g'
mk.targets/%:; $(call __targets__,${*})
	@# Returns only local targets from the given file, ignoring includes.
	@# Returns a newline-delimited list of targets inside the given Makefile.
	@# Unlike `mk.parse`, this is "flat" and too naive to parse targets that come 
	@# via includes.  Targets starting with "." are considered private, and 
	@# ommitted from the return value.
	
mk.targets:; $(call __targets__,$${path:-${MAKEFILE}})
	@# Returns only local targets for the current Makefile, ignoring includes.
	@# Shallow target-names of the current MAKEFILE (== `mk.targets/<MAKEFILE>`).

	@#
	@# USAGE: 
	@#   ./compose.mk mk.parse.targets/<file>
	@#

mk.reconn/%:; make --reconn -f ${*}
	@# Runs makefile in dry-run / reconn mode 


mk.set/%:; $(eval $(call m5.__args__,1,/):=$(call m5.__args__,2-,/))
	@# Setter for make variables, available as a target. 
	@# This is experimental stuff for reflection support.
	@#
	@# USAGE: ./compose.mk mk.set/<key>/<val>

# mk.stat lives in the `__hosted__` partition (built with the `jqlang` DSL).

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: supervisor :: Signals, interrupts, bootloader, trampoline
##
## The make-side runtime supervisor: signal handling (mk.interrupt / mk.super.trap),
## process reflection (mk.super.pid), the bootloader (_mk.super.bootloader), the
## yield/dispatch trampoline (_mk.super.tramp), and the
## enter/boot/exit lifecycle.  (The early polyglot bash-header half is at the top of the
## file; this is the target/define half it dispatches into.)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# mk.super.interrupt: the default interrupt, shorthand for the sigint form of the parametric target below.
mk.super.interrupt mk.interrupt: mk.interrupt/SIGINT

# WARNING: do not use ${make} here!
mk.interrupt=CMK_INTERNAL=1 ${MAKE} -f ${MAKEFILE} mk.interrupt

# mk.super.once: deprecated alias for m5.memoize! (run-scoped once).
mk.super.once=$(call m5.memoize!,$(1))

ifeq (${CMK_SUPERVISOR},0)
mk.super.interrupt/% mk.interrupt/%:
	@# CMK_SUPERVISOR is 0; signals are disabled.
	@#
	$(call log.base, ${GLYPH_MK} ${@} ${sep} ${dim}Supervisor is disabled.) \
	; exit 1
mk.super.pid/%: #; $(call log.base ${GLYPH_COMPOSE} ${@} ${sep} ${dim}Supervisor is disabled.)
	@# CMK_SUPERVISOR is 0; signals are disabled.
	@#
else
# Single source for supervisor-pid detection: the child make whose PPid is
# MAKE_SUPER (returns empty when MAKE_SUPER is unset/has no child). Inlined by
# both the pid query and the interrupt path so the hot interrupt path computes
# it in-process instead of paying a full sub-make re-parse.
_mk.super.pid.find=case "${OS_NAME}" in Darwin) ps -axo pid=,ppid=|awk -v me="$${MAKE_SUPER}" '$$2==me{print $$1}';; *) awk -v me="$${MAKE_SUPER}" 'FNR==1{n=split(FILENAME,a,"/"); p=a[n-1]} /^PPid:/{if($$2==me) print p}' /proc/[0-9]*/status 2>/dev/null || true;; esac
mk.super.pid:
	@# Returns the pid for the supervisor process which is responsible for trapping signals.
	@# See 'mk.interrupt' docs for more details.
	@#
	$(trace_maybe) \
	&& case $${MAKE_SUPER:-} in \
		"") (   header="" \
				&& $(call log.mk, $${header} ${red}Supervisor not found) \
				&& $(call log.mk, $${header} ${no_ansi_dim}MAKE_SUPER is not set by any wrapper) \
				&& $(call log.mk, $${header} ${dim}No pid to handle signals could be found.) \
				&& $(call log.mk, $${header} ${dim}Signal-handling is only supported for stand-alone mode.) \
				&& $(call log.mk, $${header} ${dim}Use 'compose.mk' instead of using 'make' directly?) \
			); exit 0; ;; \
		*) ${_mk.super.pid.find} ;; \
	esac

# mk.super.interrupt: signal the supervisor then self-kill, so greedy targets can consume the whole command line; without a supervisor wrapper the exit is always an error the caller must ignore.
mk.super.interrupt/% mk.interrupt/%:
	case $${CMK_SUPERVISOR} in \
		0) $(call log.trace, ${red}Supervisor disabled!); exit 0; ;; \
		*) \
			header="${GLYPH_MK} mk.interrupt ${sep}" \
			&& super=`${_mk.super.pid.find} || true` \
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
	
# _mk.super.bootloader: the supervisor's loader aggregator. The polyglot header sources only this, which
# sources each loader define; a loader shares the header's shell state (no subshell). Extension point: add
# a `define _mk.super.<name>` plus one load line here, no header edit needed. CMK_BOOTLOADER is a space-
# separated list of user loader refs (a file path or define name), sourced at boot before the trampoline
# runs the program; a loader may register an `EXIT` trap but must not trap INT/TERM. A missing ref is fatal.

# Supervisor stderr filter, authored as blocks (single source of truth). The bootloader is bash above
# make, so it can't see make's exports and reads these straight from source. Two stages: split breaks a
# `<content>make: *** [` line in two, then filter drops benign SIGPIPE `Broken pipe` noise, range-deletes
# the SIGINT self-kill noise, and dims the `make[N]: *** [..] Error M` cascade (already-dimmed inner lines
# start with ESC, so only the raw unwinding is dimmed). Both fflush() per line so a last message isn't lost.
#:phase SUPERVISOR seed=1 awklang=no placeholder=forbidden
define .awk.super.stderr.split
  { if (match($0, /make(\[[0-9]+\])?: \*\*\* \[/) && RSTART>1) { print substr($0,1,RSTART-1); print substr($0,RSTART) } else print; fflush() }
endef
#:phase SUPERVISOR seed=1 awklang=no placeholder=forbidden
define .awk.super.stderr.filter
  { _t=ENVIRON["CMK_TWIN_PATH"]; if (_t != "") { _s=ENVIRON["CMK_BIN"]; while (_i=index($0,_t)) $0 = substr($0,1,_i-1) _s substr($0,_i+length(_t)) } }
  /(write error|standard output): Broken pipe$/{next}   # benign SIGPIPE noise (see doc-block)
  /^make.*:.*mk.interrupt\/SIGINT.*Killed/{d=1} d{ if($0 ~ /^make:.*Error/) d=0; next } /^make(\[[0-9]+\])?: \*\*\* .*Interrupt *$/{ if(!intr){ printf "\033[93m\033[1m⚠\033[0m\033[93m interrupted\033[0m\n"; intr=1; fflush() } next } /^make(\[[0-9]+\])?: \*\*\* /{ printf "  \033[2m%s\033[0m\n", $0; fflush(); next } { print; fflush() }
endef
export _cmk_blk_super_split  := $(call lang.grammar.ctx.fill,$(value .awk.super.stderr.split))
export _cmk_blk_super_filter := $(call lang.grammar.ctx.fill,$(value .awk.super.stderr.filter))

define _mk.super.bootloader
# `_cmk_awk <name>` (extract a `define <name>..endef` body) and `_cmk_load <name>` (source it)
# are defined in the polyglot header, so they are in scope for both the header and this loader
# (and `_mk.super.tramp`, sourced below).
for _boot_ref in ${CMK_BOOTLOADER}; do
  case "${_boot_ref}" in
    @*:*) _file_goal="${_boot_ref#@}"; exec make -f "${_file_goal%%:*}" "${_file_goal#*:}" __argv__="${__argv__}" CMK_TRAMP_MK="${_make_}" ;;
    @*)   __argv__="${__argv__}" ${_make_} "${_boot_ref#@}" ;;
    *)    if [ -f "${_boot_ref}" ]; then source "${_boot_ref}";
          elif sed -n "/^define ${_boot_ref}\$/,/^endef/p" ${0} | grep -q .; then _cmk_load "${_boot_ref}";
          else printf 'compose.mk: CMK_BOOTLOADER ref not found (@file:goal, @target, file, or define): %s\n' "${_boot_ref}" >/dev/stderr; exit 1; fi ;;
  esac
done
# trampoline backend: convention @file:goal takeover, active-guarded.
_tramp="${CMK_TRAMPOLINE:-${CMK_PRAGMA_TRAMPOLINE:-}}"; _tramp_mk="${CMK_PLUGINS_DIR:-.cmk}/${_tramp}.loader.mk"
[ -n "${_tramp}" ] && [ -z "${CMK_TRAMPOLINE_ACTIVE:-}" ] && [ -f "${_tramp_mk}" ] && \
  CMK_TRAMPOLINE_ACTIVE=1 exec make -f "${_tramp_mk}" "${_tramp}.super.tramp" __argv__="${__argv__}" CMK_TRAMP_MK="${_make_}"
_cmk_load _cmk.prewarm.hosted
_cmk_load _mk.super.tramp
endef

# _mk.super.tramp: supervisor trampoline dispatch loop, sourced and run in the bootloader shell.
define _mk.super.tramp
# Goal-eval scheduler loop; register map and rationale in scratch/tramp-notes.md.
xfer=".tmp.cmk.mbox.${MAKE_SUPER}"; __ip__="${__argv__}"; __step__=0; __step_budget__="${CMK_TRAMPOLINE_MAX:-10000}"; __posix_code__=0
export CMK_SUPER_RESUME="${xfer}.resume"
rm -f -- "${xfer}" "${xfer}.post" "${xfer}.resume" 2>/dev/null || true
# In-file pre-hooks only exist after a parse, so the boot gate also probes the program source; the exit gate instead trusts the mbox flag the parsed main hop drops (covering exports, pragmas, and handle registrations alike).
_pre_f=""
grep -aqE '^[[:space:]]*export[[:space:]]+(CMK_PRAGMA_)?CMK_PRE[[:space:]]*(\+|:)?=' "${0}" 2>/dev/null && _pre_f=1
# Boot stage: unsupervised sub-make of cmk_pre gates the loop; failure skips it, at-exit still runs.
_pre_h="${CMK_PRE:-}"; [ "${_pre_h}" = flux.noop ] && _pre_h=""
if [ -n "${_pre_h}${CMK_PRAGMA_CMK_PRE:-}${_pre_f}" ]; then CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 CMK_SUPERVISOR=0 ${_make_} mk.super.boot; __posix_code__=$?; else __posix_code__=0; fi
[ "${__posix_code__}" = 0 ] || __ip__=""
while [ -n "${__ip__}" ]; do
  __step__=$((__step__+1))
  if [ "${__step__}" -gt "${__step_budget__}" ]; then printf 'compose.mk: trampoline hop limit %s exceeded\n' "${__step_budget__}" >/dev/stderr; __posix_code__=70; break; fi
  rm -f -- "${xfer}" 2>/dev/null || true
  # Stderr filter: split make-error line, drop interrupt noise; fflush per line avoids lost output.
  __ip__="${__ip__}" __alt__="${__alt__}" __yielded__="${__yielded__}" __step__="${__step__}" __step_budget__="${__step_budget__}" __posix_code__="${__posix_code__}" __exit_code__="${__exit_code__}" ${_make_} mk.super.enter/${MAKE_SUPER} ${__ip__} 2> >(awk -f <(_cmk_awk .awk.super.stderr.split) | awk -f <(_cmk_awk .awk.super.stderr.filter) >/dev/stderr)
  __posix_code__=$?
  # Router runs before fault-handling; transfer/resume/exit route first, fault is the fallthrough.
  if grep -q '^CONT=' "${xfer}" 2>/dev/null; then                              # transfer: hop yielded a goal
    __yielded__="$(sed -n 's/^CONT=//p' "${xfer}" | tail -1)"
    rm -f -- "${xfer}" ".tmp.mk.super.${MAKE_SUPER}" 2>/dev/null || true
    case ${CMK_DISABLE_HOOKS:-0} in
      0) __ip__="$(echo ${__yielded__} | awk -f <(_cmk_awk .awk.rewrite.targets.maybe))";;
      1) __ip__="${__yielded__}";;
    esac
    if [ "${CMK_SUPERVISOR_STEP_HOOK:-flux.noop}" != flux.noop ]; then CMK_STEP_INDEX=${__step__} CMK_STEP_CONT="${__ip__}" CMK_STEP_CODE=${__posix_code__} CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} ${CMK_SUPERVISOR_STEP_HOOK} || true; fi
  elif [ "${__posix_code__}" != 0 ] && [ -s "${CMK_SUPER_RESUME}" ]; then    # resume: a subsystem posted a backtrack point
    # Backtrack: the resume file names the subsystem's resolver; it answers the next untried alt, else terminate.
    _resume_h="$(head -1 "${CMK_SUPER_RESUME}" 2>/dev/null)"
    __alt__="$(CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} "${_resume_h}" 2>/dev/null)"
    if [ -n "${__alt__}" ]; then rm -f -- ".tmp.mk.super.${MAKE_SUPER}" 2>/dev/null || true; __ip__="${__alt__}"; __posix_code__=0; else __ip__=""; fi
  elif [ "${__posix_code__}" != 0 ] && [ -f ".tmp.mk.super.${MAKE_SUPER}" ]; then                # exit: intentional
    # Intentional exit: recipe saved its real code then interrupted; stop, resolve below, keep marker.
    __ip__=""
  else                                                                         # fault / done
    # Clean done or genuine fault (nonzero, no unwind marker); diagnose best-effort, runs last.
    [ "${__posix_code__}" = 0 ] || { CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 CMK_SUPERVISOR=0 faultgoals="${__ip__}" ${_make_} mk.super.fault || true; }
    __ip__=""
  fi
done
_post_h="${CMK_POST:-}"; [ "${_post_h}" = flux.noop ] && _post_h=""
{ [ -n "${_post_h}${CMK_PRAGMA_CMK_POST:-}" ] || [ -f "${xfer}.post" ]; } && CMK_DISABLE_HOOKS=1 CMK_INTERNAL=1 ${_make_} mk.super.exit/${__posix_code__} || true
# Value channel: a recipe's saved real code overrides the raw wait status of the last hop.
__exit_code__=${__posix_code__}
if [ -f .tmp.mk.super.${MAKE_SUPER} ]; then
  __marked__=`cat .tmp.mk.super.${MAKE_SUPER} 2>/dev/null`; rm -f .tmp.mk.super.${MAKE_SUPER}
  case "${__marked__}" in ''|*[!0-9]*) :;; *) __exit_code__=${__marked__};; esac
fi
# Sweep only core-owned run temps; subsystems reap their own via the at-exit idiom (see the vm plugin).
rm -f -- .tmp.cmk.brf.${MAKE_SUPER}.* "${xfer}" "${xfer}.post" "${xfer}.resume" 2>/dev/null || true
endef

# mk.super.enter: first hop of a supervised run; the argument is the supervisor wrapper pid, not the pid that mk.super.pid reports.
mk.super.enter/%:
	$(eval export MAKE_SUPER:=${*}) \
	$(call io.safe_rm,.tmp.mk.super.${*}) \
	&& { [ -z "$(strip $(filter-out flux.noop,$(__cmk_post__.targets)))" ] || : > .tmp.cmk.mbox.${*}.post ; } \
	&& $(call log.trace, ${GLYPH_MK} ${@} ${sep} ${red}started pid ${no_ansi}$${MAKE_SUPER})

mk.super.stderr.filter:; ${stream.stdin} | awk "$${_cmk_blk_super_split}" | awk "$${_cmk_blk_super_filter}"
	@# The supervisor's stderr filter, as a testable target (make-child transport of the same
	@# `.awk.super.stderr.*` blocks the bootloader source-reads): splits a run-together
	@# `<content>make: *** [` line, drops SIGINT self-kill noise, dims the make error cascade.

# mk.super.boot: the pre-pipeline handler stage, run once by the trampoline ahead of the dispatch loop; resolves env CMK_PRE plus its pragma twin, a failing handler skips the main pipeline, and the makefile gate keeps inherited env handlers from firing against bare compose.mk in the outer dispatch.
mk.super.boot:
	header="${GLYPH_MK} mk.super.boot ${sep}" \
	&& _pre="$(if $(filter %compose.mk,$(MAKEFILE)),flux.noop,$(strip $(__cmk_pre__.targets)))" \
	&& $(call log.trace, $${header} calling boot handlers: $${_pre}) \
	&& case "$${_pre}" in \
		flux.noop) : ;; \
		*) CMK_DISABLE_HOOKS=1 CMK_INTERNAL=0 ${make} $${_pre} ;; \
	esac

mk.super.fault:
	@# Core "root traceback handler": re-run a failed job's goals (faultgoals) under `make -n` to
	@# reproduce the error, classify it via `lang.runtime.classify_fault` (the same mechanism mk.validate uses),
	@# and present the typed fault -- delegating to the `fault.*` module when loaded, else a core
	@# default (themed `<Type>:` header + the raw error).  Compliant with the module contract
	@# (`.cmk/fault.cmk`) without depending on it -- so a direct `compose.mk <bad-goal>` reads the same
	@# as a `cmk run` fault.  Only static (make -n-reproducible) faults classify; others are inert.
	err=`${make} -n $${faultgoals} 2>&1 1>${devnull}` \
	; _type=`printf '%s\n' "$${err}" | ${lang.runtime.classify_fault}` \
	; [ -z "$${_type}" ] || $(if $(call m5.defined?,fault.throw),$(call fault.throw,$${_type}),{ printf '${red}%s:${no_ansi}\n' "$${_type}" >${stderr} ; printf '%s\n' "$${err}" | ${stream.as.log} ; }) \
	; true

# mk.super.exit: the at-exit handler stage (CMK_POST, gated on the makefile like the boot stage), always exiting zero because the wrapper delivers the real code from the supervisor mailbox; teardown on an external interrupt is a best-effort race between nested supervisors, see the supervisor-teardown-reaper-interrupt memory and the docstring-migration note in scratch for the full mechanics.
mk.super.exit/%:
	header="" \
	&& $(call log.trace, $${header} ${red} status=${*} ${sep} ${bold}pid=$${MAKE_SUPER}) \
	&& _post="$(if $(filter %compose.mk,$(MAKEFILE)),flux.noop,$(strip $(__cmk_post__.targets)))" \
	&& case "$${_post}" in \
		flux.noop) $(call log.trace, $${header} ${dim}no at-exit handlers ${sep} teardown clean) ;; \
		*) $(call log.mk, $${header} ${dim}at-exit teardown ${sep} ${no_ansi}$${_post}) \
		   && CMK_DISABLE_HOOKS=1 CMK_INTERNAL=0 ${make} $${_post} \
		   && $(call log.mk, $${header} ${green}✓ teardown clean ${sep} ${dim}$${_post}) ;; \
	esac \
	&& exit 0
	
mk.super.trap/%:
	@# Executed by the supervisor program when the given signal is trapped.
	@#
	header="${GLYPH_MK} mk.super.trap ${sep}" \
	&& $(call log.trace, $${header} ${red}${*} ${sep} ${dim}Supervisor trapped signal)


# BOOT PRAGMAS: `hooks`/`bootloader_disabled`/`bootloaders` are read pre-make by the bash header, so the
# generic CMK_PRAGMA_* injection can't reach them.  We scrape them from the compiled output and thread the
# canonical env into the program's re-exec (scalars: pragma wins + a loud notice; `bootloaders` appends).
# mk.super.boot.scalar(<KEY>,<ENVVAR>,<truthy-case-pat>,<on-match>,<else>,<label>).
mk.super.boot.scalar=_v=$$(cat $${tmpf} | $(call __pragma__.sh,$(1))) ; if [ -n "$${_v}" ]; then case "$${_v}" in $(3)) _o="$(4)";; *) _o="$(5)";; esac ; $(call log.io, ${yellow}cmk run ${sep}${no_ansi} pragma $(6)=$${_v} ${sep} sets $(2)=$${_o} (overrides env/default)${no_ansi}) ; export $(2)="$${_o}" ; fi
# mk.super.boot.bootloaders -- the LIST knob: APPEND the pragma's loaders to any invoker CMK_BOOTLOADER.
mk.super.boot.bootloaders=_v=$$(cat $${tmpf} | $(call __pragma__.sh,BOOTLOADERS)) ; if [ -n "$${_v}" ]; then _bl="$${CMK_BOOTLOADER:-} $${_v}" ; export CMK_BOOTLOADER="$${_bl\# }" ; $(call log.io, ${dim}cmk run ${sep}${no_ansi_dim} sourcing bootloaders via pragma ${sep} ${no_ansi}$${_v}) ; fi
# mk.super.boot.thread -- apply all three boot pragmas.
mk.super.boot.thread={ $(call mk.super.boot.scalar,HOOKS,CMK_DISABLE_HOOKS,off|false|0|no|OFF|FALSE|NO,1,0,hooks) ; $(call mk.super.boot.scalar,BOOTLOADER_DISABLED,CMK_BOOTLOADER_DISABLED,""|0|off|false|no,,1,bootloader_disabled) ; $(call mk.super.boot.bootloaders) ; }

# mk.super.tramp: the supervisor's trampoline transfer primitive -- the engine the VM's control-transfer
# verbs fire into. Unlike `mk.yield` (which evals the continuation inline, so jumps nest makes), it writes
# the next goals to the supervisor mailbox and interrupts, so the dispatch loop re-runs them flat at top
# level. Atomic mailbox write (temp+mv); fires the yield hook. A transferring recipe must not also exit terminally.
# _mk.interrupt.fast: a cheaper interrupt for the trampoline hot path. The full interrupt re-parses the
# whole combined makefile to send one signal -- paid per hop, ~40x costlier on make 4.4. This runs the
# same interrupt recipe from a 2-line standalone makefile, keeping the `... Killed` marker the stderr
# filter keys on; the resolved child PID lets the tiny form skip pid-find.
_mk.interrupt.tiny=mk.interrupt/%:\n\t@{ [ -n "$$CMK_INT_SUPER" ] && kill -$* $$CMK_INT_SUPER 2>/dev/null; } ; kill -KILL $$$$\n
_mk.interrupt.fast=_super=`${_mk.super.pid.find} 2>/dev/null` ; CMK_INTERNAL=1 CMK_INT_SUPER="$${_super}" ${MAKE} -f <(printf '%b' '$(value _mk.interrupt.tiny)') mk.interrupt/SIGINT
define mk.super.tramp
	header="${GLYPH_MK} mk.super.tramp ${sep}${dim}" \
	&& cont_to="$(if $(filter undefined,$(origin 1)),,$(1))" \
	&& $(call log.trace, $${header} transfer:${dim_cyan} $(call strip, $${cont_to})) \
	&& ( export CMK_YIELD_TARGET="$${cont_to}"; $(CMK_YIELD_HOOK) || true ) \
	&& printf 'CONT=%s\n' "$${cont_to}" > .tmp.cmk.mbox.$${MAKE_SUPER}.tmp \
	&& mv -f .tmp.cmk.mbox.$${MAKE_SUPER}.tmp .tmp.cmk.mbox.$${MAKE_SUPER} \
	; ${_mk.interrupt.fast}
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mk.targets.simple/%:; $(call __targets__,${*}) | grep -v '%$$'
	@# Returns only local targets from the given file, 
	@# excluding parametric targets, and ignoring included targets.

mk.targets.filter/%:
	@# Lists all targets in the given namespace, filtering them by the given pattern.
	@# Simple, pipe-friendly output.  
	@# WARNING:  Callers must anticipate parametric targets with percent-signs, i.e. "foo.bar/%"
	@#
	@# USAGE: ./compose.mk mk.targets.filter/<namespace>
	@#
	${trace_maybe} && pattern="${*}" && pattern="$${pattern//./[.]}" \
	&& $(call __targets__,$${path:-${MAKEFILE}}) | grep ^$${pattern}

mk.targets.parametric:; $(call __targets__.parametric,$${path:-${MAKEFILE}})
	@# This finds only the parametric targets in the current namespace.
	@#
	@# Note that targets like 'foo/%:' are automatically converted to simply 'foo', 
	@# which makes this friendly for use with stuff like `flux.starmap`, etc.
	@#

mk.targets.filter.parametric/%:
	@# Filters all parametric targets by the given pattern.
	pattern="`printf ${*}|sed 's/\./[.]/g'`" \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.base.part1, ${GLYPH_IO} mk.targets.filter.parametric ${sep} matching \'$${pattern}\') || true) \
	&& targets="$$($(call __targets__.parametric,$${path:-${MAKEFILE}}) | grep "^$${pattern}" || true)" \
	&& count=`printf '%s\n' "$${targets}"|${stream.count.lines}` \
	&& ([ "$${quiet:-0}" == 1 ] && $(call log.base.part2, ${yellow}$${count}${no_ansi_dim} total) || true ) \
	&& printf '%s\n' "$${targets}"

mk.validate=_vf="$(1)" \
	&& $(call log.compiler.part1, mk.validate) \
	&& err=`make -n -f $${_vf} $${goals:-} 2>&1 1>/dev/null` \
	; case $$? in \
		0) $(call log.compiler.part2, $${_vf} ${GLYPH_CHECK});; \
		[1-9]*) ( orig="$${__interpreting__:-$${_vf}}" ; \
			$(call log.part1, $${orig}) ; $(call log.base.part2, ${red}failed) ; \
			$(call log, $${orig} ${sep} ERR:) ; \
			printf '\n' >${stderr} ; \
			_type=`printf '%s\n' "$${err}" | ${lang.runtime.classify_fault}` ; \
			printf '${red}%s:${no_ansi_dim}\n' "$${_type:-ValidationError}" >${stderr} ; \
			printf '%s\n' "$${err}" | ${stream.as.log} ; \
			$(if $(filter 0,$(__hosted__.enabled)),printf '${yellow}note: seed-only mode (CMK_LANG=0) is active -- hosted-partition constructs (dsl / machine / import / protocol) are unavailable and pass through unlowered.${no_ansi}\n' >${stderr} ;) \
			if [ "$${orig}" != "$${_vf}" ]; then \
				_frames=`printf '%s\n' "$${err}" | awk -v tb="$${_vf\#\#*/}" -v src="$${orig}" -v red="$$(printf '${red}')" -v dim="$$(printf '${no_ansi_dim}')" "$${_awklang_trace_remap}" /dev/stdin "$${orig}" "$${_vf}" 2>/dev/null` ; \
				[ -z "$${_frames}" ] || { printf '\n${red}source:${no_ansi_dim}\n' >${stderr} ; printf '%s\n' "$${_frames}" | ${stream.as.log} ; } ; \
			fi ; \
			__interpreting__="$${orig}" ${make} lang.lint.deep/- || true ; \
				_c=`printf '%s\n' "$${err}" | grep -oE 'code=[0-9]+' | head -1 | cut -d= -f2` ; { [ -z "$${_c}" ] || [ -z "$${MAKE_SUPER}" ] || echo "$${_c}" > .tmp.mk.super.$${MAKE_SUPER} ; } ; exit 39);; \
	esac

mk.validate: mk.validate//dev/stdin
	@# Validates whether the input stream is legal Makefile
mk.validate/%:
	@# Validate the given Makefile (using `make -n`).  This is the compile GATE: `mk.compile` is
	@# permissive (it lowers, it does not vet), so a program is "legal" iff it parses here.  The
	@# quiet-on-success/loud-on-failure policy also lives here -- the success line is compiler
	@# chatter (gated by CMK_COMPILER_VERBOSE), while the failure branch always speaks.
	@# On failure it also fires the best-effort deep-lint post-mortem (`lang.lint.deep`; never
	@# masks the underlying error).  The body lives in the macro twin above; compile-phase
	@# call sites use the macro directly, and this target is the CLI/dispatch face.
	$(call mk.validate,${*})

mk.vars=echo "${.VARIABLES}" | tr ' ' '\n' | sort
mk.vars:; ${mk.vars}
	@# Lists all the variables known to Make, including local or 
	@# inherited env-vars, make-vars, make-defines etc. 
	@# This target is also available as a macro.

mk.vars.filter/%:; (${mk.vars} | grep ${*}) || true
	@# Filter output of `mk.vars` with the given pattern.
	@# Non-strict; no error in case of no-match.

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.lint :: The CMK source linter, in two tiers
##
## The linter for user programs, in two cost/trigger tiers. `preflight` is cheap and
## always-on, riding the compiler (namespace/shadow checks in the receivers stage plus
## `lang.lint.source` hygiene), so it stays a compiler stage. `deep` is expensive and runs on demand
## (`cmk lint`) or as a post-mortem when `mk.validate` fails; it is currently a wired stub extension
## point. The framework self-audit (compose.mk auditing its own source) is project dev-tooling, not
## core: it moved to `.automation.cmk` as `lint.self` (+ `.collisions` / `.phase`).
##
## `lang.lint.source` is the hygiene deferral point the `cmk` entrypoints call; it chains them:
## an exists-guard (the one hard failure) plus soft notes (silenced by CMK_COMPILER_VERBOSE=0) for a
## non-`.cmk` extension, a missing `__main__`/`repl` entrypoint, an overwrite, and a raw self-var
## read. The `-` sentinel (stdin) is always valid.
##
## `lang.lint.divergent` (below) is the curated set of intentionally-diverging twins the receivers
## shadow-lint classifies against; it stays in core because that compiler stage consumes it.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
lang.lint.exists=case "$(1)" in -) true;; *) [ -f "$(1)" ] || { $(call log.io, ${red}cmk ${sep}${no_ansi} no such file${no_ansi_dim}: ${no_ansi}${underline}$(1)${no_ansi}); exit 1; };; esac
lang.lint.ext=case "$(1)" in *.cmk|-) true;; *) [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} note: ${no_ansi}${underline}$(1)${no_ansi_dim} has no .cmk extension);; esac
lang.lint.output=([ -e "$(1)" ] && { [ "${CMK_COMPILER_VERBOSE}" == "0" ] && true || $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} overwriting ${no_ansi}${underline}$(1)); } || true)
lang.lint.entrypoint=case "$(1)" in \
	-) true;; \
	*) if [ "${CMK_COMPILER_VERBOSE}" != "0" ] && ! grep -qsE '$(lang.main.re)' "$(1)" && ! grep -qsE 'cmk_pragma.*"repl"' "$(1)"; then $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} note: ${no_ansi}${underline}$(1)${no_ansi_dim} declares no __main__ entrypoint); fi;; \
	esac
lang.lint.selfref=case "$(1)" in \
	-) true;; \
	*) if [ "${CMK_COMPILER_VERBOSE}" != "0" ] && grep -qsF '$$(self)' "$(1)"; then $(call log.io, ${yellow}cmk ${sep}${no_ansi_dim} note: ${no_ansi}${underline}$(1)${no_ansi_dim} reads the raw self variable at recipe time ${sep}${no_ansi_dim} unreliable across prerequisites${comma} reference members through the instance); fi;; \
	esac
lang.lint.source=$(call lang.lint.exists,$(1)) && $(call lang.lint.ext,$(1)) && $(call lang.lint.entrypoint,$(1)) && $(call lang.lint.selfref,$(1))

# Reverse source-map for a dry-run/interpret failure: make blames the compiled temp (meaningless to
# the author), but compiler-emitted anchors let a blamed line be traced back to the CMK source.
#:phase SEED-PARSE seed=1 awklang=no
define .awk.trace.remap
  # Self-contained: reads make's stderr (`tb`=temp basename), the `src`, then the temp -- one pass
  # each.  Anchors are STRUCTURAL, not grammar keywords: a compiled line names its construct via a
  # `def=<name>` ctor arg, a `define <name>`, or a `<name>:` header; source indexed likewise.
  function tok(s) { sub(/^[ \t]+/, "", s); sub(/[^A-Za-z0-9_.].*/, "", s); return s }
  function lookup(nm,   h) {   # source line declaring NAME (or its leading path segment), else ""
    if (nm in DECL) return DECL[nm]; if (nm in TGT) return TGT[nm]
    h = nm; sub(/[.\/%].*/, "", h)
    if (h in DECL) return DECL[h]; if (h in TGT) return TGT[h]
    return "" }
  function anchor(t,   s) {    # the construct a compiled line names
    if (match(t, /def=[A-Za-z_][A-Za-z0-9_.]*/)) return substr(t, RSTART + 4, RLENGTH - 4)
    if (match(t, /^[ \t]*define[ \t]+/)) return tok(substr(t, RSTART + RLENGTH))
    if (match(t, /^[A-Za-z_][A-Za-z0-9_.\/%-]*[ \t]*:/)) { s = t; sub(/[ \t]*:.*/, "", s); return tok(s) }
    return "" }
  FNR == 1 { pass++ }
  pass == 1 {   # make's stderr: blamed temp lines + missing-target names
    if (match($0, tb ":[0-9]+")) { s = substr($0, RSTART, RLENGTH); sub(/^.*:/, "", s); WANT[s + 0] = 1 }
    if (index($0, "No rule to make target") && split($0, Q, sprintf("%c", 39)) >= 2) NORULE[Q[2]] = 1
    next }
  pass == 2 {   # CMK source: index each declared name and target header to its line
    nm = ""
    if (match($0, /[([{]\|/)) { h = $0; sub(/^[ \t]+/, "", h); sub(/^[A-Za-z_][A-Za-z0-9_.]*[ \t]+/, "", h); nm = tok(h) }
    if (nm == "" && match($0, /^[ \t]*[A-Za-z_][A-Za-z0-9_.]*[ \t]*(:=|<-|=)/)) nm = tok($0)
    if (nm != "" && !(nm in DECL)) DECL[nm] = FNR
    if (match($0, /^[A-Za-z_][A-Za-z0-9_.\/%-]*[ \t]*:/)) { s = $0; sub(/[ \t]*:.*/, "", s); s = tok(s); if (!(s in TGT)) TGT[s] = FNR }
    next }
  FNR in WANT { TMP[FNR] = $0 }   # pass 3: the compiled temp -- keep the blamed lines
  END {
    for (ln in TMP) { nm = anchor(TMP[ln]); w = lookup(nm); if (w != "") FR[w] = src ":" w ": in " red nm dim }
    for (nm in NORULE) { w = lookup(nm); if (w != "") FR[w] = src ":" w ": target " red nm dim }
    for (w in FR) print FR[w] }
endef
$(call lang.awk.export, main=.awk.trace.remap as=trace_remap)

lang.lint.deep/%:
	@# Deep user-program lint over the target's args.  Stub: no deep checks yet (wired extension point).
	@[ "$${TRACE:-0}" = 1 ] && $(call log.io, ${dim}lang.lint.deep ${sep}${no_ansi_dim} stub -- no deep checks yet ${sep} ${no_ansi_dim}$${*}) || true
lang.lint.deep:; ${make} lang.lint.deep/-
	@# Bare form: deep-lint stdin (`-`).

# Curated-divergent twins: intentionally-diverging, must not be smart-routed as pure stand-ins
# (arg-shape mismatch, impure `exit`, a path var). The collisions lint classifies against it;
# the receivers stage is threaded it so a compile-time send to a divergent opened member warns.
lang.lint.divergent=io.env io.env.log mk.exit.code stage.file
# Predicate: non-empty iff the named twin is curated-divergent.
lang.lint.divergent.p=$(strip $(filter $(m5[1]),${lang.lint.divergent}))

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: mk.unpack :: Argument unpackers for make macros
##
## Pull positional, comma-variadic, and k=v args out of a call or a target
## stem; fork-lean and parse-time-safe.
##
## * mk.unpack.any :: Field N (or N-) of the target stem by a delimiter (+ default)
## * mk.unpack.arg :: The comma-fixed case of mk.unpack.any
## * m5.__nargs__ :: Normalize a variadic call to one comma string (a,b,c)
## * mk.unpack.args :: Bind named positional args (up to 20) from a comma stem
##
## * mk.unpack.kwargs :: Read / bind kwargs, two forms.
##     single (`<args>, name[, default]`) binds one kwargs_<name>; batch
##     (`<args>, n1 n2=def n3='sp ace'`) binds several left-to-right.  Quote-aware
##     (via m5.ctx?), fork-free.  Private: .batch / .tokenize / .bind / .one.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
mk.unpack.any=$(or $(if $(findstring $(m5[2]),${*}),$(if $(filter %-,$(m5[1])),$(subst $(space),$(m5[2]),$(wordlist $(patsubst %-,%,$(m5[1])),$(words $(subst $(m5[2]),$(space),${*})),$(subst $(m5[2]),$(space),${*}))),$(word $(m5[1]),$(subst $(m5[2]),$(space),${*})))),$(m5[3]?))

mk.unpack.arg=$(call mk.unpack.any,${1},$(comma),$(m5[2]?))

m5.__nargs__=$(subst $(space),,$(if $(filter-out undefined,$(origin 1)),$(1))$(foreach _n,2 3 4 5 6 7 8 9 10 11 12,$(if $(call m5.defined?,$(_n)),$(if $(strip $($(_n))),$(comma)$(strip $($(_n)))))))

mk.unpack.args = $(foreach _i,$(wordlist 1,$(words $(m5[1])),1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20),$(word $(_i),$(m5[1]))=$(if $(filter $(_i),$(words $(m5[1]))),$(subst $(space),$(comma),$(wordlist $(_i),$(words $(subst $(comma),$(space),${*})),$(subst $(comma),$(space),${*}))),$(word $(_i),$(subst $(comma),$(space),${*}))))

define mk.unpack.kwargs
$(if $(or $(call m5.lex.kwarg?,$(m5[2])),$(word 2,$(m5[2]))),$(call _mk.unpack.kwargs.batch,$(m5[1]),$(m5[2])),$(if $(filter-out undefined,$(origin 3)),$(call _mk.unpack.kwargs.one,$(m5[1]),$(m5[2]),$(m5[3])),$(call _mk.unpack.kwargs.batch,$(m5[1]),$(m5[2]))))
endef

define _mk.unpack.kwargs.batch
$(foreach _kwtok,$(call _mk.unpack.kwargs.tokenize,${2}),$(call _mk.unpack.kwargs.bind,${1},$(_kwtok)))
endef

_mk.unpack.kwargs.tokenize=$(call m5.lex.qnorm,${1})

_mk.unpack.kwargs.bind=$(if $(call m5.lex.kwarg?,${2}),$(call _mk.unpack.kwargs.one,${1},$(word 1,$(subst =,${space},${2})),$(subst «qk.s»,${space},$(patsubst $(word 1,$(subst =,${space},${2}))=%,%,${2}))),$(call _mk.unpack.kwargs.one,${1},${2}))

define _mk.unpack.kwargs.one
$(eval _kwargs_dupes:=$(filter $(strip ${2})=%,${1}))
$(if $(filter-out 0 1,$(words ${_kwargs_dupes})),$(shell $(call log.mk, ${red}mk.unpack.kwargs ${sep}${no_ansi} duplicate kwarg ${bold}$(strip ${2})${no_ansi}${dim} = ${no_ansi}${_kwargs_dupes}$(if $(strip ${@}),${dim} ${sep} in ${no_ansi}${@})))$(call mk.error, mk.unpack.kwargs: duplicate kwarg '$(strip ${2})' (${_kwargs_dupes})$(if $(strip ${@}), in '${@}'), errno=DUPLICATE_KWARG))
$(eval _kwargs_value:=$$(or $$(call m5.ctx?,${1},${2}),$(m5[3]?)))
$(eval $(if ! $(or $(strip $(_kwargs_value)),$(filter undefined,$(origin 3)),,${3}),\
	export kwargs_$(strip ${2})=$(_kwargs_value),
	$(call mk.error, `mk.unpack.kwargs` expected parameter '$(strip ${2})'$(comma) extracted `$(_kwargs_value)` and no default value was provided.  Input: `$(m5[1])`, errno=KWARG_MISSING)))
endef

define _mk.unpack.kwargs
export _kwargs_value="$(or $(call m5.ctx?,${1},${2}),$(m5[3]?))" \
&& $(if ! $(or $(strip $${_kwargs_value}),$(filter undefined,$(origin 3)),,${3}),\
	export $(strip ${2})="$${_kwargs_value}",false)
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# _mk.forward.args -- the arg-forwarding suffix for a macro twin (`NAME=${make} NAME${_mk.forward.args}`).
# A naive `${make} NAME` drops a smart-routed call's args; this forwards them, but only on a
# genuine self-call: the `$(0)` guard fires only when `$(0)` is a self-trampoline, so a bare
# `${NAME}/stem` leaves the stem byte-unchanged.
_mk.forward.args=$(if $(strip $(m5.__nargs__)),$(if $(findstring make} $(0),$(value $(0))),/$(m5.__nargs__)))

# mk.yield -- transfer control to a target, firing the optional yield-hook seam (jump target exported)
# so an external reflection / control-stack layer can observe every yield without core knowing about it.
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
# With no supervisor (CMK_SUPERVISOR=0 -- e.g. a nested `cli.subcommands.enter` dispatched via
# `_cli.subcommands.make`), there is nothing to signal: `mk.interrupt` would just log "Supervisor
# is disabled" and exit 1 (noise + a spurious error).  So we skip it and propagate `rc` directly;
# the real top-level yield still fires its own interrupt to unwind the whole stack once.

mk.exit.code/%:; [ -z "$${MAKE_SUPER}" ] || echo "${*}" > .tmp.mk.super.$${MAKE_SUPER} ; exit ${*}
	@# Records an EXACT process exit-code, then fails so the make stack unwinds
	@# NORMALLY (flux.*.finally / cleanup arms still run).  The bash supervisor
	@# wrapper reads it out-of-band and the top-level `./compose.mk` exits with <N>.
	@# Requires CMK_SUPERVISOR=1 (no out-of-band channel without it; degrades to the
	@# usual make exit 2).  Contrast `mk.yield`, which short-circuits via signal and
	@# SKIPS intermediate finally arms.
	@#
	@# USAGE: ... || make mk.exit.code/42      (or the `mk.exit.code` macro form, inline)
	@#

# Macro form of `mk.exit.code/<N>` for inline use inside other recipes.
mk.exit.code=([ -z "$${MAKE_SUPER}" ] || echo "${1}" > .tmp.mk.super.$${MAKE_SUPER}) ; exit ${1}

#░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

mk.exit.clear:; @[ -z "$${MAKE_SUPER}" ] || $(call io.safe_rm,.tmp.mk.super.$${MAKE_SUPER})
	@# Retracts any pending exact exit-code recorded by `mk.exit.code` (drops the
	@# supervisor pidfile).  Custom handlers that SWALLOW a failure (e.g. `|| true`)
	@# and intend to succeed must call this, else the recorded code still reaches the
	@# top-level process.  `flux.try.except.finally` calls it automatically when its
	@# `except` arm recovers, so this is only for hand-rolled error handling.
	@#
	@# USAGE: ... || { make this.thing.handled ; make mk.exit.clear ; }
	@#        (or the `mk.exit.clear` macro form, inline)

# Macro form of `mk.exit.clear` for inline use inside other recipes.
mk.exit.clear=([ -z "$${MAKE_SUPER}" ] || $(call io.safe_rm,.tmp.mk.super.$${MAKE_SUPER}))

# mk.errno: curated symbol to exit-code table (default 1).
$(call m5.table, mk.errno, GENERIC=1 ENVVAR_UNSET=39 MODULE_MISSING=66 MODULE_ARGS=64 INCLUDE_MISSING=66 IMPORT_NOT_FOUND=66 DUPLICATE_KWARG=64 REGISTRY_ASSERT=70 NOT_IMPLEMENTED=70 GRAMMAR=65 IMPORT_DEF=66 IMPORT_TARGET=66 IMPORT_SYNTAX=64 NO_FORMATTER=69 KWARG_MISSING=64 BIND_ARGS=64 NOT_CALLABLE=70 NOT_RUNNABLE=70 CLASS_DECL=65 MODULE_MEMBER=65 DSL_BACKING=70, 1)
# mk.error: expansion-time root emitter (thin error wrapper, errno=).
mk.error = $(eval _mkerr_sym := $(patsubst errno=%,%,$(m5[2]?)))$(eval _mkerr_code := $(call mk.errno.resolve,$(_mkerr_sym),1))$(eval _mkerr_meta := $(strip $(m5[3]?) $(m5[4]?) $(m5[5]?) $(m5[6]?)))$(error cmk-fault errno=$(_mkerr_sym) code=$(_mkerr_code) :: $(strip $(m5[1]))$(if $(_mkerr_meta), :: $(_mkerr_meta)))
# mk.die: recipe-time twin; themed line + exact exit code.
mk.die = $(call log.mk, ${red}${bold}error${no_ansi} ${sep}${dim} $(patsubst errno=%,%,$(m5[2]?)) ${no_ansi}${sep} $(strip $(m5[1]))) ; $(call mk.exit.code,$(call mk.errno.resolve,$(patsubst errno=%,%,$(m5[2]?)),1))

# __supervisor__.*: stable accessors over the core supervisor's identity + lifecycle, so
# callers (e.g. flux.pool) depend on this surface instead of poking MAKE_SUPER /
# _mk.super.pid.find directly.  Thin wrappers -- no reimplementation.
__supervisor__.run_id    = ${_mk.run.id}
__supervisor__.pid       = $${MAKE_SUPER}
# Recipe-context shell snippet: PIDs of this supervisor's children (portable; no pgrep).
__supervisor__.children  = ${_mk.super.pid.find}
# Recipe-context shell snippet: portably TERM those children (no-op without a supervisor).
__supervisor__.reap      = ${_mk.super.pid.find} | xargs -I% kill -TERM % 2>/dev/null || true
# Inline macro forms of the exact-exit-code channel (wrap the existing recipes/macros).
__supervisor__.exit_code  = $(call mk.exit.code,${1})
__supervisor__.exit_clear = $(call mk.exit.clear)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: flux.* :: A miniature workflow library
##
## Combining flux with container dispatch is similar in spirit to declarative
## pipelines in Jenkins, but simpler, more portable, and easier to use.
##
## What's a workflow in this context? Shell alone covers "process algebra"
## with operators like `&&`, `||`, `|` in the grand unix tradition, and adding
## `make` to the mix already provides DAGs.  What `flux.*` adds is
## *flow-control constructs* and *higher-level join/loop/map* instructions
## over other make-targets, taking inspiration from functional programming and
## threading libraries.  Alternatively, think of flux as a programming
## language whose primitives are the objects make understands: targets,
## defines, and variables.  Every target in `make` is a DAG, so task-DAGs are
## also primitives; `compose.import` maps containers onto targets, so
## containers are primitives too; `tux` targets map targets onto TUI panes, so
## UI elements are effectively primitives as well.
##
## Flux targets are mostly used programmatically for scripting, but in
## stand-alone mode they can help clean up (external) bash scripts, port bash
## to makefiles, or support ad-hoc interactive scripting.
##
## For parts more specific to shell code see `flux.*.sh`; for working with
## scripts see `flux.*.script`.
##
## DOCS:
## * `[1]:` [Main API](https://robot-wranglers.github.io/compose.mk/api#api-flux)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░


FLUX_POLL_DELTA?=5
define _flux.always
	@# NB: Used in 'flux.always' and 'flux.finally'.  For reasons related to ONESHELL,
	@# this code cannot be target-chained and to make it reusable, it needs to be embedded.
	@#
	printf "${GLYPH_FLUX} flux.always${no_ansi_dim} ${sep} registering target: ${green}${*}${no_ansi}\n" >${stderr}
	target="${*}" pid="$${PPID}" ${make} .flux.always.bg &
endef

# A constructor for (binary) partials.
# See demos/partial.mk for example usage.
__flux.partial__=$(eval $(m5[1])/%:; ${make} $(m5[2])/$(m5[3]),$${*})

flux.apply.later/%:
	@# Applies the given (unary) target at some point in the future.  This is non-blocking.
	@# Low-level slash-form primitive; see `flux.delay` for the comma/callform/N-target twin.
	@# Not pipe-safe, because since targets run in the background, this can garble your display!
	@#
	@# USAGE:
	@#   ./compose.mk flux.apply.later/<seconds>/<target>
	@#
	time=$(call m5.__args__,1,/) \
	&& target=$(call m5.__args__,2-,/) \
	cmd="${make} $${target}" \
		${make} flux.apply.later.sh/$${time}

# flux.delay(<seconds>,<t1>,...,<tn>): non-BLOCKING -- schedule the targets to run after
# <seconds> in the background (the async counterpart to the blocking form).  Macro-first twin (like
# the worker-pool): the `flux.delay/%` target is a thin wrapper, so `cmk.flux.delay(...)` is an
# inline callform.  Accepts both the callform's N comma-split args and the target's single
# comma-stem.  Not pipe-safe (background output can garble display).
flux.delay=( spec="$(m5.__nargs__)" \
	&& secs=`printf '%s' "$${spec}" | cut -d, -f1` \
	&& targets=`printf '%s' "$${spec}" | cut -s -d, -f2-` \
	&& target="$${targets}" cmd="${make} flux.and/$${targets}" ${make} flux.apply.later.sh/$${secs} )

# QUARANTINE
flux.ok:
	@# Alias for 'exit 0', which is success.
	@# This is mostly for used for testing other pipelines.
	@#
	@# See also `flux.fail`
	@#
	$(call log.flux, ${no_ansi}succeeding as requested!) \
	&& exit 0

# flux.after(<seconds>,<t1>,...,<tn>): BLOCKING -- sleep <seconds>, then run
# the targets in the FOREGROUND.  Synchronous counterpart to the background form;
# pipe-safe and ordered.  Macro-first twin so `cmk.flux.after(...)` works
# inline.  Targets may carry their own `/`-args (the COMMA is the field separator).
flux.after=( spec="$(m5.__nargs__)" \
	&& secs=`printf '%s' "$${spec}" | cut -d, -f1` \
	&& targets=`printf '%s' "$${spec}" | cut -s -d, -f2-` \
	&& ${make} io.wait/$${secs} && ${make} flux.and/$${targets} )

flux.apply.later.sh/%:
	@# Applies the given command at some point in the future.  This is non-blocking.
	@# Not pipe-safe since targets run in the background, this can garble your display!
	@#
	@# USAGE:
	@#   cmd="..." ./compose.mk flux.apply.later.sh/<seconds>
	@#
	header="${dim_green}$${target} ${sep}" \
	&& time=$(call m5.__args__,1,/) \
	&& ([ -z "$${quiet:-}" ] && true || $(call log.flux, after ${yellow}$${time}s)) \
	&& ( \
		$(call log.flux, $${header} ${dim_cyan}callback scheduled for ${yellow}$${time}s) \
		&& ${make} io.wait/$${time} \
		&& $(call log.flux, $${header} ${dim}callback triggered after ${yellow}$${time}s) && $${cmd:-true} \
	)&

flux.pipe.fork=${make} flux.pipe.fork${_mk.forward.args}
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
	@# available as a macro.  The named target must be parametric so it
	@# can accept the argument that is passed through!
	@#
	@# USAGE:
	@#
	@#  printf 'one\ntwo' | ./compose.mk flux.each/flux.echo
	@#
	 ${stream.space.to.nl} | ${stream.peek.summary} \
	| xargs -I% sh ${dash_x_maybe} -c "${make} ${*}/% || exit 255"
flux.each=${make} flux.each${_mk.forward.args}

flux.each.json/%:
	@# Given a target, treats each part of the nl-delimited input stream as arguments,
	@# returning JSON-ouput of `{key: target(key), .. }`
	@# USAGE:
	@#   ls *.md | make flux.each.json/flux.echo
	$(call log, mapping key -> ${dim_cyan}${*}${no_ansi_dim}(key))
	${stream.peek.summary} \
	| xargs -I {} bash ${dash_x_maybe} -c 'echo "{\"{}\": $$(${make} ${*}/{})}"'

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

_sh.obliviate=${1} 2>/dev/null > /dev/null

flux.NIY:; $(call log, ${red}Target Not Implemented Yet); exit 1
	@# Shorthand for "not implemented yet".  Exits immediately as failure.

# flux.or(<t1>,..,<tN>): first-success OR, the canonical impl -- a macro-first twin so
# cmk.flux.or(..) is an inline callform with no dispatcher fork.  Comma -> ` || ${make} `.
flux.or=${make} $(subst $(comma), || ${make} ,$(m5.__nargs__))
flux.any=$(call flux.or,$(m5.__nargs__))
flux.or/% flux.any/%:; $(call flux.or,${*})
	@# Performs an 'or' operation with the named comma-delimited targets.
	@# This is equivalent to 'make target1 || .. || make targetN'.  See also 'flux.and'.
	@# Thin wrapper over the `flux.or` macro (also `cmk.flux.or(..)`).
	@#
	@# USAGE: (generic)
	@#   ./compose.mk flux.or/<t1>,<t2>,..
	@#
	@# USAGE: (example)
	@#   ./compose.mk flux.or/flux.fail,flux.ok
	@#

# flux.pool -- bounded streaming worker-pool shell snippet, the canonical impl (the target wrapper is
# thin, so the callform is inline and efficient). Accepts both the callform's N comma-split args and a
# single comma-string. Runs the targets with at most <size> concurrent workers via `xargs -P`, fail-fast:
# a worker exiting nonzero exits 255, so xargs stops launching new work. No at-exit reaper -- `xargs -P`
# already waits for every worker, and a backgrounded grandchild orphans to init anyway.
flux.pool=( spec="$(m5.__nargs__)" \
	&& size=`printf '%s' "$${spec}" | cut -d, -f1` \
	&& targets=`printf '%s' "$${spec}" | cut -s -d, -f2-` \
	&& $(call log.flux, flux.pool ${sep} ${dim}size=${cyan}$${size}${no_ansi_dim} ${sep} ${dim}$${targets}) \
	&& printf '%s' "$${targets}" | ${stream.comma.to.nl} \
	| xargs -P $${size} -I% sh ${dash_x_maybe} -c "${make} % || exit 255" )


# flux.pool.bounded -- the jobserver variant of the worker-pool. Same comma signature and macro/target
# twin, but runs the targets under `make --jobs <n>` instead of `xargs -P`. The crucial difference: `--jobs`
# bounds the global recursion budget (the jobserver is shared with every sub-make in the DAG), so the cap
# is on total concurrent work, not <n> top-level workers -- a worker that itself recurses competes for the
# same tokens. Noisy (jobserver warnings, filtered here); use `flux.pool` for a true bounded worker pool.
flux.pool.bounded=( spec="$(m5.__nargs__)" \
	&& n=`printf '%s' "$${spec}" | cut -d, -f1` \
	&& targets=`printf '%s' "$${spec}" | cut -s -d, -f2- | ${stream.comma.to.space}` \
	&& $(call log.flux, flux.pool.bounded ${sep} ${dim}jobs=${cyan}$${n}${no_ansi_dim} ${sep} ${dim}$${targets}) \
	&& ${make} --jobs $${n} $${targets} \
		2> >(grep -v "resetting jobserver mode" | grep -v "warning: jobserver unavailable") )



# flux.retry -- run a shell command repeatedly until it SUCCEEDS (exit 0), bounded by an
# attempt cap (the optional second arg, default FLUX_RETRY_N) and FLUX_RETRY_DELAY seconds
# between tries (override per-call with the interval env var).  The poll/backoff sibling of
# flux.bg: keep trying until X holds -- a socket accepting a connection, a count reached, a
# file appearing.  Runs inline in the CALLER's shell, so the command can read the recipe's
# own locals, and exits with the last attempt's status.  This is the single retry loop; the
# flux.retry/% target wraps it to retry a make target.  Give the command through the
# make-call form, not the banana callform, so a pipe or bracket is not read as cmk grammar.
$(call m5.declare, FLUX_RETRY_N ?= 100, FLUX_RETRY_DELAY ?= 0.1)


flux.pipeline/: flux.noop
	@# No-op.  This just bottoms out the recursion on `flux.pipeline`.
flux.pipeline=${make} flux.pipeline${_mk.forward.args}
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
	$(call log.flux, ${dim}$(shell echo $${targets//,/ ; }))
	$(call io.mktemp) && \
	mcmds=`printf $${targets} \
	| ${stream.comma.to.nl} \
	| xargs -I% printf '${make} % & pids+=\"$$! \"\n' \
	` \
	&& (printf 'pids=""\n' \
		&& printf "$${mcmds}\n" \
		&& printf 'wait $${pids}\n') > $${tmpf} \
	&& $(call log.flux, script ${cyan_flow_right} ) \
	&& cat $${tmpf} | ${stream.as.log} \
	&& bash ${dash_x_maybe} $${tmpf}

flux.mux/% flux.join%:; targets="${*}" ${make} flux.mux
	@# Like `flux.join` but accepts arguments directly.

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
	&& $(call log.flux,${dim} starting pipe (${no_ansi}${bold}$${count}${no_ansi_dim} components)) \
	&& $(call log.flux, ${no_ansi_dim}flux.sh.tee${no_ansi} ${sep} ${no_ansi_dim}$${cmd}) \
	&& eval $${cmd}

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
	@# Evals the selector in-context (subshell/tty cases where target-composition fails), then runs script.
	$(call log.flux, $${selector} ${sep} $${target}) \
	&& script="${make} $${target}/\$${chosen}" \
	&& ${trace_maybe} && eval "`${make} mk.get/$${selector}` && $${script:-true}"

define _flux.timer
${trace_maybe} && start_time=${io.time.ns} \
	&& ${make} ${1} \
	&& end_time=${io.time.ns} \
	&& time_diff_ns=$$((end_time - start_time)) \
	&& delta=$$(awk -v ns="$$time_diff_ns" 'BEGIN {printf "%.9f", ns / 1000000000}') \
	&& $(call log.flux, flux.timer ${sep} `echo ${1}|cut -d/ -f2-` ${sep} ${dim}$${label:-done in} ${yellow}$${delta}s)
endef
flux.timer/%:; $(call _flux.timer,${*})
	@# Emits run time for the given make-target in seconds.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timer/<target_to_run>

assert.timeout:; command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || $(call _assert.tool.available,timeout,on macOS install coreutils for gtimeout)
	@# Guards that a portable `timeout` is on PATH: coreutils `timeout` or macOS/brew `gtimeout`.

flux.timeout/%: assert.timeout
	@# Runs the given target for the given number of seconds, then stops it with TERM.
	@#
	@# USAGE:
	@#   ./compose.mk flux.timeout/<seconds>/<target>
	timeout=$(call m5.__args__,1,/) \
	&& target=$(call m5.__args__,2-,/) \
	&& $(call log.io, flux.timeout ${sep} running target ${bold}$${target} ${no_ansi_dim} for ${yellow} $${timeout} seconds) \
	&& $(io.timeout) $${timeout}s ${make} $${target} \
	; stat=$$? \
	&& case $${stat} in \
		124) $(call log.io, timed out as requested);; \
		*) $(call log.io, finished with no timeout); exit $${stat};; \
	esac

flux.timeout.sh: assert.timeout
	@# Like `flux.timeout/<target>` but works with a shell command.
	@#
	@# USAGE: (tails docker logs for up to 10s, then stops)
	@#   cmd='docker logs -f xxxx' timeout=10 ./compose.mk flux.timeout.sh
	$(call log.io, flux.timeout ${sep} running command ${bold}$${cmd} ${no_ansi_dim} for ${yellow} $${timeout} seconds) \
	&& $(io.timeout) $${timeout}s bash -c "$${cmd}" \
	; stat=$$? \
	&& case $${stat} in \
		124) $(call log.io, timed out as requested);; \
		*) $(call log.io, finished with no timeout); exit $${stat};; \
	esac

flux.with.ctx/% flux.context_manager/%:
	@# Runs the given target, using the given namespace as a context-manager
	@#
	@# USAGE: 
	@#  ./compose.mk flux.ctx/<target>,<ctx_name>
	@#
	@# Roughly equivalent to `compose.mk <ctx_name>.enter <target> <ctx_name>.exit`
	target=$(call m5.__args__,1) \
	&& manager=$(call m5.__args__,2) \
	&& man_args=$(call m5.__args__,3) \
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
	$(trace_maybe) \
	&& try=$(call m5.__args__,1) \
	&& except=$(call m5.__args__,2) \
	&& finally=$(call m5.__args__,3) \
	&& $(call log.flux, ${underline}${cyan}try${no_ansi_dim} ${sep} $${try}) \
	&& ${make} $${try} && exit_status=0 || exit_status=1 \
	&& case $${exit_status} in \
		0) true; ;; \
		1) $(call log.flux, ${underline}${cyan}except${no_ansi_dim} ${sep} $${except}) && ${make} $${except} && { $(call mk.exit.clear); exit_status=0; } || exit_status=1; ;; \
	esac \
	&& $(call log.flux, ${underline}${cyan}finally${no_ansi_dim} ${sep} $${finally}) && ${make} $${finally} \
	&& exit $${exit_status}
flux.try.except/%:
	@# Performs a try/except operation with the named targets.
	@# This is just `flux.try.except.finally` where `finally` is `flux.noop`.
	@#
	@# USAGE: (generic)
	@#  ./compose.mk flux.try.except/<try_target>,<except_target>
	$(call mk.unpack.args, _try _except) \
	&& ${make} flux.try.except.finally/$${_try},$${_except},flux.noop
flux.watchdog/%:; cmd="${make} ${*}" ${make} io.fs.watch/$${path}
	@# Runs the given target once, and again in a loop whenever the given path changes.
	@# Requires inotify.
	@#
	@# USAGE: path='..' make flux.watchdog/<target>

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: stage.* :: File-backed persistence for workflows
##
## These targets add lightweight, file-backed persistence to otherwise
## stateless workflows.  A stage is a named JSON stack that cooperating tasks
## push to and pop from: `stage.enter/<name>` draws a divider and records a
## timestamp, `stage.exit/<name>` dumps and cleans the stage file, and
## `stage.wrap/<name>/<target>` runs a target between the two like a
## context-manager.  Each stage layers over the `io.stack.*` primitive, keyed by
## name at `.stage.<name>`; the current stage name lives in `CMK_STAGE`.
##
## DOCS:
## * `[1]:` [Stages](https://robot-wranglers.github.io/compose.mk/stages)
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

CMK_STAGES=
export CMK_STAGE?=

stage: mk.get/CMK_STAGE
	@# Returns the name of the current stage. No Arguments.

stage.clean/%:
	@# Cleans only stage files that belong to the given stage.
	@#
	@# USAGE: 
	@#   ./compose.mk stage.clean/<stage_name>
	header="${bold}${underline}${*}${no_ansi} ${sep}" \
	&& $(call log.flux, $${header} ${dim}removing stack file @ ${dim_cyan}${stage.file}) \
	&& $(call io.safe_rm,${stage.file}) 2>/dev/null || $(call log.flux, $${header} ${yellow} could not remove stack file!)

stage.file=.stage.${*}

stage.enter/% stage/%:
	@# Declares entry for the given stage.
	@# Stage names are generally target names or similar, no spaces allowed.
	@#
	@# Calling this target prints a pretty divider that makes output easier 
	@# to parse, but stages also add an idea of persistence to our otherwise 
	@# pretty stateless workflows, via a file-backed JSON stack object that 
	@# cooperating tasks can *push/pop* from.
	@#
	@# By default we draw a banner with `io.draw.banner`, but you can override
	@# with e.g. `export CMK_STAGE_BANNER=io.figlet`, etc.
	@#
	@# USAGE:
	@#  ./compose.mk stage.enter/<stage_name>
	stagef="${stage.file}" \
	&& header="${bold}${underline}${*}${no_ansi} ${sep}" \
	&& (label="${*}" CMK_INTERNAL=1 ${make} $${CMK_STAGE_BANNER:-io.draw.banner}) \
	&& true $(eval export CMK_STAGE=${*}) $(eval export CMK_STAGES+=${*}) \
	&& $(call log.flux, $${header}${dim} stack file @ ${dim_ital}$${stagef}) \
	&& ${jb} stage.entered="`date`" | ${make} stage.push/${*}

stage.exit/%:; ${make} stage.stack/${*} stage.clean/${*}
	@# Declares exit for the given stage.
	@# Calling this is optional but if you do not, stack-files will not be deleted!
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk stage.exit/<stage_name>

stage.file/%:; echo "${stage.file}"
	@# Returns the name of the current stage file.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk stage.file/<stage_name>

stage.clean:; rm -f -- .stage.*
	@# Cleans all stage-files from all runs, including ones that do not belong to this pid!
	@# No arguments.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk stage./

stage.stack/%:; ${make} io.stack/${stage.file}
	@# Returns the entire stack given a stack name

stage.push/%: 
	@# Push the JSON data on stdin into the stack for the named stage.
	@#
	@# USAGE:
	@#   echo '<json_data>' | ./compose.mk stage.push/<stage_name>
	header="${bold}${underline}${*}${no_ansi}" \
	&& test -p ${stdin}; st=$$?; case $${st} in \
		0) ${stream.stdin} | ${make} io.stack.push/${stage.file}; ;; \
		*) $(call log.flux, $${header} ${sep} ${red}Failed pushing data${no_ansi} because no data is present on stdin); ;; \
	esac

stage.push:; ${stream.stdin} | ${make} stage.push/${CMK_STAGE}
	@# Push the JSON data on stdin into the stack for the implied stage 
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk stage.push

stage.pop/%:
	@# Pops the stack for the named stage.  
	@# Caller should handle empty value, this will not throw an error.
	@#
	@# USAGE:
	@#   ./compose.mk stage.pop/<stage_name>
	@#   {"key":"val"}
	$(call log.flux,   ${*})
	${make} io.stack.pop/${stage.file}

stage.count/%:
	@# Number of items on the named stage's stack.
	@# USAGE: ./compose.mk stage.count/<stage_name>
	${make} io.stack.count/${stage.file}
stage.get/%:
	@# Read-only query of the named stage's stack: applies the jq on stdin (compact JSON).
	@# USAGE: echo '<jq>' | ./compose.mk stage.get/<stage_name>
	${make} io.stack.get/${stage.file}
stage.update/%:
	@# Transform the named stage's stack IN PLACE with the jq on stdin (stays an array).
	@# USAGE: echo '<jq>' | ./compose.mk stage.update/<stage_name>
	${make} io.stack.update/${stage.file}

stage.stack:
	@# Dumps JSON for all the data on the current stack-file.
	@#
	@# USAGE: ( generic )
	@#  ./compose.mk stage.stack/
	$(call io.stack, ${stage.file})

# Recipe-body shorthands for the stage operators: `${stage.<op>}/<stage>` is just
# terser than spelling out the full sub-make target (and reads better in a recipe).
# Each expands to the sub-make invocation, so `${@}` (current target name) is a tidy stage.
# NB `stage.file` stays a PATH var (`.stage.${*}`), so it is intentionally absent.
stage.enter=${make} stage.enter${_mk.forward.args}
stage.exit=${make} stage.exit${_mk.forward.args}
stage.push=${make} stage.push${_mk.forward.args}
stage.pop=${make} stage.pop${_mk.forward.args}
stage.stack=${make} stage.stack${_mk.forward.args}
stage.count=${make} stage.count${_mk.forward.args}
stage.get=${make} stage.get${_mk.forward.args}
stage.update=${make} stage.update${_mk.forward.args}
stage.clean=${make} stage.clean${_mk.forward.args}
stage.wrap=${make} stage.wrap${_mk.forward.args}

stage.wrap:
	@# Like `stage.wrap/<stage>/<target>`, but taking args from env
	@#
	${make} \
		stage.enter/$${stage} \
		$${target} stage.exit/$${stage} 

stage.wrap/%:
	@# Context-manager that wraps the given target with stage-enter 
	@# and stage-exit.  It only accepts one stage at a time, but can
	@# easily be combined with `flux.wrap` for multiplem targets.
	@# 
	@# USAGE: ( generic )
	@#  ./compose.mk stage.wrap/<stage>/<target>
	@#
	@# USAGE: ( concrete )
	@#  ./compose.mk stage.wrap/MAIN/flux.ok
	export stage="$(call m5.__args__,1,/)" \
	&& header="stage.wrap ${sep}${dim_cyan} $${stage} ${sep}" \
	&& export target="$(call m5.__args__,2-,/)" \
	&& $(call log.trace, $${header} ${dim_ital}$${target}) \
	&& (printf "$${target}" | grep "," > /dev/null) \
		&& ( \
			export target="flux.and/$${target}" && ${make} stage.wrap  ) \
		|| (${make} stage.wrap ) 

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: stream.* :: Helpers for IO streams
##
## Basic operations over JSON, newline-delimited, and space-delimited formats.
##
## * For conversion, see `stream.nl.to.comma`, `stream.comma.to.nl`, etc.
## * For JSON ops, see `stream.jb`[2] and `stream.json.append.*`, etc.
## * For formatting and printing, see `stream.dim.*`, etc.
##
## Most targets here are also available as macros, an optimization that
## saves a process:
##
## ```bash
##   # For example, from a makefile, these are equivalent commands:
##   echo "one,two,three" | ${stream.comma.to.nl}
##   echo "one,two,three" | make stream.comma.to.nl
## ```
##
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
	@#   echo foo=bar | ./compose.mk stream.jb
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
	@#   echo '{}' | cmd='from json | to yaml' make stream.nushell

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
	

stream.markdown=${glow.run}
stream.glow stream.markdown:; ${stream.glow}
	@# Renders markdown from stdin to stdout.

stream.to.docker=${make} stream.to.docker${_mk.forward.args}
stream.to.docker/%:
	@# This is a work-around because some interpreters require files and can not work with streams.
	@#
	@# USAGE: ( generic )
	@#   echo ..code.. | ./compose.mk stream.to.docker/<img>,<optional_entrypoint>
	@#
	@# USAGE: ( generic, as macro )
	@#   mk.def.read/<def_name> | stream.to.docker/<img>,<optional_entrypoint>
	@#
	$(call io.mktemp) && ${stream.stdin} > $${tmpf} \
		&& cmd="$${cmd:-} $${tmpf}" ${make} docker.image.run/${*}

stream.lstrip=( ${stream.stdin} | sed 's/^[[:space:]]*//' )
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

stream.nl.to.space=xargs
stream.nl.to.space:; ${stream.nl.to.space}
	@# Converts newline-delimited input stream to space-delimited output.
	@# Also available as a macro.
	@#
	@# USAGE: 
	@#   echo '\nfoo\nbar' | ./compose.mk stream.nl.to.space
	@#   > foo bar

stream.comma.to.nl=( ${stream.stdin} | tr ',' '\n')
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
	@#   echo "logging info" | ./compose.mk stream.dim

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

# Converts multiple sequential newlines to just one, accumulating the stream so
# the gsub spans line boundaries.  Accumulate-then-gsub (not a NUL record
# separator, which busybox awk reads as paragraph mode and which lands a NUL in
# the compiled output that makes `make` warn on every re-parse).
stream.nl.compress=awk '{ _a = _a $$0 "\n" } END { gsub(/\n\n+/, "\n", _a); printf "%s", _a }'

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

# like stream.peek, but prefaced with a line-count
stream.peek.summary=tee >($(call log, $${msg:-streaming} ${sep} ${yellow}`${stream.stdin}|wc -l` lines)) 
stream.peek.40=( $(call io.mktemp) && ${stream.stdin} > $${tmpf} && cat $${tmpf} | fmt -w 35 | ${stream.as.log} && cat $${tmpf} )

# WARNING: long options will not work with OSX
stream.nl.enum=( ${stream.stdin} | awk '1' | nl -v0 -n ln )
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
## BEGIN: tux.* :: The embedded TUI interface
##
## Creation, configuration, and automation of an embedded TUI, by sending
## commands to a (dockerized) version of tmux.  See also the public/private
## sections of the tux API[1], the general docs for the TUI[2], or the spec
## for the 'compose.mk:tux' container.
##
## DOCS:
##   * `[1]`: [API](https://github.com/robot-wranglers/compose.mk/api#api-tux)
##   * `[2]`: [Embedded TUI](https://github.com/robot-wranglers/compose.mk/embedded-tui)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: TUI Environment Variables :: Knobs for the embedded TUI
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
$(call m5.declare!, TUI_SVC_NAME?=tux, TUI_INIT_CALLBACK?=.tux.init)

# WARNING: MacOS docker requires volume-from-config here, 
# but this breaks linux.  might be different for rancher desktop, etc
ifdef OS_MACOS
export TUI_TMUX_SOCKET?=/socket/dir/tmux.sock
else 
export TUI_TMUX_SOCKET?=tmux.sock
endif

export TMUX:=${TUI_TMUX_SOCKET}
export TUI_TMUX_SESSION_NAME?=tui
export _TUI_TMUXP_PROFILE_DATA_ = $(value .sh.tmuxp.profile)

$(call m5.declare!, \
	TUI_THEME_NAME?=powerline/double/green, TUI_THEME_HOOK_PRE?=.tux.init.theme, \
	TUI_THEME_HOOK_POST?=.tux.init.buttons, TUI_CONTAINER_IMAGE?=compose.mk:tux)
export TUI_SVC_BUILD_ORDER?=dind_base,tux
export TUX_LAYOUT_CALLBACK?=.tux.commander.layout
# TMUXP (the tmuxp profile path) is no longer a fixed `.tmp.tmuxp.yml`; tux.mux.detach
# generates it per-run via io.mktemp (auto-removed on exit), previews it under
# verbose, and exports it into the container so .tux.init reads the same file.

tux.repl.kernel:
	@# The generic REPL eval loop (REPL-as-execution-mode): read one target-name per line on stdin,
	@# dispatch each as a fresh `mk.kernel.each` run over this program's whole target namespace (an
	@# interactive shell for a .cmk, like python -i).  The DEFAULT eval target the runtime wires when a
	@# program enters REPL mode (`repl: true` pragma, or `cmk repl <file>`); not normally called directly.
	@# At launch it lists the program's local targets (CMK_REPL_TARGETS, scraped by the runtime).
	{ [ -z "$${CMK_REPL_TARGETS:-}" ] || { printf 'local targets:\n' ; for t in $${CMK_REPL_TARGETS}; do printf '  %s\n' "$$t" ; done ; printf '\036\n' ; } ; } ; trap ':' INT ; while IFS= read -r w; do [ -z "$$w" ] && continue ; set +e ; printf '%s\n' "$$w" | ${__interpreting__} mk.kernel.each 2>&1 | grep -avE '✱|flux[.]timer|cmk run|deduplicated|__main__|starting interpreter|mk[.]interpret|mk[.]src|Generating source' ; rc=$${PIPESTATUS[1]} ; set -e ; printf '\036%s\n' "$${rc:-0}" ; done

# _tux.repl.modeline.jq: build the modeline `mode_segs` from the runtime fingerprint (+ optional __vm__).
# all the formatting lives here (the Go wrapper only elides segments to width).  `\`-continued so the make
# VALUE collapses to a single jq line (jq vars are $$-escaped; no `#`, which make would treat as a comment).
_tux.repl.modeline.jq= "L\($$lvl) ⚙\($$np) ⌗\($$nm) \($$bin)" as $$diag \
 | (if $$vm == null \
     then ([{t:$$diag,s:"dim",p:0,k:"L"}] + (if $$cli != "" then [{t:(" · "+$$cli),s:"dim",p:3,k:"R"}] else [] end)) \
     else (($$vm.chain // "" | split(" ") | map(select(length>0))) as $$c \
           | ([range(0;($$c|length)) | select($$c[.]==$$vm.ip)] | last) as $$ipi \
           | (if $$ipi==null then ($$vm.ip // "") else $$c[$$ipi] end) as $$ip \
           | (if $$ipi==null or $$ipi==0 then "" else ($$c[0:$$ipi]|join(" ")) end) as $$pre \
           | (if $$ipi==null then "" else ($$c[$$ipi+1:]|join(" ")) end) as $$suf \
           | (($$vm.e // {})|tojson|gsub("\"";"")) as $$e \
           | "K\($$vm.k) E\($$e) ·\($$diag)" as $$tail \
           | ((if $$pre!="" then [{t:($$pre+" "),s:"dim",p:5,k:"R"}] else [] end) + [{t:$$ip,s:"ip",p:0,k:"L"}] + (if $$suf!="" then [{t:(" "+$$suf),s:"dim",p:4,k:"L"}] else [] end) + [{t:(" "+$$tail),s:"dim",p:0,k:"R"}])) end) as $$segs \
 | {mode_segs:$$segs}
tux.repl.modeline:
	@# Default `read` target for the tux.repl mode-line (the env-driven REPL status line): emit one
	@# `mode_segs` object per line (~1Hz).  This jq owns the formatting (segment text, style, and
	@# drop-priority); the Go wrapper only elides segments to terminal width and paints them.  Always
	@# emits a runtime fingerprint (L<lvl> ⚙<plugins> ⌗<modules> <bin> · <cli>), folding in the live
	@# __vm__ control stack when virtual-machine.cmk is imported.  A trailing printf fallback keeps the
	@# output valid JSON if the jq hiccups.
	@np=`echo $${__plugins__} | wc -w | tr -d ' '`; nm=`echo $${__modules__} | wc -w | tr -d ' '`; \
	bin=`basename "$${CMK_BIN:-compose.mk}"`; cli="$${CMK_REPL_CLI:-$${MAKE_CLI}}"; \
	while true; do vm=null; \
	  $(if $(call __plugins__.has,virtual-machine.cmk),vm=$$($(call __vm__.snapshot) 2>/dev/null); [ -n "$$vm" ] || vm=null;,:;) \
	  ${jq.run} -nc --arg cli "$$cli" --arg bin "$$bin" --argjson lvl "$${MAKELEVEL:-0}" \
	    --argjson np "$$np" --argjson nm "$$nm" --argjson vm "$$vm" \
	    '${_tux.repl.modeline.jq}' 2>/dev/null \
	    || printf '{"mode_segs":[{"t":"tux.repl","s":"dim","p":0,"k":"L"}]}\n'; \
	  sleep 1; \
	done

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
	$(call log.tux,  ${dim}Starting demo) \
	&& layout=spiral ${make} tux.open/.tte,.tte,.tte,.tte

tux.pane/%:
	@# Sends the given make-target into the given pane.
	@# This is a public interface & safe to call from the docker-host.
	@#
	@# USAGE:
	@#   ./compose.mk tux.pane/<int>/<target>
	@#
	pane_id=$(call m5.__args__,1,/) \
	&& target=$(call m5.__args__,2-,/) \
	&& ${make} tux.dispatch/tui/.tux.pane/${*}

# Possible optimization: this command is *usually* but not 
# always called from  `MAKELEVEL<3` and above that it is 
# probably cached already?
# NB: `tux.require` and `tux.purge` now live in the HOSTED partition
# (`define __hosted__`), authored in CMK-lang and bound via the hosted cache.


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
	&& $(call log.tux,  ${dim}layout=${bold}$${orient}${no_ansi_dim} pane_count=${bold}$${count}) \
	&& $(call log.tux,  ${dim}targets=$${targets}) \
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
	&& $(call log.trace, ${no_ansi_dim}Generated layout callback:\n  $${layout}) \
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

# `cmd` (the command to run in the tux container) and `svc` reach the inner `compose.dispatch.sh` purely
# by environment inheritance: callers export `cmd` (tux.dispatch/% above) or set it in the env, and the
# `svc=tux` prefix on the inner make flows down to that recipe.
tux.dispatch.sh=sh ${dash_x_maybe} -c "svc=tux ${make} tux.require compose.dispatch.sh/${TUI_COMPOSE_FILE}"
tux.dispatch.sh:; ${tux.dispatch.sh}
	@# Runs the given <cmd> inside the embedded TUI container.
	@#
	@# USAGE:
	@#   cmd=... ./compose.mk tux.dispatch.sh
	
tux.mux/%:
	@# Maps execution for each of the comma-delimited targets
	@# into separate panes of a tmux (actually 'tmuxp') session.
	@#
	@# USAGE:
	@#   ./compose.mk tux.mux/<target1>,<target2>
	@#
	$(call log.tux,  ${bold}${*})
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
	&& header="${no_ansi_dim}" \
	&& $(call log.tux, $${header} ${bold}${*}) \
	&& $(call log.tux, $${header} reattach=${dim_red}$${reattach}) \
	&& $(call log.tux, $${header} TUI_SVC_NAME=${dim_green}$${TUI_SVC_NAME}) \
	&& $(call log.tux, $${header} TUI_INIT_CALLBACK=${dim_green}$${TUI_INIT_CALLBACK}) \
	&& $(call log.tux, $${header} TUX_LAYOUT_CALLBACK=${dim_green}$${TUX_LAYOUT_CALLBACK}) \
	&& $(call log.tux.part1, $${header} Generating pane-data) \
	&& export panes=$(strip $(shell ${make} .tux.panes/${*})) \
	&& $(call log.base.part2, ${dim_green}ok) \
	&& $(call log.tux.part1, $${header} Generating tmuxp profile) \
	&& suffix=.yml && $(call io.mktemp) && export TMUXP=$${tmpf} \
	&& eval "$${_TUI_TMUXP_PROFILE_DATA_}" > $${TMUXP}  \
	&& $(call log.base.part2, ${dim_green}ok) \
	&& if [ "$${verbose:-0}" = 1 ]; then $(call log.preview.file, $${TMUXP}); fi \
	&& cmd="${trace_maybe}" \
	&& cmd="$${cmd} && tmuxp load -d -S ${TUI_TMUX_SOCKET} $${TMUXP}" \
	&& cmd="$${cmd} && TMUX=${TMUX} tmux list-sessions" \
	&& cmd="$${cmd} && label='TUI Init' ${make.dind} io.print.banner $${TUI_INIT_CALLBACK}" \
	&& cmd="$${cmd} && label='TUI Layout' ${make.dind} io.print.banner $${TUX_LAYOUT_CALLBACK} $${reattach}" \
	&& trap "${docker.compose} -f ${TUI_COMPOSE_FILE} stop -t 1; rm -f $${TMUXP}" exit \
	&& $(call log.tux, $${header} Enter main loop for TUI) \
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} \
	&& compose_env="-e TUI_TMUX_SOCKET=${TUI_TMUX_SOCKET} \
		-e TUI_TMUX_SESSION_NAME=${TUI_TMUX_SESSION_NAME} \
		-e TUI_INIT_CALLBACK=$${TUI_INIT_CALLBACK} \
		-e TUX_LAYOUT_CALLBACK=$${TUX_LAYOUT_CALLBACK} \
		-e TUI_SVC_STARTED=1 \
		-e geometry=$${geometry:-} \
		-e reattach=$${reattach} \
		-e k8s_commander_targets=$${k8s_commander_targets:-} \
		-e tux_commander_targets=$${tux_commander_targets:-} \
		-e TMUXP=$${TMUXP}" \
	&& ${docker.compose.run} ${dash_x_maybe} -c "$${cmd}" $(compose._quiet) \
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
			targets=`echo $(strip $(shell printf ${*}|tr ',' '\n' | xargs -I% printf '%.shell,'))| sed 's/,$$//'` \
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
	$(call log.tux, ${dim} Stopping all TUI sessions)
	${make} tux.ps | xargs -I% bash -x "id=% ${make} docker.stop" | ${stream.dim.indent}

tux.ps:
	@# Lists ID's for containers related to the TUI.
	@#
	@# USAGE:
	@#  ./compose.mk tux.ps
	$(call log.tux,  $${TUI_CONTAINER_IMAGE} ${sep} ${dim} Looking for TUI containers)
	docker ps | grep compose.mk:tux | awk '{print $$1}'

tux.shell: tux.require
	@# Opens an interactive shell for the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.shell
	${trace_maybe} \
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} \
	&& ${docker.compose.run} ${dash_x_maybe} -i $(compose._quiet)

tux.shell.pipe: tux.require
	@# A pipe into the shell for the embedded TUI container.
	@#
	@# USAGE:
	@#  ./compose.mk tux.shell
	${trace_maybe} \
	&& compose_file=${TUI_COMPOSE_FILE} svc=$${TUI_SVC_NAME} compose_run_flags=-T \
	&& ${docker.compose.run} ${dash_x_maybe} -c "`${stream.stdin}`" $(compose._quiet)

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: TUI internals :: Private targets, run only from inside the TUI
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
	header=""  \
	&& $(call log.tux, $${header} ${dim}Initializing geometry) \
	&& geometry="$${geometry:-${GEO_DEFAULT}}" ${make} .tux.geo.set \
	&& case $${tux_commander_targets:-} in \
		"") \
			$(call log.tux, $${header}${dim} User-provided targets for main pane ${sep} None); ;; \
		*) \
			$(call log.tux, $${header}${dim} User-provided targets for main pane ${sep} $${tux_commander_targets:-} ) \
			&& ${make} .tux.pane/0/flux.and/$${tux_commander_targets} \
			|| $(call log.tux, $${header} ${red}Failed to send commands to the primary pane.${dim}  ${yellow}Is it ready yet?) \
			; ;; \
	esac

.tux.init:
	@# Initialization for the TUI (a tmuxinator-managed tmux instance).
	@# This needs to be called from inside the TUI container, with tmux already running.
	@#
	@# Typically this is used internally during TUI bootstrap, but you can call this to
	@# rexecute the main setup for things like default key-bindings and look & feel.
	@#
	$(call log.tux, ${dim}Initializing TUI)
	$(trace_maybe) \
	&& ${make} .tux.init.panes .tux.init.bind_keys .tux.theme || exit 16
	$(call log.tux, ${dim}Setting pane labels ${TMUX})
	tmux set -g pane-border-style fg=green \
	&& tmux set -g pane-active-border-style "bg=black fg=lightgreen" \
	&& index=0 \
	&& cat "$${TMUXP:-/dev/null}" | yq -r .windows[].panes[].name | ${stream.peek} \
	| while read item; do \
		$(call log.tux, ${dim}Setting pane labels ${TMUX} $${item})\
		; tmux select-pane -t $${index} -T " ┅ $${item} " \
		; ((index++)); \
	done || $(call log.tux, ${red}failed setting pane labels)
	tmux set -g pane-border-format "#{pane_index} #{pane_title}" || $(call log.tux, ${red}failed setting pane labels)
	$(call log.tux, ${dim}Done initializing TUI)
.tux.init.bind_keys:
	@# Private helper for .tux.init.
	@# This binds default keys for pane resizing, etc.
	@# See also: xmonad defaults[1] 
	@#
	@# [1]: https://gist.github.com/c33k/1ecde9be24959f1c738d
	@#
	@#
	$(call log.tux, ${dim}Binding keys)
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

.tux.init.panes:
	@# Private helper for .tux.init.  (This fixes a bug in tmuxp with pane titles)
	@#
	$(call log.tux,${dim} Initializing Panes) \
	&& ${trace_maybe} && tmux set -g base-index 0 \
	&& tmux setw -g pane-base-index 0 \
	&& tmux set -g pane-border-status top \
	&& ( tmux select-pane -t 0.0 || true ) || $(call log.tux,${dim} ${red}Failed initializing panes)

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
	$(call log.tux, ${dim}Initializing status-bar)
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
	$(call log.tux, ${dim}Initializing theme)
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
	
.tux.layout.shuffle: assert.tool.required/shuf
	@# Shuffles the pane layout randomly
	@#
	$(call log.tux, shuffling layout )
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
			$(call log.base.part1, ${GLYPH_TUI} ${@} ${sep} ${dim}Setting geometry) \
			&& tmux select-layout "$${geometry}" \
			; case $$? in \
				0) $(call log.base.part2, ${dim}ok); ;; \
				*) $(call log.base.part2, ${red}error setting geometry); ;; \
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
	$(call log.tux, ${dim}Focusing pane ${*})
	tmux select-pane -t 0.${*} || true

.tux.pane/%:
	@# Dispatches the given make-target to the tmux pane with the given id.
	@#
	@# USAGE:
	@#   ./compose.mk .tux.pane/<pane_id>/<target_name>
	@#
	pane_id=$(call m5.__args__,1,/) \
	&& target=$(call m5.__args__,2-,/) \
	&& cmd="$${env:-} ${make} $${target}" ${make} .tux.pane.sh/${*}

.tux.pane.sh/%:
	@# Runs command on the given tmux pane with the given ID.
	@# (Like '.tux.pane' but works with a generic shell command instead of a target-name.)
	@#
	@# USAGE:
	@#   cmd="echo hello tmux pane" ./compose.mk .tux.pane.sh/<pane_id>
	@#
	pane_id=$(call m5.__args__,1,/) \
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
	pane_id=$(call m5.__args__,1,/) \
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
	$(call log.tux, killing session)
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
	$(call log.base, ${@})
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
	pane_id=$(call m5.__args__,1,/) \
	&& filter=$(call m5.__args__,2,/) \
	&& $(trace_maybe) \
	&& tmux send-keys -t 0.$${pane_id} "lazydocker" Enter "]" \
	&& cmd="tmux send-keys -t 0.$${pane_id} Down" ${make} flux.apply.later.sh/3 \
	&& case "$${filter:-}" in \
		"") true;; \
		*) (tmux send-keys -t 0.$${pane_id} "/$${filter}" C-m );; \
	esac

.tte:
	@# Bare form: effect the current source.  Resolves `CMK_SRC` where the recipe RUNS, so a
	@# pane dispatched into the tux container reads the container's own compose.mk (never a stale
	@# host path baked in by the caller).  This is why tux.demo can pass a plain `.tte` per pane.
	${make} .tte/${CMK_SRC}
.tte/%:
	@# Interface to terminal-text-effects[1], just for fun.  Used as part of the main TUI demo.
	@#
	@# REFS:
	@#   * `[1]`: https://github.com/ChrisBuilds/terminaltexteffects
	cat ${*} | head -`echo \`tput lines\`-1 | bc` \
	| tte matrix --rain-time 1 && ${make} io.shell

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: Embedded files :: Inlined compose files, configs, and other data
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
$(call m5.marm, compose.ctx.display_profile)
compose.ctx.display=${bold_green}$(or ${target_namespace},${compose_file_stem}) ${sep} ${compose.ctx.display_profile} ${sep} 
# COMPOSE_MISSING: 1 iff compose is unavailable, derived from the memoized `docker.compose`
# probe.  Lazy -- only expanded by the compose.import paths at call time, not at parse.
COMPOSE_MISSING=$(if $(filter docker,$(firstword ${docker.compose})),0,1)

# compose.get_services: the service names from a compose file, via `docker compose config
# --services`.  Returns nothing when CMK_INTERNAL (any nested sub-make): inside a service-container
# compose is usually absent, and on a host helper it is simply skipped -- this also stops
# container->container dispatch.  Kept on CMK_INTERNAL (the union), NOT CMK_IN_CONTAINER: repointing
# would run `docker compose config` on every recursive host parse.  Guard checked at call time
# (COMPOSE_MISSING is lazy), so no parse-time `ifeq` docker probe.  NB: don't add
# --no-env-resolution/--no-path-resolution/--no-consistency -- not in all compose versions.
define compose.get_services
$(if $(filter 1,${COMPOSE_MISSING}),,$(shell if [ "${CMK_INTERNAL}" = "0" ]; then \
		(${trace_maybe} && ([ "$(m5[1])" = "" ] && echo -n "" || COMPOSE_PROFILES=${COMPOSE_PROFILES} ${docker.compose} -f ${1} config --services||echo -n ""))  ; \
	else echo -n ""; fi))
endef

# Macro to create all the targets for a given compose-service.
# See docs @ https://robot-wranglers.github.io/compose.mk/bridge
define compose.create_make_targets
$(eval compose_service_name := $1)
$(eval target_namespace := $2)
$(eval import_to_root := $(m5[3]))
$(eval compose_file := $(m5[4]))
$(eval namespaced_service:=${target_namespace}/$(compose_service_name))
$(eval compose_file_stem:=$(shell basename -s .yml $(compose_file)))

${compose_file_stem}.command/%:
	@# Passes the given command to the default entrypoint of the named service.
	@#
	@# USAGE:
	@#   ./compose.mk <stem>.command/<svc>/<command>
	@#
	cmd="$$(call m5.__args__,2-,/)" ${make} $${compose_file_stem}/$$(call m5.__args__,1,/)

${compose_file_stem}.dispatch/%:
	@# Dispatches the named target inside the named service.
	@#
	@# USAGE:
	@#   ./compose.mk <stem>.dispatch/<svc>/<target>
	@#
	${trace_maybe} && entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} $$(call m5.__args__,2-,/)" \
	${make} ${compose_file_stem}/$$(call m5.__args__,1,/)

${compose_file_stem}/$(compose_service_name).logs:
	@# Logs for this service.  NB: Uses "follow" mode by default, so this is blocking
	${make} docker.logs.follow/`${make} ${compose_file_stem}/$(compose_service_name).ps | ${jq} -r .ID` \
	|| $$(call log.docker, ${compose_file_stem}/$(compose_service_name).logs ${sep} ${red} failed${no_ansi} showing logs for ${bold}${compose_service_name}${no_ansi}.. could not find id?)

${compose_file_stem}.exec.bg/%:; detach=1 ${make} ${compose_file_stem}.exec/$${*}
${compose_file_stem}.exec/%:
	@# Like <stem>.dispatch, but using exec instead of run
	@# Foregrounded by default.  Pass detach=1 to override.
	@#
	@# USAGE:
	@#   ./compose.mk <stem>.exec/<svc>/<target>
	@#   detach=0 ./compose.mk <stem>.exec/<svc>/<target>
	@#   cmd=whoami ./compose.mk <stem>.exec/<svc>
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
	@# Detects the best shell to use with the `<svc>` container @ the compose file
	$$(call compose.get_shell, $(compose_file), $(compose_service_name))

${compose_file_stem}/$(compose_service_name).get_config:
	@# Dumps JSON-formatted config for the `<svc>` container @ the compose file.
	@# This turns off most of the string-interpolation and path-resolution that happens by default.
	docker compose -f $(compose_file) config \
		--no-interpolate --no-path-resolution --format json \
	| ${jq} .services.${compose_service_name}

${compose_file_stem}/$(compose_service_name).get_config/%:
	@# Dumps JSON-formatted config for the `<svc>` container @ the compose file.
	@# This turns off most of the string-interpolation and path-resolution that happens by default.
	${make} ${compose_file_stem}/$(compose_service_name).get_config | ${jq} -er .$${*}

${compose_file_stem}/$(compose_service_name).shell:
	@# Starts a shell for the "<svc>" container defined in the <compose-file> file.
	@#
	$$(call compose.shell, $(compose_file), $(compose_service_name))

# NB: implementation must not use 'io.mktemp'!
${compose_file_stem}/$(compose_service_name).shell.pipe:
	@# Pipes data into the shell, using stdin directly.  This uses bash by default.
	@#
	@# USAGE:
	@#   echo <commands> | ./compose.mk <stem>/<svc>.shell.pipe
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
	@# A pipe into the <svc> container @ <compose-file>.
	@# Specify 'entrypoint=...' to override the default spec.
	@#
	@# EXAMPLE: 
	@#   echo echo hello-world | ./compose.mk  <stem>/<svc>.pipe
	@#
	${stream.stdin} | pipe=yes ${make} ${compose_file_stem}/$(compose_service_name)

${compose_file_stem}.restart: ${compose_file_stem}.down ${compose_file_stem}.up.detach
${compose_file_stem}.restart.fg: ${compose_file_stem}.down ${compose_file_stem}.up
${compose_file_stem}.restart/$(compose_service_name): \
	${compose_file_stem}/$(compose_service_name).stop ${compose_file_stem}.up/$(compose_service_name)

${compose_file_stem}.with_profile/%:
	@# USAGE: make docker-compose.with_profile/all/up,sto
	prof=$$(call m5.__args__,1,/) \
	&& targets="`echo '$$(call m5.__args__,2-,/)' | ${stream.comma.to.nl} | xargs -I% echo ${compose_file_stem}.%|${stream.nl.to.space}|${stream.space.to.comma}`" \
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
	@#   ./compose.mk <stem>/<svc>.stop
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
	@# Target wrapping the '<svc>' container (via compose file @ the compose file)
$(compose_service_name).build: ${compose_file_stem}.build/$(compose_service_name)
	@# Shorthand for <stem>.build/<svc>

$(compose_service_name).clean: ${compose_file_stem}.clean/$(compose_service_name)
	@# Cleans the given service, removing local image cache etc.
	@#
	@# Shorthand for <stem>.clean/<svc>

# NB: optimization: not using chaining
$(compose_service_name).dispatch/%:
	@# Shorthand for <stem>.dispatch/<svc>/<target_name>
	${trace_maybe} \
	&& entrypoint=make \
	cmd="${MAKE_FLAGS} -f ${MAKEFILE} $${*}" \
	${make} ${compose_file_stem}/${compose_service_name}

$(compose_service_name).dispatch.quiet/%:; quiet=1 ${make} $(compose_service_name).dispatch/$${*}
$(compose_service_name)/%:
	@# Run a define (a lifted lambda body, or any define) INSIDE the <svc> service.
	@# This is the runner that `(| .. |) in <svc>` dispatches to -- the compose-service
	@# arm of the `in` machine-algebra, routed through the service binder (env/entrypoint/quiet ride in).
	$$(call compose.bind.script, svc=$(compose_service_name) def=$$*)
$(compose_service_name).exec.detach/%:
	$$(call log.docker, ${dim_green}${target_namespace} ${sep} ${no_ansi}${green}$(compose_service_name) ${sep} ${dim_cyan}exec.detach ${sep} $${*})
	docker compose -f ${compose_file} \
		exec --detach $(compose_service_name) \
		${make} $${*} 2> >(grep -v 'variable is not set' >&2)
$(compose_service_name).exec/%:
	@# Shorthand for <stem>.exec/<svc>/<target_name>
	${make} ${compose_file_stem}.exec/$(compose_service_name)/$${*}

$(compose_service_name).exec.shell: ${compose_file_stem}.exec.shell/$(compose_service_name)
	@# Open interactive shell for the container.  Requires that `up` already happened, and is still running
	
$(compose_service_name).get_shell: ${compose_file_stem}/$(compose_service_name).get_shell
	@# Shorthand for <stem>/<svc>.get_shell
$(compose_service_name).get_config: ${compose_file_stem}/$(compose_service_name).get_config
	@# Shorthand for <stem>/<svc>.get_config
$(compose_service_name).get_config/%:; ${make} ${compose_file_stem}/$(compose_service_name).get_config/$${*}
$(compose_service_name).pipe:;  pipe=yes ${make} ${compose_file_stem}/$(compose_service_name)
	@# Pipe into the default shell for the '<svc>' container (via compose file @ the compose file)

$(compose_service_name).shell: ${compose_file_stem}/$(compose_service_name).shell
	@# Shortcut for <stem>/<svc>.shell

$(compose_service_name).logs: ${compose_file_stem}/$(compose_service_name).logs
$(compose_service_name).logs/%:
	$$(call log.docker, ${dim_green}${target_namespace} ${sep} ${no_ansi}${green}$(compose_service_name) ${sep} ${dim_cyan}logs/ ${sep} `printf $${*}`)
	${trace_maybe} && docker compose -f ${compose_file} \
		logs -n $${*} $(compose_service_name)

$(compose_service_name).start $(compose_service_name).up: ${compose_file_stem}.up/$(compose_service_name)
	@# Shorthand for <stem>.up/<svc>

$(compose_service_name).stop: ${compose_file_stem}/$(compose_service_name).stop
	@# Shorthand for <stem>.stop/<svc>

$(compose_service_name).up.detach: ${compose_file_stem}.up.detach/$(compose_service_name)
	@# Shorthand for <stem>.up.detach/<svc>

$(compose_service_name).shell.pipe: ${compose_file_stem}/$(compose_service_name).shell.pipe
	@# Shorthand for <stem>/<svc>.shell.pipe

endif)

${namespaced_service}.pipe:; pipe=yes ${make} ${namespaced_service}
${target_namespace}.$(compose_service_name).exec/%:; ${make} ${compose_file_stem}.exec/$(compose_service_name)/$${*}
${target_namespace}.$(compose_service_name).exec:; ${make} ${compose_file_stem}.exec/$(compose_service_name)
${target_namespace}.$(compose_service_name).exec.shell: ${compose_file_stem}.exec.shell/$(compose_service_name)

${target_namespace}.$(compose_service_name).dispatch/%:
	@# Dispatch named target in <svc> container
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
	@# Target dispatch for <svc>
	@#
	[ -z "${MAKE_CLI_EXTRA}" ] && true || verbose=0 \
	&& ${trace_maybe} && ${make} ${compose_file_stem}/${compose_service_name}
${namespaced_service}/%:
	@# Dispatches the named target inside the <svc> service, as defined in the compose file.
	@#
	@# EXAMPLE: 
	@#  # mapping a public Makefile target to a private one that is executed in a container
	@#  my-public-target: <namespaced_service>/myprivate-target
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
	&& printf "${green}⇒${no_ansi}${dim} `basename -s.yaml \`basename -s.yml ${1}\``/$(m5[2]).shell (${green}...${no_ansi_dim})${no_ansi}\n" \
	&& docker compose -f ${1} \
		run --rm --remove-orphans --quiet-pull \
		--env CMK_INTERNAL=1 --env CMK_IN_CONTAINER=1 -e TERM="$${TERM}" \
		-e GITHUB_ACTIONS=${GITHUB_ACTIONS} -e TRACE=$${TRACE} \
		--env verbose=$${verbose} \
		 --entrypoint $${entrypoint}\
		${2}
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: *.import.* :: Import-statement macros
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
case $${CMK_INTERNAL} in 0)  ${log.rerouting} ; quiet=1 ${make} $(m5[1]).dispatch/.$(strip ${@});; *) ${make} .$(strip ${@}) ;; esac
endef

docker.import.script= $(eval $(call _docker.import.script,${1},${2},${3},${4}))
define _docker.import.script
$(strip $(if $(filter undefined,$(origin 4)),$(strip ${3}),$(4))):; $(call docker.bind.script,${1},${2},${3})
endef

$(call m5.def.!, compose.import.string, _compose.import.string)
define _compose.import.string
ifeq (${CMK_INTERNAL},1)
else
$(call mk.unpack.kwargs, ${1}, def import_to_root=TRUE)
$(shell cat $(MAKEFILE_LIST) | awk '/^define ${kwargs_def}/{flag=1; next} /endef/{flag=0} flag' > .tmp.${kwargs_def}.yml)
$(call compose.import.generic, $(kwargs_def), $(kwargs_import_to_root), .tmp.${kwargs_def}.yml)
endif
endef

define _docker.import.def
$(eval img_name:=$(patsubst Dockerfile.%,%,$(call mk.kwargs.get,${1},def)))
$(call mk.unpack.kwargs, ${1}, def namespace=$${img_name})
define ${kwargs_namespace}
img=compose.mk:${img_name} entrypoint=bash src=${img_name}
endef
$$(if $$(filter-out undefined,$$(origin cmk.Dockerfile)),$$(call cmk.Dockerfile, def=${kwargs_namespace}))
ifeq ($${CMK_INTERNAL},1)
else
${kwargs_namespace}.img:=compose.mk:${img_name}
# `.src` names which define `_cbuild` builds (via `Dockerfile.build/<src>`).  `cmk.Dockerfile`
# defaults it to `$${self}` (the namespace), but a `def=` import's Dockerfile lives in
# `define Dockerfile.$${img_name}`, not `Dockerfile.$${namespace}` -- so pin it to `$${img_name}`
# (mirrors the `.img` override just above).  Without this `<ns>.build` feeds the config define
# (`img=.. entrypoint=.. src=..`) to `docker build` -> "unknown instruction: img=..".
${kwargs_namespace}.src:=${img_name}
${kwargs_namespace}.clean: mk.docker.rmi/${img_name}
${kwargs_namespace}.dispatch/%:;
	@# Dispatch the given target in the `<kwargs_namespace>` container
	img=${img_name} hostname=${img_name} ${make} .mk.docker.dispatch/$${*}
${kwargs_namespace}.shell:; entrypoint="$$$${entrypoint:-bash}" ${make} ${kwargs_namespace}
${kwargs_namespace}:; img="${img_name}" hostname="${img_name}" ${make} mk.docker.run.sh 
endif
endef
define _docker.import
$(call mk.unpack.kwargs, ${1}, file=undefined namespace img=compose.mk:$${kwargs_namespace})
define ${kwargs_namespace}
img=${kwargs_img} entrypoint=bash file=${kwargs_file}
endef
$$(if $$(filter-out undefined,$$(origin cmk.container)),$$(call cmk.container, def=${kwargs_namespace}))
ifeq ($${CMK_INTERNAL},1)
else
${kwargs_namespace}.img:=${kwargs_img}
${kwargs_namespace}.dispatch/%:; img=${kwargs_img} hostname=${kwargs_img} \
	${make} docker.dispatch/$${*}
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

$(call m5.def.!, compose.import, _compose.import)
compose.import.*=${compose.import}
define _compose.import
$(call mk.unpack.kwargs, ${1}, file import_to_root=TRUE namespace=services)
$(call compose.import.generic, ${kwargs_namespace}, ${kwargs_import_to_root}, ${kwargs_file})
endef
define compose.import.as
$(eval
$(call mk.unpack.kwargs, ${1}, namespace file)
$(call compose.import.generic, ${kwargs_namespace}, FALSE, ${kwargs_file}))
endef

# Lazy dispatcher: decide the missing-compose no-op at call time (COMPOSE_MISSING
# is lazy) instead of via a parse-time `ifeq` that probed docker. The real body
# (renamed `.real`) is unchanged.
compose.import.generic=$(if $(filter 1,${COMPOSE_MISSING}),,$(call compose.import.generic.real,$(1),$(2),$(3)))
define compose.import.generic.real
$(eval target_namespace:=$(m5[1]))
$(eval compose_file:=$(m5[3]))
$(eval cached:=$(call io.string.hash,$(target_namespace)$(2)$(3)))
$(call log.import.part1,${dim}compose.import.generic ${sep} ${compose_file})
ifndef $${cached}
$$(eval ${cached} := 1)
$(call log.import.part2,${dim}namespace=${bold}${target_namespace})

$(eval import_to_root := $(if $(2), $(m5[2]), FALSE))
$(eval compose_file_stem:=$(shell basename -s.yaml `basename -s.yml $(strip ${3}`)))
$(eval __services__:=$(call compose.get_services, ${compose_file}))

# Operations on the compose file itself
# WARNING: these can not use '/' naming conventions as that conflicts with '<stem>/<svc>' !
${compose_file_stem}.services $(target_namespace).services:
	@# Outputs newline-delimited list of services for the compose file.
	@#
	@# NB: This must remain suitable for use with xargs, etc
	@#
	echo $(__services__) | tr ' ' '\n' | sort

${compose_file_stem}.images ${target_namespace}.images:; ${make} compose.images/${compose_file}
	@# Returns a nl-delimited list of images for this compose file

${compose_file_stem}.size ${target_namespace}.size:; ${make} compose.size/${compose_file}

${compose_file_stem}.build $(target_namespace).build:
	@# Noisy build for all services in the compose file, or for the given services.
	@#
	@# USAGE: 
	@#   ./compose.mk  <stem>.build
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}build ${sep} ${dim_ital}all services) \
	&&  $(trace_maybe) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build $${docker._quiet_flag}

${compose_file_stem}.build.quiet $(target_namespace).build.quiet:
	@# Quiet build for all services in the given file.
	@#
	@# USAGE: ./compose.mk  <compose_stem>.build.quiet
	@#
	@# WARNING: This is not actually safe for all legal compose files, because
	@# compose handles run-ordering for defined services, but not build-ordering.
	@#
	@$$(eval export svc_disp:=$(shell echo echo $$$${svc:-all services}))
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}build ${sep} ${dim_ital}$${svc_disp})
	$(trace_maybe) \
	&& quiet=1 label="build finished in" ${make} flux.timer/compose.build/${compose_file}

${compose_file_stem}.build.quiet/% ${compose_file_stem}.require/%:
	@# Quiet build for the named service in the compose file
	@#
	@# USAGE: 
	@#   ./compose.mk  <stem>.build.quiet/<svc_name>
	@#
	$(trace_maybe) && ${make} io.quiet.stderr/${compose_file_stem}.build/$${*}

${compose_file_stem}.build/% $(target_namespace).build/%:
	@# Builds the given service(s) for the compose file.
	@#
	@# Note that explicit ordering is the only way to guarantee proper 
	@# build order, because compose by default does no other dependency checks.
	@#
	@# USAGE: 
	@#   ./compose.mk <stem>.build/<svc1>,<svc2>,..<svcN>
	@#
	$$(call log.docker, ${target_namespace} ${sep} ${green}$${*} ${sep} ${no_ansi_dim}building..) 
	echo $${*} | ${stream.comma.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} build %"



${compose_file_stem}.up/%:
	@# Ups the given service(s) for the compose file.
	@#
	@# USAGE: 
	@#   ./compose.mk <stem>.up/<svc_name>
	@#
	$$(call log.docker, ${target_namespace}.up ${sep} $${*}) \
	&& ${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up $${*} 

${compose_file_stem}.up.detach/%:
	@# Ups the given service(s) for the compose file, with implied --detach
	@#
	@# USAGE: 
	@#   ./compose.mk <stem>.up.detach/<svc_name>
	@#
	$$(call log.docker, ${target_namespace} ${sep} ${dim_cyan}up.detach ${sep} ${dim_green}$${*})
	${docker.compose} $${COMPOSE_EXTRA_ARGS} -f ${compose_file} up -d $${*} $${stream.stderr.iff.failed}

${compose_file_stem}.clean/%:
	@# Cleans the given service(s) for the compose file.
	@# See 'compose.clean' target for more details.
	@#
	@# USAGE: 
	@#   ./compose.mk <stem>.clean/<svc>
	@#
	echo $${*} \
	| ${stream.comma.to.nl} \
	| xargs -I% sh ${dash_x_maybe} -c "svc=% ${make} compose.clean/${compose_file}"

${compose_file_stem}.stop $(target_namespace).stop:
	@# Stops all services for the compose file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}stop ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} stop -t 1 2> >(grep -v '\] Stopping'|grep -v '^ Container ' >&2)
 

${compose_file_stem}.down $(target_namespace).down:
	@# Bring down all services for the compose file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${bold_cyan}down ${sep} ${dim_ital}all services)
	${trace_maybe} && ${docker.compose} -f $${compose_file} down -t 1 2> >(grep -v '^Network.*Removing'|grep -v '^Network.*Removed' >&2)

${compose_file_stem}.up:
	@# Brings up all services in the given compose file.
	@# Stops all services for the compose file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${dim_ital} $$$${svc:-all services})
	${docker.compose} -f $${compose_file} up $$$${svc:-}
${compose_file_stem}.up.detach:
	@# Brings up all services in the given compose file.
	@# Stops all services for the compose file.  
	@# Provided for completeness; the stop, start, up, and 
	@# down verbs are not really what you want for tool containers!
	$$(call log.docker, ${compose.ctx.display} ${dim_ital} $$$${svc:-all services})
	${docker.compose} -f $${compose_file} up -d $$$${svc:-}

${compose_file_stem}.clean:
	@# Runs 'compose.clean' for the given service(s), or for all services in the compose file if no specific service is provided.
	@#
	svc=$${svc:-} ${make} compose.clean/${compose_file}

# NB: implementation must not use 'io.mktemp'!
${compose_file_stem}/%:
	@# Generic dispatch for given service inside <compose-file>
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
		printf "$${env:-}" | tr ',' '\n' | xargs -I% bash -c "[[ -v % ]] && printf '%\n' || true" | xargs -I% echo --env %='☂$$$${%}☂'; fi))
	@$$(eval export base:=docker compose -f $(compose_file) run $${tty} --rm --remove-orphans --quiet-pull \
		${docker.cmk.mount} \
		$$(subst ☂,\",$${extra_env}) \
		--env CMK_INTERNAL=1 --env CMK_IN_CONTAINER=1 \
		$$$${docker.env.standard} \
		--env verbose=$${verbose} \
		 $${pipe} $${user} $${entrypoint} $${svc_name} $${cmd})
	@# host-only stdin buffer (bare mktemp, not io.mktemp): only its CONTENTS stream into
	@# the container (host-side `cat`), so it needs no cwd/workspace visibility.
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
		([ $${verbose} == 1 ] && printf "$${header}${log.prefix.makelevel} ${green_flow_right}  ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${cyan}<${no_ansi}${bold}..${no_ansi}${cyan}>${no_ansi}${dim_ital}`cat $${stdin_tempf} | sed 's/^[[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
		&& ($$(call log.trace, ${dim}$$$${base}${no_ansi})) \
		&& eval $${base}  2\> \>\(\
                 grep -vE \'.\*Container.\*\(Running\|Recreate\|Created\|Starting\|Started\)\' \>\&2\ \
                 \| grep -vE \'.\*Network.\*\(Creating\|Created\)\' \>\&2\ \
                 \) ; \
	else \
		${stream.stdin} > $${stdin_tempf} \
		&& ([ $${verbose} == 1 ] && printf "$${header}${dim}$${nsdisp} ${no_ansi_dim}$${entrypoint_display}$${cmd_disp} ${cyan_flow_left} ${dim_ital}`cat $${stdin_tempf} | sed 's/^[[:space:]]*//'| sed -e 's/CMK_INTERNAL=[01] //'`${no_ansi}\n" > ${stderr} || true) \
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
	$$(call log, ${no_ansi}file=${dim}${ital}${compose_file})
	docker compose -f ${compose_file} ps --format json | ${jq} .Service | ${jq} -s .

else
$(call log.import.part2,${GLYPH_CHECK} cached)
$(call log.import,double-import${no_ansi_dim}.. skipping)
endif
endef


# Main macros to import 1 or more code-blocks
$(call m5.def.!, code.import, _code.import)
define _code.import
$(call mk.unpack.kwargs, ${1}, pattern)
$(eval __code_blocks__:=$(shell echo "$(.VARIABLES)" | ${stream.space.to.nl} | grep '${kwargs_pattern}$$'))
$(foreach codeblock, ${__code_blocks__},\
	$(call _code.unbound, def=${codeblock} ${1}))
endef



# code.pipe -- the bound code-object `|`: compose two runnables at the process boundary (run one,
# pipe its stdout into the next) via each side's own `.stream`, so cross-language pipes are safe and no
# source is spliced.  A typed pipeline fragment (its own `.__ctor__` names this ctor) that re-composes via `.__pipe__`.
code.pipe = $(strip \
  $(eval lang.banana.seq += x)\
  $(eval _lpp := __pip_$(words $(lang.banana.seq)))\
  $(eval $(_lpp).stream = $$($(m5[1]).stream) | $$($(strip ${2}).stream))\
  $(eval $(_lpp).shape = $$($(_lpp).stream))\
  $(eval $(_lpp).__ctor__ := code.pipe)\
  $(eval $(_lpp).__pipe__ = $$(call code.pipe,$(_lpp),$$(strip $${__args__})))\
  $(eval $(_lpp).__clone__ = $$(call lang.banana.clone.pipe,$$(strip $${1}),$(_lpp)))\
  $(_lpp))

# lang.seed.code!: adapt! -- wire the bound Runnable surface.
lang.seed.code! = $(call m5.self!,$(m5[__self__]))$(call m5.set,__machine__,$(m5[2]))$(if $(call m5.defined?,$(m5[2]).__in__),$(eval $(m5[__self__]).__in__ = $$(call $(m5[2]).__in__,$(m5[1]).shape)),$(if $(call m5.defined?,$(m5[2]).__call__),$(eval $(m5[__self__]).__in__ = $$(call $(m5[2]).__call__,$$($(m5[1]).file))),$(call m5.set.op,__in__,=,${make} $(m5[1]).with.file/$(m5[2]))))$(eval $(m5[__self__]).__pipe__ = $$(call code.pipe,$(m5[1]),$$(strip $${__args__})))
$(call m5.def.!, code.unbound, _code.unbound)
define _code.unbound
${nl}
$(call mk.unpack.kwargs, ${1}, def namespace=$${kwargs_def} bind=None env=)
$$(eval define ${kwargs_namespace}.__ctor_src__$${nl}$$(value ${kwargs_def})$${nl}endef)
${kwargs_namespace}.__ctor_initkw__ := ${1}
${kwargs_namespace}.__ctor_copy__ = $$(eval define $$(strip $$1)$${nl}$$(value ${kwargs_namespace}.__ctor_src__)$${nl}endef)$$(call code.unbound, def=$$(strip $$1) $$(filter-out def=%,$$(value ${kwargs_namespace}.__ctor_initkw__)))
${kwargs_namespace}.copy = $$(call ${kwargs_namespace}.__ctor_copy__,$$1)
# Materializable surface from the seed prelude (shared with the hosted Materializable protocol): the
# raw-body flag + `.__blockref__` representation.  `.shape` is then overridden to read the code
# SOURCE (`.__ctor_src__`), since a code-object shadows its own name with a run callform, so the
# prelude default (reading the instance value) would capture the callform, not the body.
$$(call lang.seed.materialize!, ${kwargs_namespace}, lang.proto.tmpl.materializable)
${kwargs_namespace}.shape := $$(value ${kwargs_namespace}.__ctor_src__)
# Materializable glyph tail, hand-lowered at seed (the `⬦`/`⬥` glyph members the hosted protocol
# gets from the `.awk.blockref` COMPILE stage, which never runs on seed): `.fd` = a process-sub FD
# streaming the body, `.file` = a real tempfile of it.  Both read the code SOURCE via the
# `.__ctor_src__`-preferring `_mk.def.to.fd`, so they see the body, not the run-callform shadow.
${kwargs_namespace}.fd = <($$(call _mk.def.to.fd, ${kwargs_namespace}))
${kwargs_namespace}.file = $$(call _mk.def.tmpfile, ${kwargs_namespace})
# Templatable surface from the seed prelude: `.render`/`.__mod__` fill the holes then re-mint via
# `.__ctor__` -- a code-object is NOT a class, so its minter is the single-arg-form ctor
# (`code.unbound`), whose `def=` reaches the constructor (the `code.unbound` minter reads argv).
${kwargs_namespace}.__ctor__ := code.unbound
$$(call lang.seed.materialize!, ${kwargs_namespace}, lang.proto.tmpl.templatable)
# `.render`/`.__mod__` re-mint under the class (the unbound single-arg minter), which would drop a
# bound object's machine.  Override the fill to re-mint carrying the original kwargs (the binding), so
# a rendered specialization of a bound object stays bound and runnable; unbound objects are unchanged.
${kwargs_namespace}.__fill__ = $$(eval lang.banana.tmp := $$(call lang.banana.__mod__,${kwargs_namespace}.shape,$${__args__}))$$(eval $$(call code.unbound, def=$$(lang.banana.tmp) $$(filter-out def=%,$$(value ${kwargs_namespace}.__ctor_initkw__))))$$(lang.banana.tmp)
# code-objects are content + an optional machine BINDING (has-a, not is-a): a BOUND object carries
# `.__machine__` + a delegating `.__in__` (so it is `Runnable`) and a PROCESS-composing `.__pipe__` (run
# one runnable, pipe stdout into the next, each side its OWN interpreter); UNBOUND has none, and pipe faults.
ifneq (${kwargs_bind},None)
$$(call lang.seed.code!, ${kwargs_namespace}, ${kwargs_bind})
else
${kwargs_namespace}.__pipe__ = $$(call mk.error, cmk: NotImplemented/Pipe: `${kwargs_def}` is an UNBOUND code-object; `|` composes runnables (run one, pipe its stdout into the next)$$(comma) so bind each side to an interpreter first (bind= / entrypoint=) -- an unbound body may not even be shell, errno=NOT_IMPLEMENTED)
endif
# `.bind`: bind this code-object to a machine after declaration.
${kwargs_namespace}.bind = $$(call lang.seed.code!, ${kwargs_namespace}, $$(patsubst machine=%,%,$$(strip $${__args__})))
ifeq ($${CMK_INTERNAL},1)
else
${kwargs_namespace}.with.file/%:; ${make} io.with.file/${kwargs_def}/$${*}
# `.to.file`/`.to.file/%` fold onto the Materializable surface: `.file` already builds a tempfile of
# the body (via `_mk.def.to.fd`), so the no-arg form just echoes it; the `/%` form streams the body
# to the named path directly (no `mk.def.read` sub-make round-trip).
${kwargs_namespace}.to.file/%:; $$(call _mk.def.to.fd, ${kwargs_namespace}) > $${*}
${kwargs_namespace}.to.file:; @echo $$(${kwargs_namespace}.file)
${kwargs_namespace}.preview: ${kwargs_namespace}.with.file/io.preview.file
${kwargs_namespace}.run/%:; CMK_INTERNAL=1 ${make} mk.def.read/${kwargs_def}/$${*}
${kwargs_namespace}:
	@# ...
	export env="$(subst ${space},${comma},${kwargs_env})" \
	&& _m="$$(if $$(filter undefined,$$(origin ${kwargs_namespace}.__machine__)),,$$(${kwargs_namespace}.__machine__))" \
	&& case "$$$${_m}" in \
		"") $$(call log.io, \
				${kwargs_namespace} ${sep} ${red}Unbound/Code${no_ansi}${dim} ${sep} bind a machine before run) \
			; printf 'cmk: Unbound/Code/${kwargs_namespace}: unbound code-object is not runnable; bind it (machine=/entrypoint=/img= at declaration, or .bind later)\n' >${stderr} \
			; exit 41 ;; \
		*) $$(call log.io, \
				${kwargs_namespace} ${sep}${dim} bound to ${no_ansi}${underline}$$$${_m}${no_ansi}) \
			&& $$(if $$(filter-out undefined,$$(origin ${kwargs_namespace}.__in__)),$$(${kwargs_namespace}.__in__),true) ;; \
	esac
${kwargs_namespace}=${make} ${kwargs_namespace}
# The callform seam: fold a call's space-form arg string into the interpreter-argv env, then
# dispatch the bare run target (which threads it down the file-seam and splices it at the machine).
# Without this the smart-send falls to the bare var, whose body has no positional, so args vanish.
${kwargs_namespace}.__call__ = CMK_LAMBDA_ARGV="$$(strip $${__args__})" ${make} ${kwargs_namespace}
# `.stream` -- the no-arg invoke (the Callable/Fragment stream face): run the body with empty argv.
${kwargs_namespace}.stream = ${make} ${kwargs_namespace}
# `.__concat__`/`.__add__` (`+`) fault on a code-object, bound or unbound: source concat means something only within ONE guest language (jqlang keeps its own), and sequencing runnables belongs at recipe scope.
${kwargs_namespace}.__concat__ = $$(call mk.error, cmk: NotImplemented/Concat: `${kwargs_def}` -- a code-object has no `+`: source concatenation is only meaningful within one guest language (e.g. jqlang)$$(comma) so sequence runnables at recipe scope$$(comma) or use `|` to pipe them, errno=NOT_IMPLEMENTED)
${kwargs_namespace}.__add__ = $$(call ${kwargs_namespace}.__concat__,$${__args__})
endif
endef
# code.unbound and code.config mint an unbound code-object.
code.config = $(call code.unbound, ${__args__})
# code.pipe composes two runnables at the process boundary.
# code: minter that also binds via machine=/entrypoint=/img=.
define _code.dispatch
$(call mk.unpack.kwargs, ${1}, machine, None)
$(call mk.unpack.kwargs, ${1}, entrypoint, None)
$(call mk.unpack.kwargs, ${1}, img, None)
$(call mk.unpack.kwargs, ${1}, cmd,)
$(call mk.unpack.kwargs, ${1}, file, None)
$(call mk.unpack.kwargs, ${1}, def)
$(call mk.unpack.kwargs, ${1}, namespace, ${kwargs_def})
ifneq (${kwargs_file}, None)
$$(eval define ${kwargs_def}$${nl}$$(file <${kwargs_file})$${nl}endef)
endif
ifneq (${kwargs_machine}, None)
$$(call code.unbound, $(patsubst machine=%,bind=%,$(filter-out file=%,${1})))
else ifneq ($(strip $(filter-out None,${kwargs_entrypoint} ${kwargs_img})),)
$$(if $$(filter-out undefined,$$(origin cmk.machine)),$$(call cmk.machine, def=${kwargs_namespace}.machine img=$(filter-out None,${kwargs_img}) entrypoint=$(filter-out None,${kwargs_entrypoint}) cmd=${kwargs_cmd}))
$$(call code.unbound, $(filter-out file=%,${1}) bind=${kwargs_namespace}.machine)
else
$$(call code.unbound, $(filter-out file=%,${1}))
endif
endef
$(call m5.def.!, code, _code.dispatch)

# Tower membership: a code-object is-a `cmk.Fragment` -- it provides the Callable invoke (its own
# `.__call__`/`.stream`), Materializable (shape/fd/file/blockref), and Templatable (render/mod).
# Literal mro names (hosted protocols load after this seed line; the predicate is load-order-free).
code.unbound.__bases__ := cmk.Fragment Templatable
code.unbound.__mro__   := code.unbound cmk.Fragment Callable Materializable Templatable

# Target decorator.
# Runs the implied private-target inside the given container.
# USAGE:
#   my_target:; $(call containerized.target, debian)
#   .my_target:; echo hello container `hostname`
define containerized.target
$(eval _data=$(m5[2]?)) true \
&& _hdr="${dim}${_GLYPH_IO}${dim} $(shell echo ${@}|sed 's/\/.*//') ${sep}${dim}" \
&& $(call _mk.unpack.kwargs,${_data},env,) \
&& $(call _mk.unpack.kwargs,${_data},quiet,$${quiet:-}) \
&& $(call _mk.unpack.kwargs,${_data},prefix,.) \
&& case $${CMK_INTERNAL} in \
	0)  ($(call log.rerouting, Invoked from top; rerouting to tool-container) \
		&& ${trace_maybe} \
		&& export env=`printf "$${env}"|sed 's/ /,/g'` \
		&& _disp=$(m5[1]).dispatch \
		&& _priv=$${prefix}$(strip ${@}) \
		&& ([ -z "$${env}" ] \
			|| $(call log.trace, $${_hdr} ${bold}env ${sep} ${green_flow_left}$${env})) \
		&& $(call log.base, $${_hdr} ${cyan_flow_right}${ital}$${_disp}/$${_priv}) \
		&& quiet=$${quiet} ${make} $${_disp}/$${_priv});; \
	*) quiet=$${quiet} ${make} $${prefix}$(strip ${@}) ;; \
esac
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: bind.* :: Run a target's body in a container or service
##
## See the docs: /compose.mk/style/#bind-declarations
##
## `docker.bind.script`/`compose.bind.script` run a target's own define-body in a container /
## compose service (used as the `@docker.bind.script(..)` / `@compose.bind.script(..)` decorators,
## and as the runtime under `(| .. |) in <service>`).  The old `docker_context`/`local_context`/
## `compose_context` as-clause macros (the retired `⨖ .. with .. as ..` sugar) are gone; run a
## body in a container via `(| .. |) in container(| img=.. |)` or a named `container`/`Dockerfile`
## instance, and in a service via `(| .. |) in <service>`.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

compose.bind.target=$(call containerized.target,${1},prefix=self. $(m5[2]?))
define compose.bind.script
$(call _mk.unpack.kwargs,${1},svc,${1}) \
&& $(call _mk.unpack.kwargs,${1},def,${@}) \
&& $(call _mk.unpack.kwargs,${1},entrypoint,$${entrypoint:-bash}) \
&& $(call _mk.unpack.kwargs,${1},entrypoint_args,-x) \
&& $(call _mk.unpack.kwargs,${1},env,$${env:-}) \
&& $(call _mk.unpack.kwargs,${1},quiet,$${quiet:-0}) \
&& $(call _mk.unpack.kwargs,${1},output,cat) \
&& $(call log.io, compose.bind.script ${sep} ${dim_cyan}$${def}) \
&& $(call log.io, ${green_flow_right} ${no_ansi_dim}svc=${no_ansi}$${svc} ${dim}entrypoint=${no_ansi}$${entrypoint}) \
&& ${log.rerouting} \
&& ( ${trace_maybe} \
	&& env="`printf "$${env}" | ${stream.space.to.comma}`" \
	&& ${io.mktemp} && ${mk.def.read}/$${def} > $${tmpf} \
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

# DEPRECATED: superseded by code-objects -- $(call code, def=X img=Y entrypoint=Z) (or code X(img= entrypoint=)(| |) in cmk-lang) runs a define/body in a machine; see demos/cmk/elixir-1.cmk + demos/script-dispatch-*.mk. Kept functional for back-compat.
# docker.bind.script -- run a define in a container.  The stock-image case (no `build=`) writes the
# def to a script and runs it directly via docker.run.sh (docker-native `<entrypoint> <cmd> <script>`,
# `env` riding the environment) -- the same runner file-sourced code-objects use.  The `build=` case (an
# inline Dockerfile built first) takes the same docker.run.sh path after the build.
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
&& $(call log.trace, docker.bind.script ${sep} def=$${def} img=$${img} entrypoint=$${entrypoint}) \
&& case $(strip $${build:-}) in \
	"") ${io.mktemp} && ${mk.def.to.file}/$${def},$${tmpf} \
			&& img="$${img}" entrypoint="$${entrypoint}" cmd="$${cmd:+$${cmd} }/workspace/$$(basename $${tmpf})" ${make} docker.run.sh;; \
	*) $(call log, building with $${build}/$${img}) \
		&& ${io.mktemp} && ${mk.def.read}/$${def} | ${stream.peek} > $${tmpf} \
		&& ${trace_maybe} && entrypoint=$${entrypoint} cmd="$${cmd} $${tmpf}" ${make} $${build}/$${img} docker.run.sh;; \
esac
endef

# One entry point for pulling values into a recipe's shell scope, dispatched on a `from=`
# selector.  Used inline (`$(call bind.args, from=env, port=8080)`) or as a decorator
# (`@bind.args(from=json, shape color=blue)`).  Each source expands to an `&&`-joined shell
# snippet the joinbody pass chains onto the recipe body, so the bindings reach every line.
#   from=json  export each `name[=default]` parsed from a JSON stream on stdin.
#   from=env   export/validate each `name[=default]` from the environment.
#   from=stem  (default) split the target stem ${*} by a delimiter (arg 2, default `,`) into
#              positional `_1st.._5th` + `_head`/`_tail`.  Needs a parametric `%` stem.
# The name-list / delimiter rides in the SECOND $(call) arg as one space-joined value; keep it
# comma-free (a comma splits it across $(call) positionals).  An unknown `from=` hard-errors.
bind.args=$(call _bind.args.route,$(or $(patsubst from=%,%,$(filter from=%,$(m5[1]))),stem),$(2))
_bind.args.route=$(if $(filter json env stem,$(1)),$(call _bind.args.$(1),$(m5[2])),$(call mk.error, bind.args: unknown source `$(1)` -- use from=json|env|stem, errno=BIND_ARGS))

# from=stem -- positional split of the target stem.
# `bind.posargs` is the named shorthand for the from=stem source; delimiter defaults to comma.
bind.posargs=$(call _bind.args.stem,$(m5[1]?))
_bind.args.stem=$(call _bind.args.stem.split,$(strip $(if $(1),$(1),${comma})))
define _bind.args.stem.split
kwargs_delim=$(1) \
&& _1st="$(call m5.__args__.cut,1,$(1))" \
&& _2nd="$(call m5.__args__.cut,2,$(1))" \
&& _3rd="$(call m5.__args__.cut,3,$(1))" \
&& _4th="$(call m5.__args__.cut,4,$(1))" \
&& _5th="$(call m5.__args__.cut,5,$(1))" \
&& _head="$(call m5.__args__.cut,1,$(1))" \
&& _tail="$(call m5.__args__.cut,2-,$(1))"
endef
define _bind.args.json
${trace_maybe} && [ -p /dev/stdin ] && input=$$(cat) || input=""; for arg in ${1}; do [[ $$arg =~ ^([^=]+)(=(.*))?$$ ]] && { val=$$(echo "$$input" | sed -n "s/.*\"$${BASH_REMATCH[1]}\"[[:space:]]*:[[:space:]]*\"\?\([^,}\"]*\)\"\?.*/\1/p"); export "$${BASH_REMATCH[1]}=$${val:-$${BASH_REMATCH[3]}}"; }; done
endef
define _bind.args.env
${trace_maybe} && for v in $1; do if [[ "$$v" =~ ^([^=]+)=(.+)$$ ]]; then n=$${BASH_REMATCH[1]}; [[ -z "$${!n}" ]] && export "$$n"="$${BASH_REMATCH[2]}" || true; else [[ -n "$${!v}" ]] || { echo "Error: $$v is not set or empty" >&2; exit 1; }; fi; done
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: help.* :: Help targets and macros
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Interactive rendering for the name-sorted target list: a bold heading per namespace root (the roots lang.mk.dir reports) over its members, parametric ones italic, wrapped on visible width since the styles do not count.
_help_group=awk -v w=$${width:-${io.term.width}} -v b="${bold}" -v i="${ital}" -v z="${no_ansi}" '{ n=$$0; d=index(n,"."); ns=(d>0)?substr(n,1,d-1):n; s=index(ns,"/"); if(s>0) ns=substr(ns,1,s-1); if(ns!=prev){ if(len>0) print line; if(prev!="") print ""; printf "%s%s:%s\n", b, ns, z; prev=ns; line=""; len=0 } m=(index(n,"%")>0)? i n z : n; if(len>0 && len+2+length(n)>w){ print line; line="  " m; len=2+length(n) } else { line=(len==0)? "  " m : line "  " m; len=(len==0)? 2+length(n) : len+2+length(n) } } END{ if(len>0) print line }'

# Explicit targets come from the database's Files section and pattern rules from Implicit Rules, so span both; a rule head can carry aliases, hence the word-split, and a dunder is private in any segment, not just the first.
define _help_gen
(LC_ALL=C $(MAKE) -pRrq -f $(firstword $(MAKEFILE_LIST)) : ${stderr_devnull} | awk -v RS= -F: '/(^|\n)# (Implicit Rules|Files)(\n|$$)/,/(^|\n)# Finished Make data base/ {if ($$1 !~ "^[#.]") {n=split($$1,a," "); for(i=1;i<=n;i++) print a[i]}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$' -e '(^|[./])__[A-Za-z0-9_]*__([./]|$$)' | LC_ALL=C sort| uniq || true)
endef

help.local: 
	@# Lists only local targets (no includes)
	@# Used from an included makefile, not with compose.mk itself. 
	$(call log, Listing local targets only)
	${mkparse} $${path:-${MAKEFILE}} --shallow --local --names-only
help.local.all:; ${mkparse} $${path:-${MAKEFILE}} --local --preview
	@# Shows all help for all local targets 

help.local/%: 
	@# Renders help for a local target, i.e. just the ones that do not come from includes.
	@# Used from an included makefile, not with compose.mk itself. 
	$(call log, Listing local targets only)
	${mkparse} $${path:-${MAKEFILE}} --local --preview --prefix ${*}

help/%:; ${mkparse} $${path:-${MAKEFILE}} --prefix ${*} --markdown --preview
	@# 

help:
	@# Attempts to autodetect the targets defined in this Makefile context.
	@# Older versions of make dont have '--print-targets', so this uses the 'print database' feature.
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
			&& if ${io.tty.stdout}; then ${_help_group} < $${tmpf}; else cat $${tmpf}; fi \
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


##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: .awk :: The compiler's awk stage definitions
##
## Lowering CMK-lang to a Makefile runs a pipeline of awk
## passes; each `.awk.<stage>` is an awk program stored as an inert `define` (read via `$(value)`,
## never expanded by make) carrying a `#:phase` pragma. A `lang.awk.stage`/`.comp`/`.export` call
## (in the registration block below) exports each as `_awklang_<name>` and mints its paired
## `.cmk.<stage>` pipe-fragment; the fused fast path chains them in one process, and each also gets
## a standalone `lang.comp.pipeline.<name>` debug target.
##
## The stages span dialect/sugar preprocessing, whitespace normalization (dedent/indent), the
## `@`-decorator rewrite, call-form and block/lambda lowering (callform, triplequote, blockref,
## lambdalift), the binding-form grammar (receivers, capture, fluent), the banana-opener grammar,
## moduledoc and lint passes, and the shared error/defskip/litparse preludes, ending in joinbody
## and unsentinel. Order among the `define`s here is irrelevant (they are inert text); only the
## registration block that reads them must follow. The subsystem-local `.awk.*` (super.stderr,
## completion.scan, rewrite.targets.maybe) live with their subsystems, not here.
##
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# Join `\`-continuation lines into one logical line (stdin->stdout), outside
# of define..endef blocks (depth-tracked), which pass through verbatim.
# Used by the minify stage so later passes see one statement per recipe
# line.
#:phase COMPILE seed=1 awklang=no
define .awk.zip
  BEGIN { def_depth = 0; continuation_line = "" }
  # Verbatim regions pass through UNTOUCHED -- including col-0 `#`, so embedded foreign-code
  # directives (C `#include`/`#define`, PEP-723 `# /// ... ///`, shebangs, comments) survive:
  # inside `define..endef` blocks and multi-line bananas.  The trailing `/^#/{next}` does the
  # top-level comment-strip that used to be a separate `grep -v '^#'` (which wrongly stripped
  # inside these blocks -- the bug this guard fixes).
  inbanana == 1 { print; if ($0 ~ /^[ \t]*\|[])}]/) inbanana = 0; next }
  /@@SYM_DEFINE@@ / { def_depth++; print; next }
  /^endef[ \t]*$/ { if (def_depth > 0) def_depth--; print; next }
  def_depth > 0 { print; next }
  # a pending `\`-continuation must be JOINED (below) before matching a banana open, so a
  # continued line like `(| .. |) \` <newline> `in container(| .. |)` reassembles as one line
  # (else the `in container(|` tail would misfire this rule and print out of order).  The
  # `\\[ \t]*$` guard is the twin for the INITIATING line: a banana line that itself ends in a
  # `\`-continuation (e.g. `NAME(| .. |) \` <newline> `.method(| .. |)`, a chain split over
  # lines) must ALSO fall through to the joiner -- a trailing `\` outside a banana body is a pure
  # line-join, never content, so it is never printed verbatim (else it survives as a stray token).
  length(continuation_line) == 0 && $0 !~ /\\[ \t]*$/ && /^[ \t]*(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/ { print; if ($0 !~ /\|[])}]/) inbanana = 1; next }
  /^#/ { next }
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

# Smart, optional dedent for multi-line banana blocks (stdin->stdout): a
# body indented for visual nesting still lands its banana heads at column 0
# once copied into a `define NAME..endef`.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.dedent
  # Nesting-aware dedent: strip each banana body's OWN leading indent so its heads land at column
  # 0, for ARBITRARY nesting (`*[| .. X[| .. |) .. |]`).  A frame stack tracks the open bananas;
  # each frame's `bp` (body-prefix) is the leading whitespace of its FIRST non-blank child, learned
  # on the fly.  A content line is stripped by its innermost frame's `bp`; an opener/closer sits at
  # the ENCLOSING frame's child level, so it is stripped by THAT frame's `bp`.  A `'''`-fenced
  # docstring is opaque to banana scanning (its prose may mention `X[|`) but is still dedented.
  # Recipe re-tabbing (and tab/space validation) stays in the `indent` stage, which now always sees
  # col-0 heads; dedent MUST leave a `\`-continued recipe line (which legitimately carries a tab+space
  # continuation indent) untouched.  A `'''` docstring and a raw `define`/`endef` (heredoc/payload) are
  # OPAQUE to banana scanning -- their prose/content may contain `X[|`/`|)` -- but are still dedented
  # with their frame.  A line whose prefix does not extend the base is left as-is (a stray comment is
  # harmless); an unbalanced block is a fail-fast parse error (`.awk.cmk.errors`), not silent weirdness.
  BEGIN { sp = 0; fence = 0; indef = 0 }
  function _lead(s) { match(s, /^[ \t]*/); return substr(s, 1, RLENGTH) }
  function _strip(s, p) { return (substr(s, 1, length(p)) == p) ? substr(s, length(p) + 1) : s }
  # _walk(s): step the frame stack over EVERY banana boundary on `s` (via the shared `_bnext`),
  # WHEREVER it sits.  Intra-line open/close pairs cancel; a close with no open still open on this
  # line pops a frame from a PREVIOUS line; opens unclosed at EOL push new frames (declaration `n`
  # -> body dedented; anon `a` bare `(|` lambda -> verbatim, lambdalift's `_mll_dedent` owns it).
  function _walk(s,   ld, i) {
      ld = 0
      while (_bnext(s)) {
          if (_bk == "c") { if (ld > 0) ld--; else if (sp > 0) sp-- }
          else { ld++; _lk[ld] = (_isnamed(_bp) ? "n" : "a"); _ln[ld] = _fname(_bp) }
          s = _brest
      }
      for (i = 1; i <= ld; i++) { sp++; hb[sp] = 0; bp[sp] = ""; warned[sp] = 0; fkind[sp] = _lk[i]; fname[sp] = _ln[i] }
  }
  # dedent a CONTENT line by the innermost frame base
  function _emit(s) {
      # top level, or an anon-lambda body -> verbatim
      if (sp == 0 || fkind[sp] == "a") { print s; return }
      if (s ~ /^[ \t]*$/) { print ""; return }
      if (!hb[sp]) { bp[sp] = _lead(s); hb[sp] = 1; print _strip(s, bp[sp]); return }
      # a tab-led line under a space-based frame is a make recipe body (its leading tab is
      # meaningful and absolute); it never carries the space base, so pass it verbatim without
      # flagging it -- the base-mismatch warning is for misindented CMK content, which is
      # space-indented by convention, never a bare tab.
      if (s ~ /^\t/ && bp[sp] !~ /\t/) { print s; return }
      # a line less-indented than the base is inconsistent -- warn once, pass verbatim
      if (substr(s, 1, length(bp[sp])) != bp[sp]) {
          if (!warned[sp]) { cmk_warn("dedent", "block `" fname[sp] "`: inconsistent indentation (a line is less-indented than the " length(bp[sp]) "-column body base); passed through verbatim"); warned[sp] = 1 }
          print s; return }
      print _strip(s, bp[sp])
  }
  # inside a ''' docstring: opaque to banana scanning, still dedented with its frame
  fence == 1 { _emit($0); if ($0 ~ /^[ \t]*'''[ \t]*$/) fence = 0; next }
  # inside a raw define/endef (heredoc/payload): opaque, still dedented
  indef > 0 { _emit($0); if ($0 ~ /^[ \t]*define[ \t]/) indef++; else if ($0 ~ /^[ \t]*endef[ \t]*$/) indef--; next }
  $0 ~ /^[ \t]*'''[ \t]*$/ { _emit($0); fence = 1; next }
  # a raw define opens an opaque heredoc/payload
  $0 ~ /^[ \t]*define[ \t]/ { _emit($0); indef = 1; next }
  # a comment line: dedent as content, but its `(|`/`|)` are INERT -- a banana form written in a
  # comment (an example, a doc-block) is not a construct, so it must not step the frame stack
  $0 ~ /^[ \t]*@?#/ { _emit($0); next }
  # a line whose FIRST token is a closer sits at the ENCLOSING frame's child level: strip by that
  # frame's bp, pop, then walk any trailing `|).ctor(|` reopen / cascade uniformly
  sp > 0 && $0 ~ /^[ \t]*\|[])}]/ {
      if (sp > 1) { if (!hb[sp-1]) { bp[sp-1] = _lead($0); hb[sp-1] = 1 } line = _strip($0, bp[sp-1]) } else line = $0
      print line; sp--
      rest = line; sub(/^[ \t]*\|[])}]/, "", rest); _walk(rest); next
  }
  # content / opener / compact chain: emit by the innermost base, then re-balance across all delimiters
  { _emit($0); _walk($0) }
  END { if (sp != 0) cmk_die("dedent", "unbalanced banana block: " sp " unclosed at end of input") }
endef

# Python-style indentation for CMK recipe bodies (stdin->stdout):
# tab-indented lines pass through verbatim; a space-indented body is
# normalized to a single leading tab (one consistent indent required).
# Errors (cmk_die) on tabs+spaces mixed in one indent, or inconsistent
# space-indents in a body. Skips define..endef bodies (depth-tracked).
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.indent
  BEGIN { sp = 0; space_unit = ""; cont = 0 }
  # A cooked banana (`⟅NAME`/`⟆`, unsentineled to define/endef LATER) holds cmk code --
  # targets + recipes -- so DESCEND and normalize a space-indented recipe to a tab, just
  # like an encapsulation ambient (`*[| |]` -> `define __ambient_N` / `⟅__ambient_N`).
  # A raw `define` (foreign payload / heredoc) stays OPAQUE.  These NEST (a cooked class
  # inside an ambient; a raw define inside a cooked class), so track a FRAME STACK: `amb`
  # = descend, `def` = opaque; normalize only when the innermost frame is `amb`.  Inside
  # an amb frame a cosmetic declaration (not under a target) stays verbatim (`rec`), and a
  # `\`-continued recipe line passes verbatim (`cont`) so a tab+spaces continuation lives.
  /@@SYM_DEFINE@@ __ambient_/ || /^define[ \t]+__ambient_/ || /^⟅/ { stk[++sp] = "amb"; rec[sp] = 0; space_unit = ""; cont = 0; print; next }
  /@@SYM_DEFINE@@ / || /^define[ \t]/ { stk[++sp] = "def"; space_unit = ""; cont = 0; print; next }
  /^endef[ \t]*$/ || /^⟆[ \t]*$/ { if (sp > 0) sp--; space_unit = ""; cont = 0; print; next }
  sp > 0 && stk[sp] == "def" { print; next }   # inside a raw define (payload/heredoc) -- verbatim
  /^[ \t]*$/ { print; next }
  /^[ \t]/ {
      if (sp > 0 && !rec[sp]) { print; next }   # cosmetic declaration inside an amb frame (not under a target) -- verbatim
      if (sp > 0 && cont) { cont = ($0 ~ /\\[ \t]*$/); print; next }   # `\`-continued recipe line -- verbatim (a tab+spaces continuation survives)
      match($0, /^[ \t]*/); lead = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH+1)
      if (lead ~ /\t/ && lead ~ / /) cmk_die("indent", "indentation mixes tabs and spaces: " rest)
      if (lead ~ / /) {
          if (space_unit == "") space_unit = lead
          else if (lead != space_unit) cmk_die("indent", "inconsistent indentation in recipe body (expected " length(space_unit) " spaces): " rest)
          if (sp > 0) cont = (rest ~ /\\[ \t]*$/); print "\t" rest
      } else { if (sp > 0) cont = ($0 ~ /\\[ \t]*$/); print $0 }
      next
  }
  { if (sp > 0) rec[sp] = ($0 ~ /^[^ \t][^=]*:([^=]|$)/) ? 1 : 0   # a col-0 rule header opens a recipe context; a declaration closes it
    space_unit = ""; cont = 0; print }
endef

# Relocate `@`-decorator lines (a column-0 `@name` written above a target)
# into that target's recipe: a prefix decorator joins ahead of the body so
# its bindings reach every line, a postfix one chains after the body by a
# connector, and a decorator may declare a default postfix mode via a
# companion line.
#:phase COMPILE seed=1 awklang=no
define .awk.decorators
  # CMK bind-declarations use a leading `@` (column 0, python-decorator style),
  # written on the line(s) IMMEDIATELY ABOVE a target.  `@<name>` is normalised here to
  # `cmk.<name>` directly (dialect then lowers `cmk.`->`؆`->`$(call <name>,..)`).  A
  # decorator is thus just an ordinary callform macro applied as a line above a target --
  # there is no reserved namespace, so any existing macro (`@log`, `@io.pushd`,
  # `@docker.bind.script`) decorates for free.
  # Safe: make's `@` is recipe-only (tab-indented), decorators are column-0, gated on `!in_def`.
  # By DEFAULT they relocate to the leading recipe
  # line(s) of that target, so the later joinbody pass chains `decorator && body` into
  # one shell (the decorator's exports/bindings then reach every recipe line).  A
  # decorator carrying a `postfix_mode=<conn>` kwarg instead relocates to after the
  # body, chained to it by <conn> -- one of `&&` (default; run after success), `;` (run
  # always), or `||` (run only on failure: a per-target catch).  The kwarg is stripped
  # before the macro call.  A decorator can also declare a DEFAULT mode via a companion
  # `<name>.postfix_mode := <conn>` line (scanned here into pdefault[]), so a bare
  # `@<name>` is treated as postfix without repeating the kwarg; an explicit kwarg still
  # wins.  The compiler runs before the compiled makefile's vars exist, so this default
  # must be visible in the SOURCE TEXT (hence a scanned companion line, not $(eval)) and
  # must appear before the decorator is used.  `@foo(a)` lowers to `cmk.foo(a)` ->
  # `$(call foo,a)`.  Body lines are re-emitted verbatim (they
  # keep their own tab/space indent, which the indent stage normalises); only injected
  # decorator lines get a leading tab.  joinbody honours a line's trailing connector, so
  # a non-`&&` postfix mode is realised by appending <conn> to the PRECEDING emitted line.
  function is_target(s) { return (s ~ /^[^\t#][^=]*:([^=]|$)/) }
  function classify(line,   conn, cleaned, name) {
      # Sort a buffered `cmk....` line into pre[] (prefix) or post[]/postc[] (postfix).  An
      # explicit `postfix_mode=` kwarg wins; otherwise consult the pdefault[] registry.
      conn = ""
      if (line ~ /postfix_mode/) {
          conn = line; sub(/.*postfix_mode=?/, "", conn); sub(/[,)].*/, "", conn)
          if (conn == "") conn = "&&"
          cleaned = line
          if (!sub(/,[ \t]*postfix_mode(=[^,)]*)?[ \t]*/, "", cleaned)) sub(/[ \t]*postfix_mode(=[^,)]*)?[ \t]*,?[ \t]*/, "", cleaned)
          sub(/\([ \t]*,[ \t]*/, "(", cleaned)
      } else {
          name = line; sub(/^cmk\./, "", name); sub(/\(.*/, "", name); sub(/[ \t]+$/, "", name)
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
      if ($0 ~ /^[A-Za-z._][A-Za-z0-9._]*\.postfix_mode[ \t]*:?=/ && !in_def) {
          dname = $0; sub(/\.postfix_mode[ \t]*:?=.*/, "", dname)
          dmode = $0; sub(/.*\.postfix_mode[ \t]*:?=[ \t]*/, "", dmode); sub(/[ \t]*$/, "", dmode)
          pdefault[dname] = dmode; print; next
      }
      # `@name`/`@name(args)` is a decorator, but `@name = ..`/`@name := ..` is a legal make
      # ASSIGNMENT (a var literally named `@name`) -- skip those (an `=` before any `(`).
      if ($0 ~ /^@[A-Za-z._]/ && !in_def && $0 !~ /^@[^(=]*=/) { sub(/^@/, "cmk."); classify($0); next }
      if (pren > 0 || postn > 0) {
          if (!is_target($0)) cmk_die("decorators", "a @ decorator must be immediately above a target (no blank line between)")
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
      if ($0 ~ /@@SYM_DEFINE@@ /) { in_def = 1; print; next }
      if ($0 ~ /^endef[ \t]*$/) { in_def = 0; print; next }
      if (in_def) { print; next }
      print $0
  }
  END { if (inpost) emit_post(); if (pren > 0 || postn > 0) cmk_die("decorators", "trailing @ decorator has no target") }
endef

# .awk.json5 / lang.comp.stage.json5: tolerant JSON5 -> strict JSON for the
# compiler hints. Hand-written pragma headers may carry conveniences jq's
# strict parser rejects, so it drops `//` line-comments (guarding a `://`
# inside a URL) and trailing commas before `}`/`]`. Not a full JSON5 parser
# (no block comments, no unquoted keys), just enough for the small
# hand-authored knob-objects the hints carry.
#:phase COMPILE seed=1 awklang=no
define .awk.json5
function _j5_strip(s,   off,pos,c) {
  off=0
  while (1) {
    pos=index(substr(s,off+1),"//"); if (pos==0) return s
    pos=off+pos; c=(pos==1)?"":substr(s,pos-1,1)
    if (c==""||c==" "||c=="\t"||c=="{"||c=="["||c==",") return substr(s,1,pos-1)
    off=pos+1
  }
}
{ buf=buf _j5_strip($0) "\n" }
END { gsub(/,[ \t\r\n]*}/,"}",buf); gsub(/,[ \t\r\n]*]/,"]",buf); printf "%s",buf }
endef

# Namespace a module body (stdin->stdout): prefix every top-level
# assignment/target LHS with `<ns>.`.  Recipe lines, comments, blanks, RHS
# values, private `.`/`_` names, and nested define bodies (depth-tracked)
# all pass through verbatim. Read via `$(value)` so awk's `$0`/`$` survive
# make expansion.
#:phase SEED-PARSE seed=1 awklang=no
define .awk.module.namespace
  function flushbuf() { printf "%s", pbuf; pbuf=""; pstate=0 }
  pstate==1 { pbuf = pbuf $0 "\n"; if ($0 ~ /^[ ]*define[ ]/) bd++; else if ($0 ~ /^[ ]*endef[ ]*$/) { if (--bd==0) pstate=2 }; next }
  pstate==2 { if ($0 ~ ("[$][(]call [^,]*,[ ]*def=" pbufname "([ \t,)]|$)")) { ren=pbuf; sub(/^[ ]*define[ \t]+[A-Za-z_][A-Za-z0-9_.]*/, "define " ns "." pbufname, ren); printf "%s", ren; sub(/def=[A-Za-z_][A-Za-z0-9_.]*/, "def=" ns "." pbufname); print; pstate=0; pbuf=""; next } flushbuf() }
  /^\t/ { print; next }
  /^[ ]*#/ { print; next }
  /^[ ]*$/ { print; next }
  frags && /^[ ]*[$][(]eval define [A-Za-z_][A-Za-z0-9_.]*[.]__doc__/ { sub(/[$][(]eval define /, "$(eval define " ns "."); print; next }
  frags && /^[ ]*define[ ]/ && depth==0 { pstate=1; pbufname=$2; pbuf=$0 "\n"; bd=1; next }
  /^[ ]*define[ ]/ { depth++; print; next }
  /^[ ]*endef[ ]*$/ { if (depth>0) depth--; print; next }
  depth > 0 { print; next }
  /^\./ { print; next }
  !dunders && /^_/ { print; next }
  /^[A-Za-z_][A-Za-z0-9_.%\/-]*[ \t]*[:=+?!]/ { print ns "." $0; next }
  { print }
  END { if (pstate) flushbuf() }
endef

# Strip the minimal common leading-space indent from a captured banana body,
# so the indent stage can re-tab its recipes and the namespace stage can
# prefix its column-0 heads. Backs the namespace ctor.
#:phase SEED-PARSE seed=1 awklang=no
define .awk.ns.dedent
  NF { s = $0; gsub(/[^ ].*/, "", s); if (min == "" || length(s) < min) min = length(s) }
  { L[NR] = $0 }
  END { for (i = 1; i <= NR; i++) print substr(L[i], min + 1) }
endef

# Lower container-dispatch call sugar: rewrite every `NAME.dispatch(args)`
# on a line to `NAME.dispatch/args`.
#:phase COMPILE seed=1 awklang=no
define .awk.dispatch
  { while (match($0, /[[:alnum:]_.]+\.dispatch\([^)]+\)/)) {
      before = substr($0, 1, RSTART-1); after = substr($0, RSTART+RLENGTH)
      seg = substr($0, RSTART, RLENGTH)
      dargs = seg; sub(/^.*\.dispatch\(/, "", dargs); sub(/\)$/, "", dargs)
      dname = seg; sub(/\.dispatch\([^)]*\)$/, "", dname)
      $0 = before dname ".dispatch/" dargs after
      }
      print }
endef
# Sugar-block lowering: turn a `<open>NAME .. <close>` marked block (the
# open/close regexes and output template arrive via ARGV) into a `define
# NAME .. endef`, substituting the block's `with ..`/`as ..` trailer into
# the template placeholders. The trailer may spill onto the lines after the
# close marker.
#:phase COMPILE seed=1 awklang=no
define .awk.sugarawk
  BEGIN {
   if (ARGC < 3) {
      print "Usage: script.awk open_pattern close_pattern post_process_template" > "/dev/stderr"
      exit 1 }
   open_pattern = ARGV[1]; close_pattern = ARGV[2]
   post_process_template = ARGV[3]
   delete ARGV[1]; delete ARGV[2]; delete ARGV[3]
   # Three emit modes share one engine (block tracking + trailer parse + `build_call`):
   #  __GENERIC__            => banana `NAME(| .. |)`: name-prefix + leading dotpath + with/using
   #  __CALL__ d CTOR KW..   => a declaration row: CTOR/KW may carry __WITH__/__NAME__ placeholders
   #                            filled from the trailer (the `d` mode field is retained for the table)
   #  (anything else)        => a raw __NAME__/__WITH__/__REST__ template (custom `cmk_sugar`)
   generic = (post_process_template == "__GENERIC__")
   callmode = (post_process_template ~ /^__CALL__[ \t]/)
   if (callmode) {
      _n = split(post_process_template, _T, /[ \t]+/)
      spec_ctor = _T[3]; spec_kw = ""   # _T[2] is the mode field (`d`; runtime `r` retired with the with/as trailer)
      for (_i = 4; _i <= _n; _i++) spec_kw = (spec_kw == "" ? _T[_i] : spec_kw " " _T[_i])
   }
   # BANANA-BRACKET FAMILIES.  `(|` is raw (no treatment); `[|` deep-cooks (built in); extra
   # opens (e.g. `{|`) map to a treatment from the `block_brackets` pragma
   # (env CMK_PRAGMA_BLOCK_BRACKETS, entries `<open><close>=<treatment>`, e.g. `{}=stream.echo`).
   # A frame records BTREAT[<its open char>] as fcook[]; frame_emit feeds it through the same
   # postfix-treatment path a trailing `cooked`/`cooked_deeply`/<target> word takes -- so a
   # bracket is a first-class block delimiter, never a synthesized trailer.
   BTREAT["["] = "cooked_deeply"
   _n = split(ENVIRON["CMK_PRAGMA_BLOCK_BRACKETS"], _BB, /[ \t]+/)
   for (_i = 1; _i <= _n; _i++) {
      if (_BB[_i] == "") continue
      _eq = index(_BB[_i], "="); if (_eq < 3) continue
      BTREAT[substr(_BB[_i], 1, 1)] = substr(_BB[_i], _eq + 1) }
  }
  # Build one lowered DECLARATION call: `$(call CTOR, def=NAME KW)`.  A comma separating two kwargs is a
  # call-arg boundary that make splits on, dropping every kwarg after the first; normalize those to
  # spaces.  A comma inside a single value (a list) has no `key=` after it, so it is left intact for the
  # per-kwarg handler to recover.
  function build_call(name, ctor, kw,   out, i, c, inq, _go, _gr, _seg) {
   _go = ""; _gr = kw
   while (match(_gr, /,[[:space:]]*[[:alnum:]_.]+=/)) {
    _seg = substr(_gr, RSTART, RLENGTH); sub(/^,[[:space:]]*/, "", _seg)
    _go = _go substr(_gr, 1, RSTART - 1) " " _seg
    _gr = substr(_gr, RSTART + RLENGTH) }
   kw = _go _gr
   # quoted spaced value (cmd='run --script') word-splits under mk.kwargs.get: strip quotes, rewrite in-quote spaces to the CMK_KWARGS_SP sentinel (one make word; capture un-sentinels), same as _mk.unpack.kwargs.tokenize.
   if (index(kw, "'")) { out = ""; inq = 0; if (KWSP == "") KWSP = ENVIRON["CMK_KWARGS_SP"]
     for (i = 1; i <= length(kw); i++) { c = substr(kw, i, 1)
       if (c == "'") { inq = !inq; continue }
       if (c == " " && inq) { out = out KWSP; continue }
       out = out c }
     kw = out }
   return "$(call " ctor ", def=" name (kw != "" ? " " kw : "") ")"
  }
  # Emit line S from banana frame at depth D: to the PARENT frame's body buffer when
  # nested (d>1), else to stdout.  This is what makes nesting work -- a closed inner
  # banana's `define`/sentinel lines land inside the outer banana's (still-buffering) body.
  function out(s, d) { if (d > 1) fbody[(d - 1), ++fbn[d - 1]] = s; else print s }
  # quoted source inside a make error function: unbalanced parens or a sigil would eat the diagnostic, so swap them for lookalikes
  function fault_safe(s) { gsub(/\(/, "\342\246\207", s); gsub(/\)/, "\342\246\210", s); gsub(/\{/, "\342\246\203", s); gsub(/\}/, "\342\246\204", s); gsub(/\$/, "\302\244", s); return s }
  # Emit frame D's buffered PRIMARY body as `define NAME`/`⟅NAME⟆` per its bracket cook flag
  # (fcook[d]): `cooked_deeply` deep-cooks (rewrite nested define/endef too), `cooked` shallow.
  # Shared by the multi-body flush sites so a `[| A |][| B |]` cooks every body, not just via
  # frame_emit's single-body path.
  function fdef(nm, d,   _j, _line, _ck, _rc) {
   _ck = (fcook[d] == "cooked" || fcook[d] == "cooked_deeply"); _rc = (fcook[d] == "cooked_deeply")
   out(_ck ? "⟅" nm : "define " nm, d)
   for (_j = 1; _j <= fbn[d]; _j++) { _line = fbody[d, _j]; if (_rc) { sub(/@@SYM_DEFINE@@ /, "⟅", _line); sub(/^endef[ \t]*$/, "⟆", _line) } out(_line, d) }
   out(_ck ? "⟆" : "endef", d) }
  # multi-BODY `(| A |)(| B |)..`: peel leading COMPLETE one-liner blocks off `s`, emit each
  # as `define <base>__<k>` (k from the frame's fMBIDX), and append `def<k>=..` to fMBN[d].
  # Blocks may be joined by bare adjacency or an explicit `+` (the same composition, spelled
  # out): `(| A |) + (| B |)`.  Single-line only -- a `+`/block spanning a newline is not peeled.
  # Returns the leftover (real trailer, or a lone `(|` = a multi-line next body).
  function mb_peel(s, base, d,   ci, b, _ck, _t) {
   _ck = (fcook[d] == "cooked" || fcook[d] == "cooked_deeply")   # extra bodies inherit the frame's cook
   while (1) {
      _t = s; sub(/^[ \t]+/, "", _t); sub(/^\+[ \t]*/, "", _t)   # skip ws + an optional explicit `+`
      if (bopen(_t) != 1) break                                 # next token isn't a block -> real trailer, stop
      ci = bclose(substr(_t, 3))
      if (ci == 0) break                                        # open with no close here -> lone multi-line opener; leave `s` for caller
      s = _t                                                    # commit (consume ws/`+`) now a complete block is confirmed
      b = substr(s, 3, ci - 1); sub(/^[ \t]+/, "", b); sub(/[ \t]+$/, "", b)
      fMBIDX[d]++
      out(_ck ? "⟅" base "__" fMBIDX[d] : "define " base "__" fMBIDX[d], d); if (b != "") out(b, d); out(_ck ? "⟆" : "endef", d)
      fMBN[d] = fMBN[d] (fMBN[d] == "" ? "" : " ") "def" fMBIDX[d] "=" base "__" fMBIDX[d]
      s = substr(s, 3 + ci + 1) }
   sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # A postfix TREATMENT that is not a builtin awk subroutine (cooked/cooked_deeply) is a
  # TARGET name: shell the buffered body through `${CMK_BIN} <target>` (compose.mk's own
  # invocation path, so it works from any CWD) at COMPILE time and take back whatever it emits
  # (`stream.echo` = identity).  Sets `_treat_rc` to the target's exit status -- a non-zero
  # (missing/failed target) is a COMPILE error at the call site, not a silent fallback.  Only
  # stdlib/plugin targets resolve here -- the file's own targets are not yet loaded at compile.
  function shell_treat(t, body,   cmd, line, res, tf, bin, _trc, _mk, _p) {
   bin = (ENVIRON["CMK_BIN"] != "" ? ENVIRON["CMK_BIN"] : "./compose.mk")
   tf = ".tmp.cmk.treat." (pid != "" ? pid : ENVIRON["CMK_RUN_ID"]) "." (++_treatseq)
   printf "%s", body > tf; close(tf)
   cmd = bin " " t " < " tf " 2>/dev/null; printf \"\\037CMK_TREAT_RC=%s\\n\" \"$?\""
   res = ""; _trc = ""; _mk = sprintf("%cCMK_TREAT_RC=", 31)
   while ((cmd | getline line) > 0) { _p = index(line, _mk); if (_p == 1) _trc = substr(line, length(_mk) + 1); else if (_p > 1) { _trc = substr(line, _p + length(_mk)); res = res substr(line, 1, _p - 1) "\n" } else res = res line "\n" }
   close(cmd); system("rm -f " tf)
   _treat_rc = (_trc == "") ? 1 : _trc + 0
   return res }
  # fbody_join(d) -- the frame's buffered body lines, newline-joined (bodies are already
  # col-0 from the dedent stage; bash ignores any residual leading space anyway).
  function fbody_join(d,   k, s) { s = ""; for (k = 1; k <= fbn[d]; k++) s = s (k > 1 ? "\n" : "") fbody[d, k]; return s }
  # dot_emit(d, lead) -- lower a recipe-position banana DOT-CHAIN.  Operand construction (a real
  # `define __<class>.<seq>.<k>` per operand + its `lang.grammar.dot.new`) and the left-assoc `.__dot__` fold are
  # HOISTED to module scope: buffered in `_DL[]`, flushed at END (mirroring the single-line
  # lambdalift dot arm).  This is mandatory, not cosmetic -- constructing a target-stamping kind
  # (container/Dockerfile) inside the recipe is illegal ("prerequisites cannot be defined in
  # recipes").  Only the `.__call__` run-for-effect stays inline in the recipe.
  function chain_kwlink(rem,   s, i, c, d2, k, after, ci) {
   if (rem !~ /^\.[ \t]*@@SYM_NAME@@+\(/) return 0
   s = rem; sub(/^\.[ \t]*/, "", s); match(s, /\(/); _clname = substr(s, 1, RSTART - 1)
   s = substr(s, RSTART); d2 = 0; k = 0
   for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
      if (c == "(") d2++; else if (c == ")") { if (--d2 == 0) { k = i; break } } }
   if (k == 0) return 0
   _clkw = substr(s, 2, k - 2); sub(/^[ \t]+/, "", _clkw); sub(/[ \t]+$/, "", _clkw)
   s = substr(s, k + 1); sub(/^[ \t]+/, "", s)
   if (bopen(s) != 1) return 0
   after = substr(s, 3); ci = bclose(after)
   _clbody = (ci > 0 ? substr(after, 1, ci - 1) : after)
   sub(/^[ \t]+/, "", _clbody); sub(/[ \t]+$/, "", _clbody)
   return 1 }
  function dot_emit(d, lead,   k, id, nm) {
   id = ++_dotseq
   for (k = 1; k <= fdc[d]; k++) {
      nm[k] = "__" (fdctor[d, k] != "" ? fdctor[d, k] : "frag") "." id "." k
      _DL[++_dln] = "define " nm[k] "\n" (fdbody[d, k] == "" ? "" : fdbody[d, k] "\n") "endef"
      _DL[++_dln] = "$(call lang.grammar.dot.new," fdctor[d, k] "," nm[k] ")" }
   _DL[++_dln] = "__dopacc_" id " := " nm[1]
   for (k = 2; k <= fdc[d]; k++) _DL[++_dln] = "__dopacc_" id " := $(call lang.grammar.dot.op,$(__dopacc_" id ")," nm[k] ")"
   print lead "$(call lang.grammar.dot.run,$(__dopacc_" id "))" }
  # _dotchain_tail(d, rem): record the operand that just closed (this frame's buffered body), then
  # consume the `.ctor(| body |)` tail in `rem` -- each operand COMPLETE inline (via the shared
  # `_bnext`) or, if the last opens with no close on the line, a MULTILINE open.  Returns 1 to STAY
  # in the frame (a multiline operand's body follows), 0 when the chain is fully consumed inline.
  # Shared by the close rule (multiline-first chains) and the opener (single-line-first chains).
  function _dotchain_tail(d, rem,   dc, db) {
   fdc[d]++; fdctor[d, fdc[d]] = (fdc[d] == 1 ? fn[d] : fdnextctor[d]); fdbody[d, fdc[d]] = fbody_join(d); fbn[d] = 0
   while (rem ~ /^\.[ \t]*(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/) {
      _bnext(rem); dc = _bp; sub(/^\.[ \t]*/, "", dc); sub(/[ \t]*$/, "", dc); gsub(/[ \t]+/, ".", dc)   # _bk=o, _bp=`.ctor`
      if (!_bnext(_brest)) { fdnextctor[d] = dc; return 1 }              # no close on the line -> multiline open, stay
      db = _bp; sub(/^[ \t]+/, "", db); sub(/[ \t]+$/, "", db)          # _bk=c, _bp = the operand's inline body
      fdc[d]++; fdctor[d, fdc[d]] = dc; fdbody[d, fdc[d]] = db
      rem = _brest; sub(/^[ \t]+/, "", rem); sub(/[ \t]+$/, "", rem) }
   return 0 }
  # Finalize the banana frame at depth D (its `|)` reached, trailer in pending_remainder):
  # parse the trailer, run ORPHAN-arg checks, emit `define`/`endef` -- or `⟅`/`⟆` cook
  # sentinels for a `cooked`/`cooked_deeply` postfix -- around the buffered body, then the
  # PREFIX constructor / value-form.  `cooked_deeply` also DEEP-cooks: it rewrites any nested
  # `define`/`endef` in the body (from closed inner bananas) to `⟅`/`⟆`, so the subtree cooks.
  # A postfix that is not a builtin (cooked/cooked_deeply) is a TARGET treatment: the body is
  # piped through it (shell_treat) before it is emitted.
  function frame_emit(d,   _ck, _rc, _nt, TT, _bd, _nn, _BL, _err, _bi, np, PF, cap, _line, ctor, _ekw, _kn) {
   parse_trailer(pending_remainder)
   # A recipe-scope PLAIN BARE `<indent>NAME(| body |)` (no prefix ctor / assignment / cook / dissolve /
   # kwargs / trailer, single-line): the name is a CTOR applied in a recipe, not a `define NAME`.  Sugar's
   # look-ahead already ruled out a dot-chain, so re-emit the raw banana and let lambdalift lower it (it
   # owns the module-scope hoist + ctor/machine semantics).
   if (fdlead[d] ~ /[ \t]/ && fc[d] == "" && fl[d] == "" && fop[d] == "" && !fdis[d] && fcook[d] == "" && fkw[d] == "" && t_with == "" && t_using == "" && t_postfix == "" && fbn[d] <= 1) {
      out(fdlead[d] fn[d] "(| " (fbn[d] == 1 ? fbody[d, 1] : "") " |)", d); return }
   # A `[|`/`{|` frame carries its treatment (fcook[d]) as the leading POSTFIX word, so a bracket
   # composes with any trailing `with`/`,`-postfixes and reuses the cook / shell_treat path below.
   if (fcook[d] != "") t_postfix = (t_postfix == "" ? fcook[d] : fcook[d] ", " t_postfix)
   _ck = 0; _rc = 0; _nt = 0
   ctor = fc[d]
   _ekw = fkw[d]; if (t_using != "") _ekw = (_ekw == "" ? t_using : _ekw " " t_using)   # paren kwargs + `using` kwargs
   if (_ekw != "" && ctor == "") out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": `using`/paren kwargs with no PREFIX constructor)", d)
   if (t_with != "" && t_postfix == "" && !_ck) out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": `with` args with no POSTFIX treatment)", d)
   np = split(t_postfix, PF, /[ \t]*,[ \t]*/)
   for (_bi = 1; _bi <= np; _bi++) {
      if (PF[_bi] == "cooked" || PF[_bi] == "cooked_deeply") { _ck = 1; if (PF[_bi] == "cooked_deeply") _rc = 1 }
      else if (PF[_bi] != "") TT[++_nt] = PF[_bi]   # non-builtin -> target treatment
   }
   if (fop[d] == ":=") _ck = 1   # assignment-form: `:=` COOKS the body (`=` leaves it raw)
   # A class declaration body (qualified `cmk.class` or the bare-keyword alias from a star-import)
   # or an encapsulation ambient (`*(| .. |)`,
   # fdis) always holds cmk CODE, never a raw payload, so COOK it (shallow) regardless of bracket:
   # emit `⟅ .. ⟆` so the later stages (indent re-tab, `<-` capture, ..) process the body -- making
   # `(|` and `[|` uniform for classes/ambients.  NOT widened to every ctor: a DSL-kind INSTANCE
   # (`python NAME(| py |)`, jqlang/awklang) carries a FOREIGN payload in its `(|` body and MUST stay
   # raw -- there the bracket keeps its raw(`(|`)/cooked(`[|`) meaning.  Nested raw defines (jq/awk
   # payloads inside a cooked class/ambient) are skipped by the later stages, so cook leaves them be.
   if ((ctor == "cmk.class" || ctor == "class" || fdis[d]) && fop[d] != "<-") _ck = 1
   if (!femit[d]) {
      if (_ck) {   # cooked body is cmk-lang: drop its # comment lines (raw keeps them)
         _kn = 0
         for (_bi = 1; _bi <= fbn[d]; _bi++) if (fbody[d, _bi] !~ /^[ \t]*#/) fbody[d, ++_kn] = fbody[d, _bi]
         fbn[d] = _kn }
      if (_nt > 0) {   # pipe the body through each target treatment (compile time), in order
         _bd = ""
         for (_bi = 1; _bi <= fbn[d]; _bi++) {
            _line = fbody[d, _bi]
            if (_rc) { sub(/@@SYM_DEFINE@@ /, "⟅", _line); sub(/^endef[ \t]*$/, "⟆", _line) }
            _bd = _bd _line "\n" }
         _err = ""
         for (_bi = 1; _bi <= _nt; _bi++) { _bd = shell_treat(TT[_bi], _bd); if (_treat_rc != 0) { _err = TT[_bi]; break } }
         if (_err == "") {
            out(_ck ? "⟅" fn[d] : "define " fn[d], d)
            sub(/\n$/, "", _bd); _nn = split(_bd, _BL, "\n")
            for (_bi = 1; _bi <= _nn; _bi++) out(_BL[_bi], d)
            out(_ck ? "⟆" : "endef", d)
         } else out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": postfix treatment `" fault_safe(_err) "` failed -- unknown target or non-zero exit)", d)
      } else {
         out(_ck ? "⟅" fn[d] : "define " fn[d], d)
         for (_bi = 1; _bi <= fbn[d]; _bi++) {
            _line = fbody[d, _bi]
            if (_rc) { sub(/@@SYM_DEFINE@@ /, "⟅", _line); sub(/^endef[ \t]*$/, "⟆", _line) }
            out(_line, d) }
         out(_ck ? "⟆" : "endef", d)
      }
   }
   femit[d] = 0; fbn[d] = 0
   if (_err != "") return   # postfix treatment failed -- error emitted, skip ctor / value form
   # assignment-form `<-`: RUN the (raw) block + capture stdout into the LHS, reusing the
   # `[stream]` producer path (`$(shell bash ⬥NAME)`).  Raw only: `⬥` blockref runs before
   # the `⟅`->`define` unsentinel, so a cooked body can't be blockref'd -- and a module-level
   # `:=` `$(shell ..)` runs at PARSE time, so shelling a cooked (`${make} ..`) body would
   # recurse (re-parse -> re-shell) into a fork storm.  A cooked module capture is therefore a
   # hard error; cooked capture is a RECIPE-level form (runs at recipe time via `$(NAME)`).
   if (fop[d] == "<-") {
      if (_ck) { out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": module-level cooked capture `" fl[d] " <- [| .. |]` shells a cooked body at parse time (recurses); use a recipe-level capture, or `<- (| .. |)` for a raw shell body)", d); return }
      out(fl[d] " := $(shell bash ⬥" fn[d] ")", d); return }
   if (fMBN[d] != "") {
      if (ctor == "") out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": multi-body (| .. |)(| .. |) needs a PREFIX constructor)", d)
      else { out(build_call(fn[d], ctor, fMBN[d] (_ekw != "" ? " " _ekw : "")), d); out(fn[d] ".__line__ := " sprintf("%08d", fline[d]), d) }
      return
   }
   if (bracket_seen) {
      cap = (fl[d] != "" ? fl[d] : fn[d])
      if (ctor != "") out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": a [stream] value cannot combine with a PREFIX constructor)", d)
      else if (t_stream == "") out(cap " := $(shell bash ⬥" fn[d] ")", d)
      else out(cap " := $(shell " t_stream " | bash ⬥" fn[d] ")", d)
   } else if (paren_seen) {
      if (ctor != "") out("$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " fn[d] ": an (args) value cannot combine with a PREFIX constructor)", d)
      else if (fl[d] != "") out(fl[d] " := $(call " fn[d] "," t_args ")", d)
      else out("$(eval $(call " fn[d] "," t_args "))", d)
   } else if (ctor != "" && !fdis[d]) {
      out(build_call(fn[d], ctor, _ekw), d)
      out(fn[d] ".__line__ := " sprintf("%08d", fline[d]), d)
   }
   # `*` dissolve flag: after the define, splice it via kind-dispatched dissolve.  The ctor (if
   # any) is the KIND -- `ambient.dissolve` dispatches on it (module/path/other), so bare `*(||)`
   # is `kind` empty (inline eval) and `ctor *(||)` passes `kind=ctor` (one call, no separate ctor).
   if (fdis[d]) out("$(call ambient.dissolve, def=" fn[d] (ctor != "" ? " kind=" ctor : "") ")", d)
  }
  # Parse the `with`/`using`/postfix trailer, order-free and each clause optional.  Sets
  # globals: t_with, t_using, t_postfix, t_stream/t_args (value forms), t_rest.
  function parse_trailer(rem,   m, n, T, i, mode) {
   t_with = ""; t_using = ""; t_postfix = ""; t_stream = ""; bracket_seen = 0; t_args = ""; paren_seen = 0; t_rest = rem
   # `[S]` STREAM value form + `(args)` MACRO value form -- block-as-value, return early.
   if (match(rem, /^\[[ \t]*.*\][ \t]*$/)) { t_stream = rem; sub(/^\[[ \t]*/, "", t_stream); sub(/\][ \t]*$/, "", t_stream); sub(/[ \t]+$/, "", t_stream); bracket_seen = 1; return }
   if (match(rem, /^\(.*\)[ \t]*$/)) { t_args = rem; sub(/^\(/, "", t_args); sub(/\)[ \t]*$/, "", t_args); paren_seen = 1; return }
   # Trailer word-walk (order-free clauses).  Leading bare words = the POSTFIX treatment
   # list (comma-separated, e.g. `cooked, stream.echo`), applied left-to-right; `with <k=v..>`
   # = postfix args (every postfix gets them, each kwarg-parses what it needs -- builtins
   # like `cooked` ignore them); `using <k=v..>` = PREFIX/constructor args.
   n = split(rem, T, /[ \t]+/); mode = "post"
   for (i = 1; i <= n; i++) {
      if (T[i] == "with")  { mode = "with";  continue }
      if (T[i] == "using") { mode = "using"; continue }
      if (mode == "with")       t_with    = t_with (t_with == "" ? "" : " ") T[i]
      else if (mode == "using") t_using   = t_using (t_using == "" ? "" : " ") T[i]
      else                      t_postfix = t_postfix (t_postfix == "" ? "" : " ") T[i]
   }
   # a fully-parenthesized `with (k=v ..)` clause may wrap its kwargs for readability -- unwrap it.
   if (t_with ~ /^\(.*\)$/) { sub(/^\(/, "", t_with); sub(/\)$/, "", t_with) }
  }
  function finalize_trailer(   cur_template, ctor, kw, cap, _ck, _nt, TT, _bd, _nn, _BL, _err, _bi, np, PF) {
   parse_trailer(pending_remainder)
   if (generic) {
      # ORPHAN-ARG checks: every modifier requires its processor.
      if (t_using != "" && pending_ctor == "")
         print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: (| |) block " pending_name ": `using` args with no PREFIX constructor)"
      if (t_with != "" && t_postfix == "")
         print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: (| |) block " pending_name ": `with` args with no POSTFIX treatment)"
      # Emit the block now (deferred from open) so the POSTFIX treatments -- known only after
      # the trailer -- pick the shape: a builtin `cooked`/`cooked_deeply` postfix -> `⟅NAME`/`⟆`
      # cook sentinels (the body COOKS through every later stage; unsentinel wraps it into a
      # real define at EOF); otherwise a plain verbatim `define NAME .. endef`.  multi-BODY
      # already flushed its main define at close (pending_emitted), so skip.
      _ck = 0; _nt = 0; np = split(t_postfix, PF, /[ \t]*,[ \t]*/)
      for (_bi = 1; _bi <= np; _bi++) {
         if (PF[_bi] == "cooked" || PF[_bi] == "cooked_deeply") _ck = 1
         else if (PF[_bi] != "") TT[++_nt] = PF[_bi]   # non-builtin -> target treatment
      }
      _err = ""
      if (!pending_emitted) {
         if (_nt > 0) {   # pipe the body through each target treatment (compile time), in order
            _bd = ""
            for (_bi = 1; _bi <= gnbody; _bi++) _bd = _bd gbody[_bi] "\n"
            for (_bi = 1; _bi <= _nt; _bi++) { _bd = shell_treat(TT[_bi], _bd); if (_treat_rc != 0) { _err = TT[_bi]; break } }
            if (_err != "") print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: block " pending_name ": postfix treatment `" fault_safe(_err) "` failed -- unknown target or non-zero exit)"
            else {
               print (_ck ? "⟅" pending_name : "define " pending_name)
               sub(/\n$/, "", _bd); _nn = split(_bd, _BL, "\n")
               for (_bi = 1; _bi <= _nn; _bi++) print _BL[_bi]
               print (_ck ? "⟆" : "endef")
            }
         } else {
            print (_ck ? "⟅" pending_name : "define " pending_name)
            for (_bi = 1; _bi <= gnbody; _bi++) print gbody[_bi]
            print (_ck ? "⟆" : "endef")
         }
      }
      gnbody = 0; pending_emitted = 0
      if (_err != "") { pending_remainder = ""; pending_name = ""; pending_ctor = ""; pending_lhs = ""; pending_mb = ""; awaiting_trailer = 0; return }
      # multi-BODY `(| A |)(| B |)..`: extras -> def2=/def3= (pending_mb); needs a PREFIX
      # constructor to consume them.  `using` = its args.
      if (pending_mb != "") {
         if (pending_ctor == "")
            print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: (| |) block " pending_name ": multi-body (| .. |)(| .. |) needs a PREFIX constructor)"
         else
            print build_call(pending_name, pending_ctor, pending_mb (t_using != "" ? " " t_using : ""))
         pending_remainder = ""; pending_name = ""; pending_ctor = ""; pending_lhs = ""; pending_mb = ""; awaiting_trailer = 0
         return
      }
      # `[S]` / `(args)` VALUE forms: capture the block as a value (LHS = target); a value
      # block cannot also be constructed.
      if (bracket_seen) {
         cap = (pending_lhs != "" ? pending_lhs : pending_name)
         if (pending_ctor != "")
            print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: (| |) block " pending_name ": a [stream] value cannot combine with a PREFIX constructor)"
         else if (t_stream == "")   # `[]` -- a producer block: run it with no input
            print cap " := $(shell bash ⬥" pending_name ")"
         else
            print cap " := $(shell " t_stream " | bash ⬥" pending_name ")"
      }
      else if (paren_seen) {
         if (pending_ctor != "")
            print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: (| |) block " pending_name ": an (args) value cannot combine with a PREFIX constructor)"
         else if (pending_lhs != "")
            print pending_lhs " := $(call " pending_name "," t_args ")"
         else
            print "$(eval $(call " pending_name "," t_args "))"
      }
      # PREFIX constructor + `using` args -> `$(call ctor, def=NAME using..)`.
      else if (pending_ctor != "")
         print build_call(pending_name, pending_ctor, t_using)
      # else: bare / postfix-only block => the `define`/sentinels already emitted are it.
      pending_remainder = ""; pending_name = ""; pending_ctor = ""; pending_lhs = ""; awaiting_trailer = 0
      return
   }
   if (callmode) {
      # `__CALL__ d` declaration rows: fill placeholders from the trailer, then lower via build_call
      ctor = spec_ctor; kw = spec_kw
      gsub(/__WITH__/, t_with, ctor); gsub(/__NAME__/, pending_name, ctor)
      gsub(/__WITH__/, t_with, kw);   gsub(/__NAME__/, pending_name, kw)
      print build_call(pending_name, ctor, kw)
      pending_remainder = ""; pending_name = ""; awaiting_trailer = 0
      return
   }
   cur_template = post_process_template
   gsub(/__WITH__/, t_with, cur_template)
   gsub(/__NAME__/, pending_name, cur_template)
   gsub(/__REST__/, t_rest, cur_template)
   print cur_template
   pending_remainder = ""; pending_name = ""; awaiting_trailer = 0
  }
  awaiting_trailer == 1 {
   if ($0 ~ /^[ \t]*$/) { if (pending_remainder == "") next; finalize_trailer(); next }
   stripped = $0; sub(/^[ \t]+/, "", stripped); sub(/[ \t]+$/, "", stripped)
   if (pending_remainder == "" && stripped ~ /^with[ \t(]/) { pending_remainder = stripped; next }
   finalize_trailer()
  }
  # generic await: a parked `|)` frame (awaitd) whose trailer may continue on the NEXT
  # line(s).  A `with`/`using` line, a `,`-led postfix, or a line after a `,`-ended trailer
  # is stitched onto awrem; anything else (incl. blank) finalizes the frame, pops to the
  # parent depth, and (if non-blank) falls through to be reprocessed there.
  generic && awaitd > 0 {
   awstr = $0; sub(/^[ \t]+/, "", awstr); sub(/[ \t]+$/, "", awstr)
   # leading-dot DOT-CHAIN continuation: a parked operand (`bif(| c |)` or a multiline `|)`)
   # whose chain resumes on THIS line (`.ctor(| .. |)`) -- fold it onto the parked operand so
   # a chain split after the operand's close reads the same as one written inline.
   if (awrem == "" && fl[awaitd] == "" && awstr ~ /^\.[ \t]*(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/) {
      if (_dotchain_tail(awaitd, awstr)) { depth = awaitd; awaitd = 0; next }   # a multiline operand still to fill -> re-enter the frame
      dot_emit(awaitd, fdlead[awaitd]); fbn[awaitd] = 0; depth = awaitd - 1; awaitd = 0; next }   # chain fully inline -> emit + pop
   if (awstr != "" && (awstr ~ /^(with|using)([ \t]|$)/ || awstr ~ /^,/ || awrem ~ /,[ \t]*$/)) {
      awrem = (awrem == "" ? awstr : awrem " " awstr); next }
   pending_remainder = awrem; frame_emit(awaitd); depth = awaitd - 1; awaitd = 0; awrem = ""
   if (awstr == "") next   # blank line terminates + is consumed
   # else FALL THROUGH: reprocess this line (sibling open / parent body / parent close)
  }
  # A hand-written `define .. endef` in the SOURCE is verbatim -- a banana (any bracket
  # family) written inside it is inert data, not a construct (the inertness the docs promise,
  # alongside comments -- which minify already strips).  Track it only at STATEMENT position
  # (depth 0); a `define` while BUFFERING a banana body (depth>0) is a nested body line and is
  # handled by the body-buffer rule, not here.
  generic && depth == 0 && /@@SYM_DEFINE@@ / { def_depth++; print; next }
  generic && depth == 0 && def_depth > 0 && /^endef[ \t]*$/ { def_depth--; print; next }
  generic && depth == 0 && def_depth > 0 { print; next }
  # --- generic banana ASSIGNMENT forms: `NAME = (|`, `NAME := (|`, `NAME <- (|` ---
  # A bare anonymous block (no name-word, no trailer) bound via an assignment operator; the
  # LHS names the block and the OPERATOR picks the treatment (see frame_emit's fop[] branch):
  #   `=`  -> raw recursive `define NAME`        (verbatim body; foreign code, literals)
  #   `:=` -> cooked `define NAME`               (interior lowered through the cmk compiler)
  #   `<-` -> RUN the block + capture stdout      (`NAME := $(shell bash ⬥__cap_N)`)
  # Disjoint from the named open below (no name touches `(|`) and from lambda-lift (no trailer).
  # A tab-indented `LHS <- (| .. |)` is a RECIPE-level capture, not a module assignment;
  # skip it here so lambda-lift lifts the block + emits a shell capture (`LHS=`bash ⬥..``).
  generic && (depth == 0 || !fverb[depth]) && $0 ~ /@@BANANA_OPEN_ASSIGN@@/ && $0 !~ /^\t[ \t]*@@SYM_NAME@@+[ \t]*<-[ \t]*[([{]\|/ {
   line = $0; idx = bopen(line)
   opre = substr(line, 1, idx - 1); sub(/[ \t]*$/, "", opre)
   oop = substr(opre, length(opre) - 1)
   if (oop != ":=" && oop != "<-") oop = "="
   olhs = substr(opre, 1, length(opre) - length(oop))
   sub(/[ \t]*$/, "", olhs); sub(/^[ \t]*/, "", olhs)
   depth++; fc[depth] = ""; fl[depth] = ""; fdis[depth] = 0; fbn[depth] = 0; fmb[depth] = 0; fMBN[depth] = ""; fMBIDX[depth] = 1; femit[depth] = 0; fverb[depth] = 0; fop[depth] = oop; fcook[depth] = BTREAT[_bch]
   if (oop == "<-") { fn[depth] = "__cap_" NR; fl[depth] = olhs } else { fn[depth] = olhs }
   after = substr(line, idx + 2); cidx = bclose(after)
   if (cidx > 0) {                                  # one-liner: open + close on one line
      body = substr(after, 1, cidx - 1); sub(/^[ \t]+/, "", body); sub(/[ \t]+$/, "", body)
      rem = substr(after, cidx + 2); sub(/^[ \t]+/, "", rem); sub(/[ \t]+$/, "", rem)
      if (body != "") fbody[depth, ++fbn[depth]] = body
      pending_remainder = rem; frame_emit(depth); depth--
   } else { sub(/^[ \t]+/, "", after); sub(/[ \t]+$/, "", after); if (after != "") fbody[depth, ++fbn[depth]] = after }   # multi-line open: buffer the inline body-head (compact style)
   next
  }
  # --- generic banana-bracket open: `[LHS =] [path words..] NAME(|` (word-scan to BOL) ---
  # An optional `LHS =` / `LHS :=` prefix makes the block a VALUE (its trailer captures
  # into LHS); without it the block is at STATEMENT position (see finalize_trailer).
  # GUARD: don't parse nested opens inside a verbatim frame (a foreign-body importer --
  # Dockerfile / shell / polyglot), so a literal `NAME(|` in that body stays verbatim.
  # GUARD 2: a RECIPE-line anonymous-immediate construction is not a define -- it is a single-use
  # lift handled by lambda-lift; pass it through untouched.  Two shapes: a banana close DIRECTLY
  # followed by `.name(` (the `.method(args)` arm), or by a `{env}`/`(args)` RECEIVER trailer
  # (`ctor(| body |){cmd=..}` -> gensym-construct + `<gensym>{cmd=..}`, the recipe idiom).
  # `[ctor] *(|` -- ambient dissolve of an inline anonymous block.  The `*` prefix (optionally
  # preceded by a ctor path) reuses this whole opener/frame path with a synthetic name and a
  # dissolve flag: the close emits `define __ambient_N .. endef`, then the ctor call (if any),
  # then `$(call ambient.dissolve, def=..)`.  So `*(||)` = dissolve alone (ctor defaults to
  # identity); `ctor *(||)` = `ambient.dissolve(ctor(__ambient_N))` -- construct, then splice flat.
  generic && (depth == 0 || !fverb[depth]) && $0 ~ /@@BANANA_OPEN_NAMED@@/ && ($0 !~ /^[ \t].*\|[])}][ \t]*[\/.|][ \t]*[A-Za-z_]@@SYM_NAME@@*[ \t]*\(/ || $0 ~ /[([{]\|[ \t]*$/) && $0 !~ /^[ \t].*\|[])}][ \t]*[{(]/ {
   line = $0; idx = bopen(line)
   pre = substr(line, 1, idx - 1); sub(/^[ \t]+/, "", pre); sub(/[ \t]+$/, "", pre)
   lhs = ""; dis = 0; _fkw = ""
   if (pre ~ /\*$/) {                              # `[ctor] *` -- dissolve; ctor path (if any) precedes the star
      sub(/[ \t]*\*[ \t]*$/, "", pre); nm = "__ambient_" NR; dis = 1; ctor = ""
      if (pre != "") { nw = split(pre, W, /[ \t]+/); for (i = 1; i <= nw; i++) ctor = (ctor == "" ? W[i] : ctor "." W[i]) }
   } else {
      if (match(pre, /^@@SYM_NAME@@+[ \t]*:?=[ \t]*/)) { lhs = substr(pre, 1, RLENGTH); sub(/[ \t]*:?=[ \t]*$/, "", lhs); pre = substr(pre, RLENGTH + 1) }
      # `NAME(k=v ..)` PREFIX kwargs -- a paren group on the name, carried to the ctor call (the
      # native front-form of the `using ..` trailer).  Simple kwargs only (no nested parens).
      _pk = pre; sub(/[ \t]*$/, "", _pk)
      if (match(_pk, /\([^()|]*\)$/) && RSTART > 1 && substr(_pk, RSTART - 1, 1) ~ /@@SYM_NAME@@/) { _fkw = substr(_pk, RSTART + 1, RLENGTH - 2); pre = substr(_pk, 1, RSTART - 1) }
      if (pre !~ /^@@SYM_NAME@@+([ \t]+@@SYM_NAME@@+)*$/) { print; next }
      nw = split(pre, W, /[ \t]+/); nm = W[nw]; ctor = ""
      if (nm == "_") nm = "__anon_" NR   # `_` = a throw-away instance name -> a unique, unreferenceable gensym
      for (i = 1; i < nw; i++) ctor = (ctor == "" ? W[i] : ctor "." W[i])
   }
   # PUSH a frame.  A nested open (depth>0, inside a buffering body) pushes deeper; the
   # close pops + emits into the PARENT frame's body, so an inner banana becomes a nested
   # `define` inside the outer.  Body is BUFFERED so the trailer (at close) picks cook vs raw.
   depth++; fn[depth] = nm; frecv[depth] = ""; fline[depth] = NR; fc[depth] = ctor; fl[depth] = lhs; fdis[depth] = dis; fbn[depth] = 0; fmb[depth] = 0; fMBN[depth] = ""; fMBIDX[depth] = 1; femit[depth] = 0; fop[depth] = ""; fcook[depth] = BTREAT[_bch]; fkw[depth] = _fkw; fdc[depth] = 0; fdnextctor[depth] = ""
   match(line, /^[ \t]*/); fdlead[depth] = substr(line, 1, RLENGTH)   # recipe indent (for a dot-chain's inline emit)
   fverb[depth] = (ctor ~ /(^|\.)(import|docker|polyglot)/ || ctor ~ /(^|\.)code(\.|$)/) ? 1 : 0   # foreign-body importer -> verbatim
   after = substr(line, idx + 2); cidx = bclose(after)
   if (cidx > 0) {                                  # one-liner: open + close on one line
      body = substr(after, 1, cidx - 1); sub(/^[ \t]+/, "", body); sub(/[ \t]+$/, "", body)
      rem = substr(after, cidx + 2); sub(/^[ \t]+/, "", rem); sub(/[ \t]+$/, "", rem)
      if (rem ~ /^!/) { fcook[depth] = "cooked"; sub(/^![ \t]*/, "", rem) }   # unary `!` = shallow cook (downgrades a `[|` deep frame)
      if (body != "") fbody[depth, ++fbn[depth]] = body
      rem = mb_peel(rem, nm, depth)                # multi-body: peel extra one-liner blocks
      if (fl[depth] == "" && rem ~ /^\.[ \t]*(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/) {   # single-line-first dot-chain: this operand closed inline, the chain opens onward
         if (_dotchain_tail(depth, rem)) next     # a multiline operand still to fill -> stay in frame
         dot_emit(depth, fdlead[depth]); fbn[depth] = 0; depth--; next }   # all inline -> emit + pop
      if (rem == "" && fl[depth] == "") { awaitd = depth; awrem = ""; next }   # nothing follows on the line -> PARK: a next-line `.ctor(|` may continue the chain (else the await rule finalizes it standalone)
      pending_remainder = rem; frame_emit(depth); depth--
   } else { sub(/^[ \t]+/, "", after); sub(/[ \t]+$/, "", after); if (after != "") fbody[depth, ++fbn[depth]] = after }   # multi-line open: buffer the inline body-head (compact style)
   next
  }
  # generic body line: buffer into the current frame (or stream, once flipped to multi-body).
  # compact close: a non-verbatim body line where a banana close (`body |)`) buffers its lead
  # here, then rewrites `$0` to `|)`+remainder so the close rule below finalizes the frame.  The
  # close is honored WHEREVER it lands (mid-line too), provided what follows is the end of the
  # line OR a `.`-chain step (`body |).ctor(| .. |)`) -- so a literal `|)` inside a body string
  # (followed by other text) stays verbatim, as does any close in a foreign (import/..) body OR a
  # `#`/`@#` COMMENT line (a banana form written in a comment is inert, not a construct).
  generic && depth > 0 && $0 !~ /^[ \t]*\|[])}]/ {
   _cp = (fverb[depth] || $0 ~ /^[ \t]*@?#/ ? 0 : bclose($0))
   if (_cp > 0 && substr($0, _cp + 2) ~ /^[ \t]*(\.|$)/) {
      _ld = substr($0, 1, _cp - 1); sub(/[ \t]+$/, "", _ld)
      if (_ld != "") { if (fmb[depth]) out(_ld, depth); else fbody[depth, ++fbn[depth]] = _ld }
      $0 = substr($0, _cp)                          # -> bare `|)`; fall through to the close rule
   } else { if (fmb[depth]) out($0, depth); else fbody[depth, ++fbn[depth]] = $0; next }
  }
  # generic close `|)`/`|]`/`|}`: finalize the INNERMOST frame (inline trailer) and pop to its parent.
  generic && depth > 0 && $0 ~ /^[ \t]*\|[])}]/ {
   rem = $0; sub(/^[ \t]*\|[])}][ \t]*/, "", rem); sub(/[ \t]+$/, "", rem)
   if (rem ~ /^!/) { fcook[depth] = "cooked"; sub(/^![ \t]*/, "", rem) }   # unary `!` = shallow cook (downgrades a `[|` deep frame)
   _fck = (fcook[depth] == "cooked" || fcook[depth] == "cooked_deeply")   # frame's bracket cook flag
   rem = mb_peel(rem, fn[depth], depth)          # multi-body: peel complete one-liner extras
   if (rem ~ /^\+[ \t]*[([{]\|/) sub(/^\+[ \t]*/, "", rem)   # explicit `+` composition join before a multi-line body
   if (bopen(rem) == 1) {                        # a lone `(|`/`[|` opens the NEXT body -> MULTI-BODY
      if (!fmb[depth]) { fdef(fn[depth], depth); fbn[depth] = 0; fmb[depth] = 1; femit[depth] = 1 }
      else out(_fck ? "⟆" : "endef", depth)      # close the previous extra body
      fMBIDX[depth]++
      out(_fck ? "⟅" fn[depth] "__" fMBIDX[depth] : "define " fn[depth] "__" fMBIDX[depth], depth)
      fMBN[depth] = fMBN[depth] (fMBN[depth] == "" ? "" : " ") "def" fMBIDX[depth] "=" fn[depth] "__" fMBIDX[depth]
      b = substr(rem, 3); sub(/^[ \t]+/, "", b); sub(/[ \t]+$/, "", b); if (b != "") out(b, depth)
      next }                                      # stay in this frame, filling the new body
   # DOT-CHAIN step(s): a `.` operator to one-or-more operands after this close, each either
   # COMPLETE inline (`.ctor(| body |)`) or a multiline OPEN (`.ctor(|` with its body on following
   # lines).  Record the operand that just closed, then consume every complete inline operand in
   # `rem`; a trailing open leaves the frame to fill (the terminal `|)` finishes below), while an
   # all-inline tail finishes the chain right here.  Position-independent: where the operand's `(|`
   # and `|)` sit on the line does not matter (mirrors dedent's `bopen`/`bclose` walk).
   if (fl[depth] == "" && rem ~ /^\.[ \t]*(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/) {
      if (_dotchain_tail(depth, rem)) next                                 # multiline operand still to fill -> stay
      dot_emit(depth, fdlead[depth]); fbn[depth] = 0; depth--; next }       # chain fully consumed inline -> emit + pop
   # a chain link carrying kwargs reads as a call on the receiver's member, so close the receiver and declare the link's body against that member
   if (fl[depth] == "" && chain_kwlink(rem)) {
      _clrecv = (frecv[depth] != "" ? frecv[depth] : fn[depth]); pending_remainder = ""; frame_emit(depth); depth--
      depth++; fn[depth] = "__chain_" NR; frecv[depth] = _clrecv; fline[depth] = NR; fc[depth] = _clrecv "." _clname; fl[depth] = ""; fdis[depth] = 0
      fbn[depth] = 0; fmb[depth] = 0; fMBN[depth] = ""; fMBIDX[depth] = 1; femit[depth] = 0; fop[depth] = ""
      fcook[depth] = BTREAT[_bch]; fkw[depth] = _clkw; fdc[depth] = 0; fdnextctor[depth] = ""
      match($0, /^[ \t]*/); fdlead[depth] = substr($0, 1, RLENGTH)
      if (_clbody != "") fbody[depth, ++fbn[depth]] = _clbody
      next }
   # DOT-CHAIN finish: a closing `|)` with no further `.ctor(|` -- record the last operand and
   # emit the whole chain inline (construct each + fold via `.__dot__` + call), then pop.
   if (fdc[depth] > 0) {
      fdc[depth]++; fdctor[depth, fdc[depth]] = fdnextctor[depth]
      fdbody[depth, fdc[depth]] = fbody_join(depth)
      dot_emit(depth, fdlead[depth]); fbn[depth] = 0; depth--; next }
   if (fmb[depth]) out(_fck ? "⟆" : "endef", depth)   # close the final streamed extra body
   else if (fMBN[depth] != "") { fdef(fn[depth], depth); fbn[depth] = 0; femit[depth] = 1 }  # one-liner extras: flush main
   # DEFER finalize: park the frame (awaitd) so a trailer may continue on FOLLOWING
   # lines (`with`/`using`/`,`-postfixes); the await rule below finalizes on the next
   # non-continuation line (or at END).  Keep `depth` until finalize so the inner
   # define is emitted into the parent before later parent-body lines.  `rem` already
   # holds any inline trailer.
   awaitd = depth; awrem = rem; next
  }
  !generic && $0 ~ open_pattern && block_mode == 0 {
   block_name = $0
   sub(open_pattern, "", block_name)
   sub(/^[ \t]+/, "", block_name)
   sub(/[ \t]+$/, "", block_name)
   print "define " block_name
   block_mode = 1; next
  }
  !generic && $0 ~ close_pattern && block_mode == 1 {
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
  END { if (awaiting_trailer == 1) finalize_trailer(); if (awaitd > 0) { pending_remainder = awrem; frame_emit(awaitd); awaitd = 0 }
        for (_dli = 1; _dli <= _dln; _dli++) print _DL[_dli] }   # flush hoisted dot-chain construction (module scope)
endef
# Lower CMK triple-delimiter literals to a %-safe `printf`, in two modes
# mirroring shell quoting: the triple-single-quote form is literal (shell
# vars and backticks pass through), the triple-double-quote and
# triple-backtick forms interpolate. Make expansion happens in both. Inert
# inside define..endef.
#:phase COMPILE seed=1 awklang=no
define .awk.triplequote
  function sq(s,   n,p,i,r) {
      n = split(s, p, "'"); r = p[1]
      for (i = 2; i <= n; i++) r = r "'\\''" p[i]
      return "'" r "'" }
  function dq(s,   n,p,i,r) {
      n = split(s, p, /\\/); r = p[1]
      for (i = 2; i <= n; i++) r = r "\\\\" p[i]
      s = r; n = split(s, p, /"/); r = p[1]
      for (i = 2; i <= n; i++) r = r "\\\"" p[i]
      return "\"" r "\"" }
  function emit(content, interpolate,   n,p,i,fmt,args) {
      n = split(content, p, "\n")
      # the close-delimiter line's leading indent is framing, not content: in a dedented body it
      # survives as a whitespace-only final segment.  Normalise it to empty (keeps the trailing
      # newline, drops the leaked indent) -- the recipe-literal analog of the docstring trim.
      if (n > 1 && p[n] ~ /^[ \t]*$/) p[n] = ""
      fmt = "%s"; args = (interpolate ? dq(p[1]) : sq(p[1]))
      for (i = 2; i <= n; i++) { fmt = fmt "\\n%s"; args = args " " (interpolate ? dq(p[i]) : sq(p[i])) }
      return "printf '" fmt "' " args }
  BEGIN { in_def = 0; SQ = "'''"; DQ = "\"\"\""; BT = "```" }
  {
      rest = $0; out = ""
      while (1) {
          a = index(rest, SQ); b = index(rest, DQ); g = index(rest, BT)
          if (a == 0 && b == 0 && g == 0) { out = out rest; break }
          p = 0
          if (a != 0 && (p == 0 || a < p)) { p = a; delim = SQ; interpolate = 0 }
          if (b != 0 && (p == 0 || b < p)) { p = b; delim = DQ; interpolate = 1 }
          if (g != 0 && (p == 0 || g < p)) { p = g; delim = BT; interpolate = 1 }
          out = out substr(rest, 1, p - 1)
          after = substr(rest, p + 3)
          c = index(after, delim)
          if (c > 0) {
              dc = substr(delim, 1, 1); rl = 0
              while (substr(after, c + rl, 1) == dc) rl++
              out = out emit(substr(after, 1, c - 1 + rl - 3), interpolate); rest = substr(after, c + rl) }
          else {
              content = after; closed = 0
              while ((getline nl) > 0) {
                  c = index(nl, delim)
                  if (c > 0) {
                      dc = substr(delim, 1, 1); rl = 0
                      while (substr(nl, c + rl, 1) == dc) rl++
                      content = content "\n" substr(nl, 1, c - 1 + rl - 3); rest = substr(nl, c + rl); closed = 1; break }
                  content = content "\n" nl }
              out = out emit(content, interpolate)
              if (!closed) rest = "" } }
      print out }
endef
# Lower CMK block-reference glyphs to a file argument: one glyph becomes a
# process-substitution stream FD over the block, the other a real file
# holding the block. Inert inside define..endef (polyglots pass through).
#:phase COMPILE seed=1 awklang=no
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
          name = ""; is_self = 0; i = 1; L = length(after)
          if (substr(after, i, length("@@TOKEN_SELF@@")) == "@@TOKEN_SELF@@") { name = "@@TOKEN_SELF@@"; i += length("@@TOKEN_SELF@@"); is_self = 1 }   # a leading self-token is part of the name (crosses the `$` the char-class stops at)
          while (i <= L) { ch = substr(after, i, 1); if (ch ~ /[A-Za-z0-9._\/-]/) { name = name ch; i++ } else break }
          if (name == "") { out = out substr(rest, p, gl); rest = after; continue }
          # a self-token operand is an OBJECT: materialize through its declared representation (its
          # own dunder) -- the blockref analogue of the call dunder.  A plain name is a def, taken as-is.
          rn = is_self ? "$(if $(filter-out undefined,$(origin " name ".__blockref__)),$(call " name ".__blockref__)," name ")" : name
          if (kind == "fd") out = out "<($(call _mk.def.to.fd, " rn "))"
          else out = out "$(call _mk.def.tmpfile, " rn ")"
          rest = substr(after, i) }
      print out }
endef

# Lambda-lift for anonymous in-recipe lambdas `(| body |){env}(args)`: an
# unnamed block plus its trailer is gensym'd to a module-level `define`
# (buffered, flushed at END) and replaced in place with a runtime dispatch.
# The trailer supplies two order-free channels -- `{k=v}` env and `(a,b)`
# positional args (beyond a stream `[S]`). A named `NAME(|..|)` is left
# alone; defskip skips a lambda in a define.
#:phase COMPILE seed=1 awklang=no
define .awk.lambdalift
  # Shared lambda helpers -- used by BOTH the single-line arm and the multi-line arm below, so
  # the open-scan, trailer-parse, and emit live once.  Results come back through a caller array R.
  #
  # _lam_open -- find the FIRST anonymous banana open `(|`/`[|`/`{|` (preceded by start/space/tab,
  # so a NAMED `x(|` is skipped).  Sets R["p"] (1-based position, 0 = none) and R["bch"] (bracket).
  function _lam_open(line, R,   s, at, bef) {
    R["p"] = 0; s = 1
    while (match(substr(line, s), /[([{]\|/) > 0) {
      at = s + RSTART - 1; bef = (at == 1) ? "" : substr(line, at - 1, 1)
      if (bef == "" || bef == " " || bef == "\t") { R["p"] = at; R["bch"] = substr(line, at, 1); return }
      s = at + 2 } }
  # _lam_trailer -- parse a lambda trailer off `tail` (order-free): `in <X>`/`out` (mobility),
  # bare `cooked`, `{k=v}` (env channel), `(a,b)` (args channel).  Seeds docook from the bracket.
  # Sets R["amb"]/R["env"]/R["args"]/R["docook"]/R["seen"] and R["tail"] (the residual).
  function _lam_trailer(tail, docook, R,   tw, t0, oc, cc, depth, k, ch, inner, inpre, inseg, amaf, ambody, amrest, amctor, amb_g) {
    R["amb"] = ""; R["docook"] = docook; R["env"] = ""; R["args"] = ""; R["seen"] = 0
    # `in <ctor>(| body |)` -- an INLINE anonymous ambient.  Reuse the anonymous-instance pattern
    # (gensym define + hoist `$(call <ctor>, def=..)` to module scope), then dispatch the lambda into
    # it by name.  So `in` uniformly takes a first-class ambient -- never a raw image string.
    if (match(tail, /(^|[ \t])in[ \t]+(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|/)) {
      inpre = substr(tail, 1, RSTART - 1)
      inseg = substr(tail, RSTART); sub(/^[ \t]+/, "", inseg); sub(/^in[ \t]+/, "", inseg)
      match(inseg, /[([{]\|/); amctor = substr(inseg, 1, RSTART - 1); sub(/[ \t]+$/, "", amctor); gsub(/[ \t]+/, ".", amctor)
      amaf = substr(inseg, RSTART + 2)
      ambody = substr(amaf, 1, bclose(amaf) - 1); sub(/^[ \t]+/, "", ambody); sub(/[ \t]+$/, "", ambody)
      amrest = substr(amaf, RSTART + 2)
      amb_g = "__ambient_" NR
      LIFT[++NL] = "define " amb_g "\n" (ambody == "" ? "" : ambody "\n") "endef"
      LIFT[++NL] = "$(call " amctor ", def=" amb_g ")"
      R["amb"] = amb_g
      tail = inpre " " amrest; sub(/^[ \t]+/, "", tail); sub(/[ \t]+$/, "", tail) }
    else if (match(tail, /(^|[ \t])in[ \t]+[A-Za-z0-9._:\/-]+/)) {
      R["amb"] = substr(tail, RSTART, RLENGTH); sub(/^[ \t]*in[ \t]+/, "", R["amb"])
      sub(/(^|[ \t])in[ \t]+[A-Za-z0-9._:\/-]+/, "", tail); sub(/^[ \t]+/, "", tail) }
    while (tail ~ /^[A-Za-z_]/) {
      tw = tail; sub(/[^A-Za-z0-9_].*$/, "", tw)
      if (tw == "out") R["amb"] = "out"
      else if (tw == "cooked" || tw == "cooked_deeply") R["docook"] = 1
      tail = substr(tail, length(tw) + 1); sub(/^[ \t]*,?[ \t]*/, "", tail)
      # a name after the out keyword is the ambient being left, checked at run time by the outwards gate
      if (tw == "out" && match(tail, /^[A-Za-z0-9._-]+/)) { onm = substr(tail, RSTART, RLENGTH)
        if (onm != "cooked" && onm != "cooked_deeply") {
          R["env"] = (R["env"] == "" ? "" : R["env"] " ") "__ambient_expect__=" onm
          tail = substr(tail, RLENGTH + 1); sub(/^[ \t]*,?[ \t]*/, "", tail) } } }
    while (1) {
      t0 = substr(tail, 1, 1)
      if (t0 == "{") { oc = "{"; cc = "}" } else if (t0 == "(") { oc = "("; cc = ")" } else break
      depth = 1; k = 2
      while (k <= length(tail) && depth > 0) { ch = substr(tail, k, 1); if (ch == oc) depth++; else if (ch == cc) depth--; if (depth == 0) break; k++ }
      if (depth != 0) break
      inner = substr(tail, 2, k - 2); tail = substr(tail, k + 1); R["seen"] = 1
      if (t0 == "{") R["env"] = (R["env"] == "" ? inner : R["env"] " " inner)
      else           R["args"] = (R["args"] == "" ? inner : R["args"] " " inner) }
    R["tail"] = tail }
  # _lam_emit -- hoist BODY as a gensym define (cooked `⟅⟆` if docook), then RETURN the recipe-line
  # replacement: an env prefix (`{k=v}` -> `k='v'`, `(a,b)` -> CMK_LAMBDA_ARGV) plus the dispatch --
  # a machine callform `${make} NAME/g` for a plain `in NAME`, else the env-channel dispatcher.
  function _lam_emit(lead, g, body, docook, amb, env, args, tail, predef,   envp, argstr) {
    if (predef) { }   # g is a PRE-EXISTING def (a named receiver): skip the hoist, dispatch it by name
    else if (docook) LIFT[++NL] = "⟅" g "\n" (body == "" ? "" : body "\n") "⟆"
    else        LIFT[++NL] = "define " g "\n" (body == "" ? "" : body "\n") "endef"
    envp = env_prefix(env)
    argstr = args; gsub(/,/, " ", argstr)
    if (argstr != "") envp = envp (envp == "" ? "" : " ") "CMK_LAMBDA_ARGV='" argstr "'"
    # `in <name>` is a bare ambient: a host machine, a named KIND instance, a compose service, or an
    # anonymous instance minted by `in <ctor>(| .. |)` (see _lam_trailer).  All route through the
    # instance's own `<name>/%` dispatch -- config lives on the ambient, never sniffed from a string.
    if (amb != "" && amb !~ /[:\/]/) return lead envp (envp == "" ? "" : " ") "${make} $(call _cmk.host.machine," amb ")/" g tail
    # a bare IMAGE (has `:`/`/`) is NOT an ambient -- no string-sniff shortcut.  Wrap it so config
    # (entrypoint/cmd) lives on a first-class instance.
    if (amb != "") return lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: `(| .. |) in " amb "`: a bare image is not an ambient -- wrap it: `in container(| img=" amb " entrypoint=.. |)`, or declare a named `container`/`Dockerfile` instance)"
    # RESERVED: a bare anonymous `(| body |){env}`/`(args)` (no `in`) -- an anonymous banana has only a
    # string algebra (concat/juxtaposition), no callforms; a `{env}`/`(args)`/`{ambient=..}` trailer needs
    # a typed machine.  Emitted as a make `$(error)` (fires at validate/run, rc!=0 -- a `cmk_die` here would
    # print but the pipe swallows its exit) carrying a hierarchical code the linter/classifier keys on.
    return lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: NotImplemented/Grammar/anon-callform: an anonymous banana `(| .. |)` has only a string algebra, no callforms -- a `{env}`/`(args)` trailer needs a typed machine, e.g. `host.native.sh(| .. |){env}`, or a named `Dockerfile df(| .. |)` then `df{cmd=..}`)" }
  # _bfold -- the SHARED banana operator-chain fold (front-end/back-end split): peel `[ctor](| body |)`
  # operands (ctor OPTIONAL -- anonymous reifies to lang.banana.fragment!) joined by a TABLE-A operator
  # char, hoist+reify each (`lang.grammar.dot.new`), fold left-assoc (`.`=`dot.op` byte-identical, else
  # `dot.op.tbl` with the raw char).  Lifts the module-scope parts; sets R["ok"] + R["acc"] (the
  # `$(accumulator)` for the caller's SINK to dispose -- run/bind/etc).  Fluent chain + `&`-capture both ride this.
  function _bfold(s, R,   n, ok, ct, af, bd, i, g, _C, _B, _O, _G) {
    n = 0; ok = 1
    while (1) {
      if (!match(s, /^(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@*[([{]\|/)) { ok = 0; break }
      match(s, /[([{]\|/); ct = substr(s, 1, RSTART - 1); sub(/[ \t]+$/, "", ct); gsub(/[ \t]+/, ".", ct)
      af = substr(s, RSTART + 2)
      if (!bclose(af)) { ok = 0; break }
      bd = substr(af, 1, RSTART - 1); sub(/^[ \t]+/, "", bd); sub(/[ \t]+$/, "", bd)
      n++; _C[n] = ct; _B[n] = bd
      s = substr(af, RSTART + 2); sub(/^[ \t]+/, "", s)
      if (s ~ /^[.\/|%+]/) { _O[n] = substr(s, 1, 1); sub(/^[.\/|%+][ \t]*/, "", s); continue }
      break }
    sub(/[ \t]+$/, "", s)
    R["ok"] = (ok && n >= 2 && s == ""); R["acc"] = ""
    if (!R["ok"]) return
    for (i = 1; i <= n; i++) {
      _G[i] = "__" (_C[i] != "" ? _C[i] : "frag") "." NR "." i
      LIFT[++NL] = "define " _G[i] "\n" (_B[i] == "" ? "" : _B[i] "\n") "endef"
      LIFT[++NL] = "$(call lang.grammar.dot.new," _C[i] "," _G[i] ")" }
    LIFT[++NL] = "__fold_" NR " := " _G[1]
    for (i = 2; i <= n; i++)
      LIFT[++NL] = "__fold_" NR " := " (_O[i-1] == "." ? "$(call lang.grammar.dot.op,$(__fold_" NR ")," _G[i] ")" : "$(call lang.grammar.dot.op.tbl,$(__fold_" NR ")," _G[i] "," _O[i-1] ")")
    R["acc"] = "$(__fold_" NR ")" }
  # A recipe `@#`/`#` comment (incl. a target docstring lowered to `@#` by moduledoc) is VERBATIM:
  # a literal `(|`/`|)` in its text (e.g. a docstring mentioning `(|| true)`) must never be lifted.
  /^[ \t]*@?#/ { print; next }
  # `&LHS <- (| a |) OP (| b |)..` -- capture a banana STRING-ALGEBRA fold as a lazy HANDLE (bind, not
  # run; fold-only-under-`&`).  Front-end: parse `&LHS <-` off the anonymous banana chain; the fold
  # rides the shared `_bfold` back-end; the SINK binds under LHS (`frag.as` + a callable target),
  # lifted to module scope so `$(LHS)` reads the result.
  /^([^;(]*:;)?[ \t]*&[A-Za-z_][A-Za-z0-9._-]*[ \t]*<-[ \t]*@@SYM_NAME@@*[([{]\|.*\|[])}][ \t]*[\/.|%+][ \t]*@@SYM_NAME@@*[([{]\|/ {
   cf_s = $0; cf_lead2 = ""
   if (match(cf_s, /^[^;(]*:;[ \t]*/)) { cf_lead2 = substr(cf_s, 1, RLENGTH); cf_s = substr(cf_s, RLENGTH + 1); sub(/[ \t]*;[ \t]*$/, "", cf_lead2) }
   cf_rec = (cf_lead2 != "" || $0 ~ /^[ \t]/); sub(/^[ \t]*&/, "", cf_s); cf_id = cf_s; sub(/[ \t]*<-.*/, "", cf_id); sub(/[ \t]+$/, "", cf_id)
   sub(/^[A-Za-z_][A-Za-z0-9._-]*[ \t]*<-[ \t]*/, "", cf_s)
   cf_nl0 = NL; _bfold(cf_s, BR)
   # bind only (no `handle.target`): a pure string fragment is read via `$(LHS)`, not run as `${make}
   # LHS` (that would exec its text).  In a RECIPE keep the fold hoisted to module scope; at MODULE
   # scope (col 0) flush it IN PLACE so a later eager `$(LHS)` sees it (LIFT flushes at END, too late).
   # A `;`-recipe (`tgt:; &x <- ..`) binds at parse like any recipe capture; re-emit the bare `tgt:`.
   if (BR["ok"]) {
      cf_bind = "$(call lang.banana.as," cf_id "," BR["acc"] ")"
      if (cf_lead2 != "") { LIFT[++NL] = cf_bind; print cf_lead2; next }
      if (cf_rec) LIFT[++NL] = cf_bind
      else { for (cf_j = cf_nl0 + 1; cf_j <= NL; cf_j++) print LIFT[cf_j]; NL = cf_nl0; print cf_bind }
      next } }
  # RECIPE-level banana CAPTURE: `LHS <- (| body |)` (tab-indented, routed here from sugar).
  # Hoist the body to a module define and replace in place with a runtime shell capture, so
  # the block runs at recipe time and its stdout lands in the shell var.  Two flavors, keyed
  # on a `cooked`/`cooked_deeply` treatment left by the `[| .. |]` bracket:
  #   raw   `<- (| body |)`  -> `define __cap_N`; capture = `LHS=`bash ⬥__cap_N`` (body is
  #                            materialized to a tmpfile via `⬥` and run as shell).
  #   cooked `<- [| body |]` -> `⟅__cap_N⟆` (interior lowered to make); capture =
  #                            `LHS=`$(__cap_N)`` -- make expands the cooked define (so
  #                            `${make}`/`$(call ..)` resolve), then the shell runs the result.
  # The module-level `X <- (| .. |)` counterpart is `X := $(shell ..)` (parse-time).
  /^[ \t]*@@SYM_NAME@@+[ \t]*<-[ \t]*[([{]\|.*\|[])}]/ {
   match($0, /^[ \t]*/); clw = RLENGTH
   cpi = index($0, "<-"); clhs = substr($0, clw + 1, cpi - clw - 1); sub(/[ \t]+$/, "", clhs)
   crhs = substr($0, cpi + 2); sub(/^[ \t]+/, "", crhs)
   # Peel 1..N `(| body |)` blocks joined by ADJACENCY or `+` (single-line): each body is
   # hoisted to its own define, and the capture CONCATENATES their stdout in sequence
   # (`+` = value concatenation, "a then b").  Per-body cook by bracket (`[|`=cooked, `(|`=raw);
   # a trailing bare `cooked` word cooks a lone single body (legacy).  `!` and a spanning
   # `+`/block on a later line stay unsupported (loud error).
   ccn = 0; crun = ""; ccs = crhs
   while (match(ccs, /^[([{]\|/) > 0) {
      ccn++; CCBR[ccn] = substr(ccs, 1, 1); ccrest = substr(ccs, 3)
      if (!bclose(ccrest)) { ccn--; break }
      ccx = RSTART; ccb = substr(ccrest, 1, ccx - 1); sub(/^[ \t]+/, "", ccb); sub(/[ \t]+$/, "", ccb)
      CCBD[ccn] = ccb
      ccs = substr(ccrest, ccx + 2); sub(/^[ \t]+/, "", ccs)
      # only `+` or bare adjacency (a following `(|`) joins raw bananas -- both are string
      # concat.  `+` is consumed here; adjacency is left for the next turn.  ANY other separator
      # stops the peel (no per-operator blocklist); the leftover is caught by the guard below.
      if (ccs ~ /^\+/) sub(/^\+[ \t]*/, "", ccs)
      else if (ccs !~ /^[([{]\|/) break
      sub(/^[ \t]+/, "", ccs) }
   sub(/[ \t]+$/, "", ccs); ccword = (ccs ~ /^cooked(_deeply)?([ \t,]|$)/)
   if (ccs ~ /^!/) { print substr($0, 1, clw) "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: recipe capture `" clhs " <- (| .. |)`: `!` (shallow cook) is module-level only)"; next }
   if (ccs ~ /^in[ \t]/) { print substr($0, 1, clw) "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: recipe capture `" clhs " <- (| .. |)`: `in <X>` capture-mobility not supported yet (use a lambda `(| .. |) in X`))"; next }
   # leftover that still opens a banana = an undefined operator joining raw bananas (e.g. `|`, a
   # typed/data-flow op owned by a KIND).  reject-by-default: only `+`/juxtaposition is defined.
   if (ccs ~ /[([{]\|/) { print substr($0, 1, clw) "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: `" clhs " <- (| .. |) " ccs "`: undefined operator joining raw bananas -- only `+`/juxtaposition (concat) is defined; inline a pipe in one block (`(| a | b |)`) or type the operands (`jqlang(| .. |) | jqlang(| .. |)`))"; next }
   if (ccs != "" && !ccword) { print substr($0, 1, clw) "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: recipe capture `" clhs " <- (| .. |)`: trailing `" ccs "` unsupported)"; next }
   if (ccword && ccn > 1) { print substr($0, 1, clw) "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: `cooked` word cannot apply to a multi-body `+` capture; cook each block with `[| .. |]`)"; next }
   for (cci = 1; cci <= ccn; cci++) {
      ccg = "__cap_" NR (ccn > 1 ? "_" cci : ""); ccsep = (cci == 1 ? "" : "; ")
      if (CCBR[cci] != "(" || (cci == 1 && ccword)) {
         LIFT[++NL] = "⟅" ccg "\n" (CCBD[cci] == "" ? "" : CCBD[cci] "\n") "⟆"; crun = crun ccsep "$(" ccg ")"
      } else {
         LIFT[++NL] = "define " ccg "\n" (CCBD[cci] == "" ? "" : CCBD[cci] "\n") "endef"; crun = crun ccsep "bash ⬥" ccg } }
   print substr($0, 1, clw) clhs "=`" crun "`"
   next }
  # multi-LINE recipe capture: `LHS <- (| ` whose matching close is on a LATER line.
  # The body (already col-0 from dedent) is ACCUMULATED across lines until the closing
  # `|)`, then lowered like the single-line arm above -- just gathered over many lines.
  # `cml` is the in-flight flag; body lines are caught by the `cml == 1` buffer rule
  # (before the general lambda scan) so nothing else re-parses them.  Three outcomes:
  #   raw `(| .. |)`  -> `define __cap_N`; run from a tmpfile (`bash ⬥`, child scope).
  #   cooked `[| """..""" |]` (a triple-quote body) -> cooks to one `printf` line, so the
  #     inline `$(__cap_N)` stays single-line + recipe-scoped -- lifted as `⟅__cap_N⟆`.
  #   cooked, any other multi-line body -> REJECTED: its lowering would inline a
  #     multi-line `$(__cap_N)` that splits the recipe backtick (use raw, or one line).
  cml == 0 && /^[ \t]*@@SYM_NAME@@+[ \t]*<-[ \t]*[([{]\|/ && $0 !~ /\|[])}]/ {
   match($0, /^[ \t]*/); clw = RLENGTH; cml_lead = substr($0, 1, clw)
   cpi = index($0, "<-"); cml_lhs = substr($0, clw + 1, cpi - clw - 1); sub(/[ \t]+$/, "", cml_lhs)
   crhs = substr($0, cpi + 2); match(crhs, /[([{]\|/); cml_bch = substr(crhs, RSTART, 1)
   cbody = substr(crhs, RSTART + 2); sub(/^[ \t]+/, "", cbody); sub(/[ \t]+$/, "", cbody)
   cml = 1; cml_g = "__cap_" NR; cml_acc = (cbody == "" ? "" : cbody "\n")
   next }
  cml == 1 && /^[ \t]*\|[])}]/ {
   crest = $0; sub(/^[ \t]*\|[])}][ \t]*/, "", crest); sub(/[ \t]+$/, "", crest)
   if (crest ~ /^[!+]/ || crest ~ /[([{]\|/) { print cml_lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: recipe capture `" cml_lhs " <- (| .. |)`: trailing `" crest "` unsupported here -- `!`/`+`/multi-body are module-level only)"; cml = 0; cml_acc = ""; next }
   if (cml_bch == "(" && crest !~ /^cooked(_deeply)?([ \t,]|$)/) {   # raw shell body
      LIFT[++NL] = "define " cml_g "\n" cml_acc "endef"
      print cml_lead cml_lhs "=`bash ⬥" cml_g "`"
   } else if (cml_acc ~ /^"""/ && cml_acc ~ /"""[ \t]*\n$/) {        # cooked triple-quote
      LIFT[++NL] = "⟅" cml_g "\n" cml_acc "⟆"
      print cml_lead cml_lhs "=`$(" cml_g ")`"
   } else
      print cml_lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: `" cml_lhs " <- [| .. |]` -- multi-line cooked capture would split the recipe; use a triple-quote body, raw `<- (| .. |)` for shell, or keep it on one line)"
   cml = 0; cml_acc = ""; next }
  cml == 1 { cml_acc = cml_acc $0 "\n"; next }
  # multi-LINE recipe lambda: an anonymous `(| ` whose matching close is on a LATER line --
  # the effect/`in` counterpart of the multi-line capture arm above (no `<-`).  The body is
  # ACCUMULATED verbatim (real newlines, so indented-block languages survive) into a module
  # define, then dispatched exactly like the single-line arm below -- the trailer (`in <X>`,
  # `{env}`, `(args)`, `cooked`) is read from the CLOSING `|)` line.  `mll` is the in-flight
  # flag; body lines are caught by the `mll == 1` buffer rule before any other arm re-parses
  # them.  A multi-line anonymous banana gets no col-0 dedent from earlier stages (it is
  # neither NAMED nor ASSIGN), so `_bdedent` strips the common indent here.  A body line
  # that itself contains `|)`, and a `.method()`/`+`/multi-body trailer, stay unsupported
  # (same limits as the capture arm); a bare multi-line lambda with no target is a loud error.
  mll == 0 && /^[ \t]/ && $0 !~ /<-/ && $0 !~ /\|[])}]/ {
   _lam_open($0, LR)
   if (LR["p"] > 0) {
      match($0, /^[ \t]*/); mll_lead = substr($0, 1, RLENGTH); mll_bch = LR["bch"]
      mll_head = substr($0, LR["p"] + 2); sub(/^[ \t]+/, "", mll_head); sub(/[ \t]+$/, "", mll_head)
      mll = 1; mll_g = "__lambda_" NR; mll_acc = ""
      next } }
  mll == 1 && /^[ \t]*\|[])}]/ {
   mtail = $0; sub(/^[ \t]*\|[])}][ \t]*/, "", mtail); sub(/[ \t]+$/, "", mtail)
   if (mtail ~ /^[!+]/ || mtail ~ /^[([{]\|/) { print mll_lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: multi-line recipe lambda `(| .. |)`: `" substr(mtail, 1, 1) "` trailer unsupported -- `!`/`+`/multi-body are single-line/module-level)"; mll = 0; mll_acc = ""; next }
   _lam_trailer(mtail, (mll_bch == "[" || mll_bch == "{"), LR)
   # bare multiline lambda (no `in`/ambient, no other treatment) is an inert string, not
   # runnable: like the single-line arm below, it needs an execution context (a machine, a
   # ctor, or a capture) before it can run.  Alone on a recipe line it is an error.
   if (!LR["seen"] && LR["amb"] == "") {
      print mll_lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: a bare `(| .. |)` is an inert string, not runnable at recipe scope -- attach an execution context first: `(| .. |) in host.native.sh`, a ctor `host.native.sh(| .. |)`, or a capture `x <- (| .. |)`)"
      mll = 0; mll_acc = ""; next }
   print _lam_emit(mll_lead, mll_g, (mll_head != "" ? mll_head "\n" : "") _bdedent(mll_acc), LR["docook"], LR["amb"], LR["env"], LR["args"], LR["tail"])
   mll = 0; mll_acc = ""; next }
  mll == 1 { mll_acc = mll_acc $0 "\n"; next }
  # UNCAPTURED multi-banana `(| a |) + (| b |)` (or adjacency) on a recipe line, no trailer:
  # string-concat with no execution context is an inert value, not runnable -- so this errors.
  # Bodies are peeled first only to CONFIRM a clean >=2-block concat with no leftover trailer;
  # otherwise fall through (a single bare banana or a `(args)`/`{env}`/`.method` trailer is left
  # to the lambda arms below, which reject a bare banana in the same way).
  /^\t[ \t]*[([{]\|/ {
   ueff_lead = ""; if (match($0, /^[ \t]+/) > 0) ueff_lead = substr($0, 1, RLENGTH)
   ueff_s = $0; sub(/^[ \t]+/, "", ueff_s); ueff_n = 0; ueff_ok = 1
   while (match(ueff_s, /^[([{]\|/) > 0) {
      ueff_n++; UEFFC[ueff_n] = substr(ueff_s, 1, 1); ueff_r = substr(ueff_s, 3)
      if (!bclose(ueff_r)) { ueff_ok = 0; break }
      ueff_x = RSTART; ueff_b = substr(ueff_r, 1, ueff_x - 1); sub(/^[ \t]+/, "", ueff_b); sub(/[ \t]+$/, "", ueff_b)
      UEFFB[ueff_n] = ueff_b
      ueff_s = substr(ueff_r, ueff_x + 2); sub(/^[ \t]+/, "", ueff_s)
      # only `+` or bare adjacency (a following `(|`) joins raw bananas -- both are string
      # concat.  `+` is consumed here; adjacency is left for the next turn.  ANY other separator
      # stops the peel (no per-operator blocklist); the leftover is caught by the guard below.
      if (ueff_s ~ /^\+/) sub(/^\+[ \t]*/, "", ueff_s)
      else if (ueff_s !~ /^[([{]\|/) break
      sub(/^[ \t]+/, "", ueff_s) }
   sub(/[ \t]+$/, "", ueff_s)
   # a clean `>=2`-banana line joined only by `+`/adjacency (no leftover) is the concat case; a
   # single banana, or a leftover (a trailer, or a bad-operator second banana) FALLS THROUGH to
   # the single-line lambda arm -- which parses `in`/`{env}`/... and rejects a stray banana there.
   if (ueff_ok && ueff_n >= 2 && ueff_s == "") {
      # `+`/juxtaposition is string-concat; with no capture and no machine there is nothing to
      # run it against, so an uncaptured concat alone on a recipe line is an error.
      print ueff_lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: bare `(| a |) + (| b |)` at recipe scope is inert string-concat, not runnable -- capture with `x <- ..` or attach a machine like `in host.native.sh` to run)"; next }
  }
  # BANANA-DOT-BANANA operator chain: `ctorA(| a |).ctorB(| b |)..` on one recipe line -- named-ctor
  # banana operands joined by a TABLE-A operator, folded (shared `_bfold`) then RUN inline (`dot.run`).
  # The `&LHS <- ..` capture arm above rides the SAME `_bfold` with a bind sink instead.  A leading
  # pipe-terminated `<cmd> |` prefix feeds the chain's stdin (kept as LEAD).
  /^[ \t].*@@SYM_NAME@@+[([{]\|.*\|[])}][ \t]*[\/.|][ \t]*@@SYM_NAME@@+[([{]\|/ {
   match($0, /^[ \t]*/); bd_lead = substr($0, 1, RLENGTH); bd_s = substr($0, RLENGTH + 1)
   if (match(bd_s, /@@SYM_NAME@@+[([{]\|/)) { bd_pre = substr(bd_s, 1, RSTART - 1); if (bd_pre ~ /\|[ \t]*$/) { bd_lead = bd_lead bd_pre; bd_s = substr(bd_s, RSTART) } }
   _bfold(bd_s, BR)
   if (BR["ok"]) { print bd_lead "$(call lang.grammar.dot.run," BR["acc"] ")"; next } }
  # ANONYMOUS-IMMEDIATE ctor(-path) on one recipe line -- hoist the body to a gensym define, then
  # invoke inline.  The ctor MUST be the FIRST token (anchored, no `.*` before it) so a lambda with
  # an `in <ctor>(| .. |)` trailer -- first banana anonymous `(|` -- falls through to the lambda arm.
  # A bare `(| body |){env}` is an anonymous banana (no callforms, string algebra only), left below.
  # Two trailers:
  #   `.method(args)` -> CONSTRUCT a gensym instance (`$(call ctor, def=g)`) + fold to `$(call g.method,args)`.
  #   `{env}` / `(args)` -> the RECEIVER/recipe idiom (e.g. `host.native.sh(| code |){WHO=w}`): route the
  #     body to the ctor's `.__call__` as a blockref (`$(call <name>.__call__, ⬥g args)`), run via its
  #     entrypoint -- so a machine RUNS the block; `{env}`=env-prefix, `(args)`=positional.  (Building a
  #     handle for a class ctor, e.g. `Dockerfile(| .. |){build_args}`, is a separate follow-up.)
  /^[ \t]+(@@SYM_NAME@@+[ \t]+)*@@SYM_NAME@@+[([{]\|.*\|[])}][ \t]*((\.[A-Za-z_]@@SYM_NAME@@*[ \t]*\(|[{(])|$)/ {
   match($0, /^[ \t]*/); ai_lead = substr($0, 1, RLENGTH); ai_rest = substr($0, RLENGTH + 1)
   match(ai_rest, /[([{]\|/); ai_pre = substr(ai_rest, 1, RSTART - 1); sub(/[ \t]+$/, "", ai_pre)
   ai_af = substr(ai_rest, RSTART + 2)
   ai_body = substr(ai_af, 1, bclose(ai_af) - 1); sub(/^[ \t]+/, "", ai_body); sub(/[ \t]+$/, "", ai_body)
   # the trailer: `.method(args)` or `{env}`/`(args)`
   ai_tail = substr(ai_af, RSTART + 2); sub(/^[ \t]+/, "", ai_tail)
   # ctor = pre-open words, dotted
   ai_nw = split(ai_pre, ai_W, /[ \t]+/); ai_ctor = ""
   for (ai_i = 1; ai_i <= ai_nw; ai_i++) ai_ctor = (ai_ctor == "" ? ai_W[ai_i] : ai_ctor "." ai_W[ai_i])
   # no ctor -> leave to the lambda arm (bare banana)
   if (ai_ctor == "") { print; next }
   ai_g = "__lambda_" NR
   LIFT[++NL] = "define " ai_g "\n" (ai_body == "" ? "" : ai_body "\n") "endef"
   # bare `NAME(| body |)` (no trailer): ctor gensym'd (no `define NAME`). A ctor constructs an inert instance
   # (no-op unless captured); a machine runs the body.
   if (ai_tail == "") {
      ai_tmpl = "$(filter-out undefined,$(origin " ai_ctor ".__tmpl))"
      LIFT[++NL] = "$(if " ai_tmpl ",$(call " ai_ctor ", def=" ai_g "))"
      print ai_lead "$(if " ai_tmpl ",:,$(call " ai_ctor ".__call__, ⬥" ai_g "))"
      next
   }
   # `.method(args)` -- construct a gensym instance, call the method
   if (ai_tail ~ /^\./) {
      LIFT[++NL] = "$(call " ai_ctor ", def=" ai_g ")"
      sub(/^\.[ \t]*/, "", ai_tail); match(ai_tail, /\(/); ai_method = substr(ai_tail, 1, RSTART - 1); sub(/[ \t]+$/, "", ai_method)
      # matching close for method args
      ai_ap = substr(ai_tail, RSTART); ai_d = 0; ai_k = 0
      for (ai_i = 1; ai_i <= length(ai_ap); ai_i++) { ai_c = substr(ai_ap, ai_i, 1); if (ai_c == "(") ai_d++; else if (ai_c == ")") { if (--ai_d == 0) { ai_k = ai_i; break } } }
      ai_args = substr(ai_ap, 2, ai_k - 2); sub(/^[ \t]+/, "", ai_args); sub(/[ \t]+$/, "", ai_args)
      # a body after the method args is the link's own banana: hoist it and hand it over the way a ctor takes one
      ai_brest = substr(ai_ap, ai_k + 1); sub(/^[ \t]+/, "", ai_brest)
      if (bopen(ai_brest) == 1) {
         ai_after = substr(ai_brest, 3); ai_ci = bclose(ai_after)
         if (ai_ci > 0) {
            ai_bd = substr(ai_after, 1, ai_ci - 1); sub(/^[ \t]+/, "", ai_bd); sub(/[ \t]+$/, "", ai_bd)
            ai_bg = "__lambda_" NR "b"
            LIFT[++NL] = "define " ai_bg "\n" (ai_bd == "" ? "" : ai_bd "\n") "endef"
            ai_args = (ai_args == "" ? "" : ai_args " ") "def=" ai_bg } }
      print ai_lead "$(call " ai_g "." ai_method (ai_args == "" ? "" : "," ai_args) ")"
   } else {
      # `{env}`/`(args)` trailer. A CONSTRUCTOR-kind (has `.__tmpl`) constructs an instance and we invoke IT
      # (the `.method` arm's move); a MACHINE (Runnable, no `.__tmpl`) routes the body to its `.__call__` as a
      # blockref (run via entrypoint).
      # {k=v} -> LR["env"], (a,b) -> LR["args"]
      _lam_trailer(ai_tail, 0, LR)
      ai_env = env_prefix(LR["env"]); ai_ac = LR["args"]; ai_as = LR["args"]; gsub(/,/, " ", ai_as)
      ai_tmpl = "$(filter-out undefined,$(origin " ai_ctor ".__tmpl))"
      # construct the instance iff the receiver is a constructor-kind
      LIFT[++NL] = "$(if " ai_tmpl ",$(call " ai_ctor ", def=" ai_g "))"
      print ai_lead ai_env (ai_env == "" ? "" : " ") "$(if " ai_tmpl ",$(call " ai_g ".__call__" (ai_ac == "" ? "" : "," ai_ac) "),$(call " ai_ctor ".__call__, ⬥" ai_g (ai_as == "" ? "" : " " ai_as) "))"
   }
   next }
  # `&<recv> in <machine>` -- run a NAMED banana/receiver (a `&`-handle, a captured fragment) in a
  # machine.  The leading `&` marks it as cmk-lang (a receiver, not shell): a plain `<recv> in <m>`
  # stays shell (so `grep in file` is left alone).  The receiver is ALREADY a def (its shape), so
  # reuse the machine dispatch (`_lam_emit` predef) by name -- no `__lambda` hoist; a bare image errors.
  /^[ \t]+&@@SYM_NAME@@+[ \t]+in[ \t]+[A-Za-z0-9._:\/-]+[ \t]*$/ {
   ri_lead = $0; sub(/[^ \t].*$/, "", ri_lead)
   ri_body = $0; sub(/^[ \t]+/, "", ri_body); sub(/[ \t]+$/, "", ri_body); sub(/^&/, "", ri_body)
   ri_name = ri_body; sub(/[ \t]+in[ \t].*$/, "", ri_name)
   ri_amb = ri_body; sub(/^.*[ \t]+in[ \t]+/, "", ri_amb)
   print _lam_emit(ri_lead, ri_name, "", 0, ri_amb, "", "", "", 1); next }
  # `&<lhs> <- <recv> in <machine>` -- CAPTURE the machine-run of a named receiver.  The leading `&`
  # marks the RHS as cmk-lang (`in` is the machine-runner); a PLAIN `<lhs> <- ..` (no `&`) is eager
  # SHELL and left alone, so `x <- foo in bar` stays a shell capture (`foo: not found`).  `in` runs at
  # runtime, so the result is a recipe shell var (read `$${lhs}`).  Reuses the bare dispatch, captured.
  /^[ \t]+&@@SYM_NAME@@+[ \t]*<-[ \t]*@@SYM_NAME@@+[ \t]+in[ \t]+[A-Za-z0-9._:\/-]+[ \t]*$/ {
   rc_lead = $0; sub(/[^ \t].*$/, "", rc_lead)
   rc_body = $0; sub(/^[ \t]+/, "", rc_body); sub(/[ \t]+$/, "", rc_body); sub(/^&/, "", rc_body)
   rc_id = rc_body; sub(/[ \t]*<-.*/, "", rc_id)
   rc_rhs = rc_body; sub(/^@@SYM_NAME@@+[ \t]*<-[ \t]*/, "", rc_rhs)
   rc_name = rc_rhs; sub(/[ \t]+in[ \t].*$/, "", rc_name)
   rc_amb = rc_rhs; sub(/^.*[ \t]+in[ \t]+/, "", rc_amb)
   print rc_lead rc_id "=`" _lam_emit("", rc_name, "", 0, rc_amb, "", "", "", 1) "`"; next }
  # SINGLE-LINE recipe lambda: an anonymous `(| body |)` with its close + trailer on one line.
  # Same shape as the multi-line arm above, minus the accumulation -- body, dispatch, and the
  # `in`/`{env}`/`(args)`/`cooked` trailer all come off this one line, via the shared helpers.
  {
   _lam_open($0, LR)
   if (LR["p"] == 0) { print; next }
   p = LR["p"]; aft = substr($0, p + 2)
   if (!bclose(aft)) { print; next }
   c = RSTART
   body = substr(aft, 1, c - 1); sub(/^[ \t]+/, "", body); sub(/[ \t]+$/, "", body)
   tail = substr(aft, c + 2); sub(/^[ \t]+/, "", tail); lead = substr($0, 1, p - 1)
   # `!`/`+`/multi-body with a lambda `(args)`/`{env}` trailer is undefined -> error (`(|` here =
   # multi-body; a real `(x)` args trailer is `(` not `(|`).
   if (tail ~ /^[!+]/ || tail ~ /^[([{]\|/) { print lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: recipe lambda `(| .. |)`: `" substr(tail, 1, 1) "` with a lambda trailer is undefined -- capture with `<- ..` to concatenate, or attach a machine; `!` is module-level)"; next }
   _lam_trailer(tail, (LR["bch"] == "[" || LR["bch"] == "{"), LR)
   # a raw banana still joined to ANOTHER banana after trailer-parsing (`in`/`{env}`/`(args)`/
   # `cooked` are all consumed above, incl. `in ctor(| .. |)`) means an operator with no string
   # -algebra meaning joins them -- only `+`/juxtaposition (concat) is defined.  reject-by-default
   # (no per-operator blocklist); recipe lines only, so module-level prose with `(|` passes through.
   if ($0 ~ /^\t/ && LR["tail"] ~ /[([{]\|/) { print lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: undefined operator joining raw `(| .. |)` bananas -- only `+`/juxtaposition (concat) is defined; inline a pipe in one block (`(| a | b |)`) or type the operands (`jqlang(| .. |) | jqlang(| .. |)`))"; next }
   # a bare `(| body |)` with no trailer/ambient is an inert string (a quote), not runnable: at
   # module scope it is a template, and a recipe line (tab-led) that tries to run one alone is an
   # error -- it needs an execution context (a machine, a ctor, or a capture) first.  A NON-recipe
   # line that merely contains the open (a docstring, prose, ...) is left as is; lambdalift only
   # rewrites recipe lambdas.
   if (!LR["seen"] && LR["amb"] == "") {
      if ($0 !~ /^\t/) { print; next }
      print lead "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: a bare `(| .. |)` is an inert string, not runnable at recipe scope -- attach an execution context first: `(| .. |) in host.native.sh`, a ctor `host.native.sh(| .. |)`, or a capture `x <- (| .. |)`)"; next }
   print _lam_emit(lead, "__lambda_" NR, body, LR["docook"], LR["amb"], LR["env"], LR["args"], LR["tail"])
  }
  END { for (i = 1; i <= NL; i++) print LIFT[i] }
endef
# Join a target's recipe body into one shell invocation: every line but the
# last gets a trailing connector so the body shares shell state and is
# fail-fast. The connector is the `-v JOIN` arg (the `recipe_join` pragma):
# default/`&&` joins with ` && \`, `;` with ` ; \`, `none` leaves each line
# separate (no shared shell state). A real trailing shell comment is
# stripped first. Runs last; skips define..endef bodies (depth-tracked).
#:phase COMPILE seed=1 awklang=no
define .awk.joinbody
  BEGIN { def_depth = 0; n = 0; in_doc = 1
      CONN = " && \\"; if (JOIN == ";") CONN = " ; \\"; else if (JOIN == "none") CONN = ""
      # target_locals pragma (read generically from the env, no per-pragma -v threading):
      # when truthy, recipes that reference `__locals__` get a baseline-capture preamble.
      TL = ENVIRON["CMK_PRAGMA_TARGET_LOCALS"]; TL = (TL != "" && TL != "0" && TL != "false" && TL != "no")
      # vm_trace pragma: when truthy, inject ${__vm__.frame.enter} as the first recipe line of every eligible
      # recipe (-> each becomes an observable VM frame, no hand-placed call).  VTSKIP excludes infra/observer
      # + private target NAMES; observer recipes that READ the VM are also skipped (in flush()).
      VT = ENVIRON["CMK_PRAGMA_VM_TRACE"]; VT = (VT != "" && VT != "0" && VT != "false" && VT != "no")
      VTSKIP = ENVIRON["CMK_VM_TRACE_SKIP"]; if (VTSKIP == "") VTSKIP = "^([._]|__vm__[.]|mk[.]|flux[.]|io[.]|tux[.]|cmk[.]|polyglot[.])" }
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
  function flush(   i, conn, uses) {
      # target_locals: inject a baseline-capture preamble as the first recipe line, but only
      # for recipes that actually use locals (zero overhead elsewhere).  `compgen -v` in
      # `$$(...)` is fork-only (no exec); joined with `&&` it persists across the recipe.
      # Detect both the direct `__locals__` and any `*.locals` convenience wrapper (e.g.
      # `log.locals`).  A false match just injects one cheap unused baseline.
      if (TL && n > 0) {
          uses = 0
          for (i = 1; i <= n; i++) if (buf[i] ~ /__locals__|[.]locals/) { uses = 1; break }
          if (uses) {
              for (i = n; i >= 1; i--) buf[i+1] = buf[i]
              buf[1] = "_target_local_baseline=\"$$(compgen -v)\""
              n++ } }
      # vm_trace: inject ${__vm__.frame.enter} as buf[1] -> the recipe shell becomes a live VM frame.  Once
      # per target (vt_injected), skipping: excluded NAMES (VTSKIP), recipes already calling frame.enter, and
      # OBSERVER recipes that READ the VM (__vm__.frames/.snapshot -- else the tracer would trace itself).
      # `$(or ..,true)` keeps it a valid no-op when the virtual-machine plugin isn't imported (empty expansion).
      if (VT && n > 0 && cur_target != "" && cur_target !~ VTSKIP && !vt_injected) {
          vt_injected = 1; vtskip = 0
          for (i = 1; i <= n; i++) if (buf[i] ~ /__vm__[.]frame[.]enter|__vm__[.]frames|__vm__[.]snapshot/) { vtskip = 1; break }
          if (!vtskip) {
              for (i = n; i >= 1; i--) buf[i+1] = buf[i]
              buf[1] = "$(or ${__vm__.frame.enter},true)"
              n++ } }
      for (i = 1; i <= n; i++) {
          if (i < n) {
              if (buf[i] ~ /\\$/) conn = ""
              else if (buf[i] ~ /(;|&&|\|\||\||&)[ \t]*$/) conn = (CONN == "" ? "" : " \\")
              else conn = CONN
              print "\t" buf[i] conn }
          else print "\t" buf[i] }
      n = 0 }
  /^define __ambient_/ { flush(); print; in_doc = 1; next }   # encapsulation ambient: its body is ordinary targets+recipes -- descend and join them, don't treat as opaque macro text
  /^define / { flush(); def_depth++; print; in_doc = 1; next }   # literal: .awk.joinbody is invoked raw (io.awk), so it bypasses lang.grammar.ctx.fill
  /^endef[ \t]*$/ { flush(); if (def_depth > 0) def_depth--; print; in_doc = 1; next }
  def_depth > 0 { print; next }
  /^\t/ {
      c = $0; sub(/^\t/, "", c)
      # A leading `@#` block is the target's docstring: emit it verbatim (as separate
      # `\t@#` lines, never folded into the joined body) so `help`/mk.parse can read it.
      # A `@#` after the body has started is a throwaway annotation -- drop it.
      if (in_doc && c ~ /^@#/) { print "\t" c; next }
      if (c ~ /^@#/) next
      in_doc = 0
      c = strip_comment(c)
      if (c ~ /^[ \t]*$/) next
      if (c ~ /^[-+]/) { flush(); print "\t" c; next }
      if (n > 0) sub(/^@/, "", c)
      buf[++n] = c; next }
  { flush()   # a non-recipe line ends the previous recipe; capture the NEXT recipe's target name (for vm_trace)
    if ($0 ~ /^[^\t][^:=]*:([^=]|$)/) { _t = $0; sub(/:.*/, "", _t); sub(/^[ \t]+/, "", _t); split(_t, _ta, " "); cur_target = _ta[1] } else cur_target = ""
    vt_injected = 0; print; in_doc = 1 }
  END { flush() }
endef

# Shared `{env}` callform-channel helper (a callform-channel is a trailer --
# the `(args)`/`[stream]`/ `{env}` grammar, unrelated to the event-bus
# channel feature): the one `{k=v k2="v w spaces"}` becomes a shell env
# prefix `k='v' ..`, used by both the callform stage and lambdalift.
# Quote-aware: tokens split on unquoted whitespace, one layer of user quotes
# is stripped, and the value is re-wrapped in quotes.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.callform.channels
  # The `{k=v ..}` channel content is already a shell env prefix, so pass it through raw -- the
  # shell resolves quoting and $-expansion, matching how (args)/ctor kwargs carry values verbatim.
  # Re-quoting here would be the lone exception in the grammar and would freeze $-refs.
  function env_prefix(kw) {
    sub(/^[ \t]+/, "", kw); sub(/[ \t]+$/, "", kw); return kw }
endef

# Shared banana-bracket scanners -- the one source of truth for "where is a
# banana boundary": the digraph `(|`/`[|`/`{|` (open) or `|)`/`|]`/`|}`
# (close), at any position on the line. `bopen` returns the column of the
# first open (stashing its bracket char), `bclose` the first close. Consumed
# by the sugar and dedent stages, so both agree on a banana's extent
# regardless of layout.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.banana
  function bopen(s) { if (match(s, /[([{]\|/)) { _bch = substr(s, RSTART, 1); return RSTART } _bch = ""; return 0 }
  # TODO: bclose accepts any closer regardless of the opener recorded in `_bch`, so a mismatched pair
  # (`(| .. |]`) lowers as if matched instead of erroring (see test_banana_bracket_mismatch_is_rejected).
  function bclose(s) { if (match(s, /\|[])}]/)) return RSTART; return 0 }
  # _bnext(s): advance to the next banana boundary in s.  Sets _bk ("o"pen | "c"lose), _bp (the
  # text just before the digraph -- an open's PREFIX for name/ctor; a close's preceding BODY) and
  # _brest (the text after the digraph).  Returns 1 if a boundary was found, else 0.  THE one
  # line-walk, driven by both dedent (frame balance) and sugar (dot-chain operands).
  function _bnext(s,   oc, cc) {
     oc = bopen(s); cc = bclose(s)
     if (oc == 0 && cc == 0) return 0
     if (cc != 0 && (oc == 0 || cc < oc)) { _bk = "c"; _bp = substr(s, 1, cc - 1); _brest = substr(s, cc + 2) }
     else { _bk = "o"; _bp = substr(s, 1, oc - 1); _brest = substr(s, oc + 2) }
     return 1 }
  # classify an open's prefix: a name/path/kwargs/`*`/assign before `(|` = a DECLARATION banana; a
  # bare `(|` = an ANON lambda.  `_fname` extracts the declaration's name (for diagnostics/ctor).
  function _isnamed(p) { return (p ~ /[A-Za-z0-9_.)*]$/ || p ~ /(:=|=|<-)[ \t]*$/) }
  function _fname(p) { sub(/[ \t]*$/, "", p); if (p ~ /(:=|=|<-)$/) sub(/[ \t]*(:=|=|<-)$/, "", p); sub(/^.*[^A-Za-z0-9_.]/, "", p); sub(/^\.+/, "", p); return p }
  # _bdedent(s): strip the longest common leading-whitespace prefix from the non-blank lines of a
  # newline-joined body, so foreign code lands at column 0 regardless of its authored indent.  The
  # FLAT dedent (no frame nesting) shared by lambdalift (lambda bodies) and the namespace capture.
  function _bdedent(s,   n, a, i, pref, havep, out) {
    n = split(s, a, "\n"); pref = ""; havep = 0
    for (i = 1; i <= n; i++) {
      if (a[i] ~ /^[ \t]*$/) continue
      match(a[i], /^[ \t]*/)
      if (!havep) { pref = substr(a[i], 1, RLENGTH); havep = 1 }
      else while (pref != "" && substr(a[i], 1, length(pref)) != pref) pref = substr(pref, 1, length(pref) - 1) }
    out = ""
    for (i = 1; i <= n; i++) {
      if (i == n && a[i] == "") break
      if (a[i] ~ /^[ \t]*$/) out = out "\n"
      else if (pref != "" && substr(a[i], 1, length(pref)) == pref) out = out substr(a[i], length(pref) + 1) "\n"
      else out = out a[i] "\n" }
    return out }
endef

# Shared error helpers for CMK compiler awk stages: print a stage-tagged
# message to stderr and exit 79 (the compile-error code).  `cmk_die` -- bare
# error. `cmk_die_at` -- error citing the offending source line (defaults to
# current NR/$0).
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.errors
  function cmk_die(stage, msg) {
    printf "compose.mk (cmk:%s) error: %s\n", stage, msg > "/dev/stderr"
    if (ENVIRON["_CMK_CERR"] != "") { print stage > ENVIRON["_CMK_CERR"]; close(ENVIRON["_CMK_CERR"]) }
    exit 79 }
  # cmk_warn -- the soft (non-fatal) companion to cmk_die: same `compose.mk (cmk:<stage>)`
  # prefix, `warning:` severity, no exit.  The one lint/diagnostic voice for the awk stages.
  function cmk_warn(stage, msg) {
    printf "compose.mk (cmk:%s) warning: %s\n", stage, msg > "/dev/stderr" }
  function cmk_die_at(stage, msg, lineno, src) {
    if (lineno == "") lineno = NR
    if (src == "") src = $0
    printf "compose.mk (cmk:%s) error: %s\n  at line %s: %s\n", stage, msg, lineno, src > "/dev/stderr"
    if (ENVIRON["_CMK_CERR"] != "") { print stage > ENVIRON["_CMK_CERR"]; close(ENVIRON["_CMK_CERR"]) }
    exit 79 }
endef

# Shared define..endef guard for line-oriented CMK stages: pass define-block
# bodies (raw polyglot/awk/docstring text) through untouched.  Prepended
# before a stage's main `{...}` rule.  Depth-tracked, so nested defines pass
# through verbatim too.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.defskip
  /@@SYM_DEFINE@@ / { def_depth++; print; next }
  /^endef[ \t]*$/ { if (def_depth > 0) def_depth--; print; next }
  def_depth > 0 { print; next }
endef

# Wrap a bare m5 reference as a value-expansion; skips already-wrapped refs, literals, and banana bodies.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.m5wrap
  BEGIN { _na = split(M5ACC, _aa, " "); for (_ai = 1; _ai <= _na; _ai++) _acc[_aa[_ai]] = 1 }
  function wrap(s,   out,i,L,c3,c2,pc,prev2,start,j,grp,k,nm) {
    out = ""; i = 1; L = length(s)
    while (i <= L) {
      c3 = substr(s, i, 3); c2 = substr(s, i, 2)
      if (_bd > 0) {
        if (bclose(c2) == 1) { _bd--; out = out c2; i += 2; continue }
        if (bopen(c2)  == 1) { _bd++; out = out c2; i += 2; continue }
        out = out substr(s, i, 1); i++; continue }
      if (bopen(c2) == 1) { _bd++; out = out c2; i += 2; continue }
      if (is_delim(c3)) { parse_literal(substr(s, i), "m5wrap"); out = out LIT_; s = REM_; i = 1; L = length(s); continue }
      if (c3 == "m5[") {
        prev2 = (i >= 3) ? substr(s, i-2, 2) : ""
        pc = (i >= 2) ? substr(s, i-1, 1) : ""
        if (prev2 == "$(" || prev2 == "${" || pc ~ /[A-Za-z0-9._]/) { out = out "m5["; i += 3; continue }
        start = i; i += 2; grp = 0
        while (substr(s, i, 1) == "[") { j = i+1; while (j <= L && substr(s, j, 1) != "]") j++; if (j > L) break; i = j+1; grp = 1 }
        if (!grp) { out = out substr(s, start, 2); continue }
        if (substr(s, i, 1) == ".") { k = i+1; while (k <= L && substr(s, k, 1) ~ /[A-Za-z0-9_]/) k++; nm = substr(s, i+1, k-i-1); if (nm in _acc) i = k }
        if (substr(s, i, 1) == "?") i++
        out = out "$(" substr(s, start, i - start) ")"; continue }
      out = out substr(s, i, 1); i++
    }
    return out }
  { print wrap($0) }
endef

# Shared triple-quote literal parser for the sugar stages (tagged,
# callform). `is_delim` -- is a string one of `'''`/`"""`/```` ``` ````?
# `parse_literal(s, stage)` -- read a leading literal from `s` (multi-line
# via getline), setting globals LIT_ (the literal incl. delimiters) and REM_
# (the remainder); cmk_die_at if unterminated.
#:phase COMPILE seed=1 awklang=no
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

# Shared shell-lexing prelude (like litparse): next_sep scans a line for the
# first top-level statement separator (a semicolon or a logical and/or),
# reporting its position and text.  Ones inside quotes or a paren/brace
# group are skipped, so a compound command reads as one statement. Any stage
# that splits a recipe line on real statement boundaries can reuse it.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.sepscan
  function next_sep(s, sepout,   i, c, n, q, d, two, bs) {
    n = length(s); q = ""; d = 0; bs = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q == "'") { if (c == "'") q = ""; continue }
      if (bs) { bs = 0; continue }
      if (c == "\\") { bs = 1; continue }
      if (q == "\"") { if (c == "\"") q = ""; continue }
      if (c == "'" || c == "\"") { q = c; continue }
      if (c == "(" || c == "{") { d++; continue }
      if (c == ")" || c == "}") { if (d > 0) d--; continue }
      if (d > 0) continue
      if (c == ";") { sepout[1] = i; sepout[2] = ";"; return }
      two = substr(s, i, 2)
      if (two == "&&") { sepout[1] = i; sepout[2] = "&&"; return }
      if (two == "||") { sepout[1] = i; sepout[2] = "||"; return }
    }
    sepout[1] = 0; sepout[2] = "" }
endef

# Docstring capture (early stage, after dedent, before sugar): three forms
# of a bare triple-quote. A column-0 block outside any banana is the module
# `__doc__` (first binds, later ones warn + drop). A column-0 block inside a
# banana body is that instance's docstring, lowered to a `${self}.__doc__`
# the constructor binds. The first indented line under a column-0 target
# header is the target docstring, lowered to the canonical `@#` form so
# mk.parse and CLI-help surface it like a hand-written one. A delimiter with
# trailing content (a pipe or capture form) is left verbatim for the
# triplequote stage. Reuses the shared literal parser and warn helpers.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.moduledoc
  BEGIN { seen = 0; want_tdoc = 0; bd = 0 }
  # A doc-bearing banana's leading docstring is always lifted OUT to
  # a sibling `<name>.__doc__` via fragdoc_capture; the ns-qualifier
  # prefixes a nested member's name, so a docstring never lands in
  # `.shape`.  `docstrings=0` opts OUT: the kind goes in RAW so its instances' leading triple-quote
  # is left VERBATIM in the shape (a language that needs it as literal data), never lowered to a make
  # carrier that would pollute the raw program.  Registers
  # NAME and its dotted basename; form-independent (multi-line `[| .. |]` and single-line `(.. )(| |)`).
  ($1 == "dsl" || $1 == "cmk.dsl") {
    _dn = $2; sub(/[([{].*$/, "", _dn)
    if (_dn != "") { _db = _dn; sub(/^.*\./, "", _db)
      if ($0 ~ /docstrings[ \t]*=[ \t]*0([^0-9]|$)/) { RAW[_dn] = 1; RAW[_db] = 1 } } }
  is_delim(substr($0, 1, 3)) {
    if (bd > 0 && (bstk[bd] == "x" || braw[bd])) { print; next }   # payload triple-quote in a capture/lambda/assign banana, or a `docstrings=0` raw-shape instance -- not a docstring
    want_tdoc = 0; want_mdoc = 0
    START_NR = NR; START_SRC = $0
    parse_literal($0, "moduledoc")
    if (REM_ ~ /^[ \t]*$/) { if (bd > 0) { if (bfrag[bd] != "") fragdoc_capture(bd) } else moduledoc_emit(); next }
    print LIT_ REM_; next }
  want_tdoc {
    want_tdoc = 0
    if ($0 ~ /^[ \t]+/) {
      match($0, /^[ \t]+/); lead = substr($0, 1, RLENGTH); body0 = substr($0, RLENGTH + 1)
      if (is_delim(substr(body0, 1, 3))) {
        START_NR = NR; START_SRC = $0
        parse_literal(body0, "moduledoc")
        if (REM_ ~ /^[ \t]*$/) { targetdoc_emit(lead); next }
        print lead LIT_ REM_; next } }
  }
  # A SPACE-indented `'''..'''` as the first body line of a doc-bearing banana (the encapsulation
  # `*[| .. |]` block indents its members) is a member docstring -- strip the lead, emit scoped.
  want_mdoc {
    want_mdoc = 0
    if (braw[bd]) { print; next }   # `docstrings=0` raw-shape instance -- leave the triple-quote literal
    if ($0 ~ /^[ ]+/) {
      match($0, /^[ ]+/); lead = substr($0, 1, RLENGTH); body0 = substr($0, RLENGTH + 1)
      if (is_delim(substr(body0, 1, 3))) {
        START_NR = NR; START_SRC = $0
        parse_literal(body0, "moduledoc")
        if (REM_ ~ /^[ \t]*$/) { if (bfrag[bd] != "") fragdoc_capture(bd); next }
        print lead LIT_ REM_; next } }
  }
  # A triple-quote that opens a multi-line literal away from a docstring position (mid-line,
  # after other content) is consumed whole here, so its closing line is not later taken for a
  # fresh opener.  Single-line and docstring cases are handled above.  Reuses parse_literal.
  bd == 0 && tq_multiline_open() {
    START_NR = NR; START_SRC = $0
    parse_literal(substr($0, TQ_POS), "moduledoc")
    print substr($0, 1, TQ_POS - 1) LIT_ REM_; next }
  # Track banana nesting so a `'''..'''` is scoped right.  Each multi-line banana open is pushed as
  # "doc" -- a named kind/instance/class/constructor/dsl decl, whose first line may be a member
  # docstring -- or "x" -- a recipe-embedded or `<-`/`:=`/`=` capture/lambda, whose dedented body may
  # hold a triple-quote that is payload (left verbatim).  bd==0 (top level) is the module docstring.
  # A decl may be col-0 or space-indented (an encapsulation `*[| .. |]` block indents its members);
  # a tab-indented open is a recipe lambda, so the `^[ ]*` (spaces only, no tab) keeps those "x".
  { if ($0 ~ /[([{]\|[ \t]*$/) { bd++
      if ($0 ~ /^[ ]*[^ \t#].*[([{]\|[ \t]*$/ && $0 !~ /(<-|:=|=)[ \t]*[([{]\|[ \t]*$/) { bstk[bd] = "doc"; want_mdoc = 1
        _bn = $0; sub(/[ \t]*[([{]\|[ \t]*$/, "", _bn); sub(/\(.*$/, "", _bn); sub(/^.*[ \t]/, "", _bn); bfrag[bd] = _bn; bfrag_doc[bd] = ""; braw[bd] = ($1 in RAW) }
      else { bstk[bd] = "x"; bfrag[bd] = ""; braw[bd] = 0 } }
    else if ($0 ~ /^[ \t]*\|[])}]/ && bd > 0) { _cd = bd; bd--
      if (bfrag_doc[_cd] != "") { print; print bfrag_doc[_cd]; bfrag_doc[_cd] = ""; next } }
    if ($0 ~ /^[^ \t#][^=]*:([^=]|$)/) want_tdoc = 1
    print }
  # Lift a doc-bearing banana's leading docstring OUT to a sibling define; flushed at close.
  function fragdoc_capture(d,   delim, body, n, a, i, out) {
    delim = substr(LIT_, 1, 3); body = substr(LIT_, 4, length(LIT_) - 6)
    sub(/^[ \t\n]+/, "", body); sub(/[ \t\n]+$/, "", body)
    if (delim == "'''") gsub(/\$/, "$$", body)
    n = split(body, a, "\n"); out = a[1]
    for (i = 2; i <= n; i++) out = out "${nl}" a[i]
    bfrag_doc[d] = "$(eval define " bfrag[d] ".__doc__${nl}" out "${nl}endef)" }
  function moduledoc_emit(   delim, body, n, a, i, ln) {
    delim = substr(LIT_, 1, 3); body = substr(LIT_, 4, length(LIT_) - 6)
    sub(/^[ \t\n]+/, "", body); sub(/[ \t\n]+$/, "", body)   # trim surrounding ws + framing newlines (internal newlines kept)
    if (seen) {
      if (MODULEDOC_LINT + 0) cmk_warn("moduledoc", "floating docstring near line " START_NR " optimized out (only the first module docstring becomes __doc__)")
      return }
    seen = 1
    if (delim == "'''") gsub(/\$/, "$$", body)
    print "define __doc__"
    n = split(body, a, "\n")
    for (i = 1; i <= n; i++) { ln = a[i]
      if (ln ~ /^(define|endef)[ \t]*$/) cmk_warn("moduledoc", "docstring body contains a bare `" ln "` line")
      print ln }
    print "endef"
    print "$(if ${__name__},$(eval define ${__name__}.__doc__${nl}$(value __doc__)${nl}endef))" }
  function targetdoc_emit(lead,   body, n, a, i, ln) {
    body = substr(LIT_, 4, length(LIT_) - 6)
    sub(/^[ \t\n]+/, "", body); sub(/[ \t\n]+$/, "", body)   # drop framing ws/newlines (incl. the indented close-delim line)
    n = split(body, a, "\n")
    for (i = 1; i <= n; i++) { ln = a[i]; sub(/^[ \t]+/, "", ln); print lead "@# " ln } }
  # tq_multiline_open -- true when this line opens a multi-line triple-quote (earliest of the
  # three delimiters, no matching close on the same line), setting TQ_POS to its column.
  function tq_multiline_open(   a, b, g, p, dl, rest3) {
    a = index($0, "'''"); b = index($0, "\"\"\""); g = index($0, "```"); p = 0
    if (a && (p == 0 || a < p)) p = a
    if (b && (p == 0 || b < p)) p = b
    if (g && (p == 0 || g < p)) p = g
    if (p == 0) return 0
    dl = substr($0, p, 3); rest3 = substr($0, p + 3)
    if (index(rest3, dl) > 0) return 0
    TQ_POS = p; return 1 }
endef

# Shared call-lowering helper for the sugar stages.  `lower_calls(text)`
# rewrites `NAME(args)` -> `$(call NAME,args)` with balanced parens,
# recursing on the args.  The trigger is set by the calling stage's BEGIN:
# TRIG_MODE="prefix" scans for the fixed string TRIG_PREFIX;
# TRIG_MODE="names" matches any NAMESET[] key (longest wins).  A trigger
# with no `(`, or an unbalanced `(`, is re-emitted verbatim.
#:phase COMPILE seed=1 awklang=no
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
        while (pos <= length(text) && substr(text, pos, 1) ~ /@@SYM_NAME_CALL@@/) { name = name substr(text, pos, 1); pos++ }
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

# Stage: import-name sugar -- lower the fixed set of import shorthands
# `NAME(args)` -> `$(call NAME,args)` (balanced + recursive via
# lower_calls).  Inert in define..endef.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.imports
  BEGIN { TRIG_MODE = "names"
    # The bare import-shorthand callforms actually used in source (demos/tests).  Any name
    # also reachable qualified as `cmk.<name>(..)` via the call stage; entries here only add
    # the ANCHORLESS bare spelling, so unused aliases (code.import, singular
    # import.target, plural import.defs) were dropped as dead.
    NAMESET["compose.import"]; NAMESET["compose.import.string"]
    NAMESET["compose.import.as"]
    NAMESET["import.def"]; NAMESET["import.targets"]
    NAMESET["docker.import"] }
  { print lower_calls($0) }
endef
# Stage: generic macro-call sugar -- lower `cmk.NAME(args)` -> `$(call
# NAME,args)`.  The macro anchor is the dialect sentinel `؆` (dialect
# rewrites `cmk.`->`؆`); the late .awk.cmk.unsentinel restores any leftover
# `؆`.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.call
  BEGIN { TRIG_MODE = "prefix"; TRIG_PREFIX = "؆" }
  { print lower_calls($0) }
endef
# Stage: lower the `cmk.` macro calling-convention to the sentinel, consumed
# by callform/call and restored by unsentinel. Banana-aware: a `cmk.NAME` in
# the constructor-chain of a banana head is left intact for the sugar stage
# to lower as a literal qualified callform; every other `cmk.` anchors. Runs
# right after dialect, before dedent/sugar, so downstream stages keep the
# sentinel invariant.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.cmkanchor
  function anchor(s) { gsub(/cmk\./, "؆", s); return s }
  {
    if ($0 ~ /@@BANANA_OPEN_NAMED@@/ && match($0, /[([{]\|/)) {
      # protect the ctor-chain prefix up to+including the opener; anchor only the remainder
      print substr($0, 1, RSTART + 1) anchor(substr($0, RSTART + 2)); next }
    print anchor($0)
  }
endef
# Stage: restore the macro-anchor sentinel -- map any `؆` that survived
# call-lowering back to `cmk.` (it was `cmk.` content, not a call).  Blanket
# gsub; runs last. Also drop any smart anchor `؇` that callform did not
# consume (defensive -- receivers only inject `؇` with a trailer, so a
# leftover is a bare receiver name).
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.unsentinel
  # COOK banana (deferred-wrap): sugar emitted `⟅NAME`/`⟆` sentinels instead of
  # define/endef so the interior cooked through every lowering stage (callform,
  # receivers, cmk., capture) as ordinary source; wrap it into a real define now.
  /^⟅/ { sub(/^⟅/, "define "); print; next }
  /^⟆[ \t]*$/ { print "endef"; next }
  { gsub(/؆/, "cmk."); gsub(/؇/, ""); print }
endef
# Stage: NS-LINT -- `open`/`import` INTENT vs actual use, standalone +
# decoupled.  Records directives (verb per name), col-0 defines, and
# `ns.method(..)` uses ENTIRELY on its own (its own `nl_use` scan, not the
# receivers stage's routing); warns at END on mismatch. Identity transform.
# Runs BEFORE `acquire` (so it sees the original `open X` directives) and
# `receivers` (so it sees uses before `؇` anchoring).  Disable with
# CMK_NS_LINT=0.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.nslint
  function rc_name(c) { return (c ~ /@@SYM_NAME@@/) }
  # forward method-name class adds the predicate and bang suffix, so a predicate use is not read as a dead namespace.
  function rc_name_call(c) { return (c ~ /@@SYM_NAME_CALL@@/) }
  # an in-core module (e.g. the `cmk` prelude) is neither defined-into nor called as `ns.*`, so
  # skip it: `open cmk` binds keywords bare, it does not contribute or use a `cmk.` namespace.
  function rc_core(n) { return (CORE_MODULES != "" && index(" " CORE_MODULES " ", " " n " ")) }
  function rc_nsdir(kw, ns,   n, a, k) { n = split(ns, a, " ")
    for (k = 1; k <= n; k++) if (a[k] != "" && a[k] !~ /\// && !rc_core(a[k])) {   # `/`-paths aren't namespaces
      if (!(a[k] in NSVERB)) NSORDER[++NSN] = a[k]
      if (kw == "open") NSVERB[a[k]] = (NSVERB[a[k]] == "import" ? "both" : "open")
      else NSVERB[a[k]] = (NSVERB[a[k]] == "open" ? "both" : "import") } }
  # nl_dir -- pull (verb, ns-names) from an open/import directive, feed rc_nsdir.  `import .. as`
  # records the NSLIST (rhs); `open|import <ns..> [kw=v]` records the leading names before `=`.
  function nl_dir(line,   kw, rest, names, i, a, n) {
    if (line ~ /^[ \t]*import[ \t]+.*[ \t]+as[ \t]+@@SYM_NAME@@/) {
      rest = line; sub(/^[ \t]*import[ \t]+/, "", rest); match(rest, /[ \t]+as[ \t]+/); rest = substr(rest, RSTART+RLENGTH) }
    else if (line ~ /^[ \t]*(open|import)[ \t]/) { kw = line; sub(/^[ \t]+/, "", kw); sub(/[ \t].*$/, "", kw); rest = line; sub(/^[ \t]*(open|import)[ \t]+/, "", rest) }
    else return
    if (kw == "") kw = "import"
    n = split(rest, a, /[ \t]+/); names = ""
    for (i = 1; i <= n; i++) { if (a[i] ~ /=/) break; names = (names == "" ? a[i] : names " " a[i]) }
    gsub(/[ \t]*,[ \t]*/, " ", names); rc_nsdir(kw, names) }
  function rc_markdef(nm,   r) { for (r in NSVERB) if (index(nm, r ".") == 1) defined[r] = 1 }
  function rc_defcheck(line,   h, ci, names, na, arr, k) {
    if (NSN == 0) return
    h = line; ci = index(h, ";"); if (ci > 0) h = substr(h, 1, ci - 1)
    if (h ~ /^[A-Za-z0-9._\/%+ \t-]+:([^=]|$)/) {
      ci = index(h, ":"); names = substr(h, 1, ci - 1)
      na = split(names, arr, /[ \t]+/); for (k = 1; k <= na; k++) rc_markdef(arr[k]); return }
    if (match(h, /^[A-Za-z0-9._\/-]+[ \t]*[:+?!]?=/)) {
      names = substr(h, 1, RLENGTH); sub(/[ \t]*[:+?!]?=$/, "", names); rc_markdef(names) } }
  # nl_use -- mark used[ns] when the line references `ns.method` + a call suffix, for an opened ns.
  function nl_use(line,   i, L, prev, r, rl, nx, m, suf, s, pfx) {
    if (NSN == 0) return
    L = length(line)
    for (i = 1; i <= L; i++) {
      prev = (i == 1) ? "" : substr(line, i-1, 1)
      # ؆/؇ are macro/smart-send anchors (cmk.->؆ pre-nslint); see through them, and through a literal this. prefix, so cmk.code.rust.lambda( registers code.rust as used
      if (rc_name(prev)) {
        s = i - 1; while (s >= 1 && rc_name(substr(line, s, 1))) s--
        pfx = substr(line, s + 1, i - s - 1)
        if (pfx !~ /^this\.$/) continue }
      for (r in NSVERB) {
        rl = length(r); nx = substr(line, i+rl, 1)
        if (substr(line, i, rl) != r) continue
        if (nx == ".") {
          m = i + rl + 1; while (m <= L && rc_name_call(substr(line, m, 1))) m++
          suf = substr(line, m, 1)
          if (suf == "(" || suf == "[" || suf == "{" || suf == "/") used[r] = 1 }
        # bare callform: an imported macro used unqualified still counts as a use
        else if (nx == "(" || nx == "[" || nx == "{") used[r] = 1 } } }
  function rc_nswarn(   k, ns, v, u, d) {
    for (k = 1; k <= NSN; k++) { ns = NSORDER[k]; v = NSVERB[ns]; u = (ns in used); d = (ns in defined)
      if (!u && !d) cmk_warn("ns-lint", sprintf("`%s %s` but `%s.*` is never used or defined (dead)", (v == "import" ? "import" : "open"), ns, ns))
      else if (v == "import" && d) cmk_warn("ns-lint", sprintf("`import %s` but you DEFINE `%s.*` (namespace pollution) -- use `open %s` to contribute", ns, ns, ns))
      else if (v == "open" && !d) cmk_warn("ns-lint", sprintf("`open %s` but define no `%s.*` (nothing contributed) -- use `import %s` to just call it", ns, ns, ns)) } }
  END { if (NS_LINT+0) rc_nswarn() }
  { if (NS_LINT+0) { nl_dir($0); nl_use($0); rc_defcheck($0) } print }
endef
# Stage: lower the module-acquisition directives to their loads --
# `include`/`import`/`open` become a module import or an ambient dissolve.
# Loads only: no smart-routing (that is the receivers stage) and no ns-lint
# (that is nslint). Runs after nslint, before receivers.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.acquire
  # emit_pathdis(src, kwargs) -- lift an import source into a def and dissolve it through the `path`
  # ambient subkind, so every open/import form funnels through the one `ambient.dissolve` seam
  # (path.dissolve resolves the name against CMK_PLUGINS_DIR + forwards the kwargs to import.module).
  # A per-file sequence keeps interleaved emits from colliding on the def name.
  function emit_pathdis(src, kwargs,   d) { d = "__opena_" NR "_" (++_pdseq)
    print "define " d; print src; print "endef"
    print "$(call ambient.dissolve, def=" d " kind=path " kwargs ")" }
  {
    line = $0
    # import/open wrap: a trailing `,` continues to the next line.
    if (line ~ /^[ \t]*(open|import)[ \t]/ && line ~ /,[ \t]*$/) {
      while (line ~ /,[ \t]*$/) { if ((getline _cont) <= 0) break
        sub(/^[ \t]+/, "", _cont); if (_cont == "") break
        sub(/[ \t]+$/, "", line); line = line " " _cont } }
    # a kw=v trailer must follow a comma (else it reads like a typo).  Disambiguate from a bare
    # `import a, b` source list by the first `=`: require a comma right before the first kwarg key
    # (later space-separated kw=v pairs are fine once the comma has introduced the trailer).
    if (line ~ /^[ \t]*(open|import)[ \t]/ && line ~ /[A-Za-z_][A-Za-z0-9_]*=/) {
      _ikhd = line; sub(/=.*$/, "", _ikhd); sub(/[A-Za-z_][A-Za-z0-9_]*$/, "", _ikhd)
      if (_ikhd !~ /,[ \t]*$/) {
        print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: import trailer needs a comma -- write `import <src> as <ns>, <kw=v..>` (got `" line "`))"; next } }
    # `goal NAME = <expr>` -- named lift: bind a target-expr as a first-class goal value (reify +
    # run + register, via goal.bind).  Module scope only, like the directives below.
    if (line ~ /^goal[ \t]+@@SYM_NAME@@+[ \t]*=/) {
      gname = line; sub(/^goal[ \t]+/, "", gname); sub(/[ \t]*=.*$/, "", gname)
      gexpr = line; sub(/^goal[ \t]+@@SYM_NAME@@+[ \t]*=[ \t]*/, "", gexpr)
      gsub(/,/, "$(comma)", gexpr)   # protect the expr's commas from the $(call) arg-split
      print "$(call goal.bind, " gname ", " gexpr ")"; next }
    # both open-forms lower to the one lang.module.from dispatcher; core-vs-disk resolves at import time.
    if (line ~ /^[ \t]*open[ \t]+@@SYM_NAME@@+([ \t]+except[ \t]+.+)?[ \t]*$/) {
      mod = line; sub(/^[ \t]*open[ \t]+/, "", mod); sub(/[ \t].*$/, "", mod)
      xc = ""; if (line ~ /[ \t]except[ \t]/) { xc = line; sub(/^.*except[ \t]+/, "", xc); gsub(/[ \t]*,[ \t]*/, " ", xc); gsub(/[ \t]+/, " ", xc); sub(/^ +/, "", xc); sub(/ +$/, "", xc) }
      print "$(call lang.module.from," mod ", *" (xc == "" ? "" : " except " xc) ")"; next }
    if (line ~ /^[ \t]*from[ \t]+@@SYM_NAME@@+[ \t]+import[ \t]+.+/) {
      mod = line; sub(/^[ \t]*from[ \t]+/, "", mod); sub(/[ \t].*$/, "", mod)
      fi = line; sub(/^[ \t]*from[ \t]+@@SYM_NAME@@+[ \t]+import[ \t]+/, "", fi)
      gsub(/[ \t]*,[ \t]*/, " ", fi); gsub(/[ \t]+/, " ", fi); sub(/^ +/, "", fi); sub(/ +$/, "", fi)
      print "$(call lang.module.from," mod "," fi ")"; next }
    # `include <file> <kw=v>..` -- lower to import.module (default raw+flat; kwargs override).
    if (line ~ /^-?s?include[ \t]+[^ \t]+[ \t]+[A-Za-z_][A-Za-z0-9_]*=/) {
      inc = line; sub(/^-?s?include[ \t]+/, "", inc); incf = inc; sub(/[ \t].*$/, "", incf)
      inckw = inc; sub(/^[^ \t]+[ \t]+/, "", inckw)
      if (inckw !~ /(^| )preprocs=/) inckw = inckw " preprocs=stream.echo"
      if (inckw !~ /(^| )(flat|prefix|namespace)=/) inckw = inckw " flat=1"
      print "$(call import.module, file=" incf " " inckw ")"; next }
    # `import <srclist> as <nslist> [kw=v]` -- load + namespace/flat-route the module(s).
    if (line ~ /^[ \t]*import[ \t]+.*[ \t]+as[ \t]+@@SYM_NAME@@/) {
      asr = line; sub(/^[ \t]*import[ \t]+/, "", asr); match(asr, /[ \t]+as[ \t]+/)
      asrc = substr(asr, 1, RSTART-1); asrhs = substr(asr, RSTART+RLENGTH)
      asnl = ""; askw = ""; askwon = 0; asm = split(asrhs, astk, /[ \t]+/)
      for (asj = 1; asj <= asm; asj++) { if (!askwon && astk[asj] ~ /=/) askwon = 1
        if (askwon) askw = askw " " astk[asj]; else asnl = asnl " " astk[asj] }
      # peel trailing kw=v off the left of `as` too, so `import src kw=v as ns` isn't a phantom source
      assrc = ""; askwon = 0; asm = split(asrc, astk, /[ \t]+/)
      for (asj = 1; asj <= asm; asj++) { if (!askwon && astk[asj] ~ /=/) askwon = 1
        if (askwon) askw = askw " " astk[asj]; else assrc = assrc " " astk[asj] }
      asrc = assrc
      gsub(/[ \t]*,[ \t]*/, " ", asnl); sub(/^ +/, "", asnl); sub(/ +$/, "", asnl)
      gsub(/[ \t]*,[ \t]*/, " ", asrc); sub(/^ +/, "", asrc); sub(/ +$/, "", asrc)
      asnn = split(asnl, asna, " "); assn = split(asrc, assa, " ")
      if (assn > 1 && asnn > 1) { print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: `import a,b as x,y` -- both sides listed is ambiguous; use separate `import` lines)"; next }
      if (asnn > 1) {
        askw2 = askw; if (askw2 !~ /(^| )flat=/) askw2 = askw2 " flat=1"
        if (askw2 !~ /(^| )preprocs=/ && assa[1] ~ /\.mk$/) askw2 = askw2 " preprocs=stream.echo"
        emit_pathdis(assa[1], askw2) }
      else for (ask = 1; ask <= assn; ask++) {
        askw2 = askw; asnsa = (askw2 ~ /(^| )flat=/) ? "" : ("namespace=" asnl " ")
        if (askw2 !~ /(^| )preprocs=/ && assa[ask] ~ /\.mk$/) askw2 = askw2 " preprocs=stream.echo"
        emit_pathdis(assa[ask], asnsa askw2) }
      next }
    # naked `*` is the ambient prefix -- valid only on an inline banana `*(| .. |)` (lowered in sugar).
    if (line ~ /^\*[ \t]/) { print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: bare `* <name>` removed -- `*` prefixes an inline ambient `*(| .. |)`; to dissolve a module use `open <name>` or a file with `open <path>`)"; next }
    # `open|import <ns..> <kw=v..>` -- kwargs form: route each through import.module so the kwargs apply.
    if (line ~ /^[ \t]*(open|import)[ \t]+[A-Za-z0-9._,\/ \t-]*[A-Za-z_][A-Za-z0-9_]*=/) {
      ik_kw = line; sub(/^[ \t]+/, "", ik_kw); sub(/[ \t].*$/, "", ik_kw)
      ik_rest = line; sub(/^[ \t]*(open|import)[ \t]+/, "", ik_rest)
      ik_ns = ""; ik_kwargs = ""; ik_on = 0; ik_n = split(ik_rest, ik_a, /[ \t]+/)
      for (ik_j = 1; ik_j <= ik_n; ik_j++) { if (!ik_on && ik_a[ik_j] ~ /=/) ik_on = 1; if (ik_on) ik_kwargs = ik_kwargs " " ik_a[ik_j]; else ik_ns = ik_ns " " ik_a[ik_j] }
      gsub(/[ \t]*,[ \t]*/, " ", ik_ns); sub(/^ +/, "", ik_ns); sub(/ +$/, "", ik_ns)
      ik_cnt = split(ik_ns, ik_na, " ")
      # smart-route registration is for namespace names, not file sources: a `.mk`/`.cmk` token loads
      # via its basename namespace, so skip it here (else cmk.import errors resolving a filename)
      ik_reg = ""; for (ik_i = 1; ik_i <= ik_cnt; ik_i++) if (ik_na[ik_i] !~ /\.(mk|cmk)$/) ik_reg = ik_reg " " ik_na[ik_i]
      sub(/^ +/, "", ik_reg)
      if (ik_kw == "import" && ik_reg != "") print "$(call cmk.import," ik_reg ")"
      for (ik_i = 1; ik_i <= ik_cnt; ik_i++) emit_pathdis(ik_na[ik_i], ik_kwargs)
      next }
    # bare `open|import <ns>[, <ns2>]` -- dissolve through the ambient subkinds: a bare name -> the
    # `module` subkind, a `/`-path -> the `path` subkind, via the one `ambient.dissolve` seam.
    if (line ~ /^[ \t]*(open|import)[ \t]+[A-Za-z0-9._,\t \/-]+$/) {
      imp_kw = line; sub(/^[ \t]+/, "", imp_kw); sub(/[ \t].*$/, "", imp_kw)
      imp_ns = line; sub(/^[ \t]*(open|import)[ \t]+/, "", imp_ns); gsub(/[ \t]*,[ \t]*/, " ", imp_ns)
      gsub(/[ \t]+/, " ", imp_ns); sub(/^ +/, "", imp_ns); sub(/ +$/, "", imp_ns)
      imp_names = ""; imp_n = split(imp_ns, imp_a, " ")
      for (imp_i = 1; imp_i <= imp_n; imp_i++) {
        if (imp_a[imp_i] ~ /\//) emit_pathdis(imp_a[imp_i], "flat=1")
        else imp_names = imp_names " " imp_a[imp_i] }
      sub(/^ /, "", imp_names)
      if (imp_names != "") {
        if (imp_kw == "import") print "$(call cmk.import," imp_names ")"
        print "define __open_" NR; print imp_names; print "endef"
        print "$(call ambient.dissolve, def=__open_" NR " kind=module)" }
      next }
    print
  }
endef
# Stage: multi-line chain fold (just before receivers). A leading-dot
# continuation line whose previous line ends in a call-close `)`/`]`/`}` is
# merged onto it (the close and dot made adjacent), turning a broken
# multi-line chain back into one physical line for the single-line junction
# to rewrite. Gated on the right operand being a registered receiver, so a
# plain leading-dot shell line is never merged. Recipe context only; passes
# define..endef and cooked bananas verbatim.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.fluent
  function flush() { if (hasbuf) { print buf; hasbuf = 0; buf = "" } }
  # recv_at(s) -- the longest RECEIVERS member that is a prefix of s at a name boundary
  # (next char `.`/`(`/`[`/`{`), or "" (mirrors the receivers stage's own match).
  function recv_at(s,   r, rl, nx, best) {
    best = ""
    for (r in RSET) { rl = length(r); nx = substr(s, rl + 1, 1)
      if (substr(s, 1, rl) == r && (nx == "." || nx == "(" || nx == "[" || nx == "{") && rl > length(best)) best = r }
    return best }
  BEGIN { _rn = split(RECEIVERS, _ra, " ")
    for (_ri = 1; _ri <= _rn; _ri++) if (_ra[_ri] != "") RSET[_ra[_ri]] = 1
    hasbuf = 0; buf = ""; def_depth = 0 }
  # verbatim bodies (define / cooked banana): flush, then pass through until the body closes.
  /@@SYM_DEFINE@@ / || /^⟅/ { flush(); def_depth++; print; next }
  /^endef[ \t]*$/ || /^⟆[ \t]*$/ { flush(); if (def_depth > 0) def_depth--; print; next }
  def_depth > 0 { print; next }
  {
    cont = $0; sub(/^[ \t]+/, "", cont)
    if (hasbuf && substr(cont, 1, 1) == "." && (buf ~ /^[ \t]/ || index(buf, ";"))) {
      # a continuation qualifies iff it is `.<receiver-path><call-suffix>` AND the buffered
      # previous line ends (ignoring trailing ws) in a call-close.
      tb = buf; sub(/[ \t]+$/, "", tb); last = substr(tb, length(tb), 1)
      if (cont ~ /^\.@@SYM_NAME_CALL@@+[([{]/ && recv_at(substr(cont, 2)) != "" && (last == ")" || last == "]" || last == "}")) {
        buf = tb cont; next }                        # MERGE: adjacency preserved, keep buffering
    }
    flush(); buf = $0; hasbuf = 1
  }
  END { flush() }
endef

# Stage: anchorless smart-send routing only (open/import lowering is
# acquire, ns-lint is nslint). A name declared a receiver (via -v RECEIVERS)
# needs no `this.`/`cmk.` anchor: a `R.method` send with a call suffix
# (args, a stream, `/arg`, or an adjacent literal) gets an anchor injected,
# lowered later by tagged/callform. Fires only at a word boundary with a
# call-suffix, in recipe content, never on an already-anchored token; inert
# without receivers or in define..endef. A call-close immediately followed
# by a `.<receiver>` call is a chain junction: the `.` becomes a ` | ` pipe
# and the right operand routes as a fresh send, so a fluent chain composes
# every receiver kind through one router. The default junction operator is
# the pipe; a per-name `<name>.__junction__` declaration (via -v JUNCTIONS)
# overrides it.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.receivers
  function rc_name(c) { return (c ~ /@@SYM_NAME@@/) }
  # forward method-name class adds the predicate and bang suffix, used only to consume a method name past a receiver.
  function rc_name_call(c) { return (c ~ /@@SYM_NAME_CALL@@/) }
  function rc_delim3(s) { return (s == "'''" || s == "\"\"\"" || s == "```") }
  # rc_shadow(nm) -- nm is a smart-routed send to a curated-DIVERGENT twin (its $(call) macro form
  # does not stand in for the target).  Warn to stderr, once per name; CMK_SHADOW_STRICT escalates
  # to a compile error (flagged here, enforced at END).
  function rc_shadow(nm) {
    if (nm in _shadow_seen) return
    _shadow_seen[nm] = 1
    cmk_warn("smart-send", sprintf("smart send `%s(..)` routes to a DIVERGENT macro twin (its $(call) form does not match the `%s` target) -- write `this.%s`/`cmk.%s` explicitly", nm, nm, nm, nm))
    if (SHADOW_STRICT+0) _shadow_fail = 1 }
  # rc_sep(nm) -- the chain-junction separator when the right operand is receiver `nm`: a
  # declared `nm.__junction__` operator (-v JUNCTIONS) replaces the default ` | ` pipe, so a
  # KIND can make its fluent chains compose by concatenation / sequencing instead of a pipe.
  function rc_sep(nm) { return (nm in JOP) ? " " JOP[nm] " " : " | " }
  function rc_scan(seg,   out, i, L, hit, prev, blen, r, rl, m, suf, rc_nm, bestr, isjunc, c2) {
    out = ""; i = 1; L = length(seg)
    while (i <= L) {
      hit = 0; prev = (i == 1) ? "" : substr(seg, i-1, 1); prevpfx = substr(seg, 1, i-1)
      # Fluent-style chain junction: a call-close `)`/`]`/`}` immediately followed by `.<receiver>`
      # starts a FRESH send piped from the left operand -- not a dotted path on the left.  Normally
      # a `.` prev blocks a match (it is a name char); permit it in this one case and flag it so the
      # already-emitted junction `.` is rewritten to a ` | ` pipe boundary at the emit below.
      isjunc = 0
      if (prev == "." && i >= 3) { c2 = substr(seg, i-2, 1); if (c2 == ")" || c2 == "]" || c2 == "}") isjunc = 1 }
      if ((!rc_name(prev) && prevpfx !~ /؆$/ && prevpfx !~ /؇$/) || isjunc) {
        # A receiver `R` matches when followed by `.method` (dotted send) or directly by a
        # call suffix `(`/`[`/`{` (a bare send -- `R` is itself the macro/target, so
        # `jqlang_prog(..)` needs no `cmk.` anchor, same as `jqlang_prog.locals(..)`).
        blen = 0
        for (r in RSET) { rl = length(r); rnx = substr(seg, i+rl, 1); if (substr(seg, i, rl) == r && (rnx == "." || rnx == "(" || rnx == "[" || rnx == "{") && rl > blen) { blen = rl; bestr = r; bnx = rnx } }
        if (blen > 0) {
          m = i + blen
          if (bnx == ".") while (m <= L && rc_name_call(substr(seg, m, 1))) m++
          suf = substr(seg, m, 1)
          # arg / stream / env trailers route SMART (؇ -> macro-if-defined else target);
          # `/`-stem and triple-literal stay TARGET (path stem / heredoc body shapes)
          if (suf == "(" || suf == "[" || suf == "{") {
            # skip if already smart-anchored (؇) or target-anchored (a `this.`->`${make} ` send)
            if (prevpfx !~ /؇$/ && !(i > 8 && substr(seg, i-8, 8) == "${make} ")) {
              rc_nm = substr(seg, i, m - i)
              if (rc_nm in DSET) rc_shadow(rc_nm)   # opened member is a divergent twin -> warn
              if (isjunc) out = substr(out, 1, length(out)-1) rc_sep(bestr)   # rewrite the junction `.` (pipe, or a declared override)
              out = out "؇" rc_nm; i = m; hit = 1 } }
          else if (suf == "/" || rc_delim3(substr(seg, m, 3))) {
            if (!(i > 8 && substr(seg, i-8, 8) == "${make} ")) {
              if (isjunc) out = substr(out, 1, length(out)-1) rc_sep(bestr)   # rewrite the junction `.` (pipe, or a declared override)
              out = out "${make} " substr(seg, i, m - i); i = m; hit = 1 } } } }
      if (!hit) { out = out substr(seg, i, 1); i++ }
    }
    return out }
  BEGIN { _rn = split(RECEIVERS, _ra, " "); RCOUNT = 0
    for (_ri = 1; _ri <= _rn; _ri++) if (_ra[_ri] != "") { RSET[_ra[_ri]] = 1; RCOUNT++ }
    RSET["@@TOKEN_SELF@@"] = 1; RCOUNT++   # the self-ref is always a self-send receiver inside a class body
    _dn = split(DIVERGENT, _da, " ")   # curated-divergent twin names
    for (_di = 1; _di <= _dn; _di++) if (_da[_di] != "") DSET[_da[_di]] = 1
    _jn = split(JUNCTIONS, _ja, " ")   # per-receiver junction-operator overrides (name=op, -v JUNCTIONS)
    for (_ji = 1; _ji <= _jn; _ji++) if (_ja[_ji] != "") { _je = index(_ja[_ji], "="); if (_je > 1) JOP[substr(_ja[_ji], 1, _je-1)] = substr(_ja[_ji], _je+1) } }
  # strict (CMK_SHADOW_STRICT): the fused compile is lenient (defers hard failures to mk.validate),
  # so escalation POISONS the output with a module-level $(error) that fails validation/run.
  END { if (_shadow_fail) print "$(error cmk-fault errno=GRAMMAR code=65 :: cmk: CMK_SHADOW_STRICT -- a smart send routes to a divergent macro twin; see the warnings above and use an explicit this./cmk. anchor)" }
  # Routing only: anchorless smart sends `ns.method(..)` -> `؇` (acquisition + ns-lint are the
  # `acquire`/`nslint` stages).  A recipe line routes wholesale; a col-0 `target:; recipe` routes
  # only its recipe part.  Inert without receivers.
  {
    line = $0
    if (RCOUNT == 0) { print; next }
    if (line ~ /^define[ \t]/) { _indef++; print; next }
    if (line ~ /^endef[ \t]*$/) { if (_indef > 0) _indef--; print; next }
    if (line ~ /^[ \t]/) { print rc_scan(line); next }
    # a col-0 self-assignment: route its whole right-hand side (even when the value carries a `;`),
    # so a self-member's macro body gets the same callform anchoring a recipe line would.  Gated on
    # a self-token left-hand side with an assignment operator -- an unambiguous in-class target that
    # can never be a module-level construction, a recipe definition, or an unrelated macro.
    ts = "@@TOKEN_SELF@@"; tl = length(ts)
    if (substr(line, 1, tl) == ts && match(substr(line, tl+1), /^(\.@@SYM_NAME@@+)?[ \t]*:?=/)) {
      eq = tl + RLENGTH; print substr(line, 1, eq) rc_scan(substr(line, eq+1)); next }
    # a col-0 macro assignment routes its value too, so a member send there anchors like one on a recipe line
    if (_indef == 0 && match(line, /^@@SYM_NAME@@+[?!]?[ \t]*[:?+]?=/)) {
      eq = RLENGTH; print substr(line, 1, eq) rc_scan(substr(line, eq+1)); next }
    sc = index(line, ";")
    if (sc == 0) {
      # a bare module-scope callform statement `ns.method(args)`: the head (before the first `(`)
      # must carry no rule-colon or assignment-`=` -- kwargs like `machine=x` live INSIDE the parens,
      # so guard on the head only, not the whole line, then confirm rc_scan anchored a callform.
      _p = index(line, "("); _head = (_p > 0) ? substr(line, 1, _p - 1) : line
      if (_indef == 0 && _head !~ /[:=]/) { _s = rc_scan(line); if (_s ~ /^؇/) { print _s; next } }
      print line; next }
    print substr(line, 1, sc) rc_scan(substr(line, sc+1))
  }
endef
# Stage: the `<-` capture operator binds the RHS output to the LHS. The LHS
# is a bare identifier at a statement boundary (recipe-line start after the
# tab, or after a `;`/`&&`/`||`); the `<-` arrow must be adjacent (a space
# inside it, `< -`, stays a shell redirect); spacing around the arrow is
# free. The RHS runs to the next shell separator or trailing `\`. A recipe
# (tab-indented) LHS becomes a shell capture, a module (column-0) LHS a make
# parse-time capture. Runs after the call stage; inert in define..endef.
# Heredocs, arithmetic, and `$<` are excluded by the boundary and adjacency
# rules.
#:phase COMPILE seed=1 awklang=no
define .awk.cmk.capture
  # `LHS <- RHS` binds the RHS's STDOUT (a one-shot value): run it and capture (backticks at
  # recipe-level, `$(shell ..)` at module-level).  `&LHS <- RHS` is a HANDLE bind (the `&` reads
  # as a reference declaration, C++-style): store the already-lowered RHS as a callable macro
  # WITHOUT running it, so `LHS` is a deferred handle -- `LHS()` runs it later.  The LHS is
  # registered as a receiver either way (`lang.rex.recv.capture`), so the handle is callable.
  BEGIN {   # parse TABLE A (-v FRAGOPS="char=dunder ..") -> FOP[char]=dunder + a bracket class of the
    # operator chars, so the fragment fold below is table-driven, not hardcoded.  `.` is never a member
    # (it collides with `.` inside fragment names), so a raw bracket class is safe for the ops (+, /, |).
    _fon = split(FRAGOPS, _foa, " ")
    for (_foi = 1; _foi <= _fon; _foi++) { _fop = index(_foa[_foi], "="); if (_fop) { _foc = substr(_foa[_foi], 1, _fop - 1); FOP[_foc] = substr(_foa[_foi], _fop + 1); FRAG_OPCLASS = FRAG_OPCLASS _foc } }
    if (FRAG_OPCLASS != "") FRAG_RE = "^[A-Za-z_][A-Za-z0-9_.]*([" FRAG_OPCLASS "][A-Za-z_][A-Za-z0-9_.]*)+$"
  }
  function lower(lead, id, rhs, isrec, ishandle,   srcobj, fn, fops, fsep, fi, ffold, fch, ffcur) {
    # `&LHS <- a+b/c` -- FRAGMENT FOLD, gated on the `&` HANDLE marker: bare `<-` is EAGER (run RHS now,
    # capture stdout -- shell land, where `/`|`|` are path/pipe chars), so the fold lives only in the
    # LAZY `&` form (bind a callable, run later -- fragment land).  That split makes bare `<- dir/file`
    # unambiguously a shell capture and frees ALL table operators inside `&`.  Compose the operands
    # left-assoc via the dunder TABLE A picks for each infix op (FOP/FRAG_RE, built in BEGIN from
    # -v FRAGOPS), then bind the composite under LHS as a NAMED, callable fragment (`lang.banana.as`;
    # receiver-registered by `lang.rex.recv.capture`, so `LHS(..)` works).  No spaces; left-assoc, no precedence.
    # A new operator is one row in the operator table + the dunder on the kind -- no change here.  At MODULE
    # scope (`!isrec`), also mint a `LHS:` TARGET twinning the callable, so `${make} LHS` / `this.LHS`
    # dispatch the handle like `LHS()` does (`lang.grammar.handle.target`).
    if (ishandle && FRAG_OPCLASS != "" && rhs ~ FRAG_RE) {
      fn = 0; ffcur = ""                                  # tokenize into operands + the per-pair dunder
      for (fi = 1; fi <= length(rhs); fi++) { fch = substr(rhs, fi, 1); if (fch in FOP) { fops[++fn] = ffcur; fsep[fn] = FOP[fch]; ffcur = "" } else ffcur = ffcur fch }
      fops[++fn] = ffcur; ffold = fops[1]
      for (fi = 2; fi <= fn; fi++) ffold = "$(call " ffold "." fsep[fi-1] "," fops[fi] ")"
      return lead "$(call lang.banana.as," id "," ffold ")" (isrec ? "" : "$(call lang.grammar.handle.target," id ")") }
    # `LHS <- <obj>.copy()` -- re-mint <obj> under the new name LHS (the assignment supplies the
    # name a blind RHS callform cannot).  `<obj>.copy` re-inits from <obj>'s stashed ctor source.
    if (rhs ~ /\.copy\(\)[ \t]*$/) {
      srcobj = rhs; sub(/[ \t]*\.copy\(\)[ \t]*$/, "", srcobj)
      return lead "$(call " srcobj ".copy," id ")" }
    # `LHS <- Class.new()` -- mint a FRESH Class instance under name LHS (sibling of the
    # `.copy()` re-mint above).  A class is its own positional ctor, so LHS becomes `self`.
    # A trailing `# comment` is tolerated (and dropped): unlike the shell-capture branches, this
    # does not route through `$(shell ..)`, so a comment would otherwise reach the regex tail.
    if (rhs ~ /\.new\(\)[ \t]*(#.*)?$/) {
      srcobj = rhs; sub(/[ \t]*\.new\(\).*$/, "", srcobj)
      return lead "$(call " srcobj "," id ")" }
    if (ishandle) return lead id " = " rhs
    if (isrec) return lead id "=`" rhs "`"
    return lead id " := $(shell " rhs ")" }
  # capture ends a right-hand side at the first top-level separator, so a grouped or
  # quoted command is captured whole.
  function capture(line,   cont, isrec, out, s, ce, sep, seg, rhs, lead, id, rest, ishandle, _sp) {
    cont = ""
    if (line ~ /[ \t]*\\$/) { sub(/[ \t]*\\$/, "", line); cont = " \\" }
    # A capture is module-level (a parse-time shell-out) only as the leading statement of a
    # column-0 line; a tab recipe line, an inline recipe after a target colon, or a
    # make-variable value all run in a shell, so those capture with backticks.
    isrec = (line ~ /^\t/) || !(line ~ /^ *&?[A-Za-z_][A-Za-z0-9_]*[ \t]*<-/)
    out = ""; s = line
    while (length(s) > 0) {
      next_sep(s, _sp)
      if (_sp[1] > 0) { ce = _sp[1]; sep = _sp[2] } else { ce = length(s) + 1; sep = "" }
      seg = substr(s, 1, ce - 1)
      if (match(seg, /^[ \t]*&?[A-Za-z_][A-Za-z0-9_]*[ \t]*<-[ \t]*/)) {
        rhs = substr(seg, RLENGTH + 1); sub(/[ \t]+$/, "", rhs)
        lead = seg; sub(/[^ \t].*/, "", lead)
        rest = substr(seg, length(lead) + 1)
        ishandle = (substr(rest, 1, 1) == "&")
        if (ishandle) rest = substr(rest, 2)
        id = rest; sub(/[ \t]*<-.*/, "", id)
        out = out lower(lead, id, rhs, isrec, ishandle)
      } else { out = out seg }
      if (sep != "") { out = out sep; s = substr(s, ce + length(sep)) } else { s = "" }
    }
    return out cont }
  { if (index($0, "<-")) $0 = capture($0); print }
endef

# CMK tagged callable-target sugar: a target invocation with a
# triple-delimiter literal adjacent to the name (no parens/brackets) is
# rewritten so the literal pipes into the target. Target-only (macros use
# `[stream]`). Runs before callform (which then sees a bare target call).
# Reuses the shared literal parser. Skips `.dispatch`; inert in
# define..endef.
#:phase COMPILE seed=1 awklang=no
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

# CMK unified call-form sugar -- one stage for both call anchors, the macro
# anchor and the target anchor. `NAME(args)` supplies args, `NAME[stream]`
# supplies stdin (combinable in either order); a stream may be a
# triple-quote literal, a balanced `[...]` command (which may nest
# call-forms), or a block-ref glyph. Bare `NAME` is left verbatim. Errors
# (cmk_die_at) on an unterminated literal/bracket/paren or mixed content
# after a literal. Runs after dialect+tagged, before blockref+triplequote;
# inert in define..endef.
#:phase COMPILE seed=1 awklang=no
define .awk.callform
  function extract_balanced(bp, oc, cc, what,   depth, k, c) {
    depth = 1; k = bp
    while (k <= L && depth > 0) { c = substr(line, k, 1); if (c == oc) depth++; else if (c == cc) depth--; if (depth == 0) break; k++ }
    if (depth != 0) cmk_die_at("callform", "unterminated " what "; unquoted is single-line, use triple-quotes for multi-line", START_NR, START_SRC)
    EB_ = substr(line, bp, k - bp); EB_REM = k + 1 }
  # eat_group -- consume a balanced `oc..cc` group at the START of s (an `(args)` or `{env}`
  # callform-channel, dual of `[stream]`'s pipe-prefix): sets GRP_ = the inner text, GREM_ = the rest.
  function eat_group(s, oc, cc, what,   depth, q, ch) {
    GRP_ = ""; GREM_ = s
    if (substr(s, 1, 1) != oc) return
    depth = 1; q = 2
    while (q <= length(s) && depth > 0) { ch = substr(s, q, 1); if (ch == oc) depth++; else if (ch == cc) depth--; if (depth == 0) break; q++ }
    if (depth != 0) cmk_die_at("callform", "unterminated " what, START_NR, START_SRC)
    GRP_ = substr(s, 2, q - 2); GREM_ = substr(s, q + 1) }
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
  function build_call(type, name, args, hadp,   a, ot, mb, tb, oc, cb) {
    if (type == "smart") {
      # SMART receiver: prefer the instance's `.__call__` dunder (the canonical invoke) when
      # one is defined -- so `NAME()` on a dsl/constructor instance dispatches through it.
      # Else route at RUNTIME -- a defined MACRO (fast, no reparse) if one exists, else the
      # published TARGET.  `filter file override` (positive) so an env/command-line name
      # collision does not mis-route to `$(call)`.
      oc = "$(filter file override,$(origin " name ".__call__))"
      ot = "$(filter file override,$(origin " name "))"
      if (!hadp || args == "") { cb = "$(call " name ".__call__)"; mb = (hadp ? "$(if $(filter-out undefined,$(origin " name ".__name__)),$(error cmk-fault errno=GRAMMAR code=65 :: cmk: " name "() is not callable: " name " is a namespace with no .__call__ -- call a member like " name ".x or define .__call__),$(call " name "))" : "$(call " name ")"); tb = MK name }
      else { a = args; gsub(/[ \t]+/, "", a); cb = "$(call " name ".__call__," args ")"; mb = MAC name "(" args ")"; tb = MK name "/" a }
      return "$(if " oc "," cb ",$(if " ot "," mb "," tb "))" }
    if (type == "macro") { if (!hadp) return "$(call " name ")"; return MAC name "(" args ")" }
    if (!hadp) return MK name
    a = args; gsub(/[ \t]+/, "", a); return MK name "/" a }
  function lower(rec,   out, i, pm, pt, ps, type, alen, p, abs, npos, name, cc, ch, nxt, hadp, args, env, stream, hasS, t0, callstr, sline, sL, srec) {
    line = rec; out = ""; i = 1; L = length(line); MK = "${make} "; MAC = "؆"; SMART = "؇"; FD = "⬦"; FILE = "⬥"
    while (i <= L) {
      pm = index(substr(line, i), MAC); pt = index(substr(line, i), MK); ps = index(substr(line, i), SMART)
      if (pm == 0 && pt == 0 && ps == 0) { out = out substr(line, i); break }
      # pick the EARLIEST of macro (؆) / target (${make} ) / smart (؇) anchors
      p = L + 2; type = ""
      if (pm != 0 && pm < p) { p = pm; type = "macro"; alen = length(MAC) }
      if (pt != 0 && pt < p) { p = pt; type = "target"; alen = length(MK) }
      if (ps != 0 && ps < p) { p = ps; type = "smart"; alen = length(SMART) }
      abs = i + p - 1
      out = out substr(line, i, p - 1)
      npos = abs + alen; name = ""
      if (type == "target") cc = "[A-Za-z0-9._/-]"; else cc = "@@SYM_NAME_CALL@@"
      if (substr(line, npos, length("@@TOKEN_SELF@@")) == "@@TOKEN_SELF@@") { name = "@@TOKEN_SELF@@"; npos += length("@@TOKEN_SELF@@") }   # cross the self-ref name prefix
      while (npos <= L) { ch = substr(line, npos, 1); if (ch ~ cc) { name = name ch; npos++ } else break }
      if (name == "") { out = out substr(line, abs, alen); i = npos; continue }
      if (type == "target" && name ~ /\.dispatch$/) { out = out MK name; i = npos; continue }
      hadp = 0; args = ""; env = ""; stream = ""; hasS = 0; nxt = substr(line, npos, 1)
      # no trailer: emit the anchor+name verbatim (bare `؆f` is finished by the late `call` stage);
      # a bare smart anchor still routes (defensive -- receivers only inject `؇` with a trailer)
      if (nxt != "(" && nxt != "[" && nxt != "{") {
        if (type == "smart") { out = out build_call("smart", name, "", 0); i = npos; continue }
        out = out substr(line, abs, npos - abs); i = npos; continue }
      # consume `(args)` / `[stream]` / `{env}` trailers ORDER-FREE off the remainder
      line = substr(line, npos); L = length(line)
      while (1) {
        t0 = substr(line, 1, 1)
        if (t0 == "(") { eat_group(line, "(", ")", "(args)"); args = GRP_; hadp = 1; line = GREM_
          # recursively lower a nested send inside the args, mirroring the stream path below
          srec = RECURSING; RECURSING = 1; sline = line; sL = L; args = lower(args); RECURSING = srec; line = sline; L = sL }
        else if (t0 == "[") { parse_body(2); stream = BODY_; hasS = 1; line = BREM_ }
        else if (t0 == "{") { eat_group(line, "{", "}", "{env}"); env = (env == "" ? env_prefix(GRP_) : env " " env_prefix(GRP_)); line = GREM_ }
        else break
        L = length(line) }
      # `{env}` is a runtime (recipe) prefix; at module scope it is meaningless -- warn
      # (reserved for later), don't error, and drop it.  Recipe = indented (tab or space,
      # before the `indent` stage normalizes), a `:;` one-liner, or a make-variable value
      # (`NAME = ..`, whose body runs in a recipe when expanded); a bare column-0 statement
      # is module.
      if (env != "" && $0 !~ /^[ \t]/ && $0 !~ /:;/ && $0 !~ /^[^\t=]*=[ \t]/) { print "cmk: warning: {env} at module scope is not yet meaningful (reserved) -- " START_SRC > "/dev/stderr"; env = "" }
      # assemble as  STREAM | ENV command  (env-prefix dual to stream's pipe-prefix)
      callstr = build_call(type, name, args, hadp)
      if (env != "") callstr = env " " callstr
      if (hasS) callstr = stream " | " callstr
      out = out callstr
      L = length(line); i = 1 }
    return out
  }
  # The `__target__` recipe-reflection family: the current-target name (`__target__`), its params
  # (`.args`) and its docstring (`.docs`/`.__doc__`).  Each reads either bare (ergonomic) or `${..}`-
  # wrapped (like the make-var dunders `${__doc__}`/`${<kls>.__bases__}`).  Both spellings are
  # callform-safe IDENTIFIERS that the dialect leaves alone, so they ride this stage's name-matcher as
  # plain arguments; here, after lowering, every form is UNWRAPPED to bare then MAPPED to its target:
  # the name lands on the `__target__=$@` make var, `.args` on the stem `${*}`, and the docstrings on
  # the recipe-shell doc reader.  The compound replacements carry no `__target__`, so the final bare-
  # name pass cannot re-touch them, and unwrap-then-map keeps a user's explicit `${..}` from doubling.
  { START_NR = NR; START_SRC = $0; _r = lower($0)
    gsub(/\$[({]__target__\.__doc__[)}]/, "__target__.__doc__", _r); gsub(/\$[({]__target__\.docs[)}]/, "__target__.docs", _r); gsub(/\$[({]__target__\.args[)}]/, "__target__.args", _r); gsub(/\$[({]__target__[)}]/, "__target__", _r)
    gsub(/__target__\.__doc__/, "${_cmk.target.doc}", _r); gsub(/__target__\.docs/, "${_cmk.target.doc}", _r); gsub(/__target__\.args/, "${*}", _r); gsub(/__target__/, "${__target__}", _r)
    print _r }
endef


# Compile-stage def-blocks captured literally (via `$(value)`, like
# mk.def.read) and exported so the `.cmk.*` stage macros can read them
# straight from the environment, with no per-block sub-make and no temp
# files. `:=` (after all the define blocks above) freezes the unexpanded
# body; export ships it verbatim; awk consumes it in-shell. Each stage call
# mints the paired `.cmk.<stage>` pipe-fragment too.

$(call lang.awk.stage.frag, main=.awk.zip stage_name=minify)

# Stages that can raise parser errors prepend the shared `.awk.cmk.errors`
# prelude (cmk_die/cmk_die_at), separated by a literal newline. The shared
# banana-opener regexes (defined once near `lang.rex.recv.*`) are injected
# into the two awk stages that gate on them, so the opener grammar lives in
# one place. Reflective tower: cmkanchor's export is sourced from a
# stage-fragment (main-only), replacing lang.awk.stage.
$(call lang.awk.stage.frag, main=.awk.cmk.cmkanchor)
$(call lang.awk.stage.frag, main=.awk.cmk.m5wrap pipeline=.awk.cmk.litparse:.awk.cmk.banana:.awk.cmk.defskip:.awk.cmk.errors, -v M5ACC="$(m5.__acc__)")
# Reflective tower: multi-source stage sourced from a stage-fragment (splice
# of the source list).
$(call lang.awk.stage.frag, main=.awk.cmk.dedent pipeline=.awk.cmk.errors:.awk.cmk.banana)

$(call lang.awk.stage.frag, main=.awk.cmk.moduledoc pipeline=.awk.cmk.litparse:.awk.cmk.defskip:.awk.cmk.errors, -v MODULEDOC_LINT="$$$${CMK_MODULEDOC_LINT:-1}")

$(call lang.awk.stage.frag, main=.awk.cmk.indent pipeline=.awk.cmk.errors)

$(call lang.awk.stage.frag, main=.awk.decorators pipeline=.awk.cmk.errors)

$(call lang.awk.stage.frag, main=.awk.tagged pipeline=.awk.cmk.litparse:.awk.cmk.defskip:.awk.cmk.errors)

$(call lang.awk.stage.frag, main=.awk.callform pipeline=.awk.cmk.litparse:.awk.cmk.defskip:.awk.cmk.errors:.awk.cmk.callform.channels)
export _cmk_blk_dialect := $(call lang.grammar.ctx.fill,$(value lang.comp.dialect))
export _cmk_blk_sugar := $(call lang.grammar.ctx.fill,$(value lang.comp.sugar))
$(call lang.awk.export.frag, main=.awk.sugarawk pipeline=.awk.cmk.banana)

$(call lang.awk.stage.frag, main=.awk.cmk.imports pipeline=.awk.cmk.lower:.awk.cmk.defskip)

$(call lang.awk.stage.frag, main=.awk.cmk.call pipeline=.awk.cmk.lower:.awk.cmk.defskip)

# Reflective tower: unsentinel's export is sourced from a stage-fragment
# (main-only), replacing lang.awk.stage.
$(call lang.awk.stage.frag, main=.awk.cmk.unsentinel)

# preflight lint tier (see `lang.lint.*`): the namespace (`nslint`) + shadow
# (`receivers`) checks ride the compile pipeline, so they run on every `cmk
# run` / eval / banana-cook.  Keep them as stages -- a separate cheap-lint
# pass would re-scan per cook.
$(call lang.awk.stage.frag, main=.awk.cmk.nslint pipeline=.awk.cmk.defskip:.awk.cmk.errors, -v NS_LINT="$$$${CMK_NS_LINT:-1}" -v CORE_MODULES="$$(lang.module.core)")
$(call lang.awk.stage.frag, main=.awk.cmk.acquire pipeline=.awk.cmk.defskip)

$(call lang.awk.stage.frag, main=.awk.cmk.fluent, -v RECEIVERS="$$$${RECEIVERS}")
$(call lang.awk.stage.frag, main=.awk.cmk.receivers pipeline=.awk.cmk.defskip:.awk.cmk.errors, -v RECEIVERS="$$$${RECEIVERS}" -v DIVERGENT="$${lang.lint.divergent}" -v JUNCTIONS="$$$${JUNCTIONS}" -v SHADOW_STRICT="$$$${CMK_SHADOW_STRICT:-0}")

$(call lang.awk.stage.frag, main=.awk.cmk.capture pipeline=.awk.cmk.sepscan:.awk.cmk.defskip, -v FRAGOPS="$(lang.grammar.ops)")
$(call lang.awk.export.frag, main=.awk.dispatch)

$(call lang.awk.stage.frag, main=.awk.triplequote pipeline=.awk.cmk.defskip)

$(call lang.awk.stage.frag, main=.awk.blockref pipeline=.awk.cmk.defskip)

$(call lang.awk.stage.frag, main=.awk.lambdalift pipeline=.awk.cmk.defskip:.awk.cmk.banana:.awk.cmk.callform.channels)
$(call lang.awk.export.frag, main=.awk.joinbody)
$(call lang.awk.comp, main=.awk.json5)
# as=module_ns keeps the short exported-var name for the awk stage, plus a
# `-v ns` stdin runner.
$(call dsl.awklang, def=.awk.module.namespace as=module_ns run=_mk.module.namespace stem=ns)
$(call dsl.awklang, def=.awk.ns.dedent)
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

# self.strip: not a registered pipeline stage -- lang.class.mixin.clean
# reads it back to drop a redundant self-target recipe block on a real
# recipe-override (off the hot path for current classes).
#:phase SEED-PARSE seed=1 awklang=no
define .awk.self.strip
BEGIN { n = split(drop, dd, " "); for (i = 1; i <= n; i++) DROP[dd[i]] = 1 }
skip && /^\t/  { next }
skip && /^ *$/ { next }
{ skip = 0 }
/^(\$\{self\}|self)([.\/%][A-Za-z0-9_%]*)*[ \t]*:([^=]|$)/ {
  h = $0; sub(/[ \t]*:.*/, "", h); k = split(h, a, " "); alldrop = 1;
  for (i = 1; i <= k; i++) {
    if (a[i] ~ /^\$\{self\}/ || a[i] ~ /^self[.\/%]/) { nm = a[i]; sub(/^\$\{self\}/, "", nm); sub(/^self/, "", nm); if (nm == "") nm = "__self__"; if (!(nm in DROP)) alldrop = 0 }
    else alldrop = 0 }
  if (alldrop) { skip = 1; next } }
{ print }
endef


# Extract one make target's full definition from a file -- the `^<name>:`
# header plus its tab-indented recipe lines (incl. `@#` docs and
# `\`-continuations) -- for an exact name (glob resolution happens
# upstream).  Read via `$(value)` so awk's `$0`/`$`/backslashes survive make
# expansion.  `g2r` -- glob (`*`/`?`) to regex.
#:phase SEED-PARSE seed=1 awklang=no
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
# exported AFTER its define so the := captures the awk (not empty).
export _cmk_blk_target_extract := $(call lang.grammar.ctx.fill,$(value .awk.target.extract))
# Target names declared textually in a stream, or with a want list only their intersection; skips define bodies and assignment lines, read via value so awk stays intact.
#:phase SEED-PARSE seed=1 awklang=no
define .awk.target.names
BEGIN { if (want != "") { k = split(want, w, " "); for (i = 1; i <= k; i++) W[w[i]] = 1; filt = 1 } }
/^define /{d=1} /^endef/{d=0;next} d{next}
/^[^[:space:]#=][^=]*:([^=]|$)/{ h=$0; sub(/[ \t]*:.*/,"",h); n=split(h,a," "); for(j=1;j<=n;j++) if(!filt || (a[j] in W)) print a[j] }
endef
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

flux.pre/%:
	@# Dispatch pre-hook if one is available
	@# Record this goal into the per-make-level VM ledger (only when virtual-machine.cmk is
	@# imported -- the gate keeps non-VM programs paying nothing; cleared again by flux.post/%).
	$(if $(call __plugins__.has,virtual-machine.cmk),@$(call __vm__.level.record,${*}),@true)
	export CMK_DISABLE_HOOKS=1 \
	&& { grep -qE '^[A-Za-z0-9_.%/-]+\.pre:' $(MAKEFILE_LIST) 2>/dev/null || exit 0 ; } \
	&& ${make} -q ${*}.pre > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.mk,  pre-hook found, dispatching ${*}) ; ${make} ${*}.pre ;; \
		1) $(call log.trace, pre-hook found, dispatching ${*}) ; ${make} ${*}.pre ;; \
		*) $(call log.trace, no such hook: ${*}.pre); exit 0;; \
	esac
flux.post/%:
	@# Dispatch post-hook if one is available
	@# Clear this goal from the per-make-level VM ledger (pair of flux.pre/%'s record above), so
	@# the set of ledger files left at any instant is exactly the LIVE cross-make-level callstack.
	$(if $(call __plugins__.has,virtual-machine.cmk),@$(call __vm__.level.clear),@true)
	export CMK_DISABLE_HOOKS=1 \
	&& { grep -qE '^[A-Za-z0-9_.%/-]+\.post:' $(MAKEFILE_LIST) 2>/dev/null || exit 0 ; } \
	&& ${make} -q ${*}.post > /dev/null 2>&1 \
	; case $$? in \
		0) $(call log.mk,  post-hook found, dispatching ${*}) ; ${make} ${*}.post;; \
		1) $(call log.trace, post-hook found, dispatching ${*}) ; ${make} ${*}.post;; \
		*) $(call log.trace, no such hook: ${*}.post ${MAKE_CLI}) && exit 0;; \
	esac

# Rewrite CLI goals to add pre/post hooks: a plain target `T` becomes
# `flux.pre/T T flux.post/T`.  Whole-line bypass for special invocations
# (help/jq/jb/yq/cmk/include/loadf, mk.interpret/compile/preprocess);
# per-field bypass for `.`-prefixed and path-like (`/`) tokens.
#:phase SUPERVISOR seed=1 awklang=no placeholder=forbidden
define .awk.rewrite.targets.maybe
  { if ($0 ~ /help/ || $0 ~ /jb/ || $0 ~ /yq/ || $0 ~ /jq/ || $0 ~ /include/ || $0 ~ /loadf/ || $0 ~ /cmk/) {
      print $0; next }
    if ($0 ~ /mk.interpret/ || $0 ~ /mk.compile/ || $0 ~ /lang.comp.pipeline/) { print $0; next }
    result = ""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^\./ || $i ~ /\//) {result = result " " $i; continue}
      if (result != "") result = result " "
      result = result "flux.pre/" $i " " $i " flux.post/" $i
    }
    print result }
endef

##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.src.fork.* :: Source-forking / packaging
##
## Co-host other files *inside* a single stand-alone
## compose.mk by rewriting its named sections (between the `# 𒄡 BEGIN/END <SECTION>` markers):
##
##   .guest      <- an embedded Makefile       (rewrites the GUEST section)
##   .services   <- a docker-compose file      (rewrites the SERVICES section)
##   .payload    <- arbitrary data             (rewrites the PAYLOAD section)
##
## Each verb takes a file arg or stdin; `lang.src.fork/<mk>,<compose>` chains guest+services and
## writes the forked binary.  The shared section-rewriter is `.lang.src.fork.section` (in lang.pkg).
## Docs: https://robot-wranglers.github.io/compose.mk/demos/packaging#guests-and-payloads

lang.src.fork/%:
	@# USAGE: ./compose.mk lang.src.fork/<Makefile>,<composefile>
	@# Like `lang.src.fork.guest/1st` followed by `lang.src.fork.services/2nd`
	@#
	${io.mktemp} && outf=$${tmpf} \
	&& ${io.mktemp} && guest=$(m5.__args__.first) \
	&& $(call log.mk,${dim} forking guest ${sep} $${guest}) \
	&& ${make} lang.src.fork.guest/$${guest} > $${tmpf} \
	&& chmod +x $${tmpf} && services=$(call m5.__args__.cut,2-) \
	&& $(call log.mk,${dim} forking services ${sep} $${services}) \
	&& $${tmpf} lang.src.fork.services/$${services} > $${outf} \
	&& chmod +x $${outf} \
	&& bin=$${bin:-${CMK_BIN}.fork} \
	&& $(call log.mk,${dim} ${dim}saving to ${no_ansi}$${bin}) \
	&& mv $${outf} $${bin} 

lang.src.fork.services: lang.src.fork.services/-
	@# Like `lang.src.fork.services`, but with streaming input.
lang.src.fork.services/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the default services section.
	PREFIX="define SERVICES" POSTFIX="endef" \
	POSTHOOK='$$(call compose.import.string, def=SERVICES import_to_root=TRUE)' \
	CMK_INTERNAL=1 ${make} .lang.src.fork.section/SERVICES/${*} 

lang.src.fork.guest: lang.src.fork.guest/-
	@# Like `lang.src.fork.guest`, but with streaming input.
lang.src.fork.guest/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the current "guest" section.
	${io.mktemp} && cat ${*} > $${tmpf} \
	&& cat $${tmpf} | grep -v '^include compose.mk' \
	| CMK_INTERNAL=1 ${make} lang.main.ensure/help \
	| CMK_INTERNAL=1 ${make} .lang.src.fork.section/GUEST/-

lang.src.fork.payload: lang.src.fork.payload/-
	@# Like `lang.src.fork.payload`, but with streaming input.
lang.src.fork.payload/%:
	@# Forks this source code, returning modified version on stdout.
	@# This rewrites the contents of the current "guest" section.
	PREFIX="define PAYLOAD" POSTFIX="endef" \
	CMK_INTERNAL=1 ${make} \
		.lang.src.fork.section/PAYLOAD/${*} 
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


