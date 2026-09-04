"""Behavioral regression net for the channel operator surface.

A channel is a stack plus a suite of operators (the hosted `cmk.class channel`).  Each test writes
a small `.cmk` that constructs a channel with the normalized cmk-lang form `channel inbox(| |)` (the
two-paren constructor, kwargs like `init_data=`/`at_exit=`/`match=` in the first paren), drives it in
a `probe:` recipe, and runs it through the REAL compiler via `cmk run`.  Assertions are on OBSERVABLE
behavior (not generated text), so the suite survives a re-implementation of how the operators are
stamped.  (These replaced an earlier make-level `declare.channel` harness once that bridge was dropped.)

Two things here are the load-bearing contract for any future rework: the `<chan>/<value>` dispatch
surface (drain/match route events to user handlers named under the channel's SLASH namespace, with
the event exported as `$CMK_EVENT`), and the at-exit registration order (`at_exit` op before the
auto-`purge` in CMK_POST).
"""

import shutil
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# Channels shell out to jq for every read/mutate; without it on the host there is
# nothing to regress (the docker demos cover the jq-in-container path separately).
if not shutil.which("jq"):
  pytest.skip("channel operators need jq on the host", allow_module_level=True)


def _run(cmk, tmp_path, body, target="probe"):
  """Compile + run a cmk-lang file that constructs a channel and drives it in a recipe.

  `body` is the channel construction (`channel inbox(| |)`), any handler targets, and the recipe.
  Runs via `cmk run` -- the compiler path -- so the two-paren construction sugar is lowered.
  `CMK_SUPERVISOR=1` because `cmk run` dispatches through the supervisor (the fixture disables it).
  Returns (rc, stdout+stderr).  cwd=tmp_path keeps the channel's `.tmp.*` scratch in the throwaway dir.
  """
  src = tmp_path / "chan.cmk"
  src.write_text(f"{body}\n__main__: {target}\n")
  r = cmk("cmk", "run", str(src), cwd=tmp_path, env={"CMK_SUPERVISOR": "1"}, timeout=120)
  return r.returncode, r.stdout + r.stderr


def _recipe(*lines, name="probe"):
  """A make target `name:` whose recipe is `lines` (each tab-indented)."""
  return f"{name}:\n" + "".join(f"\t{ln}\n" for ln in lines)


# A channel's backing stack persists across the run's sub-makes, so the ergonomic
# pattern is: populate inline in the recipe shell (`$(call <chan>.emit,..)` /
# `printf .. | ${make} <chan>.push`), then read/route via `${make} <chan>.<op>`.
DECL = "channel inbox(| |)\n"

# `2>/dev/null` on a read sub-make drops its log noise but KEEPS its exit status,
# so a broken operator still fails the recipe line (and the `assert rc == 0`).
CNT = '"$$(${make} inbox.count </dev/null 2>/dev/null)"'


def test_emit_and_count(cmk, tmp_path):
  # `.emit` (macro form) builds one JSON event from kwargs and pushes it; `.count`
  # reports the stack depth.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      "@$(call inbox.emit,type=login user=carol)",
      "@$(call inbox.emit,type=login user=alice)",
      f'@printf "COUNT=%s\\n" {CNT}',
    ),
  )
  assert rc == 0, out
  assert "COUNT=2" in out


def test_macro_and_target_emit_are_equivalent(cmk, tmp_path):
  # `.emit` exists as BOTH a macro (`$(call inbox.emit,..)`) and a target reading
  # stdin (`inbox.emit[k=v]` desugars to a stdin send) -- both push one event.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      "@$(call inbox.emit,type=a)",                          # macro form
      '@printf "type=b" | ${make} inbox.emit 2>/dev/null',   # target form (stdin)
      f'@printf "COUNT=%s\\n" {CNT}',
    ),
  )
  assert rc == 0, out
  assert "COUNT=2" in out


def test_push_stdin_and_pop_lifo(cmk, tmp_path):
  # `.push` takes a raw JSON event on stdin; `.pop` returns the NEWEST (LIFO) and
  # shrinks the stack.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"n":1}\' | ${make} inbox.push 2>/dev/null',
      '@printf \'{"n":2}\' | ${make} inbox.push 2>/dev/null',
      '@printf "POP="; ${make} inbox.pop </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
      f'@printf "LEFT=%s\\n" {CNT}',
    ),
  )
  assert rc == 0, out
  assert 'POP={"n":2}' in out   # last in, first out
  assert "LEFT=1" in out


def test_pop_empty_is_null(cmk, tmp_path):
  # Popping an empty channel yields `null` (jq `.[-1]` of `[]`), not an error.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf "POP="; ${make} inbox.pop </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "POP=null" in out


def _seeded(*tail_lines):
  # Compose a wrapper: declare inbox, a `seed` helper that pushes 3 events (two
  # logins bracketing a suspend, oldest-to-newest carol/danny/alice), and a `probe`
  # that depends on it then runs `tail_lines`.
  return (
    DECL
    + _recipe(
      "@$(call inbox.emit,type=login user=carol)",
      "@$(call inbox.emit,type=suspend user=danny)",
      "@$(call inbox.emit,type=login user=alice)",
      name="seed",
    )
    + _recipe(*tail_lines, name="probe")
    + "probe: seed\n"
  )


def test_filter_dump_all(cmk, tmp_path):
  # Bare `.filter` (no stem, empty stdin) dumps the whole state as one JSON array.
  rc, out = _run(
    cmk, tmp_path,
    _seeded('@printf "DUMP="; ${make} inbox.filter </dev/null 2>/dev/null | tr -d "[:space:]"; echo'),
  )
  assert rc == 0, out
  assert 'DUMP=[{"type":"login","user":"carol"},{"type":"suspend","user":"danny"},{"type":"login","user":"alice"}]' in out


def test_dump_summary_and_records(cmk, tmp_path):
  # `.dump` logs a count summary, then emits every event as one compact JSON per line
  # (arrival order).  Distinct from `.filter` (whole-state array): dump is the readable view.
  rc, out = _run(cmk, tmp_path, _seeded("@${make} inbox.dump </dev/null 2>&1"))
  assert rc == 0, out
  assert "3 records" in out                                  # the logged count summary
  assert '{"type":"login","user":"carol"}' in out            # first event (arrival order)
  assert '{"type":"login","user":"alice"}' in out            # last event present too


def test_filter_spec_field_value(cmk, tmp_path):
  # `.filter/<key>,<value>` keeps matching events as an array (source order).
  rc, out = _run(
    cmk, tmp_path,
    _seeded('@printf "KV="; ${make} inbox.filter/type,login </dev/null 2>/dev/null | tr -d "[:space:]"; echo'),
  )
  assert rc == 0, out
  assert 'KV=[{"type":"login","user":"carol"},{"type":"login","user":"alice"}]' in out


def test_filter_field_equal_is_newest_first(cmk, tmp_path):
  # `.filter.field_equal/<field>,<value>` streams ALL matches NEWEST-FIRST (one jq
  # reverse-pass), distinct from the array-shaped `.filter/` spec query above.
  rc, out = _run(
    cmk, tmp_path,
    _seeded('@printf "FE="; ${make} inbox.filter.field_equal/type,login </dev/null 2>/dev/null | tr "\\n" "|"; echo'),
  )
  assert rc == 0, out
  assert 'FE={"type":"login","user":"alice"}|{"type":"login","user":"carol"}|' in out


def test_first_match_field_equal(cmk, tmp_path):
  # `.first.match.field_equal/` returns only the newest match.
  rc, out = _run(
    cmk, tmp_path,
    _seeded('@printf "FIRST="; ${make} inbox.first.match.field_equal/type,login </dev/null 2>/dev/null | tr -d "[:space:]"; echo'),
  )
  assert rc == 0, out
  assert 'FIRST={"type":"login","user":"alice"}' in out


def test_filter_jq_from_def_and_alias(cmk, tmp_path):
  # `.filter.jq/<def>` runs an arbitrary jq program from a `define`; `.jq/<def>` is
  # the documented alias -- both must resolve the same way.
  body = (
    "define only_logins\nmap(select(.type==\"login\"))\nendef\n"
    + _seeded(
      '@printf "JQ="; ${make} inbox.filter.jq/only_logins </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
      '@printf "ALIAS="; ${make} inbox.jq/only_logins </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert 'JQ=[{"type":"login","user":"carol"},{"type":"login","user":"alice"}]' in out
  assert 'ALIAS=[{"type":"login","user":"carol"},{"type":"login","user":"alice"}]' in out


def test_update_jqlang_mutates_in_place(cmk, tmp_path):
  # `.update/jqlang,<def>` applies a jq transform to the WHOLE state destructively.
  body = (
    "define only_logins\nmap(select(.type==\"login\"))\nendef\n"
    + _seeded(
      "@${make} inbox.update/jqlang,only_logins </dev/null 2>/dev/null >/dev/null",
      f'@printf "KEPT=%s\\n" {CNT}',
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "KEPT=2" in out   # the lone suspend dropped


def test_filter_in_place_is_destructive_keep(cmk, tmp_path):
  # `.filter.in_place/<key>,<value>` keeps only matching events (destructive filter).
  rc, out = _run(
    cmk, tmp_path,
    _seeded(
      "@${make} inbox.filter.in_place/type,login </dev/null 2>/dev/null >/dev/null",
      f'@printf "KEPT=%s\\n" {CNT}',
    ),
  )
  assert rc == 0, out
  assert "KEPT=2" in out


def test_emit_type_takes_type_from_stem(cmk, tmp_path):
  # `.emit.type/<T>` pushes an event of type <T>, merging extra metadata from stdin.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf "user=bob" | ${make} inbox.emit.type/logout 2>/dev/null',
      '@printf "OUT="; ${make} inbox.filter.field_equal/type,logout </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert '"type":"logout"' in out
  assert '"user":"bob"' in out


def test_drain_routes_by_type_to_handlers_with_event(cmk, tmp_path):
  # THE dispatch contract: `.drain` (== `.dispatch.by_type`) pops every event and
  # routes it by `.type` to a handler under the channel's SLASH namespace
  # (`inbox/<type>`), exporting the event as `$CMK_EVENT`; an explicit handler wins
  # over the `inbox/%` fallback (make rule precedence).  Any rework of the operator
  # codegen MUST keep this surface -- the slash namespace is the user's, not the
  # operators' (they live under the dot).
  body = (
    DECL
    + "inbox/login:; @printf 'H_LOGIN user=%s\\n' \"$$(printf '%s' \"$$CMK_EVENT\" | jq -r .user)\"\n"
    + "inbox/%:; @printf 'H_OTHER type=%s\\n' \"${*}\"\n"
    + _recipe(
      "@$(call inbox.emit,type=login user=carol)",
      "@$(call inbox.emit,type=suspend user=danny)",
      "@$(call inbox.emit,type=login user=alice)",
      "@${make} inbox.drain </dev/null 2>/dev/null",
      f'@printf "DRAINED=%s\\n" {CNT}',
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "H_LOGIN user=alice" in out          # newest login, event carried through
  assert "H_LOGIN user=carol" in out          # ... and the older one
  assert "H_OTHER type=suspend" in out         # unmatched type hits the `%` fallback
  assert "DRAINED=0" in out                    # drain consumes the whole stack


def test_dispatch_drain_routes_by_arbitrary_field(cmk, tmp_path):
  # `.dispatch.drain/<field>` generalizes drain to ANY field (not just `.type`):
  # here route by `.user` to `inbox/<user>`.
  body = (
    DECL
    + "inbox/carol:; @printf 'BY_USER carol\\n'\n"
    + "inbox/%:; @printf 'BY_USER other=%s\\n' \"${*}\"\n"
    + _recipe(
      "@$(call inbox.emit,type=login user=carol)",
      "@$(call inbox.emit,type=login user=alice)",
      "@${make} inbox.dispatch.drain/user </dev/null 2>/dev/null",
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "BY_USER carol" in out
  assert "BY_USER other=alice" in out


def test_match_registered_query_routes_to_handler(cmk, tmp_path):
  # `.match` runs each registered query and pipes its matches to `<chan>.match/<value>`.
  # The query is registered at parse time (as in the demos), so the `inbox.match`
  # sub-make sees it; matches arrive newest-first.
  body = (
    DECL
    + "$(call inbox.match,key=type value=login)\n"
    + "inbox.match/login:; @printf 'MATCHED='; cat | tr -d '[:space:]'; echo\n"
    + _recipe(
      "@$(call inbox.emit,type=login user=carol)",
      "@$(call inbox.emit,type=suspend user=danny)",
      "@$(call inbox.emit,type=login user=alice)",
      "@${make} inbox.match </dev/null 2>/dev/null",
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert 'MATCHED={"type":"login","user":"alice"}{"type":"login","user":"carol"}' in out


def test_purge_empties_the_channel(cmk, tmp_path):
  # `.purge` drops the backing stack (also auto-registered as the at-exit cleanup).
  rc, out = _run(
    cmk, tmp_path,
    _seeded(
      f'@printf "BEFORE=%s\\n" {CNT}',
      "@${make} inbox.purge </dev/null 2>/dev/null",
      f'@printf "AFTER=%s\\n" {CNT}',
    ),
  )
  assert rc == 0, out
  assert "BEFORE=3" in out
  assert "AFTER=0" in out


def test_init_data_seeds_on_initialize(cmk, tmp_path):
  # `declare.channel(.. init_data=<def>)` registers a JSON-array seed; `.initialize`
  # overwrites the stack with it (one-shot, `__main__`-prereq style).
  body = (
    "define seed_events\n[ {\"type\":\"login\",\"user\":\"carol\"}, {\"type\":\"suspend\",\"user\":\"danny\"} ]\nendef\n"
    "channel inbox(init_data=seed_events)(| |)\n"
    + _recipe(
      "@${make} inbox.initialize </dev/null 2>/dev/null",
      f'@printf "SEEDED=%s\\n" {CNT}',
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "SEEDED=2" in out


def test_at_exit_registers_dispatch_before_purge(cmk, tmp_path):
  # `at_exit=<op>` opts a channel into deferred dispatch: the op is appended to
  # CMK_POST BEFORE the auto-`purge`, so at exit the stack is drained/routed and
  # THEN dropped.  Pinned structurally (the registration + ordering) here; the
  # actual at-exit FIRING is covered end-to-end by the exceptions.cmk demo, which
  # needs the supervisor this docker-free path disables.
  body = (
    "channel fault(at_exit=dispatch.by_type)(| |)\n"
    + _recipe("@printf 'POST=[%s]\\n' '$(CMK_POST)'")
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "POST=[" in out
  post = out.split("POST=[", 1)[1].split("]", 1)[0].split()
  assert "fault.dispatch.by_type" in post, post
  assert "fault.purge" in post, post
  # dispatch drains/routes strictly before the purge that drops the stack.
  assert post.index("fault.dispatch.by_type") < post.index("fault.purge"), post


def test_match_via_constructor_kwarg_cmk_lang(cmk, tmp_path):
  # The DECLARATIVE cmk-lang idiom: `channel inbox(match='key=type value=login')(| |)` registers the
  # query at MINT (quote-aware, reusing `mk.unpack.kwargs`), so a matching event dispatches with no
  # imperative `.match(..)` call.  Driven via `cmk run` (the compiler path) -- the make-level
  # `declare.channel` tests above cannot express the two-paren construction sugar.
  src = tmp_path / "match.cmk"
  src.write_text(
    "channel inbox(match='key=type value=login')(| |)\n"
    "inbox.match/login:; @printf 'MATCHED=%s' \"$$(cat | ${jq.run} -r .user)\"\n"
    "probe:\n"
    "\t$(call inbox.emit,type=login user=carol)\n"
    "\t$(call inbox.emit,type=logout user=dave)\n"
    "\t@${make} inbox.match </dev/null\n"
    "__main__: probe\n"
  )
  # `cmk run` dispatches through the supervisor (the fixture's CMK_SUPERVISOR=0 would make `run` an
  # unknown target), so enable it for this one.
  r = cmk("cmk", "run", str(src), cwd=tmp_path, env={"CMK_SUPERVISOR": "1"}, timeout=120)
  out = r.stdout + r.stderr
  assert r.returncode == 0, out
  assert "MATCHED=carol" in out, out
