#!/usr/bin/env -S make -f
# An implementation of Underload: a stack-based concatenative esolang
# See also: https://esolangs.org/wiki/Underload
#
# USAGE:
#   ./demos/underload.mk                                # run the demo
#   printf '(Hello, world!)S' | ./demos/underload.mk ul.eval
#   printf '(a(:^)*S):^'      | ./demos/underload.mk ul.eval     # quine

include compose.mk

# pop the top element as a raw word, and push the literal in env `q`: both are
# stdlib io.stack.* *macros* (argless default-stack forms), composed inline so a
# program runs without spawning a `${make}` for any stack op. `q="..."` is read
# by the leading jq, so the env-prefix form `q="x" ${ul.push}` works directly.
ul.pop  = `${io.stack.pop.word}`
ul.push = ${jq} -n 'env.q' | ${io.stack.push}

# `ul.push/<literal>` is the dispatch form the decoder emits for a quotation, so
# the whole decoded program is just goals (run by mk.kernel.each). It feeds the
# literal to the push macro; the operators below use ${ul.push} inline instead,
# for computed values, so they never pay a sub-make. The empty quotation `()`
# decodes to a bare `ul.push/` (empty stem, which `%` can't match), so it gets
# its own literal target.
ul.push/%:; q="${*}" ${ul.push}
ul.push/:;  q="" ${ul.push}

# the eight commands, as concatenative stack-targets
# Single-pop/single-use commands consume ${ul.pop} inline (it already emits the
# value, so an intermediate `x=...` shell var would be redundant). The commands
# that pop twice, or use a popped value twice, must bind it to a shell var first.
ul.swap:
	@# Swap operator:  "~"     
	@#   (x)(y) -> (y)(x)
	y=${ul.pop} ; x=${ul.pop} \
	; q="$${y}" ${ul.push} \
	; q="$${x}" ${ul.push}

ul.dup:
	@# Duplicate operator: ":" 
	@#   (x) -> (x)(x)
	x=${ul.pop} ; q="$${x}" ${ul.push} ; q="$${x}" ${ul.push}

ul.discard: io.stack.discard
	@# Discard operator: "!"
	@#   (x) -> nil

ul.cat:
	@# Concat operator: "*" 
	@#   (x)(y) -> (xy)
	y=${ul.pop} \
	; x=${ul.pop} \
	; q="$${x}$${y}" ${ul.push}

ul.enclose:
	@# Enclose operator: "a" 
	@#   (x) -> ((x))
	q="(${ul.pop})" ${ul.push}

ul.print:
	@# Pop/print operator.  "S" 
	@#  (x) -> ; pop x and output it
	printf '%s' "${ul.pop}"

ul.apply: flux.pipeline/ul.print,ul.eval
	@# Apply Operator:  "^" 
	@#	(x) ->         pop x and run it as Underload

# the reader: rewrite program text into the command vocabulary
define ul.lexer
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
      print "ul.push/" body
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

ul.decode: io.awk/ul.lexer
	@# stdin: Underload program -> stdout: one dispatchable goal per line (io.awk)

ul.eval: flux.pipeline/ul.decode,mk.kernel.each
	@# Parse and run Underload program text.  The decoded program is a stream of
	@# goals (operators + `ul.push/<literal>`); `mk.kernel.each` is the engine that
	@# dispatches each, in order, re-running repeats (cf. `mk.kernel`, which would
	@# dedup them).

hello.world: io.stack.reset
	$(call log.target)
	printf '(Hello, world!)S' | ${make} ul.eval && echo

swapper: io.stack.reset
	$(call log.target)
	printf '(A)(B)~*S' | ${make} ul.eval && echo

quine: io.stack.reset
	$(call log.target)
	printf '(a(:^)*S):^' | ${make} ul.eval && echo

quine.palindrome:
	$(call log.target)
	printf '(:aS(:^S^:)Sa:):^S^:(:aS(:^S^:)Sa:)' | ${make} ul.eval && echo

factorial:
	$(call log.target)
	printf '(:::::):(:((^:()~((:)*~^)a~*^!!()~^))~*()~^^)~(^a(*~^)*a~*()~^!()~^)a~**^!!^S' \
	| ${make} ul.eval | tail -1 | ${stream.peek} | wc -c

__main__: hello.world swapper quine quine.palindrome