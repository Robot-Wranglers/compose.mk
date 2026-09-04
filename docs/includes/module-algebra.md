{#- Reusable Module Algebra card.  Include with `{% include "includes/module-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  First pass: the import spine + the open / in operators over a module. #}
<a name="module-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["module @NAME [|body|]", "Declare: create a module from the body (a dedented, reusable block)"],
    ["#open @M",              "Open: dissolve M's members flat into the current scope"],
    ["@X #in @M",             "Exec: run @X with M in scope (a module is Runnable)"],
  ],
  library_calls=[
    ["`import.module`(def=@N)", "Stage a namespaced copy of an inline block, members into scope"],
    ["`import.module`(file=@f)", "Import an existing file instead (its basename names it)"],
    ["`import.module`(def=@N namespace=@ns)", "Rename the member prefix on import (source name stays @CMK_MODULE)"],
    ["`import.module`(def=@N flat=1)", "Dissolve into the global namespace, un-prefixed (this is a plugin)"],
    ["`import.module`(def=@N targets=@glob)", "Partial import by glob (or defs=@glob), mutually exclusive"],
    ["`import.module`(def=@N preprocs=@p)", "Run the body through a compile pipeline before include"],
    ["@N`.import`(namespace=@ns)", "Instance-method spelling on a `module` decl: its own .import, def=@N implied"],
  ],
  subject='Module Algebra',
  toggle=True,
  form='import.module(def=@NAME namespace=@ns preprocs=@p)',
  example=(cmkmath.imath("@MyModule [| .. |]") | trim) ~ ' &rarr; ' ~ (cmkmath.imath("`import.module`(def=@MyModule)") | trim),
  operands='A **module body** `@NAME [| .. |]` (inline block or `file=`)<br>An **import pipeline** (namespace / selectors / preprocs)',
  properties=[
    '**Copy-on-import:** the source is never mutated; a namespaced, optionally-compiled copy is staged',
    '**Polymorphic:** one body, many mountings: flat, namespaced, partial, or compiled',
    '**Isomorphic:** plugin, module, and namespace are one mechanism, differing only by pipeline',
    '**Dual-nature:** a module is both importable and runnable, like a script with a main entry',
  ],
  inherits=[
    ['Ambient Algebra', _ ~ '/cmk/concepts/#ambient-algebra'],
    ['Banana Algebra', _ ~ '/cmk/banana/#banana-algebra'],
  ],
  badges=[
    ['namespace', _ ~ '/cmk/concepts/#namespaces'],
  ]
) }}
