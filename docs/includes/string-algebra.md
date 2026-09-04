{#- Reusable String Algebra card.  Include with `{% include "includes/string-algebra.md" %}`. #}
<a name="string-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["(|@a|) + (|@b|)",  "Concat: join the two bodies into one block (newline-joined)"],
    ["(|@a|) (|@b|)",    "Juxtaposition: the same concat, written with no operator"],
    ["(|@a|) % (|@kw|)", "Fill: substitute the `@@hole@@`s in the left body from the kwargs block"],
  ],
  subject='String Algebra',
  toggle=True,
  form='(| @a |) + (| @b |)',
  example=(cmkmath.imath("(| foo |) + (| bar |)") | trim),
  operands='**Block bodies** `(| .. |)` (verbatim, untyped source)',
  properties=[
    '**Closed:** the result is itself a block, so it composes again, and fills chain left-to-right',
    '**Addition is juxtaposition:** both forms concatenate; there is no separate juxtaposition operator',
    '**Templating:** the fill operator substitutes the holes in the left body from a keyword block, and a subclass can change the hole syntax',
    '**Nothing runs:** a pure block is text; concatenation and fill produce blocks, never effects, until you give it a machine to execute in',
    '**Untyped otherwise:** only concatenation and fill are defined; typed operations belong to a [DSL](' ~ _ ~ '/cmk/concepts/#dsls)',
  ],
  badges=[
    ['banana blocks', _ ~ '/cmk/banana/'],
    ['DSL', _ ~ '/cmk/concepts/#dsls'],
  ]
) }}
