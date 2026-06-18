#!/usr/bin/env -S CMK_SUPERVISOR=1 ./compose.mk mk.interpret
# overlay.mk: a console-TUI "control-stack overlay" for the __vm__ machine, built on host tmux.
#
#   `demo.ui` opens a 2-pane tmux layout: pane 0 STREAMS a live __vm__ program (the coroutine
#   demo) while pane 1 is a panel (full-width io.print.banner header + K/E body) that REFLECTS
#   the live __vm__ control stack -- the CEK state read from its run-shared files (K = frame
#   stack, E = environment).  tmux owns the screen, so each pane is its own surface: no
#   two-writer races, no scroll-region cursor math, no pipe buffering -- the corruption a
#   hand-rolled ANSI overlay can't avoid.
#
#   Run FROM THE REPO ROOT, in a real terminal:
#       ./demos/overlay.mk demo.ui      # the 2-pane overlay (needs tmux + a tty)
#       ./demos/overlay.mk              # just runs the coroutine inline (no tmux)
#
#   Deps: host tmux + jq (degradable).  The panel reads the state files the
#   main run writes; both panes share this cwd, so the glob below finds them across the two
#   different MAKE_SUPER values.  CAVEAT: two concurrent overlay runs in ONE cwd would
#   cross-read each other's state (fine for a demo).  The continuation C lives in MAKE_CLI (not
#   file-backed), so it is not externally reflectable; the panel shows K + E (+ depth + clock).
include compose.mk
# The __vm__ plugin (control stack + CEK machine) is no longer in core -- import it.
$(call include.plugins, __vm__.mk)

__main__: coro.demo

# ── the main program (pane 0) ───────────────────────────────────────────────
# Copied from demos/vm.mk (coro.demo): a re-entrant coroutine whose resume-state lives in the
# threaded environment E (the `phase` binding), NOT in the goal -- so the trampoline keeps it
# FLAT (K depth stays 0; the panel shows `phase` advancing in E).  io.wait/1 per entry is the
# only addition, so each phase lingers long enough to watch in the overlay.
coro.demo:; @$(call __vm__.setenv, phase, 0) && $(call __vm__.goto, coro)
coro:
	@${make} io.wait/1 \
	&& case "`$(call __vm__.getenv, phase)`" in \
		0) echo "coro: enter (phase 0) -> init"  && $(call __vm__.setenv, phase, 1) && $(call __vm__.goto, coro) ;; \
		1) echo "coro: resume (phase 1) -> step" && $(call __vm__.setenv, phase, 2) && $(call __vm__.goto, coro) ;; \
		2) echo "coro: resume (phase 2) -> done" ;; \
	esac

# ── the overlay panel (pane 1) ──────────────────────────────────────────────
# vm.inspect: render ONE frame of the live __vm__ control stack.  Reads the run-shared CEK
# state by GLOB (the reader's MAKE_SUPER differs from the running ops'):
#   K = .tmp.CONTROL_STACK_FRAMES.*  (JSON array of {goal,cont,env})
#   E = .tmp.cmk.vmenv.*             (JSON object of bindings)
# The header is compose.mk's FULL-WIDTH `io.print.banner` (sized to `width`, threaded in as
# COLS by the loop); the K/E body is plain text.  jq is the host binary; missing files degrade.
vm.inspect:
	@fr="`cat .tmp.CONTROL_STACK_FRAMES.* 2>/dev/null`" \
	; ev="`cat .tmp.cmk.vmenv.* 2>/dev/null`" \
	; depth="`printf '%s' "$${fr:-[]}" | jq 'length' 2>/dev/null`" \
	; case "$$depth" in ''|*[!0-9]*) depth=0;; esac \
	; goals="`printf '%s' "$${fr:-[]}" | jq -r '.[]?.goal // empty' 2>/dev/null | sed 's/^/  /'`" \
	; [ -n "$$goals" ] || goals="  (none)" \
	; env="`printf '%s' "$${ev:-{}}" | jq -r 'to_entries[]? | "  \(.key) = \(.value)"' 2>/dev/null`" \
	; [ -n "$$env" ] || env="  (empty)" \
	; ( export width="$${COLS:-`tput cols 2>/dev/null || echo 80`}" \
		; export label="__vm__ control stack // ${io.timestamp}" \
		; ${io.print.banner} ) 2>&1 \
	; printf '\nK (frames)  depth=%s\n%s\n\nE (env)\n%s\n' "$$depth" "$$goals" "$$env"

# vm.overlay: the refresh loop for pane 1.  Compute the pane width HERE (this recipe has the
# pane tty; vm.inspect's stdout is captured through a pipe, so tput can't read it there) and
# thread it down as COLS.  Render into a var FIRST, then clear+print, so the render cost is
# hidden and the redraw barely flickers; recomputing cols each tick tracks live resizes.
vm.overlay:
	@while :; do \
		cols="$$(tput cols 2>/dev/null || echo 80)" \
		; out="$$(COLS=$$cols ${make} vm.inspect 2>/dev/null)" \
		; clear 2>/dev/null || true \
		; printf '%s\n' "$$out" \
		; sleep 1 \
	; done

# ── the launcher (demo.ui) ──────────────────────────────────────────────────
# One shell: with a tty + tmux, open the 2-pane session and attach; otherwise degrade to
# running the program inline (so CI / headless gets sane output + exit code, never blocking on
# a tmux attach).  Pane 0 runs the program then `tmux kill-session` (no -t: kills its own
# session) -- so when the program exits the session dies, the overlay loop dies with it, attach
# returns, and the prompt is clean.  Unique per-pid session name keeps concurrent runs separate.
demo.ui:
	@if [ -t 1 ] && command -v tmux >/dev/null 2>&1; then \
		sess="cmk-overlay-$$$$" \
		&& tmux new-session -d -s "$$sess" -x "`tput cols`" -y "`tput lines`" \
			"./demos/overlay.mk coro.demo; tmux kill-session" \
		&& tmux split-window -t "$$sess" -v "./demos/overlay.mk vm.overlay" \
		&& tmux resize-pane -t "$$sess".1 -y 9 \
		&& tmux select-pane -t "$$sess".0 \
		&& tmux attach-session -t "$$sess" ; \
	else \
		exec ./demos/overlay.mk coro.demo ; \
	fi
