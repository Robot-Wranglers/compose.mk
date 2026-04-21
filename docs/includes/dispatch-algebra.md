{#- Reusable Dispatch & Structure card.  Include with `{% include "includes/dispatch-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  Covers the dispatch / import / decorator operators plus the two structural
    facts (recipe-body joining, indentation). #}
<a name="dispatch-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["@svc ᐉ @target",  "Dispatch: run @target inside container @svc (a reparse; the container may expose different targets than the launch context)"],
    ["@name(@args)",    "Import: the bare-call form of an import statement (`compose.import`, `code`, `import.def`, ...)"],
    ["`@`@deco(@args)", "Decorate: a bind-declaration (decorator) above a target"],
  ],
  subject='Dispatch & Structure',
  toggle=True,
  form='@svc ᐉ @target',
  example=(cmkmath.imath("web ᐉ build") | trim),
  operands='A **service / container** `@svc`<br>A **target** `@target`',
  properties=[
    '**Reparse:** container dispatch reparses in the target context and costs a process/container; the container may expose *different targets* than the launch context',
    '**Recipe body:** recipe lines join into one shell with `&&` (fail-fast, shared state)',
    '**Indentation:** bodies may be indented with tabs *or* spaces (python-style); mixed or mismatched indentation is an error',
  ],
  badges=[
    ['dialects', _ ~ '/cmk/metaprogramming/#dialects'],
    ['modules', _ ~ '/cmk/modules/#module-algebra'],
    ['decorators', _ ~ '/cmk/compiler/#bind-declarations'],
  ]
) }}
