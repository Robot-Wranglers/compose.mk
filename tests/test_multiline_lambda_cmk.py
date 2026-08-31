"""Multi-line recipe lambda: an inline `(| .. |) in X` whose body spans lines (P2).

A single-line recipe banana `(| body |) in X` runs `body` in ambient X.  The multi-line
form -- the body on its own lines between a bare `(|` open and a `|)` close carrying the
`in <X>` trailer -- is folded by the `lambdalift` stage into a hoisted module `define`
(body accumulated verbatim, so real newlines survive) plus a runtime dispatch.  The
verbatim accumulation is the crux: an indented-block language (python `for:`/`if:`) must
keep its indentation, which a `;`-join would destroy.

Host cases (`in host.native.sh`, `in host.native.python`) are docker-free `unit`; the
container case is `needs_docker`.
"""

import os
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _transpile(src, timeout=120):
  r = subprocess.run(
    [str(COMPOSE), "lang.transpile"],
    cwd=str(REPO),
    input=src,
    capture_output=True,
    text=True,
    errors="replace",
    timeout=timeout,
  )
  return r.stdout


def _run_src(src, *targets, timeout=200):
  # Write the snippet to a tmp .cmk in-repo (relative compose.mk shebang path) and run it.
  f = REPO / ".tmp.mll_test.cmk"
  f.write_text(src)
  try:
    r = subprocess.run(
      [str(COMPOSE), "cmk", "run", str(f), *targets],
      cwd=str(REPO),
      stdin=subprocess.DEVNULL,
      capture_output=True,
      text=True,
      errors="replace",
      timeout=timeout,
    )
    return r, (r.stdout + r.stderr)
  finally:
    f.unlink(missing_ok=True)


def test_multiline_lambda_lowers_to_define_plus_dispatch():
  # `(|` open + later `|) in host.native.sh` folds to a hoisted `define __lambda_N` and a `${make} $(call _cmk.host.machine,host.native.sh)/..`.
  low = _transpile('foo:\n  (|\n    echo one\n    echo two\n  |) in host.native.sh\n')
  assert "define __lambda_" in low, low
  assert "${make} $(call _cmk.host.machine,host.native.sh)/__lambda_" in low, low
  # both body lines survive, dedented to column 0.
  assert "\necho one\n" in low and "\necho two\n" in low, low


def test_no_target_errors():
  # a bare multi-line lambda with no `in <ambient>` is an inert string, not runnable: it errors
  # (nothing hoisted or sourced), the same as the single-line bare form.
  low = _transpile('baz:\n  (|\n    echo nope\n  |)\n')
  assert "$(error" in low and "inert string" in low, low
  assert ". <($(call _mk.def.to.fd," not in low, low


def test_multiline_sh_lambda_runs():
  src = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "__main__: foo\n"
    "foo:\n"
    "  (|\n"
    '    echo "line one"\n'
    '    echo "line two"\n'
    "  |) in host.native.sh\n"
  )
  r, out = _run_src(src)
  assert r.returncode == 0, out
  assert "line one" in out and "line two" in out, out


def test_multiline_python_preserves_indented_block():
  # the crux: a python `for:` body keeps its indentation through the fold (a `;`-join
  # would break it).  Host python3, docker-free.
  src = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "__main__: bar\n"
    "bar:\n"
    "  (|\n"
    "    for i in range(3):\n"
    '        print("py block", i)\n'
    "  |) in host.native.python\n"
  )
  r, out = _run_src(src)
  assert r.returncode == 0, out
  assert "py block 0" in out and "py block 1" in out and "py block 2" in out, out


def test_multiline_lambda_env_trailer():
  # a `{k=v}` env channel on the closing line reaches the body.
  src = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "__main__: e\n"
    "e:\n"
    "  (|\n"
    "    import os\n"
    '    print("WHO", os.environ.get("WHO", "unset"))\n'
    "  |) in host.native.python {WHO=cmk}\n"
  )
  r, out = _run_src(src)
  assert r.returncode == 0, out
  assert "WHO cmk" in out, out


def test_single_line_lambda_unaffected():
  # the single-line arm reuses the same helpers: `(| .. |) in host.native.sh` on one line still lowers + runs.
  low = _transpile('q:\n  (| echo solo |) in host.native.sh\n')
  assert "${make} $(call _cmk.host.machine,host.native.sh)/__lambda_" in low, low


def test_multiline_cooked_bracket_lambda_runs():
  # the cooked bracket form `[| .. |]` multi-line dispatches like the raw `(| .. |)` form
  # (the docook flag rides the same accumulator + emit path).
  src = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "__main__: k\n"
    "k:\n"
    "  [|\n"
    "    for i in 1 2 3\n"
    '    do echo "cooked-multi $i"\n'
    "    done\n"
    "  |] in host.native.sh\n"
  )
  r, out = _run_src(src)
  assert r.returncode == 0, out
  assert "cooked-multi 1" in out and "cooked-multi 3" in out, out


@pytest.mark.docker
@pytest.mark.needs_docker
def test_multiline_lambda_in_container():
  # the original goal: an inline multi-line body run in a container ambient.
  src = (
    "#!/usr/bin/env -S ./compose.mk cmk run\n"
    "open cmk\n"
    "container py312(| img=python:3.12-slim entrypoint=python3 |)\n"
    "__main__: c\n"
    "c:\n"
    "  (|\n"
    "    import sys\n"
    "    total = sum(n * n for n in range(1, 11))\n"
    '    print("in-container", sys.version.split()[0], "sumsq", total)\n'
    "  |) in py312\n"
  )
  r, out = _run_src(src)
  assert r.returncode == 0, out
  assert "in-container 3.12" in out and "sumsq 385" in out, out
