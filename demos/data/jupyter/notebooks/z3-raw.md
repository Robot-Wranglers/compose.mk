---
jupyter:
  jupytext:
    cell_markers: region,endregion
    formats: ipynb,md
    notebook_metadata_filter: language_info,nbconvert_exporter,pygments_lexer
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: z3
    language: scheme
    name: kernel.z3
  language_info:
    name: scheme
    pygments_lexer: scheme
---

## Raw Z3
---------------------

See also:
* De Morgans law proof from [wikipedia](https://en.wikipedia.org/wiki/Z3_Theorem_Prover#Propositional_and_predicate_logic)

Note: *Success here is 'unsat'

---------------------


```scheme
(declare-fun a () Bool)
(declare-fun b () Bool)
(assert (not (= (not (and a b)) (or (not a)(not b)))))
(check-sat)
```
