"""Unit tests for the pure ``stream.*`` transforms (stdin -> stdout).

These targets depend only on coreutils/awk/sed/jq (already assumed by
compose.mk), so the layer is fast and needs no docker. Expected values
were derived by running each target and reviewing the bytes against its
docstring — they encode *intended* behavior, not a blind snapshot. Where
the earlier code review found a real defect, the test asserts the correct
result and is marked ``xfail`` (non-strict) with a pointer to the
finding: the suite stays green, the bug stays pinned, and the case flips
to XPASS once the target is fixed.
"""

import pytest

pytestmark = pytest.mark.unit


# (target, stdin, expected_stdout). Trailing-newline behavior is
# per-target and intentional: sed/cat-based transforms preserve the
# input's lack of a final newline, while xargs/nl/jq-based ones append
# one.
CASES = [
  # comma <-> nl <-> space
  ("stream.comma.to.nl", "a,b,c", "a\nb\nc"),
  ("stream.comma.to.nl", "solo", "solo"),
  ("stream.comma.to.nl", "", ""),
  ("stream.comma.to.space", "a,b,c", "a b c"),
  ("stream.nl.to.comma", "a\nb\nc", "a,b,c"),
  ("stream.nl.to.comma", "", ""),
  ("stream.space.to.nl", "a b c", "a\nb\nc\n"),
  ("stream.nl.to.space", "a\nb\nc", "a b c\n"),
  # indent / strip
  ("stream.indent", "x\ny", "  x\n  y"),
  ("stream.indent", "x", "  x"),
  ("stream.lstrip", "   hi", "hi"),
  ("stream.lstrip", "\t  hi", "hi"),
  (
    "stream.strip",
    "a   b",
    "a b",
  ),  # collapse internal runs (no leading/trailing)
  # passthrough
  ("stream.echo", "hello", "hello"),
  ("stream.echo", "", ""),
  # enumerate (GNU `nl -v0 -n ln`: 6-wide left-justified index, tab)
  ("stream.nl.enum", "one\ntwo", "0     \tone\n1     \ttwo\n"),
  ("stream.space.enum", "one two", "0     \tone\n1     \ttwo\n"),
  # json arrays
  ("stream.comma.to.json", "a,b", '["a","b"]\n'),
  ("stream.comma.to.json", "1,2,3", '["1","2","3"]\n'),
  ("stream.nl.to.json.array", "a\nb", '["a","b"]\n'),
]


@pytest.mark.parametrize(
  "target,stdin,expected",
  CASES,
  ids=[f"{t}::{s!r}" for t, s, _ in CASES],
)
def test_stream_transform(cmk, target, stdin, expected):
  r = cmk(target, stdin=stdin)
  assert r.ok, f"{target} exited {r.returncode}; stderr:\n{r.stderr}"
  assert r.stdout == expected


def test_json_array_append(cmk):
  r = cmk("stream.json.array.append", stdin='["a","b"]', env={"val": "c"})
  assert r.ok, r.stderr
  assert r.stdout == '[\n  "a",\n  "b",\n  "c"\n]\n'


def test_json_object_append(cmk):
  r = cmk("stream.json.append", stdin='{"a":1}', env={"key": "b", "val": "2"})
  assert r.ok, r.stderr
  assert r.stdout == '{\n  "a": 1,\n  "b": "2"\n}\n'


# --- Known bugs (from the code review) ----------------------------------
# Asserted against intended behavior; xfail(non-strict) until the
# target is fixed.


@pytest.mark.xfail(
  reason=(
    "stream.nl.to.space uses bare `xargs`, which errors on "
    "apostrophes/quotes instead of passing them through "
    "(compose.mk:3760; review HIGH)"
  ),
  strict=False,
)
def test_nl_to_space_preserves_quotes(cmk):
  r = cmk("stream.nl.to.space", stdin="it's\na test")
  assert r.ok, r.stderr
  assert r.stdout == "it's a test\n"


@pytest.mark.xfail(
  reason=(
    "stream.space.to.nl uses bare `xargs`, which errors on "
    "quotes instead of splitting literally "
    "(compose.mk:3925; review HIGH)"
  ),
  strict=False,
)
def test_space_to_nl_preserves_quotes(cmk):
  r = cmk("stream.space.to.nl", stdin='a"b c')
  assert r.ok, r.stderr
  assert r.stdout == 'a"b\nc\n'


@pytest.mark.xfail(
  reason=(
    "stream.nl.to.json.array routes through `xargs` (via "
    "stream.nl.to.space) so a line containing spaces is wrongly "
    "split (compose.mk:3911; review HIGH)"
  ),
  strict=False,
)
def test_nl_to_json_array_keeps_spaced_line(cmk):
  r = cmk("stream.nl.to.json.array", stdin="a b")
  assert r.ok, r.stderr
  assert r.stdout == '["a b"]\n'


@pytest.mark.xfail(
  reason=(
    "stream.strip does not trim leading/trailing whitespace, "
    "only collapses internal runs (compose.mk:3736; review MED)"
  ),
  strict=False,
)
def test_strip_trims_ends(cmk):
  r = cmk("stream.strip", stdin="  a  b  ")
  assert r.ok, r.stderr
  assert r.stdout == "a b"


@pytest.mark.xfail(
  reason=(
    "stream.strip deletes tabs entirely, joining adjacent "
    "tokens instead of preserving separation "
    "(compose.mk:3739; review MED)"
  ),
  strict=False,
)
def test_strip_tab_preserves_separation(cmk):
  r = cmk("stream.strip", stdin="a\tb")
  assert r.ok, r.stderr
  assert r.stdout == "a b"
