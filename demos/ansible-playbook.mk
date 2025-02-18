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
	img=compose.mk:Ansible.base ${make} docker.run/self.demo.playbook

self.demo.playbook:
	@# This target runs inside the `Ansible.base` container described above, 
	@# so now the ansible CLI is available.  First we write the `Ansible.playbook` 
	@# def above as a tmpfile, and call ansible, ensuring JSON oputput.
	$(call io.mktemp) \
	&& $(call log, ${GLYPH_IO} ${dim_green} Running playbook:) \
	&& ${make} mk.def.read/Ansible.playbook | ${stream.peek} > $${tmpf} \
	&& ANSIBLE_STDOUT_CALLBACK=json \
	ansible-playbook -i localhost, -c local $${tmpf} \
	&& $(call log, ${GLYPH_IO} ${dim_green} Playbook finished.) 
	