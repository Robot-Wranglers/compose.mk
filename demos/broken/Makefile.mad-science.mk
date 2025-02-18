##
# Exercising 'mk.def.dispatch' and friends for bad ideas.  
#
# Have you ever wondered if you could implement make targets in other languages?  
# The answer is yes.
#
# USAGE: ( from project root)
#   $ make mad
#
##
SHELL := bash
MAKEFLAGS=-sS --warn-undefined-variables
.SHELLFLAGS := -eu -c

include compose.mk

.DEFAULT_GOAL := all 
all: demo.elixir demo.dockerfile demo.python demo.python.pipes

###############################################################################

# Minimal boilerplate for working with elixir-lang.  
# This picks an image for the language kernel 
# allowing overrides from the environment, 
# then runs a script with it.

export IMG_ELIXIR?=elixir:otp-27-alpine

demo.elixir:
	img=$${IMG_ELIXIR} \
	entrypoint=elixir \
	def=Elixir.hello_world \
	make docker.run.def

define Elixir.hello_world 
import IO, only: [puts: 1]
puts("elixir World!")
System.halt(0)
endef 

###############################################################################

## Inlined Docker Files

# Minimal inlined dockerfile.  
# You can install anything or nothing here, 
# but let's have the minimal stuff required for target dispatch.
define Dockerfile.demo_dockerfile
FROM alpine
RUN echo building container spec from inlined dockerfile
RUN apk add --update --no-cache coreutils alpine-sdk bash procps-ng
endef


# Wrapper target that's using the container.
# This sets the container-build as a pre-req, so that
# within the body we can assume the base image exists.
demo.dockerfile: docker.from.def/demo_dockerfile
	# Working with the image directly, note the 'compose.mk' prefix.
	docker image inspect compose.mk:demo_dockerfile > /dev/null
	docker run -it --entrypoint sh compose.mk:demo_dockerfile -x -c "true" > /dev/null
	
	# Working with compose.mk builtins omits prefix, 
	# and can do dispatch targets to run inside the new image
	img=demo_dockerfile make mk.docker.run/self.demo.dockerfile
	
	# Add the prefix explicitly, and you can use `docker.run` instead of private `.docker.run`
	img=compose.mk:demo_dockerfile make docker.run/self.demo.dockerfile
	entrypoint=sh cmd='-c "ls"' img=compose.mk:demo_dockerfile make docker.run.sh 
	# Subsequent runs will use the cached image.  
	# Pass 'force' to work around this.
	force=1 make docker.from.def/demo_dockerfile

self.demo.dockerfile:
	echo "Testing target from inside the inlined-container"
	uname -a

###############################################################################

## Local Interpretters, Without a Container

# Look, here's a simple python script 
define Python.demo
import sys
print('python world')
print('dollarsigns are safe: $')
endef

# Minimal boilerplate to run the script,
# using a specific interpretter (python3).
# No container here, so this requires that 
# the interpretter is actually available.
demo.python:
	make mk.def.dispatch/python3/Python.demo


###############################################################################

## Exotic Targets & Pipes

# A more complex python script, 
# testing comments, indention, & using pipes
define Python.demo.python.pipes
# python script
import sys, json
input = json.loads(sys.stdin.read())
input.update(hello_python=sys.platform)
output = input
print(json.dumps(output))
for x in [1, 2, 3]:
  msg=f"{x} testing loops, indents, string interpolation"
  print(msg, file=sys.stderr)
endef

# Runs the script, passing data into the pipe
demo.python.pipes:
	echo '{"hello":"bash"}' \
	| make mk.def.dispatch/python3/Python.${@}

###############################################################################

### Passing Data Structures to Externally Managed Containers

# Look, it's a simple ansible playbook 
define Ansible.example_playbook
- name: Example Playbook with Debug Task
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Print a debug message
      debug:
        msg: "Hello, this is a debug message!"
endef

# Writes the playbook to a temp file,
# then runs it from inside the 'ansible' container
# demo.ansible.playbook: 
# 	$(call io.mktemp) \
# 	&& make mk.def.to.file/Ansible.example_playbook/$${tmpf} \
# 	&& entrypoint=ansible-playbook \
# 		cmd="-i localhost, $${tmpf}" \
# 			make xxxxx/ansible

test.mk.let:
	./compose.mk mk.let/foo:flux.ok mk.let/bar:foo bar

