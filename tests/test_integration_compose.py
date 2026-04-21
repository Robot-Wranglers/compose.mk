"""Integration tests for compose.* (docker-compose integration).

Scaffold a docker-compose.yml (and, for compose.import, a project Makefile that
imports it) and exercise the targets. compose.* shells out to `docker compose`,
so these are [integration, needs_docker], driven via the `project` fixture.
"""

import pytest

pytestmark = [pytest.mark.integration, pytest.mark.needs_docker]

# A minimal compose file with one concrete service (config-only; never run).
DC = "services:\n  testsvc:\n    image: alpine:3.21.2\n"


def test_compose_services(project):
  project.write("dc.yml", DC)
  r = project.run("compose.services/dc.yml")
  assert r.ok, r.stderr
  assert r.stdout.strip() == "testsvc"


def test_compose_images(project):
  project.write("dc.yml", DC)
  r = project.run("compose.images/dc.yml")
  assert r.ok, r.stderr
  assert "alpine:3.21.2" in r.stdout


def test_compose_validate_accepts_valid(project):
  project.write("dc.yml", DC)
  assert project.run("compose.validate/dc.yml").ok


def test_compose_validate_rejects_broken(project):
  project.write("bad.yml", "services:\n  x: {image: [broken\n")
  assert not project.run("compose.validate/bad.yml").ok


def test_compose_import_dispatch(project):
  # The fixture imports dc.yml; running <service>.dispatch/<target> runs the
  # target inside the service container (which mounts the project dir).
  project.load("compose-import")
  r = project.run("testsvc.dispatch/hello")
  assert r.ok, r.stderr
  assert "HELLO-CMK-COMPOSE" in r.stdout


def test_compose_import_generated_services(project):
  # `compose.import` synthesizes a per-file target family. The generated
  # `<stem>.services` and `<namespace>.services` both list the imported file's
  # services -- this exercises the dynamic targets directly (not the underlying
  # compose.* library), and credits the generated-coverage report.
  project.load("compose-import")
  for target in ("dc.services", "services.services"):
    r = project.run(target)
    assert r.ok, r.stderr
    assert "testsvc" in r.stdout


def test_compose_import_generated_images(project):
  # Generated `<stem>.images` resolves to compose.images for the imported file.
  project.load("compose-import")
  r = project.run("dc.images")
  assert r.ok, r.stderr
  assert "debian/buildd:bookworm" in r.stdout


def test_compose_import_generated_command(project):
  # Generated `<stem>.command/<svc>/<cmd>` should run <cmd> in the service:
  # `dc.command/appsvc/whoami` -> `whoami` (-> root), not `appsvc/whoami`.
  project.load("compose-import-app")
  r = project.run("dc.command/appsvc/whoami")
  assert r.ok, r.stderr
  assert "root" in r.stdout


def test_compose_import_generated_build_family(project):
  # Generated build targets, at both the <stem>.* and <namespace>.* aliases.
  # The compose-import-app fixture builds a tiny alpine image.
  project.load("compose-import-app")
  for target in (
    "dc.build",
    "dc.build.quiet",
    "dc.require/appsvc",
    "services.build",
    "services.build.quiet",
  ):
    assert project.run(target).ok, target


def test_compose_import_generated_introspection(project):
  # ps (JSON list), size (JSON map), images, get_config -- at <stem>.* and
  # <namespace>.*. Build first so an image exists for size/images.
  project.load("compose-import-app")
  r = project.run("dc.ps")
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("[")
  assert project.run("services.ps").ok
  assert project.run("dc.build.quiet").ok
  r = project.run("dc.size")
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("{")
  assert project.run("services.size").ok
  assert project.run("services.images").ok
  assert project.run("services.get_config").ok
  # with_profile sets COMPOSE_PROFILES then runs the stem-prefixed target.
  assert project.run("dc.with_profile/anyprof/services").ok


def test_compose_import_generated_lifecycle(project):
  # Running-container family: up.detach -> assert_running -> exec -> restart ->
  # stop -> down -> clean, across <stem>.* and <namespace>.* aliases. The
  # service runs `sleep`, so it stays up for exec. A mid-run failure leaks only
  # to the session's scoped cleanup (label/project-scoped), not the dev's box.
  project.load("compose-import-app")
  assert project.run("dc.up.detach").ok
  assert project.run("services.up.detach").ok
  assert project.run("dc.assert_running/appsvc").ok
  r = project.run("dc.exec/appsvc", env={"cmd": "whoami"})
  assert r.ok, r.stderr
  assert "root" in r.stdout
  assert project.run("dc.exec.bg/appsvc", env={"cmd": "true"}).ok
  assert project.run("dc.restart").ok
  assert project.run("services.restart").ok
  assert project.run("dc.stop").ok
  assert project.run("services.stop").ok
  assert project.run("dc.down").ok
  assert project.run("services.down").ok
  assert project.run("dc.clean").ok


def test_compose_import_generated_dispatch(project):
  # <stem>.dispatch/<svc>/<target> runs a target in the service (needs make in
  # the image -> debian fixture). Credits the <compose>.dispatch template.
  project.load("compose-import")
  r = project.run("dc.dispatch/testsvc/hello")
  assert r.ok, r.stderr
  assert "HELLO-CMK-COMPOSE" in r.stdout


def test_compose_import_generated_run(project):
  # The bare <stem>/<svc> dispatch runs a command via the service's default
  # entrypoint -- the alpine fixture has none, so the command runs directly
  # (the debian fixture's `entrypoint: sh` would wrap it). Credits <compose>.
  project.load("compose-import-app")
  r = project.run("dc/appsvc", env={"cmd": "whoami"})
  assert r.ok, r.stderr
  assert "root" in r.stdout


def test_compose_import_code_generated(project):
  # `code.unbound` synthesizes targets over a named define-block (pure;
  # no container): write-to-file, read/run, preview. Covers the <ns>.to.file /
  # .run / .preview / .with.file generated templates.
  project.load("code-import")
  r = project.run("greet.to.file/out.txt")
  assert r.ok, r.stderr
  assert "CODE-BLOCK-OK" in (project.dir / "out.txt").read_text()
  assert project.run("greet.run/x").ok
  assert project.run("greet.preview").ok
  assert project.run("greet.with.file/io.preview.file").ok


def test_compose_dispatch_sh(project):
  # Standalone dispatch (no compose.import): run a shell command in a service.
  project.write("dc.yml", DC)
  r = project.run(
    "compose.dispatch.sh/dc.yml",
    env={"cmd": "echo DISP-OK", "svc": "testsvc", "entrypoint": "sh"},
  )
  assert r.ok, r.stderr
  assert "DISP-OK" in r.stdout


def test_compose_size(project):
  project.write("dc.yml", DC)
  r = project.run("compose.size/dc.yml")
  assert r.ok, r.stderr
  assert r.stdout.lstrip().startswith("{")  # JSON {repo:tag -> size}


def test_compose_build_then_clean(project):
  # compose-build fixture has a service with a build context + Dockerfile.
  project.load("compose-build")
  assert project.run("compose.build/dc.yml").ok
  # down --rmi local --remove-orphans removes the built image + network.
  assert project.run("compose.clean/dc.yml").ok


# --- per-service scaffold (<svc>.* and <ns>.<svc>.*) ------------------------
# The tests above cover the stem (<stem>.*) and namespace (<ns>.*) verbs; the
# per-SERVICE families generated by compose.create_make_targets (bare <svc>.*
# under import_to_root=TRUE, and namespaced <ns>.<svc>.*) were uncovered. These
# pin that surface so the upcoming container-KIND reimplementation can't drop it.


def test_compose_import_generated_service_introspection(project):
  # Parse-only per-service verbs (no container run): get_config[/key] renders
  # the service's compose config; ps queries (empty when down); assert_running
  # exits 23 when the service is not up. Covered at both <svc>.* and <ns>.<svc>.*.
  project.load("compose-import")
  r = project.run("testsvc.get_config")
  assert r.ok, r.stderr
  assert "debian/buildd:bookworm" in r.stdout
  r = project.run("testsvc.get_config/image")
  assert r.ok, r.stderr
  assert "debian/buildd:bookworm" in r.stdout.strip()
  # NB: get_config exists only bare (<svc>.*) and namespace-level (<ns>.get_config),
  # NOT per-service-namespaced (`<ns>.<svc>.get_config` is not generated).
  assert project.run("testsvc.ps").ok
  assert project.run("services.testsvc.ps").ok
  # not up -> assert_running fails (exit 23), at bare + namespaced aliases.
  assert not project.run("testsvc.assert_running").ok
  assert not project.run("services.testsvc.assert_running").ok


def test_compose_import_generated_service_dispatch(project):
  # Per-service dispatch runs a make target inside the service, at both the bare
  # <svc>.dispatch/<target> and namespaced <ns>.<svc>.dispatch/<target> aliases
  # (debian fixture has make). Distinct from the <stem>.dispatch/<svc>/<target>
  # form already covered.
  project.load("compose-import")
  r = project.run("testsvc.dispatch/hello")
  assert r.ok, r.stderr
  assert "HELLO-CMK-COMPOSE" in r.stdout
  r = project.run("services.testsvc.dispatch/hello")
  assert r.ok, r.stderr
  assert "HELLO-CMK-COMPOSE" in r.stdout


def test_compose_import_generated_service_lifecycle(project):
  # Per-service running-container family (bare <svc>.* + namespaced <ns>.<svc>.*):
  # build -> up.detach -> assert_running -> ps (running) -> exec -> stop, across
  # both aliases. The appsvc fixture sleeps, so it stays up for exec. One cycle.
  # NB: the per-service `.restart/<svc>` uses a FOREGROUND `up` (blocks), unlike
  # the namespace-level `.restart` (up.detach), so it is intentionally not run here.
  project.load("compose-import-app")
  assert project.run("appsvc.build").ok
  assert project.run("appsvc.up.detach").ok
  assert project.run("appsvc.assert_running").ok
  r = project.run("appsvc.ps")
  assert r.ok, r.stderr
  assert "appsvc" in r.stdout  # running -> non-empty ps JSON
  r = project.run("services.appsvc.exec", env={"cmd": "whoami"})
  assert r.ok, r.stderr
  assert "root" in r.stdout
  assert project.run("services.appsvc.up.detach").ok  # namespaced, idempotent
  assert project.run("services.appsvc.stop").ok  # namespaced stop
  assert project.run("appsvc.stop").ok  # bare stop (idempotent)
  assert project.run("dc.clean").ok
