{#- Reusable Ambient Algebra card.  Include with `{% include "includes/ambient-algebra.md" %}`.
    Links are absolute so it reads on any page. #}
<a name="ambient-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["(|@p|) #in @m",   "Run @p inside the ambient @m"],
    ["(|@p|) #out",     "Escape to the enclosing (host) ambient"],
    ["#open @m",        "Dissolve module/namespace @m into the current scope"],
    ["#open #cmk",      "Bind the prelude keywords bare"],
    ["*(|@a|)",         "Dissolve the block @a in place (the star form)"],
    ["(|@a|) + (|@b|)", "Sequence @a then @b (concatenate the bodies)"],
  ],
  subject='Ambient Algebra',
  toggle=True,
  form='(| @p |) #in @m',
  example=(cmkmath.imath("(| pip list |) #in #bash") | trim),
  operands='A **block** `(| .. |)`<br>An **ambient** `@m` (machine / namespace / module)',
  properties=[
    '**Duality:** entering an ambient names a destination; leaving is its dual, moving one level out',
    '**Concatenation is inherited:** Addition / Juxtaposition / Concatenation live in String Algebra',
  ],
  inherits=[
    ['String Algebra', _ ~ '/cmk/quickref/#string-algebra'],
  ],
  badges=[
    ['machine', _ ~ '/cmk/concepts/#machines'],
    ['namespace', _ ~ '/cmk/concepts/#namespaces'],
    ['DSL', _ ~ '/cmk/concepts/#dsls'],
  ]
) }}
