---
jupyter:
  jupytext:
    formats: ipynb,md
    notebook_metadata_filter: language_info
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: lean4
    language: python
    name: kernel.lean4
  language_info:
    name: python
    pygments_lexer: lean
---

## Demo: Lean Theorems

----------

Law of the excluded middle in lean4.  

See also:

  * [Classical reasoning](https://leanprover-community.github.io/logic_and_proof/classical_reasoning.html)
  * [Propositions and proofs](https://lean-lang.org/theorem_proving_in_lean4/propositions_and_proofs.html)

*Note: success is quiet here*

-------------------

```python
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
```
