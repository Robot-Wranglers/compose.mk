"""Unit contract for the `m5.table` subscript-table constructor (compose.mk).

`$(call m5.table, NAME, K1=V1 K2=V2 .., default)` code-gens, for NAME:

  * NAME[k]        -- O(1) value accessor (reads like m5[..])
  * NAME.resolve   -- k[,def] -> value (warn-safe via m5|; baked default on miss)
  * NAME.reverse   -- v[,def] -> key(s) (many:1 deduped list via m5.lex.uniq)
  * NAME.has?      -- k iff present (membership predicate)
  * NAME.__all__   -- keys in declaration order
  * m5.table/*     -- map fn(key,value) over every row

When the values are handler-macro names, the same table doubles as a
dispatch/jump table (inert on a data table, a vtable when opted into):

  * NAME.dispatch  -- k[,args..] -> $(call <handler>, args..); default on miss
  * NAME.call      -- guarded twin: errno=NOT_CALLABLE on an unknown key w/ no default

These are REAL unit tests: an inline `.cmk` mints a throwaway table and a
`__main__` recipe echoes each accessor, so the contract stands on its own
(no demo files, no docker).  Stage 0 of the fault/errno unification: errno
and fault-type tables ride this primitive, so its behavior is pinned first.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")

# A table with a deliberate many:1 collision (A and C both map to 1) and a
# baked default of 9, exercised by the __main__ recipe below.
_BODY = r"""
$(call m5.table, tt, A=1 B=2 C=1, 9)
tt.dump = <$(1)=$(2)>
__main__:
	@echo "fwdA=$(tt[A])"
	@echo "fwdB=$(tt[B])"
	@echo "resHit=$(call tt.resolve,A)"
	@echo "resBaked=$(call tt.resolve,ZZ)"
	@echo "resCall=$(call tt.resolve,ZZ,77)"
	@echo "rev1=[$(call tt.reverse,1)]"
	@echo "rev2=[$(call tt.reverse,2)]"
	@echo "hasA=[$(call tt.has?,A)]"
	@echo "hasZZ=[$(call tt.has?,ZZ)]"
	@echo "all=[$(tt.__all__)]"
	@echo "map=[$(call m5.table/*,tt,tt.dump)]"
"""


@pytest.fixture(scope="module")
def out(tmp_path_factory):
  f = tmp_path_factory.mktemp("m5table") / "t.cmk"
  f.write_text(_BODY)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  text = _ANSI.sub("", r.stdout + r.stderr)
  assert r.returncode == 0, text
  return text


# A dispatch table: values are handler-macro names.  `dt` carries a default
# handler (dh.def); `nd` has none, so its .call errors on an unknown key.
_DBODY = r"""
$(call m5.table, dt, add=dh.add mul=dh.mul, dh.def)
dh.add = A[$(1):$(2)]
dh.mul = M[$(1):$(2)]
dh.def = D[$(1)]
__main__:
	@echo "dispAdd=$(call dt.dispatch,add,3,4)"
	@echo "dispMul=$(call dt.dispatch,mul,3,4)"
	@echo "dispDefault=$(call dt.dispatch,zzz,3,4)"
	@echo "callHit=$(call dt.call,add,3,4)"
	@echo "callDefault=$(call dt.call,zzz,3,4)"
"""

# No baked default -> .call on an unknown key raises errno=NOT_CALLABLE.
_NDBODY = r"""
$(call m5.table, nd, x=dh.add)
dh.add = A[$(1):$(2)]
__main__:
	@echo "ndMiss=$(call nd.call,zzz,3,4)"
"""


def _run(tmp_path_factory, name, body):
  f = tmp_path_factory.mktemp(name) / "t.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f)],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=180,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


@pytest.fixture(scope="module")
def dout(tmp_path_factory):
  r, text = _run(tmp_path_factory, "m5dtable", _DBODY)
  assert r.returncode == 0, text
  return text


def test_forward_accessor(out):
  # NAME[k] is a plain O(1) variable read.
  assert "fwdA=1" in out, out
  assert "fwdB=2" in out, out


def test_resolve_hit(out):
  assert "resHit=1" in out, out


def test_resolve_baked_default(out):
  # unknown key -> the table's baked default (9).
  assert "resBaked=9" in out, out


def test_resolve_call_default_overrides(out):
  # an explicit call-time default beats the baked one.
  assert "resCall=77" in out, out


def test_reverse_many_to_one(out):
  # 1 <- A and C (declaration order, deduped); 2 <- B only.
  assert "rev1=[A C]" in out, out
  assert "rev2=[B]" in out, out


def test_has_predicate(out):
  # present -> echoes the key; absent -> empty.
  assert "hasA=[A]" in out, out
  assert "hasZZ=[]" in out, out


def test_all_registry_order(out):
  assert "all=[A B C]" in out, out


def test_map_over_rows(out):
  # m5.table/* applies fn(key,value) across every row, in order.
  assert "map=[<A=1> <B=2> <C=1>]" in out, out


def test_dispatch_hit(dout):
  # .dispatch resolves the key to its handler and $(call)s it with the args.
  assert "dispAdd=A[3:4]" in dout, dout
  assert "dispMul=M[3:4]" in dout, dout


def test_dispatch_default_handler(dout):
  # unknown key -> the baked default handler (dh.def), args still forwarded.
  assert "dispDefault=D[3]" in dout, dout


def test_call_hit(dout):
  # .call is the guarded twin: a present key dispatches identically.
  assert "callHit=A[3:4]" in dout, dout


def test_call_falls_to_default(dout):
  # a table WITH a default never errors -- unknown key routes to the default.
  assert "callDefault=D[3]" in dout, dout


def test_call_errors_without_default(tmp_path_factory):
  # no default + unknown key -> structured fault (errno=NOT_CALLABLE), nonzero.
  r, text = _run(tmp_path_factory, "m5ndtable", _NDBODY)
  assert r.returncode != 0, text
  assert "NOT_CALLABLE" in text, text
