#!/usr/bin/env -S make -f

# dockerfs.mk: files bound to an image build, written out as plain make (needs docker)

# The cmk twin is demos/cmk/dockerfs.cmk; its chain spelling is sugar for the receiver call below.

# USAGE: ./demos/dockerfs.mk

include compose.mk

# Intent only: the greeter script and its config arrive from the bound files below.
define greeter_img
FROM alpine:3.21
RUN apk add --no-cache jq
ENTRYPOINT ["/usr/local/bin/greet"]
endef
$(call cmk.Dockerfile, def=greeter_img)

# An executable: mode=+x, and the shell dollars reach the image unmangled.
define greet
#!/bin/sh
who=$(jq -r .who /etc/greeter.json)
punct=$(jq -r .punct /etc/greeter.json)
echo "hello, ${who}${punct} (from $(uname -s), pid $$)"
endef
$(call cmk.dockerfs, def=greet bind=greeter_img path=/usr/local/bin/greet mode=+x)

# Data alongside it: same binding, different mode.
define greet_conf
{"who": "dockerfs", "punct": "!"}
endef
$(call cmk.dockerfs, def=greet_conf bind=greeter_img path=/etc/greeter.json mode=0644)

# The second image binds through its own member instead of naming itself in every file.
define motd_img
FROM alpine:3.21
ENTRYPOINT ["/usr/local/bin/motd"]
endef
$(call cmk.Dockerfile, def=motd_img)

define motd_sh
#!/bin/sh
cat /etc/motd.txt
endef
$(call motd_img.dockerfs, def=motd_sh path=/usr/local/bin/motd mode=+x)

define motd_txt
bound by a receiver call, landed by the same fold
endef
$(call motd_img.dockerfs, def=motd_txt path=/etc/motd.txt mode=0644)

# The machine that runs the built image, so a call reaches the bound entrypoint.
define greeter
img=compose.mk:greeter_img
endef
$(call cmk.container, def=greeter)

# The same image with the entrypoint overridden, for looking at what landed.
define greeter_cat
img=compose.mk:greeter_img entrypoint=cat
endef
$(call cmk.container, def=greeter_cat)

# The second image, to show both bindings land the same way.
define motd
img=${motd_img.img}
endef
$(call cmk.container, def=motd)

demo.render:
	@# Show the folded recipe without building: base line first, then the injected copy and chmod pairs.
	$(call log, ${bold}rendered Dockerfile${no_ansi} (bound files folded in):)
	${make} greeter_img.render

demo.build:
	@# Build the image, which materializes both bound files into a private context.
	$(call log, ${bold}building${no_ansi} compose.mk:greeter_img)
	${make} greeter_img.build

demo.run:
	@# Run the entrypoint the bound files supplied, then read the bound config back out.
	$(call log, ${bold}entrypoint${no_ansi} (the +x bound file):)
	$(call greeter.__call__)
	$(call log, ${bold}config${no_ansi} (the 0644 bound file, as it landed):)
	$(call greeter_cat.__call__,/etc/greeter.json)

demo.member:
	@# Build and run the image whose files were bound through its own member.
	$(call log, ${bold}receiver call${no_ansi} (same fold, no bind= repeated):)
	${make} motd_img.build
	$(call motd.__call__)

__main__: demo.render demo.build demo.run demo.member
