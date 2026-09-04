{#- Reusable Banana Recipes card.  Include with `{% include "includes/banana-recipes.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  Sibling of banana-algebra: that card is the whole family; this one is the
    recipe-scoped operators (capture, concat, the ambient moves), each with its example. #}
<a name="banana-recipes"></a>
{{ cmkmath.algebra_card(
  [
    ["@L <- (|..|)",   "Capture: run the block, capture its stdout into recipe var @L", "who <- (| id -un |)"],
    ["(|@a|) + (|@b|)", "Concat: outputs join under a capture; uncaptured it is an inert string (an error alone on a recipe line)", "all <- (| echo a |) + (| echo b |)"],
    ["(|..|) #in @X",  "Mobility: run the block-machine in ambient @X, one of container / interpreter / host", "(| pip install -r reqs.txt |) in host.native.python"],
    ["(|..|) #out",    "Escape: run in the enclosing (host) ambient, escaping a container", "(| docker ps |) out"],
  ],
  subject='Banana Recipes',
  toggle=True,
  form='(| body |)',
  example=(cmkmath.imath('(| echo hi |) #in host.native.sh') | trim),
  operands='A **block** `(| .. |)` (a raw string until attached)<br>An **ambient** `@X` (moved by `in` / `out`)',
  properties=[
    '**Recipe-time:** every form here runs when the recipe runs (the module-scoped block-declares are compile-time by contrast)',
    '**Ambient-mobile:** `in` / `out` move the block-machine between execution contexts under the [mobile-ambient calculus](' ~ _ ~ '/cmk/concepts/#ambients)',
    '**Composable dataflow:** under a `<-` capture, `+` sequences bodies and joins their output; a pipe lives *inside* one banana (`(| a | b |)`), and the final stdout feeds the capture',
  ],
  badges=[
    ['callform', _ ~ '/cmk/quickref/#call-forms'],
    ['ambient', _ ~ '/cmk/concepts/#ambients'],
    ['machine', _ ~ '/cmk/concepts/#machines'],
    ['capture', _ ~ '/cmk/compiler/#capture-operator'],
  ]
) }}
