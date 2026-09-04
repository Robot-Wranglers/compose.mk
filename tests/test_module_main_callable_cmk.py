"""A `module` with its own `__main__` is-a program: callable via `M()`.

`module` is `dsl.cmklang + cmk.namespace`, so a module both CONSTRUCTS resident
qualified targets AND is-a program: if its body declares a `__main__`, the
cmklang half (compose.mk:4471-4474) flags `__has_main__` and wires `__call__` to
run `M.__main__`.  So `M()` invokes the module's own entrypoint, which can drive
its own resident targets.

Pins `demos/cmk/module-system.cmk`'s `RunnableModule` specimen (and the runtime
half of `graal.group`, which needs docker) docker-free.  The adjacent tests miss
this: `test_cmklang_cmk` runs an EXTERNAL program in a module (`.__in__` /
`.__exec__`), and `test_entrypoint` pins the FILE-level `__main__`.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit, pytest.mark.module_system, pytest.mark.covers_demo("module-system.cmk")]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"


def _run(tmp_path):
  src = (
    "from cmk import module\n"
    "import log\n"
    "module M[|\n"
    "  greet:; cmk.log(RESIDENT-GREET)\n"
    "  __main__:\n"
    "    ${self}.greet()\n"
    "    cmk.log(MAIN-RAN)\n"
    "|]\n"
    "report:\n"
    "\t@printf 'HASMAIN=[%s] CALL=[%s]\\n' "
    "'$(if $(M.__has_main__),y,n)' "
    "'$(if $(filter-out undefined,$(origin M.__call__)),y,n)'\n"
    "\tM()\n"
    "__main__: report\n"
  )
  f = tmp_path / "runnable.cmk"
  f.write_text(src)
  p = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), "report"],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True, text=True,
    errors="replace", timeout=120,
  )
  return p, p.stdout + p.stderr


def test_module_with_main_is_callable(tmp_path):
  # `__has_main__` detects the body `__main__`, and `__call__` is wired.
  p, out = _run(tmp_path)
  assert p.returncode == 0, out
  line = next((l for l in out.splitlines() if "HASMAIN=[" in l), None)
  assert line, f"no probe line: {out[-1500:]}"
  fs = dict(re.findall(r"(\w+)=\[([^\]]*)\]", line))
  assert fs["HASMAIN"] == "y", out
  assert fs["CALL"] == "y", out


def test_calling_module_runs_its_own_main(tmp_path):
  # `M()` invokes `M.__main__`, which drives the module's own resident target.
  p, out = _run(tmp_path)
  assert p.returncode == 0, out
  assert "RESIDENT-GREET" in out, out  # __main__ invoked its own greet via ${self}.greet()
  assert "MAIN-RAN" in out, out  # the __main__ recipe ran
