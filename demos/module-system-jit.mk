#!/usr/bin/env -S make -f
#
# module-system-jit.mk:
#   The core `native_target` / `cmk.cook` macros: JIT-compile a
#   CMK-lang `define` on first call, content-cache it, reuse after.
#
#   Because make expands recipes lazily, a target that uses these but is
#   never built costs nothing -- no fork, no compiler.  `native_target`
#   freezes the fully-expanded recipe to a shell script (warm path is
#   bash-only, zero make subprocess); it fits a single side-effecting
#   target.  `cmk.cook` cooks a multi-target define and re-execs
#   its entry in a child make.
#
#   ( This is the recipe-time JIT of a `define`, distinct from the parse-time
#   module system -- import.module namespace/partial/star/flat. )
#
# USAGE:
#   ./demos/module-system-jit.mk
#       cheap default -- compiles nothing
#   ./demos/module-system-jit.mk greet
#       native_target: JIT compile + freeze, then bash
#   ./demos/module-system-jit.mk svc
#       cmk.cook: JIT compile + run (2 targets)
#   ./demos/module-system-jit.mk proof
#       laziness + cache proof (cheap stays empty; JIT is MISS then HIT)
#   ./demos/module-system-jit.mk compare
#       native_target vs cmk.cook warm-path timing

include compose.mk

# A scoped cache (not the shared ${CMK_STAGE_DIR}/native default) so proof
# can reset it without disturbing anything else in the session.
CMK_NATIVE_CACHE := .tmp.module-system-jit

# CMK-lang, parked in an inert `define` (opaque to make until JIT-lowered).
define greet_impl
greet.entry:
  cmk.log(hello from a native_target)
  items="alpha beta gamma"
  for it in $${items}; do cmk.log(ensuring $${it} is ready); done
  cmk.log(all ready)
endef
greet:; $(call native_target, greet_impl, greet.entry)

# A fragment that introduces multiple targets -> cmk.cook (re-exec).
define svc_impl
svc.up:; cmk.log(service up)
svc.down:; cmk.log(service down)
endef
svc:; $(call cmk.cook, svc_impl, svc.up)

cheap:
	@# no native machinery touched -- nothing is ever compiled
	$(call log.io, cheap path -- no compile happened)

__main__: cheap

# -------------------------------------------------------------------------

proof:
	@# self-contained proof of laziness + cache: the cheap goal leaves the
	@# cache EMPTY; a JIT goal is MISS then HIT.
	$(call log.io, ${bold}proof${no_ansi} ${sep} 1/3 clean cache)
	rm -rf ${CMK_NATIVE_CACHE} && mkdir -p ${CMK_NATIVE_CACHE}
	$(call log.io, ${bold}proof${no_ansi} ${sep} 2/3 run the CHEAP goal -- cache must stay EMPTY)
	${make} cheap
	@ls -1 ${CMK_NATIVE_CACHE} | grep . && $(call log.io, ${red}UNEXPECTED: cache not empty) || $(call log.io, ${dim_green}OK${no_ansi} cache empty after cheap path)
	$(call log.io, ${bold}proof${no_ansi} ${sep} 3/3 run a JIT goal twice -- MISS then HIT)
	${make} svc
	${make} svc
	@ls -1 ${CMK_NATIVE_CACHE}

# -------------------------------------------------------------------------
# compare: warm-path wall-clock for N calls of each JIT shape.  Both are
# warmed once (cache populated) so we time only the steady state: the
# cmk.cook re-exec (svc) vs native_target's bash-only path (greet).
N ?= 20
compare:
	@rm -rf ${CMK_NATIVE_CACHE} && mkdir -p ${CMK_NATIVE_CACHE}
	$(call log.io, ${bold}compare${no_ansi} ${sep} warming both caches)
	@quiet=1 ${make} svc >/dev/null 2>&1
	@quiet=1 ${make} greet >/dev/null 2>&1
	$(call log.io, ${bold}compare${no_ansi} ${sep} timing ${N} warm calls each ${dim}(quiet)${no_ansi})
	@t0=$$(date +%s.%N); i=0; while [ $$i -lt ${N} ]; do quiet=1 ${make} svc >/dev/null 2>&1; i=$$((i+1)); done; \
	  t1=$$(date +%s.%N); d=$$(awk "BEGIN{printf \"%.3f\",$$t1-$$t0}"); \
	  $(call log.io, ${yellow}cmk.cook${no_ansi} ${dim}(svc)${no_ansi} re-exec ${sep} $$d s for ${N} warm calls)
	@t0=$$(date +%s.%N); i=0; while [ $$i -lt ${N} ]; do quiet=1 ${make} greet >/dev/null 2>&1; i=$$((i+1)); done; \
	  t1=$$(date +%s.%N); d=$$(awk "BEGIN{printf \"%.3f\",$$t1-$$t0}"); \
	  $(call log.io, ${dim_green}native_target${no_ansi} ${dim}(greet)${no_ansi} inline ${sep} $$d s for ${N} warm calls)
