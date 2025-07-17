#!/usr/bin/env -S make -f
# Building a custom automation API with `compose.mk`.  
# Here we build a wrapper around a containerized ansible, 
# exposing a new, opinionated interface that is is versioned,
# slim, stateless, and defaults to JSON IO.
#
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# USAGE: ./demos/ansible-adhoc.mk

include compose.mk

export ANSIBLE_LOAD_CALLBACK_PLUGINS=true 
export ANSIBLE_STDOUT_CALLBACK=json

# Look, it's a container that has ansible & ansible has support for docker.
# Could do this with an external Dockerfile or docker-compose file, 
# but for simplicity it's embedded.
define Dockerfile.Ansible
FROM ${IMG_DEBIAN_BASE:-debian:bookworm-slim}
RUN apt-get update -qq && apt-get install -qq -y jq make bash procps
RUN apt-get install -qq -y ansible python3-pip
RUN pip3 install -q docker --break-system-packages
endef

# Let's build a bridge to expose adhoc ansible[1].
# This declares a top-level target `ansible.adhoc` that takes one parameter,
# which is the name of the ansible module to call.  We mention the prereq
# target `Dockerfile.build/Ansible`, which ensures that the container 
# described above is ready.  This target runs on the host, so we don't 
# actually have access to ansible here, and so this target dispatches 
# to a private target defined at `self.ansible.adhoc/<module_name>`.
#
# [1] https://docs.ansible.com/ansible/latest/command_guide/intro_adhoc.html
ansible.adhoc/%:
	img=compose.mk:Ansible \
	${make} docker.dispatch/self.ansible.adhoc/${*} 

# This target runs inside the ansible base container defined above,
# and calls ansible in a way that ensures JSON output.  Optionally, 
# you can pass additional ansible in an environment variable.
# Once ansible returns output, we unpack the interesting part of 
# the JSON data in the last step before we return it.  
self.ansible.adhoc/%:
	ansible all -m${*} -i localhost, -c local $${ansible_args:-} \
	| ${jq} .plays[0].tasks[0].hosts.localhost

# Based on the work above, we've already got a fairly 
# complete map from ansible-modules to make-targets.  
# For example `make ansible.adhoc/ping` already works 
# like you'd expect to call the ping-module [2].  
#
# [2] https://docs.ansible.com/ansible/2.8/modules/ping_module.html

# But some modules take arguments.  Let's setup a way to pass those in.
# Ansible accepts JSON or `key=val` style data for this using `--args`. 
# The `ansible.adhoc` target is somewhat prepared for this, so we just 
# need a way to set stuff in the `ansible_args` environment variable, 
# and we need that var passed through to docker.
ansible.adhoc.pipe/%:
	export ansible_args="--args `${stream.stdin}`" \
	&& env=ansible_args ${make} ansible.adhoc/${*}

# Putting it all together, here's a simple new target for 
# the verb 'list_images'.  This returns the currently available
# docker images by using Ansible's `docker_image_info` module[3] 
# and calling it with the `timeout=60` flag.
#
# [3] https://docs.ansible.com/ansible/2.8/modules/docker_image_info_module.html
list_images:
	${jb} timeout=60 \
	| ${make} ansible.adhoc.pipe/docker_image_info \
	| ${jq} -r '.images[].RepoTags[0]' 

# Main entrypoint. 
# Exercise a few possibilities for our new custom automation API.
__main__: Dockerfile.build/Ansible ansible.adhoc/ping list_images
