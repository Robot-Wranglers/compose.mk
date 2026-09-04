"""xfail-first coverage for `ifaces=` (protocol-conformance slot). SSOT: TODO-iface.md.

`ifaces=` splits protocol conformance out of `bases=`:
  * lands at the LOW-precedence tail  ->  final precedence `own > bases > ifaces`;
  * records a typed `.__ifaces__` reflection list;
  * is-a via `.__mro__` (a $(sort) set, so order-independent for issubclass);
  * the degenerate single-element `ifaces=<seed body>` is the replacement for
    `lang.proto.tmpl.inherit` (a raw body -> mixin-only, no is-a).

Implemented via TODO-iface.md Phases 2-4: `lang.class` + `cmk.protocol` ctor parse
`ifaces=`, the protocol ctor folds the guarded mixin, and the 4 seed-body protocols
migrated off `lang.proto.tmpl.inherit` (now deleted). All tests pass.
"""

import re
import subprocess
from pathlib import Path

import pytest

pytestmark = [pytest.mark.unit]

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"
_ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _run_cmk(body, tmp_path, *targets, timeout=180):
  f = tmp_path / "iface.cmk"
  f.write_text(body)
  r = subprocess.run(
    [str(COMPOSE), "cmk", "run", str(f), *targets],
    cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
    text=True, errors="replace", timeout=timeout,
  )
  return r, _ANSI.sub("", r.stdout + r.stderr)


def _probe(body, timeout=90):
  # hermetic: plain make over compose.mk, no transpile -- queries already-minted core state.
  probe = REPO / ".tmp.iface.probe.mk"
  probe.write_text(body)
  try:
    r = subprocess.run(
      ["make", "-f", str(COMPOSE), "-f", str(probe), "probe"],
      cwd=str(REPO), stdin=subprocess.DEVNULL, capture_output=True,
      text=True, errors="replace", timeout=timeout,
    )
    return r, _ANSI.sub("", r.stdout + r.stderr)
  finally:
    probe.unlink(missing_ok=True)


def test_ifaces_stamps_typed_handle(tmp_path):
  # a class declaring `ifaces=P` records a `.__ifaces__` reflection list.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__)(|\n"
    "  '''the P protocol'''\n"
    "|)\n"
    "class Foo(ifaces=P)[| ${self}.x := 1 |]\n"
    "demo:; @printf 'ifaces=[%s]' '$(Foo.__ifaces__)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "ifaces=[P]" in out, out


def test_ifaces_member_reaches_conformer(tmp_path):
  # a CONCRETIZED protocol's default member is stamped onto the conformer via ifaces=,
  # exactly as it would be via bases= (Phase 3: protocol/class mixin fold honors ifaces).
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol Greeter(dunder=__greet__)(| ${self}.greet := from-iface |)\n"
    "class Foo(ifaces=Greeter)[| ${self}.x := 1 |]\n"
    "cmk.Foo(f)\n"
    "demo:; @printf 'greet=[%s]' '$(f.greet)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "greet=[from-iface]" in out, out


def test_ifaces_precedence_below_bases(tmp_path):
  # own > bases > ifaces: on a COLLISION the base wins (`greet`), but a NON-colliding iface
  # member (`wave`) must still be applied -- the `wave` check makes this discriminate a real
  # ifaces= impl from today's "ifaces= silently ignored" (where wave would be empty).
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "class Base[| ${self}.greet := from-base |]\n"
    "protocol Greeter(dunder=__greet__)(| ${self}.greet := from-iface\n"
    "  ${self}.wave := waved |)\n"
    "class Foo(bases=Base, ifaces=Greeter)[| ${self}.x := 1 |]\n"
    "cmk.Foo(f)\n"
    "demo:; @printf 'greet=[%s] wave=[%s]' '$(f.greet)' '$(f.wave)'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "greet=[from-base]" in out, out    # collision -> base wins
  assert "wave=[waved]" in out, out         # non-colliding iface member applied (fails if ifaces= ignored)


def test_ifaces_is_a_via_mro(tmp_path):
  # ifaces= records is-a: issubclass(Foo, P) is true, and P is in Foo.__mro__.
  r, out = _run_cmk(
    "from cmk import class, protocol\n"
    "protocol P(dunder=__p__)(|\n"
    "  '''P'''\n"
    "|)\n"
    "class Foo(ifaces=P)[| ${self}.x := 1 |]\n"
    "demo:; @printf 'sub=[%s] inmro=[%s]' "
    "'$(call issubclass,Foo,P)' '$(filter P,$(Foo.__mro__))'\n"
    "__main__: demo\n", tmp_path)
  assert r.returncode == 0, out
  assert "sub=[1]" in out, out
  assert "inmro=[P]" in out, out


def test_proto_inherit_eliminated_but_seed_mixin_survives():
  # THE PROOF: after migrating the 4 protocol sites to ifaces=<seed body>,
  # `lang.proto.tmpl.inherit` no longer exists, yet Callable still carries its seed
  # impl body in `.__mixins` (now via the degenerate ifaces= path).
  r, out = _probe(
    "probe:\n\t@printf 'inherit=[%s] callable_mixins=[%s]\\n' "
    "'$(origin lang.proto.tmpl.inherit)' '$(Callable.__mixins)'\n"
  )
  assert r.returncode == 0, out
  assert "inherit=[undefined]" in out, out                      # proto.inherit deleted
  assert "lang.proto.tmpl.callable" in out, out                 # seed mixin still attached
