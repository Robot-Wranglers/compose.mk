"""Regression net for machine FEED-discipline routing (the recurring subtle bug).

`feed=` decides how a machine hands the shape (program) to its interpreter:
  * file  (default) -> `TOOL <shapefile>`      (shape as a positional file arg)
  * stdin           -> `TOOL < <shapefile>`    (shape piped on stdin, no file arg)
  * flag  (+flag=)  -> `TOOL <flag> <shapefile>` (shape after a flag, e.g. jq -f)

The historical bug: `feed`/`feed_flag` never propagated from the machine's construction
kwargs to dispatch, so EVERY discipline silently fell back to `file`.  It stayed hidden
because tools that accept a positional file (bc, and even file-fed jq) still produced the
right answer -- the *mechanism* was wrong but the *output* looked fine.

To make the mechanism itself falsifiable, these tests use a custom probe "interpreter" that
reports HOW it was invoked (MODE) and the program it received (PROG).  If `feed` regresses to
`file`, MODE is wrong and the test fails -- for EACH discipline independently.  This is the
structural guarantee the output-only tests (bc etc.) cannot give.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")

# A fake interpreter: resolves the program from wherever the invocation put it and prints a
# discriminator.  `-F` => flag mode (program in $2); a bare arg => file mode (program in $1);
# no args => stdin mode (program on stdin).  So MODE is a direct readout of the built command.
PROBE = (
    "#!/bin/sh\n"
    'if [ "$1" = "-F" ]; then echo "MODE=flag PROG=[$(cat "$2")]"\n'
    'elif [ "$#" -ge 1 ]; then echo "MODE=file PROG=[$(cat "$1")]"\n'
    'else echo "MODE=stdin PROG=[$(cat)]"; fi\n'
)


def _run(tmp_path, kwargs):
    probe = tmp_path / "probe.sh"
    probe.write_text(PROBE)
    probe.chmod(0o755)
    src = (
        "from cmk import dsl\n"
        f"dsl m(entrypoint={probe}{kwargs})(| |)\n"
        "m s(| SHAPEMARK |)\n"
        "__main__:\n\ts()\n"
    )
    f = tmp_path / "feed.cmk"
    f.write_text(src)
    r = subprocess.run(
        [str(COMPOSE), "cmk", "run", str(f)],
        cwd=str(REPO), stdin=subprocess.DEVNULL,
        capture_output=True, text=True, errors="replace", timeout=180,
    )
    return r, _ANSI.sub("", r.stdout + r.stderr)


def test_feed_default_routes_shape_as_file(tmp_path):
    # no feed= -> the default discipline is `file`
    r, out = _run(tmp_path, "")
    assert r.returncode == 0, out
    assert "MODE=file PROG=[SHAPEMARK]" in out, out


def test_feed_file_routes_shape_as_file(tmp_path):
    r, out = _run(tmp_path, ", feed=file")
    assert r.returncode == 0, out
    assert "MODE=file PROG=[SHAPEMARK]" in out, out


def test_feed_stdin_routes_shape_to_stdin(tmp_path):
    # THE masked case: a broken feed falls back to `file` -> MODE=file, and this fails.
    r, out = _run(tmp_path, ", feed=stdin")
    assert r.returncode == 0, out
    assert "MODE=stdin PROG=[SHAPEMARK]" in out, out


def test_feed_flag_routes_shape_after_flag(tmp_path):
    r, out = _run(tmp_path, ", feed=flag, flag=-F")
    assert r.returncode == 0, out
    assert "MODE=flag PROG=[SHAPEMARK]" in out, out
