#!/usr/bin/env -S make -f
# demos/lean-2.mk: 
#   A variation on `lean.mk` leaning into a more compressed 
#   and idiomatic style, treating foreign code as first class.
#
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#   See also: http://robot-wranglers.github.io/compose.mk/demos/lean
#             http://robot-wranglers.github.io/compose.mk/demos/polyglots
#   USAGE: ./demos/lean.mk
#

include compose.mk
.DEFAULT_GOAL := __main__

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
define script
def main : IO Unit := IO.println "Hello, world!"
endef

# Look, it's a theorem we might want to prove
# https://leanprover-community.github.io/logic_and_proof/classical_reasoning.html
# https://lean-lang.org/theorem_proving_in_lean4/propositions_and_proofs.html
define theorem 
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

# Bind code objects to interpreters.  
# This creates `script.run` and `theorem.run`.
$(eval $(call compose.import.code_block, theorem, lean.run.theorem))
$(eval $(call compose.import.code_block, script, lean.run.script))

# Default entrypoint. Ensures container is built, then tests a script and a theorem
__main__: docker.from.def/Lean.base script.run theorem.run

# Top level helper to run the given target in the base-container
# Plus bonus syntactic sugar for cleaning up dispatch invocations
lean/%:; img=Lean.base ${mk.docker.dispatch}/${*}
lean.dispatch=${make} lean

# Top-level helpers to dispatch to the "private" ones running in container
lean.run.script/%:; ${lean.dispatch}/self.run.script/${*} 
lean.run.theorem/%:; ${lean.dispatch}/self.run.theorem/${*}

# Private targets. These run in the base container,
# so using lean or lake from here directly is safe.
self.run.script/%:
	$(call log.file.preview, ${*})
	source ~/.profile && set -x && lean --run ${*}

self.run.theorem/%:
	$(call log.file.preview, ${*})
	source ~/.profile && set -x && lean ${*}
