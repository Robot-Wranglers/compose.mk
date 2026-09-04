"""CMK_LANG run-mode: the __hosted__-partition bypass (a.k.a. "seed-only" slice).

`CMK_LANG` gates whether a parse loads the `__hosted__` CMK-lang partition:
1 (default) loads it, 0 bypasses it (a caller optimization on pure-compiler /
scaffolding passes, and a debugging tool). Resolution is a pure-make cascade
(no subprocess): **env `CMK_LANG` > `cmk_lang` pragma > default 1**, with
`__hosted__.enabled` as the resolved SSOT that the `-include` gate and the `∅`
log glyph both read. Pure local make -- no docker.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

COMPOSE_MK = Path(__file__).resolve().parent.parent / "compose.mk"


def _probe(tmp_path):
  # A vanilla `include compose.mk` wrapper plus a target that echoes the resolved
  # SSOT, so a test can read the gate's decision directly.
  (tmp_path / ".cmk").mkdir(exist_ok=True)  # keep the hosted cache under tmp_path
  mk = tmp_path / "Makefile"
  mk.write_text(
    "include %s\n" % COMPOSE_MK
    + "lang.probe:; @printf 'enabled=%s' '$(__hosted__.enabled)'\n"
  )
  return mk


def _selftest(tmp_path):
  (tmp_path / ".cmk").mkdir(exist_ok=True)
  mk = tmp_path / "Makefile"
  mk.write_text("include %s\n__main__: hosted.selftest\n" % COMPOSE_MK)
  return mk


# --- resolution cascade (env > pragma > default), read via __hosted__.enabled ---


def test_enabled_default_on(cmk, tmp_path):
  r = cmk("lang.probe", makefile=_probe(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr
  assert "enabled=1" in r.stdout, r.stdout


def test_enabled_env_off(cmk, tmp_path):
  r = cmk("lang.probe", makefile=_probe(tmp_path), cwd=tmp_path, env={"CMK_LANG": "0"})
  assert r.ok, r.stderr
  assert "enabled=0" in r.stdout, r.stdout


def test_enabled_env_on_explicit(cmk, tmp_path):
  r = cmk("lang.probe", makefile=_probe(tmp_path), cwd=tmp_path, env={"CMK_LANG": "1"})
  assert r.ok, r.stderr
  assert "enabled=1" in r.stdout, r.stdout


@pytest.mark.parametrize("falsey", ["0", "false", "no", "off"])
def test_enabled_accepts_falsey_spellings(cmk, tmp_path, falsey):
  # The gate treats 0/false/no/off as disabled; anything else is enabled.
  r = cmk("lang.probe", makefile=_probe(tmp_path), cwd=tmp_path, env={"CMK_LANG": falsey})
  assert r.ok, r.stderr
  assert "enabled=0" in r.stdout, (falsey, r.stdout)


# --- the gate: hosted targets present iff enabled ---------------------------


def test_default_loads_hosted_target(cmk, tmp_path):
  r = cmk("hosted.selftest", makefile=_selftest(tmp_path), cwd=tmp_path)
  assert r.ok, r.stderr
  assert "hosted partition is live" in (r.stdout + r.stderr)


def test_cmk_lang_0_bypasses_hosted_target(cmk, tmp_path):
  # With the partition bypassed, the hosted-only target is simply not defined.
  r = cmk(
    "hosted.selftest", makefile=_selftest(tmp_path), cwd=tmp_path, env={"CMK_LANG": "0"}
  )
  assert not r.ok, "hosted.selftest must be absent when CMK_LANG=0"
  assert "No rule to make target" in (r.stdout + r.stderr), r.stderr


def test_seed_target_still_runs_when_bypassed(cmk, tmp_path):
  # A SEED target (flux.ok) is unaffected by the bypass -- it never needed hosted.
  r = cmk("flux.ok", cwd=tmp_path, env={"CMK_LANG": "0"})
  assert r.ok, r.stderr
  assert "succeeding" in (r.stdout + r.stderr)


# --- lint cleanliness: CMK_LANG=0 adds no undefined-var warnings -------------


def _undefined_var_warnings(cmk, tmp_path, **env):
  flags = {"MAKEFLAGS": "--warn-undefined-variables --no-print-directory"}
  r = cmk("flux.ok", cwd=tmp_path, env={**flags, **env})
  return {
    ln.split(":", 1)[-1].strip()  # drop the file:line prefix so the set is stable
    for ln in (r.stdout + r.stderr).splitlines()
    if "undefined variable" in ln
  }


def test_cmk_lang_0_introduces_no_undefined_var_warnings(cmk, tmp_path):
  # Stage-3 contract: bypassing hosted (CMK_LANG=0) must not ADD any undefined-
  # variable warning vs the default -- measured RELATIVE so a pre-existing core
  # warning unrelated to CMK_LANG can't mask (or falsely fail) this regression.
  base = _undefined_var_warnings(cmk, tmp_path)
  lean = _undefined_var_warnings(cmk, tmp_path, CMK_LANG="0")
  assert not (lean - base), "CMK_LANG=0 added warnings: %s" % (lean - base)


def test_cmk_lang_0_does_not_reference_builtins_all(cmk, tmp_path):
  # The specific fix: __builtins__ is a hosted member, so its bare-bind is gated on
  # __hosted__.enabled -- disabling hosted must NOT reference __builtins__.__all__.
  lean = _undefined_var_warnings(cmk, tmp_path, CMK_LANG="0")
  assert not any("__builtins__.__all__" in w for w in lean), lean


# --- the ∅ glyph indicator (compact per-line "hosted bypassed" marker) -------


def test_glyph_present_when_disabled(cmk, tmp_path):
  r = cmk("flux.ok", cwd=tmp_path, env={"CMK_LANG": "0"})
  assert "∅" in (r.stdout + r.stderr), "expected the empty-set glyph on log lines"


def test_glyph_absent_by_default(cmk, tmp_path):
  r = cmk("flux.ok", cwd=tmp_path)
  assert "∅" not in (r.stdout + r.stderr), "glyph must not show when hosted is live"


# --- the `cmk_lang` pragma: whole-run mode, honored at EXECUTION -------------
# These drive the full `cmk run` path (compile + interpret + supervisor), so
# they force CMK_SUPERVISOR=1 (the cmk fixture's default supervisor-off would
# divert `cmk run` into plain transpile -- see the hosted-encapsulation gate).

_EXEC_PROBE = '__main__:; @printf "EXEC=%s" "$(__hosted__.enabled)"\n'
_PRAGMA = '# cmk_pragma ::: { "cmk_lang": 0 } :::\n'
_RUN_ENV = {"CMK_SUPERVISOR": "1", "CMK_COMPILER_VERBOSE": "0"}


def _run(cmk, tmp_path, src, **env):
  p = tmp_path / "prog.cmk"
  p.write_text(src)
  return cmk("cmk", "run", str(p), cwd=tmp_path, env={**_RUN_ENV, **env})


def test_pragma_bypasses_hosted_at_execution(cmk, tmp_path):
  r = _run(cmk, tmp_path, _PRAGMA + _EXEC_PROBE)
  assert r.ok, r.stderr
  assert "EXEC=0" in r.stdout, (r.stdout, r.stderr)


def test_no_pragma_keeps_hosted_at_execution(cmk, tmp_path):
  r = _run(cmk, tmp_path, _EXEC_PROBE)
  assert r.ok, r.stderr
  assert "EXEC=1" in r.stdout, (r.stdout, r.stderr)


def test_env_overrides_pragma(cmk, tmp_path):
  # Explicit env CMK_LANG=1 wins over an in-file cmk_lang:0 pragma.
  r = _run(cmk, tmp_path, _PRAGMA + _EXEC_PROBE, CMK_LANG="1")
  assert r.ok, r.stderr
  assert "EXEC=1" in r.stdout, (r.stdout, r.stderr)


# --- resolution is fork-free (no tmpfile re-read to decide the mode) ---------


@pytest.mark.skipif(shutil.which("strace") is None, reason="strace unavailable")
def test_resolution_is_fork_free(cmk, tmp_path):
  # The gate must resolve purely in make: probing __hosted__.enabled adds no
  # process over a bare parse (guards against a re-introduced `cat tmpf | sed`).
  mk = _probe(tmp_path)

  def _execs(args):
    import re
    import tempfile

    fd, tp = tempfile.mkstemp(suffix=".strace")
    import os as _os

    _os.close(fd)
    subprocess.run(
      ["strace", "-f", "-qq", "-e", "trace=execve", "-o", tp, "make", "-f", str(mk), *args],
      cwd=str(tmp_path),
      env={**__import__("os").environ, "NO_COLOR": "1", "CMK_INTERNAL": "1", "TERM": "dumb"},
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
    )
    n = sum(
      1
      for ln in Path(tp).read_text(errors="replace").splitlines()
      if re.search(r"=\s*0\s*$", ln) and "execve(" in ln
    )
    Path(tp).unlink(missing_ok=True)
    return n

  base = _execs(["flux.ok"])
  probe = _execs(["lang.probe"])
  # lang.probe expands __hosted__.enabled; it must not cost extra processes.
  assert probe <= base + 1, ("probe=%d base=%d -- resolution forked" % (probe, base))
