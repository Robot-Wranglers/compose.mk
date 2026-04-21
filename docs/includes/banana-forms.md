### Banana Forms {: #banana-forms}
<hr style="width:100%;border-bottom:3px solid black;">


The <a href="{{_}}/cmk/banana">banana block</a> <code>NAME(| body |)</code> is a native, generic *declare*: it keeps a body (a script, a Dockerfile, a jq program, a class body) in source and hands it to a **constructor** named as a leading word (<code>C NAME(| .. |)</code>, or a leading dotpath).  A block takes at most one block-trailer, or the stacking <a href="{{_}}/cmk/quickref/#call-forms">callform channels</a>.  The forms split by scope into the two sections below.  Full family, with a demo per idiom, on the <a href="{{_}}/cmk/banana">Banana Blocks</a> page.

{% include "includes/banana-algebra.md" %}

#### Module-Scoped
<hr style="width:95%;border-bottom:1px dashed black;margin-top:4px;">

*Declarations, parsed at compile time.*

**{{ cmkmath.imath("@NAME {| body |}") }}:** custom treatment assigned by the `block_brackets` pragma.
> `note{| freeform text |}`

<a name="recipe-scoped"></a>
{% include "includes/banana-recipes.md" %}
