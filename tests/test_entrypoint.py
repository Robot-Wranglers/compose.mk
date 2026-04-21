"""The `entrypoint` protocol + the unified `__main__` machinery on `__goals__`.

`__goals__` conforms to `entrypoint` (abstract `main`) alongside `registry`; it owns the
single entrypoint detector (`lang.main.re` -> `.has_main` file / `.has_main.stream` pipe),
the named inject stubs (`.stub.error|help|noop`), and the `.ensure/<policy>` seam.  The
formerly-scattered detect/inject sites (import.module / mk.interpret / lang.src.fork.guest /
cli.cmk.repl) now defer to these; the missing-entrypoint ADVISORY lives only in the linter
(`lang.lint.entrypoint`), so the mechanical sites stay silent.

Marked `unit` (no docker).
"""

import subprocess
import textwrap
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _probe(tmp_path, body):
  """Run a one-off makefile that `include compose.mk` + a `probe:` recipe; return stdout."""
  mk = tmp_path / "probe.mk"
  mk.write_text("include " + str(COMPOSE) + "\n" + textwrap.dedent(body))
  (tmp_path / ".cmk").mkdir(exist_ok=True)  # keep the hosted cache local to tmp
  r = subprocess.run(
    ["make", "-f", str(mk), "probe"],
    cwd=str(tmp_path), capture_output=True, text=True, errors="replace", timeout=120,
  )
  return r.returncode, (r.stdout + r.stderr)


def _cli(tmp_path, *args, timeout=120):
  r = subprocess.run(
    [str(COMPOSE), *args],
    cwd=str(REPO), stdin=subprocess.DEVNULL,
    capture_output=True, text=True, errors="replace", timeout=timeout,
  )
  return r, (r.stdout + r.stderr)


# ---- the protocol ---------------------------------------------------------------------------

def test_goals_is_registry_not_program(tmp_path):
  # __goals__ is the goal REGISTRY only.  The entrypoint contract was un-squatted off it onto the
  # `Program` protocol / dsl.cmklang, so __goals__ conforms to `registry` but NOT `Program`.
  rc, out = _probe(tmp_path, """
    probe:; @echo "reg=[$(call lang.proto.provided_by,registry,__goals__)]"
	@echo "prog=[$(call lang.proto.provided_by,Program,__goals__)]"
	@echo "abstract=[$(Program.abstract)]"
  """)
  assert "reg=[1]" in out, out
  assert "prog=[]" in out, out
  assert "abstract=[__main__]" in out, out


def test_main_var_is_the_default_goal(tmp_path):
  # ${__main__} == $(.DEFAULT_GOAL) -- the program's default-goal noun (direct now; was __goals__.main).
  rc, out = _probe(tmp_path, """
    probe:; @echo "main=[${__main__}] default=[$(.DEFAULT_GOAL)]"
  """)
  assert "main=[__main__] default=[__main__]" in out, out


# ---- the detector (one regex, two shapes) ---------------------------------------------------

def test_has_main_file_form(tmp_path):
  (tmp_path / "wm").write_text("__main__:; @echo hi\n")
  (tmp_path / "nm").write_text("foo:; bar\n")
  (tmp_path / "vc").write_text("__main__ := x\nfoo:; bar\n")   # a variable, not a target
  (tmp_path / "eq").write_text("__main__ = ${x}\nfoo:; bar\n")  # ditto
  rc, out = _probe(tmp_path, """
    probe:; @echo "wm=[$(call lang.main.has,wm)] nm=[$(call lang.main.has,nm)]"
	@echo "vc=[$(call lang.main.has,vc)] eq=[$(call lang.main.has,eq)]"
  """)
  assert "wm=[__main__] nm=[]" in out, out
  # the `__main__ :=`/`= ` VARIABLE must not read as an entrypoint TARGET.
  assert "vc=[] eq=[]" in out, out


def test_has_main_stream_form(tmp_path):
  rc, out = _probe(tmp_path, """
    probe:
	@printf '__main__: dep\\n' | ${lang.main.has.stream}
	@printf 'x:\\n\\t__main__: nope\\n' | ${lang.main.has.stream} ; echo "(absent-above)"
  """)
  assert "__main__" in out, out
  assert "(absent-above)" in out, out


# ---- the ensure seam ------------------------------------------------------------------------

def test_ensure_appends_stub_when_missing(tmp_path):
  p = subprocess.run(
    [str(COMPOSE), "lang.main.ensure/help"], cwd=str(REPO),
    input="foo:; bar\n", capture_output=True, text=True, timeout=60,
  )
  assert "foo:; bar" in p.stdout
  assert "__main__: help" in p.stdout


def test_ensure_passthrough_when_present(tmp_path):
  p = subprocess.run(
    [str(COMPOSE), "lang.main.ensure/error"], cwd=str(REPO),
    input="__main__: foo\nfoo:; bar\n", capture_output=True, text=True, timeout=60,
  )
  assert "__main__: foo" in p.stdout
  assert "wasnt set" not in p.stdout   # no stub appended


# ---- the linter owns the reporting ----------------------------------------------------------

def _lint(name, text):
  Path("/tmp", name).write_text(text)   # under /tmp to avoid polluting the repo
  r, out = _cli(REPO, "cmk", "lint", str(Path("/tmp", name)))
  return out


def test_lint_reports_missing_entrypoint():
  out = _lint("ep_nm.cmk", "foo:; @echo foo\n")
  assert "no __main__ entrypoint" in out, out


def test_lint_silent_with_entrypoint():
  out = _lint("ep_wm.cmk", "__main__:; @echo hi\n")
  assert "no __main__ entrypoint" not in out, out


def test_lint_exempts_repl_pragma():
  out = _lint("ep_rp.cmk", '# cmk_pragma ::: { "repl": true } :::\nfoo:; @echo foo\n')
  assert "no __main__ entrypoint" not in out, out


def test_run_is_silent_about_entrypoint():
  # `cmk run` forces CMK_COMPILER_VERBOSE=0, so the advisory is silenced -- the run path
  # ensures a stub mechanically without owning the reporting.
  Path("/tmp/ep_run.cmk").write_text("foo:; @echo foo\n")
  r, out = _cli(REPO, "cmk", "run", "/tmp/ep_run.cmk")
  assert "no __main__ entrypoint" not in out, out
