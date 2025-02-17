# demos/app.mk: 
#   Demonstrates building a highly customized and self-contained console application,
#   where all the application components bootstrap themselves on demand.
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   This defines/embeds two containers, one for the lean4 theorem prover[1] and one for alloylang[2].
#
#   Since there's no official docker images available, we have to provision containers from 
#   scratch, but using the ideas from `demos/makeception.mk`, we will build them in-situ and 
#   defer to `make` itself for the provisioning details.
#
#   USAGE: make -f demos/app.mk


include compose.mk
.DEFAULT_GOAL := demo.entry
export BUILD_TARGET?=none

demo.entry: demo.provision demo.dispatch 

# Look it's an embedded compose file.  This defines services `alice` & `bob`.
define proof.services
services:
  lean4: &base
    hostname: lean4
    build:
      context: .
      dockerfile_inline: |
        FROM debian/buildd:bookworm
        RUN apt-get update 
        COPY . /app
        RUN cd /app && make -f ${MAKEFILE} ${BUILD_TARGET}
    working_dir: /workspace
    volumes:
      - ${PWD}:/workspace
  alloy:
    build: https://github.com/elo-enterprises/docker-alloy-cli.git
    hostname: alloy
endef 

# Describe a lakefile for lean.  
# We need this later so we can declare requirements.
define lean.lakefile 
[[require]]
name = "mathlib"
scope = "leanprover-community"
endef

# Autogenerate target scaffolding for each service.
$(eval $(call compose.import.def,  ▰,  TRUE, proof.services))

demo.provision:
	#BUILD_TARGET=lean4.provision ${make} lean4/build 
	BUILD_TARGET=alloy.provision ${make} alloy/build 

lean4.provision:
	apt-get install -y git curl sudo
	curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf > /usr/local/bin/elan-init.sh
	bash /usr/local/bin/elan-init.sh -y 
	/root/.elan/bin/lean --help
	/root/.elan/bin/lake new default
	printf '[[require]]\nname = "mathlib"\nscope = "leanprover-community"' >> default/lakefile.toml
	cd default &&  /root/.elan/bin/lake update && /root/.elan/bin/lake build

#${make} mk.def.read/lean.lakefile > default/lakefile.toml

alloy.provision: 
	echo hello world 
# apt-get install -y gcc g++ openjdk-17-jdk-headless git tree
#COPY . /opt/alloy-cli
# RUN cd /opt/alloy-cli && bash ./gradlew distTar && tar -xvf ./build/distributions/alloy-cli.tar
# RUN echo '#!/bin/bash' > /bin/alloy-run && echo 'exec /opt/alloy-cli/alloy-cli/bin/alloy-cli "$@"' >> /bin/alloy-run
# RUN chmod o+x /bin/alloy-run
# ENTRYPOINT ["/bin/alloy-run"]
demo.dispatch: #▰/alice/internal_task ▰/bob/internal_task
internal_task:; echo "Running inside `hostname`"; echo "Special tools available: `which figlet || which ack`"
