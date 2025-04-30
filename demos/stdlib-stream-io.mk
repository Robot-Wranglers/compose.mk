#!/usr/bin/env -S make -f
# demos/stdlib-stream-io.mk: 
#   Demonstrating a few macros for stream io.  Most of these are also available as targets.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
#
# USAGE: ./demos/stdlib-stream-io.mk

include compose.mk 

__main__:
	$(call log.test, preview results mid-pipe on stderr leaving stdout uninterrupted)
	ls README.md | ${stream.peek} > .tmp.ls.out && rm .tmp.ls.out
	ls README.md | ${stream.as.log}
	
	$(call log.test, preview markdown with glow )
	cat README.md | ${stream.markdown}
	cat README.md | ${stream.glow}
	
	$(call log.test, preview an img with chafa )
	cat docs/img/icon.png | ${stream.img}
	cat docs/img/icon.png | ${stream.chafa}
	
	$(call log.test, convert spaces to new-lines)
	echo foo bar | ${stream.space.to.nl}
	$(call log.test, convert new-lines to spaces)
	printf 'foo bar' | ${stream.nl.to.space}
	$(call log.test, convert new-lines to commas)
	printf 'foo\nbar' | ${stream.nl.to.comma}
	$(call log.test, add line numbers to input)
	printf 'foo\nbar' | ${stream.nl.enum}
	
	$(call log.test, syntax highlight yaml)
	printf 'foo: bar' | ${stream.yaml.pygmentize}
	$(call log.test, syntax highlight csv)
	printf 'foo, bar' | ${stream.csv.pygmentize}
	
	$(call log.test, fold long lines)
	ls docs/*.md.j2 | width=45 ${stream.fold}
	
	$(call log.test, chaining streams works the way you'd expect )
	cat README.md | ${stream.glow} | ${stream.indent}