# demos/stdlib-stream-io.mk: 
#   Demonstrating a few macros for stream io.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/stdlib-stream-io.mk

.DEFAULT_GOAL := demo.streams 

include compose.mk 

demo.streams:
	# preview results mid-pipe on stderr, leaving stdout uninterrupted
	ls | ${stream.peek} > .tmp.ls.out
	
	# preview markdown with glow 
	cat README.md | ${stream.markdown}
	cat README.md | ${stream.glow}
	
	# preview an img with chafa 
	cat docs/img/icon.png | ${stream.img}
	cat docs/img/icon.png | ${stream.chafa}

	# convert spaces to new-lines (cleaner than using xargs)
	echo foo bar | ${stream.space.to.nl}
	
	# convert new-lines to commas (cleaner than sed)
	printf 'foo\nbar' | ${stream.nl.to.comma}
	
	# chaining streams works the way you'd expect 
	cat README.md | ${stream.glow} | ${stream.indent}