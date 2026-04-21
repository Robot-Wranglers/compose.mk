"""Docker-gated stream.* targets.

These stream helpers shell out to tools compose.mk provides via containers
(yq, pygments), so they carry `needs_docker` and run in the docker suite.
Driven through docker_cmk (CMK_INTERNAL=0, label-scoped cleanup).
"""

import json

import pytest

pytestmark = [pytest.mark.docker, pytest.mark.needs_docker]


def test_stream_yaml_to_json(docker_cmk):
  r = docker_cmk("stream.yaml.to.json", stdin="k: v\n")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == {"k": "v"}


def test_stream_ini_pygmentize(docker_cmk):
  # Builds the pygments container on first run; highlights the input stream.
  # The dispatched container's output surfaces on stderr, so check both.
  r = docker_cmk("stream.ini.pygmentize", stdin="key=val\n")
  assert r.ok, r.stderr
  assert "key" in r.stdout + r.stderr


# nushell-backed targets pull the heavy nushell container; gated behind the
# `nushell` marker (run on demand with CMK_TEST_NUSHELL=1).


@pytest.mark.nushell
def test_stream_nushell(docker_cmk):
  r = docker_cmk("stream.nushell/from_json,to_yaml", stdin='{"foo":"bar"}')
  assert r.ok, r.stderr
  assert "foo: bar" in r.stdout


@pytest.mark.nushell
def test_stream_parse_pattern(docker_cmk):
  # stream.parse (= stream.nushell.parse = stream.parse.patterns) -> JSON.
  r = docker_cmk(
    "stream.parse", stdin="alice 30\n", env={"pattern": "{name} {age}"}
  )
  assert r.ok, r.stderr
  row = json.loads(r.stdout)[0]
  assert row == {"name": "alice", "age": "30"}


@pytest.mark.nushell
def test_stream_parse_cols(docker_cmk):
  # stream.parse.cols (= stream.nushell.parse_cols = stream.parse.columns).
  r = docker_cmk("stream.parse.cols", stdin="NAME AGE\nalice 30\n")
  assert r.ok, r.stderr
  assert json.loads(r.stdout)[0] == {"NAME": "alice", "AGE": "30"}


# --- tool-backed stream helpers (containerized jb / glow / pygments) --------


def test_stream_jb(docker_cmk):
  # stream.jb builds JSON from `key=val` args on stdin via a dockerized jb.
  r = docker_cmk("stream.jb", stdin="foo=bar")
  assert r.ok, r.stderr
  assert json.loads(r.stdout) == {"foo": "bar"}


def test_stream_pygmentize(docker_cmk):
  # Builds the pygments container; highlights the input. Output -> stderr.
  r = docker_cmk("stream.pygmentize", stdin="x=1\n")
  assert r.ok, r.stderr
  assert "x" in r.stdout + r.stderr


def test_stream_json_pygmentize(docker_cmk):
  # stream.json.pygmentize == stream.pygmentize with lexer=json.
  r = docker_cmk("stream.json.pygmentize", stdin='{"a":1}\n')
  assert r.ok, r.stderr
  assert "1" in r.stdout + r.stderr


def test_stream_glow_renders_markdown(docker_cmk):
  # stream.glow / stream.markdown render markdown via a dockerized glow. The
  # output is heavily ANSI-styled, so assert it succeeded and produced output.
  r = docker_cmk("stream.glow", stdin="# Hello\n")
  assert r.ok, r.stderr
  assert r.stdout.strip()


def test_stream_to_docker(docker_cmk):
  # stream.to.docker writes stdin to a tempfile and runs it through the named
  # image's command (here `cat`), so the marker round-trips back out.
  r = docker_cmk(
    "stream.to.docker/alpine:3.21.2", stdin="MARKER-TD", env={"cmd": "cat"}
  )
  assert r.ok, r.stderr
  assert "MARKER-TD" in r.stdout
