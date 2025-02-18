#!/usr/bin/env -S bash -x -euo pipefail

# Use `stream.chafa` to preview an image on the console with chafa
cat docs/img/icon.png | ./compose.mk stream.chafa

# Use `stream.chafa` to preview an image on the console with chafa (alternate)
cat docs/img/icon.png | ./compose.mk stream.img.preview

# Use `stream.glow` to preview markdown
cat README.md | ./compose.mk stream.glow

# Use `stream.glow` to preview markdown (alternate)
cat README.md | ./compose.mk stream.markdown

# Use `stream.pygmentize` to syntax-highlight code with pygments (guess lexer)
cat Makefile | ./compose.mk stream.pygmentize

# Use `stream.pygmentize` to syntax-highlight code with pygments (explicit lexer)
cat Makefile | lexer=Makefile ./compose.mk stream.pygmentize 

# # Use `stream.json.pygmentize` to preview JSON (minified)
./compose.mk jb key=val | ./compose.mk stream.json.pygmentize

# # Use `stream.json.pygmentize` to preview JSON (expanded)
# ./compose.mk jb key=val | ./compose.mk jq . | ./compose.mk stream.json.pygmentize

# # Use `stream.peek` to preview data somewhere in the middle of a pipe and pass it on
# ./compose.mk jb key=val | ./compose.mk stream.peek > /tmp/tmp.stream.out
