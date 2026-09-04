{#- Reusable Callform Algebra card.  Include with `{% include "includes/callform-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page. #}
<a name="callform-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["@call(@a,@b)", "Args: positional, or `k=v` kwargs for a macro"],
    ["@call[@S]",    "Stream: pipe @S in as stdin"],
    ["@call{e=v}",   "Env: prefix the command's environment"],
  ],
  subject='Callform Algebra',
  toggle=True,
  collapsed=callform_collapsed|default(false),
  form='@anchor.@name(@args)[@stream]{@env}',
  example=(cmkmath.imath("`cmk.f`(@a,@b)[@S]{e=v}") | trim) ~ ' &rarr; ' ~ (cmkmath.imath("@S | e='v' `$(call f,a,b)`") | trim),
  operands='A **target** (`this.`)<br>A **macro** (`cmk.`)<br>A **receiver** (anchorless declared name)',
  properties=[
    '**Order-invariant:** the channels may be given in any order',
    '**Duals:** the stream channel pipes stdin in; the env channel prefixes the environment',
    '**Module scope:** the env channel is recipe-only (reserved, and warns at module scope)',
  ],
  badges=[
    ['banana blocks', _ ~ '/cmk/banana/#banana-channels'],
    ['streams', _ ~ '/cmk/compiler/#triple-quote-literals'],
    ['handles', _ ~ '/cmk/concepts/#handles'],
  ]
) }}
