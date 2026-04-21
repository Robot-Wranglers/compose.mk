{#- Reusable Banana Algebra card.  Include with `{% include "includes/banana-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  First pass: distills the banana-forms operator grid into the standard card shape. #}
<a name="banana-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["(|@body|)",       "Quote: a raw block, interior inert (a template / quasi-quote)"],
    ["[|@body|]",       "Deep-cook: treat the interior as live CMK-Lang (eval-all)"],
    ["(|@body|)!",      "Shallow-cook: lower this body's callforms, leave a nested block raw"],
    ["@ctor @NAME (|..|)", "Construct: hand the body to constructor @ctor (a leading word or dotpath)"],
    ["@NAME (|@A|)(|@B|)", "Curry: hand several block bodies to one constructor"],
    ["(|@a|) + (|@b|)", "Concat: outputs join under a capture (uncaptured is an inert string)"],
    ["(|..|) #in @X",   "Mobility: run the block-machine in ambient @X (container / interpreter / host)"],
    ["(|..|) #out",     "Escape: run in the enclosing (host) ambient"],
    ["@L <- (|..|)",    "Capture: run the block, capture its stdout into recipe var @L"],
  ],
  subject='Banana Algebra',
  toggle=True,
  form='@ctor @NAME (| body |)',
  example=(cmkmath.imath("code @greet (| echo hi |)") | trim),
  operands='A **block** `(| .. |)` (raw source, interior lazy)<br>A **constructor** `@ctor` (a word or dotpath on the body)',
  properties=[
    '**Closed:** every result is itself a block, so the operators compose again',
    '**Cook axis:** a block can stay quoted (interior inert), be cooked (interior treated as live CMK-Lang), or cooked shallowly; the distinction is *when the interior wakes*',
    '**Scope-split:** construction, currying, and cooking are module-scoped; capture and the ambient moves are [recipe-scoped](' ~ _ ~ '/cmk/quickref/#banana-recipes)',
    '**Concatenation is inherited:** it lives in String Algebra; the typed pipe belongs to a [DSL](' ~ _ ~ '/cmk/concepts/#dsls), not a raw block',
  ],
  inherits=[
    ['String Algebra', _ ~ '/cmk/quickref/#string-algebra'],
    ['Callform Algebra', _ ~ '/cmk/quickref/#call-forms'],
  ],
  badges=[
    ['ambient', _ ~ '/cmk/concepts/#ambients'],
    ['machine', _ ~ '/cmk/concepts/#machines'],
    ['module', _ ~ '/cmk/modules/#module-algebra'],
  ]
) }}
