
# snippet derived from tests/Makefile.mad-science.mk
MAKEFLAGS=-s -S --warn-undefined-variables
include compose.mk


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
#   $(call io.mktemp) \
#   && make mk.def.to.file/Ansible.example_playbook/$${tmpf} \
#   && entrypoint=ansible-playbook \
#       cmd="-i localhost, $${tmpf}" \
#           make xxxxx/ansible