"""Code-object composition -- the fragment algebra on imported foreign code (payoff #5 via #6).

Now that a code-object is-a `cmk.Fragment` (payoff #6), it carries the composition operators.  Two
axes, split on binding:

* `.__pipe__` (`|`) is PROCESS composition -- run one runnable, pipe its stdout into the next, EACH
  side through its OWN interpreter (so a cross-language `sh | python` pipe is legal).  It is defined
  only on BOUND code-objects; an UNBOUND one faults (`NotImplemented/Pipe`) rather than splicing raw
  source, since its guest language may have no pipe at all.  (jqlang keeps its own intra-language
  pipe; only there is source-concat-with-`|` correct.)
* `.__concat__`/`.__add__` (`+`) is NOT defined on a code-object (bound or unbound): concatenating raw
  source is only meaningful within one guest language, so it faults (`NotImplemented/Concat`).  jqlang
  keeps its own `+`; to sequence two runnables, do it at recipe scope.

The canonical surface is the `&<handle> <- a|b` capture fold (module scope; no spaces around `|`),
consumed via `this.<handle>`.  Host arm is docker-free (bind to `sh`); the cross-language arm needs
`python3` on PATH.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(src, tmp_path, goal, cwd=None):
  f = tmp_path / "comp.cmk"
  f.write_text(src)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), goal],
    cwd=str(cwd or REPO),
    stdin=subprocess.DEVNULL,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=180,
  )
  return r.stdout + r.stderr


# `&pipe <- greet|rev1` folds to `$(call greet.__pipe__,rev1)` and captures the composite as the `pipe`
# handle/target; `this.pipe` runs it.  BOTH sides are bound; the composite runs each through its own sh
# interpreter (`make greet | make rev1`), so the host pipeline reverses -> `dlrow olleh`.
PIPE_E2E = (
  "from cmk import host\n"
  "code greet(entrypoint=sh)(| echo hello world |)\n"
  "code rev1(entrypoint=sh)(| rev |)\n"
  "&pipe <- greet|rev1\n"
  "run:\n"
  "\tthis.pipe\n"
)


def test_code_object_pipe_composition_runs(tmp_path):
  out = _run(PIPE_E2E, tmp_path, goal="run", cwd=tmp_path)
  assert "dlrow olleh" in out, out


# CROSS-LANGUAGE pipe: the payoff the old source-splice could never do.  `sh` produces text, `python3`
# uppercases stdin -- each side runs through its OWN interpreter, so `hello` -> `HELLO`.  Source-splicing
# both bodies into one interpreter would be nonsense (`printf hello | import sys ...`).
XLANG_E2E = (
  "from cmk import host\n"
  "code src(entrypoint=sh)(| printf hello |)\n"
  "code up(entrypoint=python3)(|\n"
  "import sys\n"
  "print(sys.stdin.read().upper(), end='')\n"
  "|)\n"
  "&xl <- src|up\n"
  "run:\n"
  "\tthis.xl\n"
)


def test_code_object_pipe_is_cross_language(tmp_path):
  if not shutil.which("python3"):
    pytest.skip("python3 not on PATH")
  out = _run(XLANG_E2E, tmp_path, goal="run", cwd=tmp_path)
  assert "HELLO" in out, out


# Re-composition: a pipe composite is itself a runnable that re-composes, so `(src|up)|rev` extends the
# chain (`HELLO` reversed -> `OLLEH`).
RECOMPOSE_E2E = (
  "from cmk import host\n"
  "code src(entrypoint=sh)(| printf hello |)\n"
  "code up(entrypoint=python3)(|\n"
  "import sys\n"
  "print(sys.stdin.read().upper(), end='')\n"
  "|)\n"
  "code rv(entrypoint=sh)(| rev |)\n"
  "&chain <- src|up|rv\n"
  "run:\n"
  "\tthis.chain\n"
)


def test_code_object_pipe_recomposes(tmp_path):
  if not shutil.which("python3"):
    pytest.skip("python3 not on PATH")
  out = _run(RECOMPOSE_E2E, tmp_path, goal="run", cwd=tmp_path)
  assert "OLLEH" in out, out


# An UNBOUND code-object has no runtime, so piping it is a typed fault (not a silent source splice):
# `u|ok` folds to `u.__pipe__(ok)`, and `u`'s `.__pipe__` is the `NotImplemented/Pipe` error.
UNBOUND_PIPE = (
  "from cmk import host\n"
  "code.unbound u(| rev |)\n"
  "code ok(entrypoint=sh)(| echo hi |)\n"
  "&h <- u|ok\n"
  "run:\n"
  "\tthis.h\n"
)


def test_unbound_code_object_pipe_faults(tmp_path):
  out = _run(UNBOUND_PIPE, tmp_path, goal="run", cwd=tmp_path)
  assert "NotImplemented/Pipe" in out, out
  assert "UNBOUND code-object" in out, out


# `.__concat__`/`.__add__` (`+`) is NOT a code-object operation -- source concat is only meaningful
# within one guest language.  The `a+b` fold folds to `a.__add__(b)`, whose `.__concat__` faults.
CONCAT_FAULTS = (
  "from cmk import host\n"
  "code a(entrypoint=sh)(| echo AA |)\n"
  "code b(entrypoint=sh)(| echo BB |)\n"
  "&seq <- a+b\n"
  "run:\n"
  "\tthis.seq\n"
)


def test_code_object_concat_faults(tmp_path):
  out = _run(CONCAT_FAULTS, tmp_path, goal="run", cwd=tmp_path)
  assert "NotImplemented/Concat" in out, out


# `.stream` -- the no-arg Callable/Fragment invoke (payoff #6 surface): runs the body with empty argv.
STREAM_E2E = (
  "from cmk import host\n"
  "code p(entrypoint=sh)(|\n"
  '  echo "STREAM-RAN"\n'
  "|)\n"
  "run:; $(p.stream)\n"
)


def test_code_object_stream_runs_body(tmp_path):
  out = _run(STREAM_E2E, tmp_path, goal="run", cwd=tmp_path)
  assert "STREAM-RAN" in out, out
