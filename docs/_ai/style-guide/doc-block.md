# Doc-block section style (compose.mk engine sections)

House style for a `compose.mk` engine section: a fenced header **box** carrying a
bulleted `::` catalog of the section's members, followed by the bare member
definitions. This is iterating — update this file as the style evolves.

## Exemplar (the `lang.dsl` section)

```make
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
## BEGIN: lang.dsl :: A class backed by a runtime / machine / entrypoint
##
## A dsl is a class whose instances carry a runtime backing.
##
## * lang.dsl! :: Kind verb / metaclassing.
##     Binds child `dsl <name>` into caller scope, and `dsl.<name>` scope.
## * lang.dsl.__new__ :: Allocate fragment, pass to initialize
## * lang.dsl.__init__ :: Initialize runtime from { machine | entrypoint | img }
##
## * lang.dsl.machine.proxy :: Runtime half of a machine-backed dsl.
##     A bound machine (.__in__) runs the shape as a def through machine-dispatch
##     (args as argv). A bare bound target runs it as a file.  Shared by the
##     fragment call/stream dunders.
##░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

lang.dsl! = ...

lang.dsl.__new__ = ...

lang.dsl.__init__ = ...

lang.dsl.machine.proxy = ...
```

Other sections in this style: `lang.module`, `lang.proto`, `lang.banana`.

## Rules

### Header box
- The header (title + framing + catalog) is fenced top and bottom by a full-width
  `##░░░…` divider. No blank line inside the fences.
- Title: `## BEGIN: <ns> :: <Capitalized title / slash / separated>`. Separator is
  ` :: ` (never `--`; `/` separates terms in the title).
- An optional one-sentence framing line under the title. Do **not** write the word
  "Members".
- **No `## END:` marker.** A section ends where the next section's opening `##░░░`
  divider begins — that divider is the segue. Members hang between this header's
  closing divider and the next section's opening one.

### Catalog entries
- `## * <full.member.name> :: <description>` — single-space bullet `* `, the FULL
  member name (not the leaf), ` :: ` separator.
- **Construction trio leads, in fixed order.** A kind section's construction members
  come first as one group, always ordered `<ns>! :: … / <ns>.__new__ :: … /
  <ns>.__init__ :: …` (verb, allocate, initialize — the Python `__new__`/`__init__`
  order, with the factory verb ahead of both). This fixed order overrides the
  one-liner-before-multi-liner grouping *within the trio* (the verb may be a
  multi-liner sitting above one-liner `__new__`/`__init__`); the grouping rule still
  governs the remaining members below. A section without a verb (e.g. `lang.proto`)
  just leads with `__new__` then `__init__`.
- **One-liners and multi-liners do not mix**: group all one-liners together, then a
  blank `##` line, then the multi-liners.
- One-liner: the whole description fits after `::` on the line.
- Multi-liner: `::` may carry an optional one-line summary, then the detail wraps on
  the following lines indented `##` + 5 spaces (`##     …`).
- `:: FIXME` is an acceptable stub when the description isn't written yet.

### Body (member definitions)
- No inline `#` comments in the body — all prose lives in the catalog.
- Members appear in the same order as the catalog: the construction trio (`<ns>!`,
  `<ns>.__new__`, `<ns>.__init__`) leads the body, then the rest.
- One blank line between members, EXCEPT tightly-coupled members may be grouped with
  no blank (e.g. the `lang.proto` metaclass members `registry` / `provided_by` /
  `__new__` / `__init__` sit as one packed block, set off by a blank from the seed-body
  `define`s below).

### Prose
- No `--` in the catalog/framing prose (join with `:` / `,` / `;`). The ` :: ` is the
  label separator; the `/` is the title term separator.
