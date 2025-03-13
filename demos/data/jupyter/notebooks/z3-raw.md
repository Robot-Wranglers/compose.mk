---
jupyter:
  jupytext:
    cell_markers: region,endregion
    formats: ipynb,md
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: z3
    language: z3
    name: kernel.z3
---

## Raw Z3
---------------------

See also:
* De Morgans law proof from [wikipedia](https://en.wikipedia.org/wiki/Z3_Theorem_Prover#Propositional_and_predicate_logic)

Note: *Success here is 'unsat'
---------------------


```z3
(declare-fun a () Bool)
(declare-fun b () Bool)
(assert (not (= (not (and a b)) (or (not a)(not b)))))
(check-sat)
```
