# demos/lean.mk: 
#   lean4
#   This demo ships with the `compose.mk` repository and runs as part of the test-suite.  
#
#   USAGE: make -f demos/lean.mk
#
.DEFAULT_GOAL := demo.lean

include compose.mk

# See also: https://leanprover-community.github.io/install/debian.html
define Dockerfile.Lean.base
FROM debian:bookworm
SHELL ["/bin/bash", "-x", "-c"] 
RUN apt-get update
RUN apt-get install -y git make curl sudo
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf > /usr/local/bin/elan-init.sh
RUN bash /usr/local/bin/elan-init.sh -y 
RUN /root/.elan/bin/lean --help
RUN /root/.elan/bin/lake new default
RUN cd default && printf '[[require]]\nname = "mathlib"\nscope = "leanprover-community"' >> lakefile.toml
RUN cd default &&  /root/.elan/bin/lake update && /root/.elan/bin/lake build
endef

# Look, it's hello-world in lean-lang
# https://lean-lang.org/functional_programming_in_lean/hello-world/running-a-program.html
define Lean.script
def main : IO Unit := IO.println "Hello, world!"
endef

# Law of the excluded middle in lean4
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

# Default entrypoint 
# demo.lean: lean.run.def/Lean.script 
demo.lean: lean.run.def/Lean.script

lean.run.target/%: docker.from.def/Lean.base
	img=compose.mk:Lean.base ${make} docker.run/${*}

lean.run.def/%:
	$(call io.mktemp) \
	&& ${make} mk.def.to.file/${*}/$${tmpf} \
	&& ${make} lean.run.target/self.lean.run.file/$${tmpf}

self.lean.run.file/%:
	source ~/.profile && cd /default && lake env lean /workspace/${*}
