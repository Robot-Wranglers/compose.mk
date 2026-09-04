{#- Reusable Assignment Algebra card.  Include with `{% include "includes/assignment-algebra.md" %}`;
    the parent page supplies `cmkmath` / `mkdocs` in context.  Links are absolute so it reads on
    any page.  Covers the two binds: the eager `<-` capture and the lazy `&` handle-assignment. #}
<a name="assignment-algebra"></a>
{{ cmkmath.algebra_card(
  [
    ["@x <- @rhs",     "Capture (eager): run @rhs now, bind its stdout to shell var @x; the RHS lowers first, so it may be any callform"],
    ["&@name <- @rhs", "Handle-assign (lazy): bind @rhs unrun under receiver @name; the leading `&` marks a by-reference bind and reads the line as cmk-lang"],
    ["@name(@args)",   "Call: run a bound handle bare, with no anchor; calling it is what runs the deferred RHS"],
  ],
  subject='Assignment Algebra',
  toggle=True,
  form='@x <- @rhs',
  example=(cmkmath.imath("top <- this.peek") | trim) ~ ' &nbsp;&nbsp; ' ~ (cmkmath.imath("&greet <- this.hello") | trim) ~ ' &rarr; ' ~ (cmkmath.imath("greet()") | trim),
  operands='A **shell var** `@x` or **receiver** `@name`<br>An **RHS** `@rhs` (callform / fragment)',
  properties=[
    '**Eager vs lazy:** bare `<-` captures a *value* (stdout, run now); `&` binds a *deferred call*, run later on `@name()`',
    '**`&` selects cmk-lang:** the leading `&` is what tells the compiler to read the line as cmk, not shell; a bare `greet in host.native.sh` / `out <- greet in host.native.sh` stays an ordinary shell command / capture',
    '**Fragment RHS:** under `&` the RHS may be a [fragment expression](' ~ _ ~ '/cmk/quickref/#string-algebra), operands folded left-to-right by `|` / `/` / `+` / `%`; bare `<-` leaves those as shell characters',
    '**Handle dispatch:** a handle is a [receiver](' ~ _ ~ '/cmk/concepts/#callforms), so `&name in @m` runs it in a machine and the callform channels `(args)` / `{env}` stack on the call',
  ],
  inherits=[
    ['Callform Algebra', _ ~ '/cmk/quickref/#call-forms'],
    ['String Algebra', _ ~ '/cmk/quickref/#string-algebra'],
  ],
  badges=[
    ['handles', _ ~ '/cmk/concepts/#handles'],
    ['capture', _ ~ '/cmk/compiler/#capture-operator'],
  ]
) }}
