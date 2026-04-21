#!/usr/bin/env -S make -f
# j2-templating.mk: jinja via dsl; twin of j2-templating.cmk.

include compose.mk

define Dockerfile.jinjanator
FROM python:3.11-slim-bookworm
RUN pip install jinjanator --break-system-packages
endef

define hello_template.j2
{% for i in range(3) %}
hello {{name}}! ( {{loop.index}} )
{% endfor %}
endef

define bye_template.j2
bye {{name}}!
endef

# create the jinja dsl kind + a fragment per template (both self-eval).
$(call cmk.dsl, def=jinja img=compose.mk:jinjanator entrypoint=jinjanate cmd=--quiet flag=-fjson feed=flag)
$(call jinja, def=hello_template.j2)
$(call jinja, def=bye_template.j2)

__main__: Dockerfile.build/jinjanator
	@# build, then feed JSON into each template fragment
	$(call io.json_builder,name=foo) | $(hello_template.j2.__call__)
	$(call io.json_builder,name=foo) | $(bye_template.j2.__call__)
