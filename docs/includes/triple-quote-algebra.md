{#- Reusable Triple-Quote Literals card.  Include with `{% include "includes/triple-quote-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  Covers the three triple-quoted literal forms and the two expansion layers. #}
<a name="triple-quote-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["'''@body'''", "Literal: Make expands (`${VAR}`, `$(call ..)`); the Shell layer (`$$VAR`, backtick-commands, `$$(..)`) stays verbatim"],
    ["\"\"\"@body\"\"\"", "Interpolated: the Shell layer expands too, on top of the Make layer (the backtick-delimited form is equivalent)"],
  ],
  subject='Triple-Quote Literals',
  toggle=True,
  form="'''@body'''",
  example=(cmkmath.imath("'''mk=${X}'''") | trim),
  operands='A **body of text** `@body` (a snippet or a whole program, multi-line allowed)<br>The **delimiter** you pick: `\'\'\'` literal, `\"\"\"` / ```` ``` ```` interpolating',
  properties=[
    '**Two expansion layers:** Make always expands; the delimiter chooses whether the Shell layer also expands, so singles lower to a single-quoted `printf` and doubles or backticks to a double-quoted one',
    '**Doubles and backticks are equivalent:** they interpolate identically, so pick whichever delimiter does not clash with the body',
    '**Reserved positions:** a literal on a recipe first line is a target docstring, and at column 0 a module docstring, so it is not printed there',
    '**One caveat:** the body cannot contain an internal run of three-or-more of its own delimiter character',
  ],
  badges=[
    ['literals', _ ~ '/cmk/compiler/#triple-quote-literals'],
    ['block references', _ ~ '/cmk/compiler/#block-references'],
    ['banana', _ ~ '/cmk/banana/'],
  ]
) }}
