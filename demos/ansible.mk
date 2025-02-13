# demos/ansible.mk: 
#   Mad-science demo. See the docs for discussion
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/ansible.mk

# NB: this boilerplate helps to quit the default output- 
# and you'll need this whenever you want to emit JSON.
SHELL:=bash
.SHELLFLAGS:=-eu -c
MAKEFLAGS=-sS --warn-undefined-variables
.DEFAULT_GOAL := all 

include compose.mk

# Look, it's a container that has ansible, 
# and ansible has support for docker.
define Dockerfile.Ansible.base
FROM ubuntu:20.04
RUN apt-get update
RUN apt-get install -y ansible make 
RUN apt-get install -y python3-pip
RUN pip3 install docker
endef

# Look, it's a simple ansible playbook 
define Ansible.playbook
- name: Example Playbook with Debug Task
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Print a debug message
      debug:
        msg: "Hello, this is a debug message!"
endef

# Default entrypoint 
all: demo.playbook demo.adhoc 

demo.playbook: docker.from.def/Ansible.base
	@# Top-level entrypoint for the playbook demo.
	@# The prerequisite target `docker.from.def/Ansible.base` above ensures the image is ready.
	@# The next line specifies the target to run inside the container
	img=compose.mk:Ansible.base ${make} docker.run/self.demo.playbook

self.demo.playbook:
	@# This target runs inside the `Ansible.base` container described earlier, 
	@# so now the ansible CLI is available.  First we write the `Ansible.playbook` 
	@# def above as a tmpfile, and call ansible, ensuring JSON oputput.
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/Ansible.playbook/$${tmpf} \
	&& ANSIBLE_STDOUT_CALLBACK=json \
	ansible-playbook -i localhost, -c local $${tmpf}

demo.adhoc: demo.adhoc/ping demo.adhoc/docker_host_info
demo.adhoc/%: docker.from.def/Ansible.base
	@#
	img=compose.mk:Ansible.base ${make} docker.run/self.demo.adhoc/${*}
self.demo.adhoc/%:
	@# This target runs inside the `Ansible.base` container described earlier, 
	@# so now ansible is available.  First we write the playbook as a tmpfile, 
	@# then we invoke it and ensure JSON oputput.
	ANSIBLE_LOAD_CALLBACK_PLUGINS=true \
	ANSIBLE_STDOUT_CALLBACK=json \
	ansible all -m${*} -i localhost, -c local
