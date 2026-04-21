"""Tool proxy-wrapper targets: jb / jq / yq.

These are the greedy CLI *proxy wrappers* (`./compose.mk jq .foo`,
`./compose.mk jb foo=bar`, `… | ./compose.mk yq .foo`) -- distinct from the
`${jb}`/`${jq}` macros exercised indirectly elsewhere; the wrapper targets
themselves were at 0% coverage. They consume the rest of the command line via
`mk.yield`, so they need a supervisor (CMK_SUPERVISOR=1, re-enabled below).

These aren't `docker.*` targets, so they live in the `integration` suite (an
end-to-end proxy invocation), but they carry `needs_docker`: `jb` is always
dockerized and `jq`/`yq` fall back to a container when not on PATH, so a daemon
is required to run them reliably. Driven through docker_cmk (label-scoped
cleanup).
"""

import json

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]

# The greedy mk.yield epilogue needs a live supervisor (harness default is off).
SUP = {"CMK_SUPERVISOR": "1"}


def test_proxy_jq(docker_cmk):
  # `compose.mk jq <filter>`: stdin JSON piped through jq, filter from CLI tail.
  r = docker_cmk("jq", ".foo", stdin='{"foo":"bar"}', env=SUP)
  assert r.ok, r.stderr
  assert json.loads(r.stdout.strip()) == "bar"


def test_proxy_jb(docker_cmk):
  # `echo key=val | compose.mk jb`: builds JSON from args (always via dockerized
  # jb). The harness pipes stdin, so jb takes its pipe branch (args via stdin),
  # which is the documented form; CLI-args mode needs a tty and isn't harnessable.
  r = docker_cmk("jb", stdin="foo=bar", env=SUP)
  assert r.ok, r.stderr
  assert json.loads(r.stdout.strip()) == {"foo": "bar"}


def test_proxy_yq(docker_cmk):
  # `compose.mk yq <expr>`: stdin YAML piped through yq, expr from CLI tail.
  r = docker_cmk("yq", ".foo", stdin="foo: bar\n", env=SUP)
  assert r.ok, r.stderr
  assert "bar" in r.stdout
