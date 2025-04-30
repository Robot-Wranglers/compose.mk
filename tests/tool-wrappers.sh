#!/usr/bin/env -S bash -x -euo pipefail
# tests/tool-wrappers.sh:
#   Exercise some of the tool-wrappers that are part of stand-alone mode.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.
#
# USAGE: bash -x tests/tool-wrappers.sh

# Use `stream.chafa` to preview an image on the console with chafa
cat docs/img/icon.png | ./compose.mk stream.chafa

# Use `stream.chafa` to preview an image on the console with chafa (alternate)
cat docs/img/icon.png | ./compose.mk stream.img.preview

# preview image without streams
./compose.mk io.preview.img/docs/img/icon.png

# preview multiple images
find docs/img/icon.png | ./compose.mk flux.each/io.preview.img

# Use `stream.glow` to preview markdown
cat README.md | ./compose.mk stream.glow

# Use `stream.glow` to preview markdown (alternate)
cat README.md | ./compose.mk stream.markdown

# Use `stream.pygmentize` to syntax-highlight code with pygments (guess lexer, default style)
cat Makefile | ./compose.mk stream.pygmentize

# Use `stream.pygmentize` to syntax-highlight code with pygments (explicit lexer)
cat Makefile | lexer=Makefile ./compose.mk stream.pygmentize 

# Use `stream.pygmentize` to syntax-highlight code with pygments (explicit style and lexer)
cat Makefile | style=monokai lexer=Makefile ./compose.mk stream.pygmentize 

# # Use `stream.json.pygmentize` to preview JSON (minified)
./compose.mk jb key=val | ./compose.mk stream.json.pygmentize

# Use `stream.json.pygmentize` to preview JSON (expanded)
./compose.mk jb key=val | ./compose.mk jq . | ./compose.mk stream.json.pygmentize

# Use `stream.peek` to preview data somewhere in the middle of a pipe and pass it on
./compose.mk jb key=val | ./compose.mk stream.peek | ./compose.mk jq .

# Pull data from yaml with yq
echo 'one: two' | ./compose.mk yq .one

