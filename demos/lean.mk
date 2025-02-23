# demos/lean.mk: 
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   See the docs for more discussion: https://robot-wranglers.github.io/compose.mk/demos/polyglots
#
#   USAGE: make -f demos/lean.mk
#
.DEFAULT_GOAL := demo.lean

include compose.mk

# Look, it's a minimal Dockerfile for running lean4 
# See also: https://leanprover-community.github.io/install/debian.html
define Dockerfile.Lean.base
FROM debian:bookworm
SHELL ["/bin/bash", "-x", "-c"] 
RUN apt-get update
RUN apt-get install -y git make curl sudo
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf > /usr/local/bin/elan-init.sh
RUN bash /usr/local/bin/elan-init.sh -y 
RUN cp /root/.elan/bin/lean /usr/local/bin 
RUN cp /root/.elan/bin/lake /usr/local/bin 
ENV PATH="$PATH:/root/.elan/bin/"
RUN lean --help
RUN lake new default
RUN cd default && printf '[[require]]\nname = "mathlib"\nscope = "leanprover-community"' >> lakefile.toml
RUN cd default && lake update && lake build
endef

# Look, it's hello-world in scriptwise lean-lang
# https://lean-lang.org/functional_programming_in_lean/hello-world/running-a-program.html
define Lean.script
def main : IO Unit := IO.println "Hello, world!"
endef

# Look, it's a theorem we might want to prove
# https://leanprover-community.github.io/logic_and_proof/classical_reasoning.html
# https://lean-lang.org/theorem_proving_in_lean4/propositions_and_proofs.html
define Lean.theorem 
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
# Ensure the container is built, then dispatch a script there
demo.lean: 
	# Slow build, so default silence is disabled by setting val for `quiet`.
	# Pass `force=` to override cache, or `trace=1 for more info
	quiet=0 ${make} docker.from.def/Lean.base 
	${make} lean.run.script/Lean.script
	${make} lean.run.theorem/Lean.theorem

# Top level helper to run the named target inside the base-container
lean/%: 
	img=compose.mk:Lean.base ${make} docker.run/${*}

# Top-level helper to write embedded-script to disk before we use them
lean.run.script/%:
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/${*}/$${tmpf} \
	&& ${make} lean/self.lean.run.script/$${tmpf}

lean.run.theorem/%:
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/${*}/$${tmpf} \
	&& ${make} lean/self.lean.run.file/$${tmpf}

# Private target; this actually runs *inside* the container so using `lake` directly is safe.
self.lean.run.script/%:
	$(call log.file.preview,${*})
	source ~/.profile && set -x && lean --run ${*}

self.lean.run.file/%:
	$(call log.file.preview,${*})
	source ~/.profile && set -x && lean ${*}