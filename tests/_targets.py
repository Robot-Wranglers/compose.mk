"""Target-level coverage helpers (denominator parse + reporting).

compose.mk is Make/bash, so there's no line/branch coverage; instead we track
which of its *public targets* the suite exercises. The denominator comes from
an independent static parse of the source (this module) — NOT from the tool's
own `mk.parse`, which is itself under test and is used only as a cross-check.

Underscore-prefixed so pytest never collects it as a test module.
"""

import json
import os
import re
import subprocess
from pathlib import Path

# A target-definition line: one or more whitespace-separated targets, then a
# single ':' that is not ':=' (assignment) or '::'. Allows pattern targets
# (foo/%), namespaced names (a.b.c), and the '!' variants (mk.compile!).
_TARGET_LINE = re.compile(
  r"^([A-Za-z0-9._%/!-]+(?:\s+[A-Za-z0-9._%/!-]+)*):(?![=:])"
)
# A `*.mk <target>` invocation inside a shell script (first token only).
_SCRIPT_CALL = re.compile(
  r"(?:\./)?(?:compose\.mk|[\w./-]+\.mk)\s+([A-Za-z][\w./%!-]*)"
)


def base_name(arg: str) -> str:
  """Base target for an invocation: pattern targets are ``base/%``."""
  return arg.split("/", 1)[0]


def _keep(base: str) -> bool:
  return bool(base) and not base.startswith((".", "-")) and "%" not in base


def _def_line_groups(compose_mk: Path):
  """Yield the set of public bases for each target-definition line.

  Skips ``define ... endef`` blocks (their bodies contain Dockerfiles, awk, and
  heredocs that look like targets). Each yielded set is the aliases on one line
  (e.g. ``flux.all/% flux.and/%:`` -> {flux.all, flux.and}).
  """
  in_define = False
  for line in Path(compose_mk).read_text().splitlines():
    if re.match(r"^define\s", line):
      in_define = True
      continue
    if re.match(r"^endef\b", line):
      in_define = False
      continue
    if in_define or not line[:1].strip():
      continue
    m = _TARGET_LINE.match(line)
    if not m:
      continue
    group = {base_name(tok) for tok in m.group(1).split()}
    group = {b for b in group if _keep(b)}
    if group:
      yield group


def public_targets(compose_mk: Path) -> set:
  """Public target base names, via an independent static source parse."""
  bases = set()
  for group in _def_line_groups(compose_mk):
    bases |= group
  return bases


def alias_map(compose_mk: Path) -> dict:
  """base -> set of sibling bases sharing a definition line (aliases).

  Only multi-member lines matter; testing one alias should credit the rest
  (they're the same recipe). Bases with no aliases are absent from the map.
  """
  amap = {}
  for group in _def_line_groups(compose_mk):
    if len(group) < 2:
      continue
    for b in group:
      amap.setdefault(b, set()).update(group)
  return amap


def targets_in_script(path: Path) -> set:
  """Base target names invoked via ``*.mk <target>`` in a shell script.

  Liberal — the caller intersects with the denominator, which filters out demo
  / user targets and stray args.
  """
  text = Path(path).read_text()
  return {base_name(m) for m in _SCRIPT_CALL.findall(text)}


def mk_parse_targets(compose_mk: Path):
  """Public bases per the tool's own ``mk.parse`` (informational cross-check).

  Returns None on any failure — mk.parse is part of what's under test, so it
  must never define or break the metric.
  """
  try:
    cp = subprocess.run(
      [str(compose_mk), "mk.parse/compose.mk"],
      capture_output=True,
      text=True,
      env={
        **os.environ,
        "NO_COLOR": "1",
        "CMK_SUPERVISOR": "0",
        "CMK_INTERNAL": "1",
      },
      cwd=str(Path(compose_mk).parent),
    )
    data = json.loads(cp.stdout)
  except Exception:
    return None
  return {base_name(k) for k, v in data.items() if not v.get("private")}


def _namespace(base: str) -> str:
  return base.split(".", 1)[0] if "." in base else base


# --- generated (dynamically-imported) target templates ----------------------
# compose.import / docker.import / polyglot.import synthesize whole target
# *families* at eval-time, parameterized by the imported file's stem, the
# chosen namespace, and each service. The instance names depend on the YAML,
# but the *templates* are written statically inside these generator `define`
# blocks -- which public_targets() skips. We parse those blocks, normalize
# the make placeholders to canonical tokens, and report generated coverage as
# its OWN bucket (never folded into the library %).

# define-blocks that emit stably-named target templates. (Others, e.g.
# _docker.import / _compose.import.script, emit only fully-dynamic
# ${kwargs_def}-named targets, which aren't stable templates.)
_GENERATOR_DEFINES = {
  "compose.import.generic",
  "compose.create_make_targets",
  "_docker.import.def",
  "_compose.import.code",
  "_polyglot.import_container",
}

# make placeholder -> canonical, regex-safe token (slash-free so base_name and
# the template-line regex below both behave).
_TEMPLATE_VARS = [
  (re.compile(r"\$[{(]compose_file_stem[})]"), "<compose>"),
  (re.compile(r"\$[{(](?:target_namespace|kwargs_namespace)[})]"), "<ns>"),
  (re.compile(r"\$[{(]compose_service_name[})]"), "<svc>"),
  (re.compile(r"\$[{(]namespaced_service[})]"), "<nssvc>"),
]
_TEMPLATE_LINE = re.compile(
  r"^([<A-Za-z0-9._%/!>-]+(?:\s+[<A-Za-z0-9._%/!>-]+)*):(?![=:])"
)
_LEFTOVER_MAKE = re.compile(r"[${}()]")


def _template_bases(line: str) -> set:
  """Canonical template bases declared on one generator-body line.

  e.g. ``${compose_file_stem}.build/% $(target_namespace).build/%:`` ->
  {'<compose>.build', '<ns>.build'}. Lines still carrying un-normalized make
  syntax (fully dynamic names, macro calls) are rejected.
  """
  for rx, tok in _TEMPLATE_VARS:
    line = rx.sub(tok, line)
  if _LEFTOVER_MAKE.search(line.split(":", 1)[0]):
    return set()
  m = _TEMPLATE_LINE.match(line)
  if not m:
    return set()
  return {base_name(tok) for tok in m.group(1).split()}


def generated_templates(compose_mk: Path) -> dict:
  """Generated target-template bases, split into scored vs instance.

  ``{"scored": set, "instance": set}``. *scored* templates key only on the
  compose stem / namespace (measurable from the import); *instance* templates
  also vary per service (``<svc>``/``<nssvc>``) and are unbounded by design --
  reported but not scored.
  """
  scored, instance = set(), set()
  cur = None
  for line in Path(compose_mk).read_text().splitlines():
    m = re.match(r"^define\s+(\S+)", line)
    if m:
      cur = m.group(1)
      continue
    if re.match(r"^endef\b", line):
      cur = None
      continue
    if cur not in _GENERATOR_DEFINES or not line[:1].strip():
      continue
    for b in _template_bases(line):
      if "<svc>" in b or "<nssvc>" in b:
        instance.add(b)
      else:
        scored.add(b)
  return {"scored": scored, "instance": instance}


def discover_compose_imports(fixtures_dir: Path, lib_namespaces=()) -> tuple:
  """(stems, namespaces) the integration fixtures import.

  Stems come from compose-YAML basenames under fixtures/; namespaces from any
  explicit ``namespace=`` in fixture Makefiles, plus the default ``services``.
  Stems/namespaces that collide with a library namespace are dropped, so a
  library invocation can't be miscredited as a generated template.
  """
  fixtures_dir = Path(fixtures_dir)
  stems, namespaces = set(), {"services"}
  if fixtures_dir.exists():
    for pat in ("*.yml", "*.yaml"):
      for yml in fixtures_dir.rglob(pat):
        stems.add(yml.stem)
    for mk in fixtures_dir.rglob("Makefile"):
      for m in re.finditer(r"namespace=([A-Za-z0-9._-]+)", mk.read_text()):
        namespaces.add(m.group(1))
  lib = set(lib_namespaces)
  return stems - lib, namespaces - lib


def credit_generated(invoked: set, imports: tuple, scored: set) -> set:
  """Scored templates credited by concrete invocations.

  Reverse-maps each invoked base by stripping a known stem/namespace prefix
  back to its placeholder, then intersects with the scored template set.
  """
  stems, namespaces = imports
  hit = set()
  for b in invoked:
    for stem in stems:
      if b == stem:
        hit.add("<compose>")
      elif b.startswith(stem + "."):
        hit.add("<compose>." + b[len(stem) + 1 :])
    for ns in namespaces:
      if b == ns:
        hit.add("<ns>")
      elif b.startswith(ns + "."):
        hit.add("<ns>." + b[len(ns) + 1 :])
  return scored & hit


def generated_report(
  compose_mk: Path, invoked: set, fixtures_dir: Path, denom: set
) -> tuple:
  """(text, data) for generated-template coverage. Pure; never raises."""
  tmpl = generated_templates(compose_mk)
  scored, instance = tmpl["scored"], tmpl["instance"]
  lib_ns = {_namespace(b) for b in denom}
  imports = discover_compose_imports(fixtures_dir, lib_ns)
  covered = credit_generated(invoked, imports, scored)
  pct = (100.0 * len(covered) / len(scored)) if scored else 0.0
  uncovered = sorted(scored - covered)
  stems, namespaces = imports

  lines = [
    f"generated target coverage (scored): {len(covered)}/{len(scored)} "
    f"templates ({pct:.0f}%)",
    f"    imports: stems={sorted(stems)} namespaces={sorted(namespaces)}",
    f"    instance-level templates (per-service, not scored): {len(instance)}",
  ]
  if uncovered:
    shown = ", ".join(uncovered[:10])
    tail = " ..." if len(uncovered) > 10 else ""
    lines.append(f"    uncovered: {shown}{tail}")

  data = {
    "scored_total": len(scored),
    "scored_covered": len(covered),
    "scored_percent": round(pct, 1),
    "covered_templates": sorted(covered),
    "uncovered_templates": uncovered,
    "instance_templates": sorted(instance),
    "imports": {"stems": sorted(stems), "namespaces": sorted(namespaces)},
  }
  return "\n".join(lines), data


def coverage_report(
  denom: set, exercised: set, suites_run, mkparse, aliases=None, extra_ns=None
) -> tuple:
  """Return (text_summary, data_dict). Pure; never raises on counts.

  `aliases` (base -> sibling set) credits alias siblings: testing one alias of
  a recipe counts the whole line as covered. `extra_ns` (ns -> (total,
  covered)) injects extra rows into the by-namespace breakdown (e.g. the
  ``<generated>`` template bucket) without touching the library headline %.
  """
  invoked = set(exercised)
  hit = set(exercised)
  if aliases:
    for b in invoked:
      hit |= aliases.get(b, set())
  covered = denom & hit
  unknown = sorted(invoked - denom)
  pct = (100.0 * len(covered) / len(denom)) if denom else 0.0

  by_ns = {}
  for b in denom:
    ns = _namespace(b)
    tot, cov = by_ns.get(ns, (0, 0))
    by_ns[ns] = (tot + 1, cov + (1 if b in covered else 0))
  for ns, (tot, cov) in (extra_ns or {}).items():
    by_ns[ns] = (tot, cov)

  suites = ",".join(sorted(suites_run)) or "none"
  lines = [
    f"target coverage (direct): {len(covered)}/{len(denom)} "
    f"public targets ({pct:.0f}%)  [suites: {suites}]",
  ]
  for ns, (tot, cov) in sorted(
    by_ns.items(), key=lambda kv: (-kv[1][0], kv[0])
  ):
    lines.append(f"    {ns:<10} {cov}/{tot}")
  if unknown:
    shown = ", ".join(unknown[:8])
    lines.append(f"  invoked but not in denominator: {len(unknown)} ({shown})")
  if mkparse is not None:
    only_static = len(denom - mkparse)
    only_parse = len(mkparse - denom)
    lines.append(
      f"  denominator cross-check: static={len(denom)} "
      f"mk.parse={len(mkparse)} (static-only={only_static}, "
      f"parse-only={only_parse})"
    )
  else:
    lines.append("  denominator cross-check: mk.parse unavailable")

  data = {
    "suites_run": sorted(suites_run),
    "denominator": len(denom),
    "covered": len(covered),
    "percent": round(pct, 1),
    "by_namespace": {
      ns: {"covered": cov, "total": tot}
      for ns, (tot, cov) in sorted(by_ns.items())
    },
    "covered_targets": sorted(covered),
    "uncovered_targets": sorted(denom - hit),
    "invoked_unknown": unknown,
    "mk_parse_count": (len(mkparse) if mkparse is not None else None),
  }
  return "\n".join(lines), data


def coverage_markdown(data: dict) -> str:
  uncovered = ", ".join(f"`{t}`" for t in data["uncovered_targets"])
  out = [
    "# Uncovered",
    "",
    uncovered or "_none_",
    "",
    "# Overview",
    "",
    f"- suites run: `{', '.join(data['suites_run']) or 'none'}`",
    f"- covered: **{data['covered']}/{data['denominator']}** "
    f"({data['percent']}%)",
    "",
    "# Namespaces",
    "",
    "| namespace | covered | total | percent |",
    "|-----------|--------:|------:|--------:|",
  ]
  for ns, d in sorted(data["by_namespace"].items()):
    cov, tot = d["covered"], d["total"]
    pct = round(100 * cov / tot) if tot else 0
    out.append(f"| `{ns}` | {cov} | {tot} | {pct}% |")
  return "\n".join(out) + "\n"
