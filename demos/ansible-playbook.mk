# demos/ansible-playbook.mk: 
#   Demonstrates passing embedded-data into an embedded-container.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/ansible-playbook.mk

include compose.mk
.DEFAULT_GOAL := demo.playbook


# Look, it's a container that has Ansible.
define Dockerfile.Ansible.base
FROM debian:bookworm
RUN apt-get update
RUN apt-get install -y ansible make procps
endef

# Look, it's a simple Ansible playbook 
define Ansible.playbook
- name: Example Playbook with Debug Task
  hosts: localhost
  gather_facts: no
  tasks:
    - name: Print a debug message
      debug:
        msg: "Hello, this is a debug message!"
endef

demo.playbook: docker.from.def/Ansible.base
	@# Top-level entrypoint for the playbook demo.
	@# The prerequisite target `docker.from.def/Ansible.base` above ensures the image is ready.
	@# The next line specifies the target to run inside the container
	img=compose.mk:Ansible.base ${make} docker.run/self.playbook_runner/Ansible.playbook

self.playbook_runner/%:
	@# We only run on the `Ansible.playbook` def, but multiple playbooks are possible so 
	@# this target accepts the name of the define as a parameter.  Since runner runs inside
	@# the `Ansible.base` container described above, now the ansible CLI is available.  
	@# First we write the `Ansible.playbook` def above as a tmpfile, then call ansible, 
	@# ensuring JSON oputput.
	$(call io.mktemp) \
	&& $(call log, ${GLYPH_IO} ${dim_green} Running playbook:) \
	&& ${make} mk.def.read/${*} | ${stream.peek} > $${tmpf} \
	&& ANSIBLE_STDOUT_CALLBACK=json \
	ansible-playbook -i localhost, -c local $${tmpf} \
	&& $(call log, ${GLYPH_IO} ${dim_green} Playbook finished.) 
	