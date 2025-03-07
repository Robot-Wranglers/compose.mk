# demos/etl-img.mk:
#   Describes an image pipeline with `compose.mk`.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/etl-img.mk 

# Squash the default noisy output, include compose.mk primitives
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := etl
include compose.mk

# Setup a default docker image and tag for imagemagick tool container
imagemagick_tag=dpokidov/imagemagick:latest

# Now the extract-task will kick off the pipeline by just injecting any image.
extract:
	cat docs/img/icon.png

# Helper that creates an "API" over the tool container with a parametric target.
# This is basically a partial-function, allowing us to drill down to what entrypoint
# docker will use.
imagemagick/%:
	entrypoint=${*} ./compose.mk docker.run.image/${imagemagick_tag}

# Use the generic API to make an alias for something concrete:
# This fixes both the image *and* the entrypoint, but still defers
# to callers for deciding the exact command to pass.
convert: imagemagick/convert
	
# Back to the ETL, now our transform-task is ready to stream stdin
# into the dockerized `convert` tool.  We need to pass it some kind of 
# instruction in the `cmd` variable, so we just use imagemagick's own 
# syntax for "convert the png on stdin to a jpeg on stdout".
transform: 
	cat /dev/stdin | cmd="png:- jpg:-" ${make} convert
	
# For the "load" part of the ETL, we could do something else with imagemagick, 
# but let's make it interesting and preview the jpeg in the terminal. 
# This is actually a one-liner and requires no fancy dependencies!  
# Under the hood, `stream.img.preview` target uses a dockerized `chafa`.
load: stream.img.preview

# One last thing: since this pipeline is using images, 
# we need to stop `flux.pipeline` from showing us the 
# intermediate stages, or else we'll just get binary data.  
# Using `flux.pipeline.quiet` defaults to no previews.
etl: flux.pipeline.quiet/extract,transform,load