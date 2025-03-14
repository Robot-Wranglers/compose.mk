#!/usr/bin/env -S make -f
# demos/lean.mk: 
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#   See also: http://robot-wranglers.github.io/compose.mk/demos/lean
#             http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   USAGE: ./demos/lean.mk
#
.DEFAULT_GOAL := demo.lean

include compose.mk

# Look, it's a minimal Dockerfile for running lean4 
# See also: https://leanprover-community.github.io/install/debian.html
define Dockerfile.Lean.base
FROM ${IMG_DEBIAN_BASE:-debian:bookworm-slim}
SHELL ["/bin/bash", "-x", "-c"]
RUN apt-get -qq update && apt-get install -qq -y git make curl sudo procps
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf > /usr/local/bin/elan-init.sh
RUN bash /usr/local/bin/elan-init.sh -y 
RUN cp /root/.elan/bin/lean /usr/local/bin 
RUN cp /root/.elan/bin/lake /usr/local/bin 
ENV PATH="$PATH:/root/.elan/bin/"
RUN lean --help
RUN lake new default
RUN cd default && printf '[[require]]\nname = "mathlib"\nscope = "leanprover-community"' >> lakefile.toml
RUN cd default && lake update && lake build
RUN lean --version
endef

# Look, it's hello-world in scriptwise lean-lang
# https://lean-lang.org/functional_programming_in_lean/hello-world/running-a-program.html
define Code.lean.script
def main : IO Unit := IO.println "Hello, world!"
endef

# Look, it's a theorem we might want to prove
# https://leanprover-community.github.io/logic_and_proof/classical_reasoning.html
# https://lean-lang.org/theorem_proving_in_lean4/propositions_and_proofs.html
define Code.lean.theorem 
section
open Classical
example : A ∨ ¬ A := by
  apply byContradiction
  intro (h1 : ¬ (A ∨ ¬ A))
  have h2 : ¬ A := by
    intro (h3 : A)
    have h4 : A ∨ ¬ A := Or.inl h3
    show False
    exact h1 h4
  have h5 : A ∨ ¬ A := Or.inr h2
  show False
  exact h1 h5
end
endef

# Default entrypoint.  
# Ensure the container is built, then test a script and a theorem
demo.lean: lean.init \
	lean.run.script/Code.lean.script \
	lean.run.theorem/Code.lean.theorem

# Slow build, so default silence is disabled by setting val for `quiet`.
# This caches the 2nd time it runs.  Pass `force=1` to override cache, 
# or pass `trace=1 for more info.  
lean.init: docker.from.def/Lean.base 

# Top level helper to run the named target in the base-container
lean/%:; img=Lean.base ${make} mk.docker.dispatch/${*}

# Top-level helpers to write embedded-scripts to disk before use
lean.run.script/%:
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/${*}/$${tmpf} \
	&& ${make} lean/self.run.script/$${tmpf}
lean.run.theorem/%:
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/${*}/$${tmpf} \
	&& ${make} lean/self.run.file/$${tmpf}

# Private targets. These run in the base container,
# so using lean or lake from here directly is safe.
self.run.script/%:
	$(call log.file.preview,${*})
	source ~/.profile && set -x && lean --run ${*}
self.run.file/%:
	$(call log.file.preview,${*})
	source ~/.profile && set -x && lean ${*}
