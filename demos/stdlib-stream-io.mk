#!/usr/bin/env -S make -f
# demos/stdlib-stream-io.mk: 
#   Demonstrating a few macros for stream io.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#   USAGE: ./demos/stdlib-stream-io.mk

include compose.mk 

__main__:
	$(call log.test_case, preview results mid-pipe on stderr leaving stdout uninterrupted)
	ls README.md | ${stream.peek} > .tmp.ls.out && rm .tmp.ls.out
	ls README.md | ${stream.as.log}
	ls docs/*.md.j2 | with=45 ${stream.fold}
	
	$(call log.test_case, preview markdown with glow )
	cat README.md | ${stream.markdown}
	cat README.md | ${stream.glow}
	
	$(call log.test_case, preview an img with chafa )
	cat docs/img/icon.png | ${stream.img}
	cat docs/img/icon.png | ${stream.chafa}

	$(call log.test_case, convert spaces to new-lines (cleaner than using xargs))
	echo foo bar | ${stream.space.to.nl}

	$(call log.test_case, convert new-lines to commas (cleaner than sed))
	printf 'foo\nbar' | ${stream.nl.to.comma}
	
	$(call log.test_case, chaining streams works the way you'd expect )
	cat README.md | ${stream.glow} | ${stream.indent}