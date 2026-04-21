{#- Reusable Language protocol card.  Include with `{% include "includes/language-protocol.md" %}`;
    the parent page supplies `macros` (import of `macros/base.j2`), `mkdocs`, and `_` in context.
    Set `card_open = true` before the include to start the card expanded (default: collapsed).
    Links are absolute so it reads on any page. #}
{{ macros.protocol('Language', open=(card_open if card_open is defined else false),
  capability='Structural reflection over a fragment\'s own symbols, blocks, and tokens.',
  requires='`__symbols__`', tier='Concretized',
  surface='A `.__symbols__` method plus `.__blocks__` / `.__tokens__`, driven by a `.__lang__` matcher property.',
  notes='`__symbols__()` gives the names and arities a fragment defines, `__blocks__()` its balanced brace-blocks, `__tokens__()` the remainder. Keyed off a `.__lang__` matcher naming the guest grammar. Mix it into a [`dsl`](' ~ _ ~ '/cmk/concepts/#dsls) or language kind via `bases=` / `ifaces=`; a fragment is its own source, so the verbs take no name argument.',
  mkdocs=mkdocs) }}
