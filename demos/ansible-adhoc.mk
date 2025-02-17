# demos/ansible-adhoc.mk: 
#   Mad-science demo. See the docs for discussion
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/ansible-adhoc.mk

.DEFAULT_GOAL := demo.adhoc 
# NB: this boilerplate helps to quit the default output- 
# and you'll need this whenever you want to emit JSON.
MAKEFLAGS=-sS --warn-undefined-variables
include compose.mk

# Look, it's a container that has ansible & ansible has support for docker.
# Could do this with a docker-compose file instead, for simplicity it's embedded.
define Dockerfile.Ansible.base
FROM debian:bookworm
RUN apt-get update
RUN apt-get install -y jq ansible make 
RUN apt-get install -y python3-pip
RUN pip3 install docker --break-system-packages
endef

# Let's build a bridge to expose adhoc ansible[1].
# This declares a top-level target `ansible.adhoc` that takes one parameter,
# which is the name of the ansible module to call.  We mention the prereq
# target `docker.from.def/Ansible.base`, which ensures that the container 
# described above is ready.  This target runs on the host, so we don't actually 
# have access to ansible here, and so this target dispatches to the private target 
# defined at `self.ansible.adhoc/<module_name>`.
#
# [1] https://docs.ansible.com/ansible/latest/command_guide/intro_adhoc.html
ansible.adhoc/%: docker.from.def/Ansible.base
	img=compose.mk:Ansible.base \
	${make} docker.run/self.ansible.adhoc/${*} 

# This target runs inside the ansible base container defined above,
# and calls ansible in a way that ensures JSON output.  Optionally, 
# you can pass additional ansible in an environment variable.
# Once ansible returns output, we unpack the interesting part of 
# the JSON data in the last step before we return it.  
self.ansible.adhoc/%:
	ANSIBLE_LOAD_CALLBACK_PLUGINS=true ANSIBLE_STDOUT_CALLBACK=json \
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
# The `ansible.adhoc` target is somewhat prepared for this so we just 
# need a way to set stuff in the `ansible_args` environment variable, 
# and we need that var passed through to docker.
ansible.adhoc.pipe/%:
	export ansible_args="--args `cat /dev/stdin`" \
	&& env=ansible_args ${make} ansible.adhoc/${*}

# Another way to call the parametric target, accepting argument from env-variable
ansible.adhoc.pipe:
	${make} ansible.adhoc.pipe/$${module}

# Putting it all together, here's a simple new target for the verb 'list_images'.
# This returns the currently available docker images by using Ansible's 
# `docker_host_info` module[3] and calling it with the `images=yes` flag.
#
# [3] https://docs.ansible.com/ansible/2.8/modules/docker_host_info_module.html
list_images:
	echo images=yes | ${make} ansible.adhoc.pipe/docker_host_info | ${jq} .images

# Main entrypoint, this exercises a few possibilities for our new custom automation API.
demo.adhoc: ansible.adhoc/ping list_images
