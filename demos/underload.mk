#!/usr/bin/env -S make -f
# Implementing one esolang with another ;)
# This is an interpreter/compiler for "Underload", which is a
# stack-based concatenative esolang.  See also [1]
#
# USAGE:
#   ./demos/underload.mk
#   printf '(Hello, world!)S' | ./demos/underload.mk ul.eval
#   printf '(a(:^)*S):^'      | ./demos/underload.mk ul.eval
#
# REFS:
#   [1]: https://esolangs.org/wiki/Underload

include compose.mk

# A lexer for underload lang, in awk.  
# Rewrites source text into the command vocabulary.
define ul.lexer
{ n = length($0)
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1)
    # capture a (possibly nested) quotation
    if (c == "(") {
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
    # any other character is a no-op
  }
}
endef

# A few sample programs we can test the interpreter with.
# A quine, how quaint.  A palindromic quine, even more fun.
# An (abstracted) `factorial` function.. note that all the 
# args have to be encoded/prepended
define underload_quine
(a(:^)*S):^
endef
define underload_quine_palindromic
(:aS(:^S^:)Sa:):^S^:(:aS(:^S^:)Sa:)
endef
define underload_factorial_fxn
(:((^:()~((:)*~^)a~*^!!()~^))~*()~^^)~(^a(*~^)*a~*()~^!()~^)a~**^!!^S
endef

# Underload push/pop helpers.
# Just a thin layer on top of native compose.mk support.
# See also: the docs for `io.stack.*`
ul.pop  = `${io.stack.pop.word}`
ul.push = ${jq} -n 'env.q' | ${io.stack.push}
ul.push/%:; q="${*}" ${ul.push}
ul.push/:;  q="" ${ul.push}

# Begin main underload command vocabulary.
# Backend implementation for what the lexer generates
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

ul.lex: io.awk/ul.lexer
	@# Read underload program from stdin, 
	@# return one dispatchable goal per line

ul.eval: flux.pipeline/ul.lex,mk.kernel.each
	@# Parse / run Underload program text.
	@# The decoded program is a stream of goals in the form of
	@# operators + `ul.push/<literal>`.  We pipe this to
	@# `mk.kernel.each` is the engine to dispatches each

underload:
	@# The underload "VM".  This helper runs a
	@# program from stdin with some pretty-printing.
	tmp="`${stream.stdin}`" && $(call log.target,$${tmp}) \
	&& printf "$${tmp}" | ${make} ul.eval && echo

# Begin demos: sample programs + kicking off the interpreter

hello.world: io.print.banner/hello.world io.stack.reset
	printf '(Hello, world!)S' | ${make} underload

swapper: io.print.banner/swapper io.stack.reset
	printf '(A)(B)~*S' | ${make} underload

quine: io.print.banner/quine io.stack.reset
	printf '${underload_quine}' | ${make} underload

quine.palindromic: io.print.banner/quine.palindromic io.stack.reset
	printf '${underload_quine_palindromic}' | ${make} underload

factorial/%:
	@# Generic access to the underload function.
	@# Underload's factorial function only accepts and 
	@# returns *unary* arguments!  To use it, we have to 
	@# encode and decode that detail.. that's the extra
	@# boilerplate you can see with `wc` / `yes` 
	$(call log.target, calculating ${*}! ..)
	arg="`yes ':' | head -n${*} | tr -d '\n'`" \
	&& prog="($${arg}):${underload_factorial_fxn}" \
	&& printf "$${prog}" | ${make} ul.eval \
		| tail -1 | wc -c

factorial: io.print.banner/factorial io.stack.reset factorial/4

__main__: hello.world swapper quine quine.palindromic factorial