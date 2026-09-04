{#- Reusable Block-Reference Algebra card.  Include with `{% include "includes/blockref-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page. #}
<a name="blockref-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["⬦@NAME", "Stream FD: lower to process substitution `<(..)`, an ephemeral shell-owned handle"],
    ["⬥@NAME", "Real file: lower to a `mktemp` path, the block materialized on disk"],
  ],
  subject='Block-Reference Algebra',
  toggle=True,
  form='cmd .. ⬦@NAME .. ⬥@NAME ..',
  example=(cmkmath.imath("jq -f ⬦prog.jq") | trim),
  operands='A **define-block** `@NAME` (script, program, or query)<br>The **command** it feeds',
  properties=[
    '**Hollow vs filled:** the hollow glyph is an ephemeral stream that saves disk IO; the filled glyph is a real on-disk file, for a tool that needs a real path',
    '**Lifecycle:** the stream form is a shell-owned handle, torn down when the command exits; the file form is written fresh per evaluation into run-scoped scratch and auto-removed at the end of the run',
    '**Inert in blocks and comments:** a glyph inside a block or a comment is copied through verbatim, never rewritten',
  ],
  badges=[
    ['banana', _ ~ '/cmk/banana/#banana-forms'],
    ['literals', _ ~ '/cmk/compiler/#triple-quote-literals'],
    ['define', _ ~ '/cmk/compiler/#block-references'],
  ]
) }}
