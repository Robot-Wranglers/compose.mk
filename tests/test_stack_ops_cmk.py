"""Behavioral regression net for the raw stack primitive (`io.stack!` / `io.stack.*`).

The stack is the layer BENEATH channels: a jq-backed JSON-array file with LIFO
push/pop plus query/transform ops (compose.mk, the `io.stack.*` block ~2212-2346).
Unlike channels (used only by the event/exception demos), the stack primitive is
what the heavy machinery rides on -- the virtual-machine plugin's control stack
(`$(call io.stack!,CONTROL_STACK_FRAMES)`) and every REPL / frame-debugger /
continuation / fork demo manipulate frames through `io.stack.push/pop/peek` and
the exported per-run stack file.  So this is the high-blast-radius surface: pin it
BEFORE any rework of how stacks are declared or stamped.

Same idiom as test_channel_ops_cmk.py: `io.stack!` is a plain seed macro, so a
vanilla `make -f` wrapper that `include`s compose.mk drives the real operator code
with no compiler / hosted / docker path.  Assertions are on OBSERVABLE behavior, so
the suite survives a re-implementation of the primitive.

GOTCHA baked into the probes: the `io.stack.*` macros expand to a `( .. )` shell
group, so wrapping one in `$(..)` command-substitution makes bash read `$((` as
ARITHMETIC.  The recipes therefore RUN the print-macros directly (label via a
separate `printf`) rather than capturing them.
"""

import shutil
from pathlib import Path

import pytest

pytestmark = pytest.mark.unit

REPO = Path(__file__).resolve().parent.parent
COMPOSE = REPO / "compose.mk"

# The whole primitive is jq-backed; without jq on the host there is nothing to
# regress (the docker demos cover the jq-in-container path).
if not shutil.which("jq"):
  pytest.skip("stack operators need jq on the host", allow_module_level=True)


def _run(cmk, tmp_path, body, *targets):
  """Run a plain-make wrapper that declares stack(s) and drives them in a recipe.

  `body` is everything after `include compose.mk`; `targets` default to `probe`.
  Absolute `include` keeps the default fixture cwd (tmp_path) so the stacks' own
  `.tmp.*` scratch stays inside the throwaway dir.  Returns (rc, stdout+stderr).
  """
  wrapper = tmp_path / "stack_probe.mk"
  wrapper.write_text(f"include {COMPOSE}\n{body}\n")
  r = cmk(*(targets or ("probe",)), makefile=str(wrapper), timeout=60)
  return r.returncode, r.stdout + r.stderr


def _recipe(*lines, name="probe"):
  """A make target `name:` whose recipe is `lines` (each tab-indented)."""
  return f"{name}:\n" + "".join(f"\t{ln}\n" for ln in lines)


# One declared stack `S`; `$(S)` holds its per-run file path.  Operators take the
# stack file as their macro arg.
DECL = "$(eval $(call io.stack!,S))\n"


def test_push_appends_and_count(cmk, tmp_path):
  # `.push` reads one JSON event from stdin and appends; `.count` reports depth;
  # `io.stack` dumps the whole array (push order preserved).
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"x":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"x":2}\' | $(call io.stack.push,$(S))',
      '@printf "COUNT="; $(call io.stack.count,$(S))',
      '@printf "DUMP="; $(call io.stack,$(S)) | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "COUNT=2" in out
  assert 'DUMP=[{"x":1},{"x":2}]' in out


def test_pop_is_lifo(cmk, tmp_path):
  # `.pop` returns the NEWEST element (LIFO) and shrinks the stack.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"n":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"n":2}\' | $(call io.stack.push,$(S))',
      '@printf "POP="; $(call io.stack.pop,$(S)) | tr -d "[:space:]"; echo',
      '@printf "LEFT="; $(call io.stack.count,$(S))',
    ),
  )
  assert rc == 0, out
  assert 'POP={"n":2}' in out
  assert "LEFT=1" in out


def test_pop_empty_is_null(cmk, tmp_path):
  # Popping an empty stack yields `null` (jq `.[-1]` of `[]`), never an error.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf "POP="; $(call io.stack.pop,$(S)) | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "POP=null" in out


def test_discard_removes_top_without_emitting(cmk, tmp_path):
  # `.discard` drops the top like pop but emits nothing.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"n":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"n":2}\' | $(call io.stack.push,$(S))',
      '@printf "DISCARD=["; $(call io.stack.discard,$(S)); printf "]\\n"',
      '@printf "LEFT="; $(call io.stack.count,$(S))',
      '@printf "TOP="; $(call io.stack,$(S)) | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "DISCARD=[]" in out       # nothing emitted
  assert "LEFT=1" in out
  assert 'TOP=[{"n":1}]' in out    # the newest was dropped


def test_word_variants_are_raw_strings(cmk, tmp_path):
  # `.push_word` slurps a RAW string from stdin and stores it as a JSON string;
  # `.pop_word` returns the top as a raw (unquoted) value -- the twin of the
  # JSON-object `push`/`pop`.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf "hello" | $(call io.stack.push_word,$(S))',
      '@printf "STORED="; $(call io.stack,$(S)) | tr -d "[:space:]"; echo',
      '@printf "POPWORD="; $(call io.stack.pop_word,$(S))',
    ),
  )
  assert rc == 0, out
  assert 'STORED=["hello"]' in out   # stored WITH json quotes
  assert "POPWORD=hello" in out      # popped WITHOUT quotes (jq -r)


def test_get_run_applies_jq_filter_read_only(cmk, tmp_path):
  # `.get.run` applies the jq program in `$jqp` (default `.`) and emits compact
  # JSON; it does NOT mutate the stack.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"x":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"x":2}\' | $(call io.stack.push,$(S))',
      '@printf "GET="; jqp="map(.x)"; $(call io.stack.get.run,$(S)) | tr -d "[:space:]"; echo',
      '@printf "COUNT="; $(call io.stack.count,$(S))',
    ),
  )
  assert rc == 0, out
  assert "GET=[1,2]" in out
  assert "COUNT=2" in out   # read-only: still two events


def test_update_run_transforms_in_place(cmk, tmp_path):
  # `.update.run` applies the jq program in `$jqp` destructively to the whole array.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"x":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"x":2}\' | $(call io.stack.push,$(S))',
      '@jqp="map(.x)"; $(call io.stack.update.run,$(S)) >/dev/null',
      '@printf "UPDATED="; $(call io.stack,$(S)) | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "UPDATED=[1,2]" in out


def test_update_rejects_non_array_and_leaves_original(cmk, tmp_path):
  # `.update.run` asserts the transform stays a JSON ARRAY: a scalar-producing jq
  # program is rejected (nonzero) and the original stack is left INTACT (atomic).
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"x":1}\' | $(call io.stack.push,$(S))',
      '@printf "BADUPDATE="; jqp=".[0]"; if $(call io.stack.update.run,$(S)) 2>/dev/null; then echo OK_UNEXPECTED; else echo REJECTED; fi',
      '@printf "INTACT="; $(call io.stack,$(S)) | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert "BADUPDATE=REJECTED" in out
  assert "OK_UNEXPECTED" not in out
  assert 'INTACT=[{"x":1}]' in out   # non-array transform did not corrupt the file


def test_initialize_seeds_lazily_from_def(cmk, tmp_path):
  # A stack declared with `init_data=<def>` is LAZY: it stays empty until
  # `io.stack.initialize` eager-seeds it from the named JSON-array define.
  body = (
    "define seed2\n[ {\"a\":1}, {\"b\":2} ]\nendef\n"
    "$(eval $(call io.stack!,SEEDED init_data=seed2))\n"
    + _recipe(
      '@printf "BEFORE="; $(call io.stack.count,$(SEEDED))',
      "@$(call io.stack.initialize,$(SEEDED),seed2)",
      '@printf "AFTER="; $(call io.stack.count,$(SEEDED))',
    )
  )
  rc, out = _run(cmk, tmp_path, body)
  assert rc == 0, out
  assert "BEFORE=0" in out   # declare alone does NOT seed
  assert "AFTER=2" in out    # initialize does


def test_initialize_tolerates_missing_def(cmk, tmp_path):
  # Seeding from a non-existent define is a tolerated no-op (logs a skip, leaves the
  # stack untouched) -- so an optional seed never hard-fails a program.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      "@$(call io.stack.initialize,$(S),no_such_def)",
      '@printf "COUNT="; $(call io.stack.count,$(S))',
    ),
  )
  assert rc == 0, out
  assert "COUNT=0" in out


def test_reset_clears_to_empty(cmk, tmp_path):
  # `.reset` overwrites the stack with an empty array.
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"n":1}\' | $(call io.stack.push,$(S))',
      "@$(call io.stack.reset,$(S))",
      '@printf "COUNT="; $(call io.stack.count,$(S))',
    ),
  )
  assert rc == 0, out
  assert "COUNT=0" in out


def test_pattern_rule_targets_on_named_file(cmk, tmp_path):
  # The public `io.stack.<op>/<file>` pattern-rule TARGETS (as opposed to the
  # macros) take the stack file as their stem: push (stdin), count, pop (LIFO), and
  # get (jq program on stdin).
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf \'{"n":1}\' | ${make} io.stack.push/$(S) 2>/dev/null',
      '@printf \'{"n":2}\' | ${make} io.stack.push/$(S) 2>/dev/null',
      '@printf "TGT_COUNT="; ${make} io.stack.count/$(S) </dev/null 2>/dev/null',
      '@printf "TGT_POP="; ${make} io.stack.pop/$(S) </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
      '@printf "map(.n)" | ${make} io.stack.get/$(S) 2>/dev/null | { printf "TGT_GET="; tr -d "[:space:]"; echo; }',
    ),
  )
  assert rc == 0, out
  assert "TGT_COUNT=2" in out
  assert 'TGT_POP={"n":2}' in out
  assert "TGT_GET=[1]" in out   # get ran after the pop removed n=2


def test_argless_targets_use_default_stack(cmk, tmp_path):
  # The argless `io.stack` / `io.stack.push` / `io.stack.pop` TARGETS operate on the
  # shared default stack (`${CMK_IO_STACK}`), no file argument.
  rc, out = _run(
    cmk, tmp_path,
    _recipe(
      '@printf \'{"d":1}\' | ${make} io.stack.push 2>/dev/null',
      '@printf "DEF_DUMP="; ${make} io.stack </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
      '@printf "DEF_POP="; ${make} io.stack.pop </dev/null 2>/dev/null | tr -d "[:space:]"; echo',
    ),
  )
  assert rc == 0, out
  assert 'DEF_DUMP=[{"d":1}]' in out
  assert 'DEF_POP={"d":1}' in out


def test_io_stack_bang_file_is_stable_across_submakes(cmk, tmp_path):
  # the property the VM machinery depends on: io.stack! exports a per-run
  # stack file name, so a sub-make sees the SAME stack the parent populated (this is
  # what lets the virtual-machine plugin harvest child control stacks after a fork /
  # thread frame state across `${make}` hops).  Push in the parent recipe, read the
  # count from a sub-make: it must see the parent's push.
  rc, out = _run(
    cmk, tmp_path,
    DECL
    + _recipe(
      '@printf \'{"n":1}\' | $(call io.stack.push,$(S))',
      '@printf \'{"n":2}\' | $(call io.stack.push,$(S))',
      "@${make} child_reads </dev/null 2>/dev/null",
    )
    + _recipe('@printf "CHILD_SEES="; $(call io.stack.count,$(S))', name="child_reads"),
  )
  assert rc == 0, out
  assert "CHILD_SEES=2" in out   # NOT 0 -- the sub-make resolves the same exported file


def test_peek_empty_yields_object(cmk, tmp_path):
  # Pins the `.[-1] // {}` idiom that the VM's `control_stack.frame.peek` is built
  # from (virtual-machine.cmk): peeking the top of an EMPTY stack yields `{}` (an
  # empty frame), not `null` -- so a fresh control stack has a well-typed top frame.
  # (frame.peek itself is a one-line wrapper over io.stack; pinning the idiom here
  # keeps the stack-level contract explicit without loading the VM plugin.)
  rc, out = _run(
    cmk, tmp_path,
    DECL + _recipe(
      '@printf "PEEK="; $(call io.stack,$(S)) | ${jq.run} -c ".[-1] // {}"',
    ),
  )
  assert rc == 0, out
  assert "PEEK={}" in out
