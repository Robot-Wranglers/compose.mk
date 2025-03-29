#!/usr/bin/env -S make -f
# demos/lean.mk: 
#   This example shows an embedded container with a lean+mathlib container, 
#   plus enough glue code for dispatch so that we can abstract away the container usage.
#   Included is a script and a theorem that we'll test with, but of course external files 
#   are supported as well.
#
# This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/lean
#           http://robot-wranglers.github.io/compose.mk/demos/polyglots
#
# USAGE: ./demos/lean.mk

include compose.mk

# Look, it's a minimal Dockerfile for running lean4 
# See also: https://leanprover-community.github.io/install/debian.html
define Dockerfile.Lean
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
ENTRYPOINT ["lean"]
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

# Main entrypoint.  Ensures the container is ready, 
# then dispatches execution of both script and theorem
__main__: Dockerfile.build/Lean lean.run.script/script lean.run.theorem/theorem

# Top-level helpers. 
# These write embedded script/theorem to disk before use, 
# run them inside the container, and clean up afterwards.
lean.run.script/%:; lean_args="--run" ${make} lean.run.generic/${*}
lean.run.generic/% lean.run.theorem/%:
	${io.mktemp} && ${make} mk.def.to.file/${*}/$${tmpf} \
	&& img=Lean cmd="$${lean_args:-} $${tmpf}" \
      ${make} mk.docker

# io.tempfile=$(call io.mktemp)