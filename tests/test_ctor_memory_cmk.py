"""Constructor-init memory: the generic `.__ctor_*` members every banana-with-ctor carries.

The constructor's reifier `lang.ctor.__new__` (which the ex-`lang.seed!` folded into) stamps,
per KIND:

  .__ctor_src__     -- the RAW body as written (the copy source)
  .__ctor_copy__    -- re-mint THIS constructor's raw src under a new name, via `__new__` (no
                       self-recursion: the stamp re-invokes the allocator, not the reifier by name)

These are the mechanism behind `<obj>.copy()` (surfaced on code-objects as the `copy` verb).  The
probes exercise the reifier directly (`$(call lang.ctor.__new__,def=..)`) via a plain-make wrapper
-- fast + hermetic, no cmk-lang/hosted path.  Markers avoid `$(..)`/`${..}` so `$(value)`
round-trips verbatim.
"""

import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.compiler

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _probe(cmk, body, target="probe"):
  wrapper = REPO / ".tmp.ctor.probe.mk"
  wrapper.write_text("include compose.mk\n" + body + "\nprobe:; @true\n")
  try:
    r = cmk(target, makefile=str(wrapper), cwd=REPO, timeout=60)
    return r.returncode, r.stdout + r.stderr
  finally:
    wrapper.unlink(missing_ok=True)


def _cmk_run(src, *targets, timeout=120):
  # full cmk-lang path (`open cmk`, `constructor`, ...) -- exercises the desugaring, not just the
  # seed macro that `_probe` hits.
  f = REPO / ".tmp.ctor.e2e.cmk"
  f.write_text(src)
  try:
    r = subprocess.run(
      [str(COMPOSE), "cmk", "run", str(f), *targets],
      cwd=str(REPO), stdin=subprocess.DEVNULL,
      capture_output=True, text=True, errors="replace", timeout=timeout,
    )
    return r.returncode, r.stdout + r.stderr
  finally:
    f.unlink(missing_ok=True)


# a plain constructor, probed through the ctor's own reifier (`lang.ctor.__new__`, which the
# ex-`lang.seed!` folded into).  The old 2-arg prefix form retired with the fold.
_PLAIN = (
  "define Widget\n"
  "RAWMARKER widget body\n"
  "endef\n"
  "$(eval $(call lang.ctor.__new__,def=Widget))\n"
)


def test_ctor_src_is_raw_body(cmk):
  # `.__ctor_src__` holds the body exactly as written.
  rc, out = _probe(cmk, _PLAIN + "$(info CS=[$(value Widget.__ctor_src__)])\n")
  assert rc == 0, out
  assert "CS=[RAWMARKER widget body]" in out


def test_ctor_copy_remints_from_raw_seed(cmk):
  # `.__ctor_copy__` re-mints the kind under a new name; the copy carries its own raw src.
  rc, out = _probe(
    cmk,
    _PLAIN
    + "$(call Widget.__ctor_copy__,Widget2)\n"
    + "$(info COPY_SRC=[$(value Widget2.__ctor_src__)])\n"
    + "$(info COPY_IS_KIND=[$(if $(filter file,$(origin Widget2.__tmpl)),Y,N)])\n",
  )
  assert rc == 0, out
  assert "COPY_SRC=[RAWMARKER widget body]" in out
  assert "COPY_IS_KIND=[Y]" in out


def test_ctor_copy_is_generic_end_to_end():
  # the payoff, through the REAL `constructor` keyword (not just the seed macro): the `.__ctor_*`
  # members are generic over every banana-with-ctor, so a KIND minted by `constructor` can be
  # re-minted under a new name, and the copy is a usable KIND that mints working instances.
  # (`.copy()` operates at the banana-definition level -- the KIND here, the object for a
  # code-object -- so the target of the copy is the KIND, not an instance of it.)
  rc, out = _cmk_run(
    "open cmk\n"
    "constructor Greeter[|\n  ${self} = hi-from-${self}\n|]\n"
    "$(call Greeter.__ctor_copy__,Greeter2)\n"
    "$(info GEN_COPY=[$(origin Greeter2.__ctor_copy__)])\n"
    "Greeter2 g2[||]\n"
    "$(info GEN_INSTANCE=[$(g2)])\n"
    "__main__:; @true\n"
  )
  assert rc == 0, out
  assert "GEN_COPY=[file]" in out          # the copy is itself a KIND (carries the ctor members)
  assert "GEN_INSTANCE=[hi-from-g2]" in out  # ... and mints a working instance


# --- black-box copy semantics (through the `constructor` keyword, NOT the seed macro) --------
# These pin the OBSERVABLE contract independent of the internal reifier's name/location, so they
# survive a refactor of `__ctor_copy__` / the reifier and still catch a real regression.

def test_ctor_copy_transitive_independent_recopyable():
  # one probe pins three things at once: (1) copy-of-a-copy mints (transitive), (2) the ORIGINAL
  # is untouched after being copied twice (independent), (3) the copy is itself re-copyable (its
  # `__ctor_copy__` is live -- i.e. the copy re-ran the full allocator, not a shallow clone).
  rc, out = _cmk_run(
    "open cmk\n"
    "constructor Greeter[|\n  ${self} = hi-from-${self}\n|]\n"
    "$(call Greeter.__ctor_copy__,Greeter2)\n"
    "$(call Greeter2.__ctor_copy__,Greeter3)\n"   # copy OF a copy
    "Greeter g0[||]\n"
    "Greeter2 g2[||]\n"
    "Greeter3 g3[||]\n"
    "$(info R=[$(g0)|$(g2)|$(g3)])\n"
    "$(info RECOPY=[$(origin Greeter3.__ctor_copy__)])\n"
    "__main__:; @true\n"
  )
  assert rc == 0, out
  # original still works after 2 copies; each copy bakes its OWN name -> independent instances
  assert "R=[hi-from-g0|hi-from-g2|hi-from-g3]" in out, out
  # Greeter3 exists ONLY because Greeter2 was itself copyable -> the copy carries a live ctor
  assert "RECOPY=[file]" in out, out


def test_ctor_initkw_empty_via_real_constructor():
  # PINS the finding that the 2-arg (`initkw`/prefix) reify form is NOT used by the real ctor
  # path: a KIND minted by the `constructor` keyword carries an EMPTY `__ctor_initkw__`.  This is
  # the licence for a fold that drops the prefix branch -- if a real prefix path ever appears,
  # this red flags it.
  rc, out = _cmk_run(
    "open cmk\n"
    "constructor Greeter[|\n  ${self} = x\n|]\n"
    "$(info IKW=[$(value Greeter.__ctor_initkw__)])\n"
    "__main__:; @true\n"
  )
  assert rc == 0, out
  assert "IKW=[]" in out, out
