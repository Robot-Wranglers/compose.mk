#!/usr/bin/env -S make -f
#
# stdlib-stream-io.mk:
#   A guided tour of the `stream.*` standard library: small, composable
#   filters for stdin->stdout pipelines -- delimiter conversion,
#   line-numbering, folding, indenting, previews, and syntax-highlighting.
#   Each target is also exposed as a `${stream.*}` macro, which reads
#   tidier and saves a process versus a recursive `make` call.  Several
#   helpers have aliases (noted inline); only one of each pair is shown
#   here.
#
# USAGE: ./demos/stdlib-stream-io.mk

include compose.mk

__main__:
	@# --- delimiter conversions: reshape a flat list between separators
	@# ----------
	$(call log.io, space-delimited  ->  newline-delimited)
	echo foo bar baz | ${stream.space.to.nl}
	$(call log.io, newline-delimited  ->  space-delimited)
	printf 'foo\nbar\nbaz' | ${stream.nl.to.space}
	$(call log.io, newline-delimited  ->  comma-delimited)
	printf 'foo\nbar\nbaz' | ${stream.nl.to.comma}

	@# --- shaping text: number lines, fold long ones, indent
	@# --------------------
	$(call log.io, prefix each line with its index)
	printf 'first\nsecond' | ${stream.nl.enum}
	$(call log.io, fold long lines to a fixed width)
	ls docs/*.md.j2 | width=45 ${stream.fold}
	$(call log.io, indent every line)
	printf 'a\nb' | ${stream.indent}

	@# --- previews: inspect a stream without disturbing the pipe
	@# ---------------- `stream.peek` (alias: stream.as.log) tees its input to
	@# stderr and passes stdout through untouched -- handy for debugging
	@# mid-pipeline.
	$(call log.io, peek at a stream mid-pipe -- stdout is unchanged)
	ls README.md | ${stream.peek} > /dev/null
	@# `stream.markdown` (alias: stream.glow) renders Markdown; `stream.img`
	@# (alias: stream.chafa) renders an image -- both dockerized, no host
	@# install.
	$(call log.io, render markdown / preview an image in the terminal)
	cat README.md | ${stream.markdown}
	cat docs/img/icon.png | ${stream.img}

	@# --- syntax highlighting
	@# ---------------------------------------------------
	$(call log.io, colorize yaml / csv)
	printf 'foo: bar' | ${stream.yaml.pygmentize}
	printf 'foo, bar' | ${stream.csv.pygmentize}

	@# --- composition: stream filters chain like any unix pipe
	@# ------------------
	$(call log.io, chain helpers -- render markdown, then indent the result)
	cat README.md | ${stream.glow} | ${stream.indent}
