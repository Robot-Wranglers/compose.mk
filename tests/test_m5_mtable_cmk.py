"""Unit contract for `m5.mtable` + variadic `.update` (self-memoizing cells).

`m5.mtable NAME` makes an empty table; `NAME.update` keys a lazy check under a name and
self-memoizes it (first `NAME[k]` read runs it + caches into the cell; later reads hit):

  * NAME.update k ref            -- 2-arg: cache $(ref) (any caching-callable)
  * NAME.update k test fallback  -- 3-arg: cache $(shell <test> 2>/dev/null || echo <fallback>)

All m5.table accessors (.has?/.__all__/.resolve) are inherited and trigger the check on read.

Throwaway inline `.cmk`s stand the contract on its own (no demos, no docker):
  1. behavior (2-arg memoize, 3-arg ternary hit/miss) + run-once (probe-counter)
  2. the container-boundary invariant: a nested `${make}` (dind analog) RE-detects
  3. integration: the tools were cut over to `bin[]` via `.update`, incl. the previously
     un-memoized `io.curl` / `io.terminal.cols`; each legacy name aliases its bin cell.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run(tmp_path_factory, name, body):
  f = tmp_path_factory.mktemp(name) / "t.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


_BODY = r"""
_probes :=
$(call m5.mtable, m)
$(call m.update, hit, printf HITVAL, FBVAL)
$(call m.update, miss, false, FBVAL2)
myprobe = $(eval _probes += p)REFVAL
$(call m.update, ref, myprobe)
__main__:
	@echo "hit=$(m[hit])"
	@echo "miss=$(m[miss])"
	@echo "ref1=$(m[ref])"
	@echo "ref2=$(m[ref])"
	@echo "probes=$(words $(filter p,$(_probes)))"
	@echo "all=[$(sort $(m.__all__))]"
	@echo "has_hit=[$(call m.has?,hit)]"
	@echo "has_z=[$(call m.has?,z)]"
	@echo "resolve_hit=$(call m.resolve,hit)"
"""

_BOUNDARY = r"""
chk_x = $(shell echo $${CTX:-host})
$(call m5.mtable, mb)
$(call mb.update, x, chk_x)
__main__:
	@echo "outer=$(mb[x])"
	@CTX=container ${make} mt.inner
mt.inner:
	@echo "inner=$(mb[x])"
"""

_INTEG = r"""
__main__:
	@echo "all=[$(sort $(bin.__all__))]"
	@echo "curl_ne=$(if $(strip $(bin[curl])),YES,NO)"
	@echo "curl_io=$(if $(filter $(bin[curl]),$(io.curl)),YES,NO)"
	@echo "cols_io=$(if $(filter $(bin[cols]),$(io.terminal.cols)),YES,NO)"
	@echo "compose_eq=$(if $(filter $(bin[compose]),$(docker.compose)),YES,NO)"
	@echo "gum_eq=$(if $(filter $(bin[gum.present]),$(_gum.present)),YES,NO)"
	@echo "jq_eq=$(if $(filter $(bin[jq.run]),$(tools.jq.run)),YES,NO)"
"""


@pytest.fixture(scope="module")
def out(tmp_path_factory):
  r, text = _run(tmp_path_factory, "mtable", _BODY)
  assert r.returncode == 0, text
  return text


def test_three_arg_ternary_hit(out):
  # test succeeds -> its output is cached.
  assert "hit=HITVAL" in out, out


def test_three_arg_ternary_miss(out):
  # test fails -> the fallback is cached.
  assert "miss=FBVAL2" in out, out


def test_two_arg_callable_memoized_once(out):
  # 2-arg caches $(ref); two reads, but the callable fired exactly once.
  assert "ref1=REFVAL" in out, out
  assert "ref2=REFVAL" in out, out
  assert "probes=1" in out, out


def test_all_registry(out):
  assert "all=[hit miss ref]" in out, out


def test_inherited_has_predicate(out):
  assert "has_hit=[hit]" in out, out
  assert "has_z=[]" in out, out


def test_inherited_resolve_triggers_memo(out):
  assert "resolve_hit=HITVAL" in out, out


def test_memoize_does_not_cross_container_boundary(tmp_path_factory):
  # host resolves 'host'; a nested ${make} (container analog) re-detects 'container'
  # -- the self-rewritten cell is a per-process, unexported var, so it can't leak.
  r, text = _run(tmp_path_factory, "mtable_bnd", _BOUNDARY)
  assert r.returncode == 0, text
  assert "outer=host" in text, text
  assert "inner=container" in text, text


def test_bin_registry_cutover(tmp_path_factory):
  # tools cut over to bin[] via .update; legacy names alias their cells, including
  # the previously un-memoized io.curl / io.terminal.cols.
  r, text = _run(tmp_path_factory, "mtable_integ", _INTEG)
  assert r.returncode == 0, text
  for key in ("curl", "cols", "compose", "gum.present", "jq.run", "jb.run", "glow.run"):
    assert key in text, text
  assert "curl_ne=YES" in text, text
  assert "curl_io=YES" in text, text
  assert "cols_io=YES" in text, text
  assert "compose_eq=YES" in text, text
  assert "gum_eq=YES" in text, text
  assert "jq_eq=YES" in text, text
