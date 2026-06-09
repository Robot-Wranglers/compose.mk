#!/usr/bin/env -S make -f
# An implementation of Underload: a stack-based concatenative esolang
# See also: https://esolangs.org/wiki/Underload
#
# USAGE:
#   ./demos/underload.mk                                # run the demo
#   printf '(Hello, world!)S' | ./demos/underload.mk ul.eval
#   printf '(a(:^)*S):^'      | ./demos/underload.mk ul.eval     # quine

include compose.mk

# pop the top stack element as a raw string, via the stdlib io.stack.pop *macro*
# (the argless default-stack form -- inline, no `${make}` sub-make per pop).
ul.pop = `${io.stack.pop} | ${jq} -r .`

# the eight commands, as concatenative stack-targets
# Single-pop/single-use commands consume ${ul.pop} inline (it already emits the
# value, so an intermediate `x=...` shell var would be redundant). The commands
# that pop twice, or use a popped value twice, must bind it to a shell var first.
ul.swap:
	@# Swap operator:  "~"     
	@#   (x)(y) -> (y)(x)
	y=${ul.pop} ; x=${ul.pop} \
	; q="$${y}" ${make} ul.push \
	; q="$${x}" ${make} ul.push

ul.dup:
	@# Duplicate operator: ":" 
	@#   (x) -> (x)(x)
	x=${ul.pop} ; q="$${x}" ${make} ul.push ; q="$${x}" ${make} ul.push

ul.discard:
	@# Discard operator: "!" 
	@#   (x) -> nil
	${io.stack.pop}

ul.cat:
	@# Concat operator: "*" 
	@#   (x)(y) -> (xy)
	y=${ul.pop} \
	; x=${ul.pop} \
	; q="$${x}$${y}" ${make} ul.push

ul.enclose:
	@# Enclose operator: "a" 
	@#   (x) -> ((x))
	q="(${ul.pop})" ${make} ul.push

ul.print:
	@# Pop/print operator.  "S" 
	@#  (x) -> ; pop x and output it
	printf '%s' "${ul.pop}"

ul.push:
	@# Push operator (takes an argument `q`)
	@${jq} -n --arg q "$${q}" '$$q' | $(call io.stack.push)

ul.apply:; ${flux.pipeline}/ul.print,ul.eval
	@# Apply Operator:  "^" 
	@#	(x) ->         pop x and run it as Underload

# the reader: rewrite program text into the command vocabulary
define ul.decode.awk
{
  n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    if (c == "(") {                       # capture a (possibly nested) quotation
      depth = 1; body = ""
      while (++i <= n && depth > 0) {
        d = substr($0, i, 1)
        if (d == "(") depth++
        else if (d == ")") { if (--depth == 0) break }
        body = body d
      }
      print "push " body
    }
    else if (c == "~")  print "ul.swap"
    else if (c == ":")  print "ul.dup"
    else if (c == "!")  print "ul.discard"
    else if (c == "*")  print "ul.cat"
    else if (c == "a")  print "ul.enclose"
    else if (c == "^")  print "ul.apply"
    else if (c == "S")  print "ul.print"
    # any other character is a no-op (Underload ignores non-commands)
  }
}
endef

ul.decode:
	@# stdin: Underload program -> stdout: one command per line (via io.awk)
	${io.awk}/ul.decode.awk

ul.run:
	@# stdin: decoded commands -> execute each against the default stack
	@while IFS= read -r op; do \
		case "$${op}" in \
			"")      : ;; \
			push\ *) q="$${op#push }" ${make} ul.push ;; \
			*)  ${make} "$${op}" ;; \
		esac ; \
	done

ul.eval:; ${flux.pipeline}/ul.decode,ul.run
	@# Parse and run Underload program text

hello.world: io.stack.reset
	$(call log.target)
	printf '(Hello, world!)S' | ${make} ul.eval && echo

swapper: io.stack.reset
	$(call log.target)
	printf '(A)(B)~*S' | ${make} ul.eval && echo

quine: io.stack.reset
	$(call log.target)
	printf '(a(:^)*S):^' | ${make} ul.eval && echo

pquine:
	$(call log.target)
	printf '(:aS(:^S^:)Sa:):^S^:(:aS(:^S^:)Sa:)' | ${make} ul.eval && echo

factorial:
	$(call log.target)
	printf '(:::::):(:((^:()~((:)*~^)a~*^!!()~^))~*()~^^)~(^a(*~^)*a~*()~^!()~^)a~**^!!^S' \
	| ${make} ul.eval | tail -1 | ${stream.peek} | wc -c

__main__: hello.world swapper quine pquine