---
jupyter:
  jupytext:
    formats: ipynb,md
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: alloy
    language: ''
    name: kernel.alloy
---

## Alloy Lang (solvable)
----------------------
* knights puzzle: https://www.hillelwayne.com/post/knights-knaves/
* headless alloy analyzer that returns JSON: ..
-------------------

```python

abstract sig Person {}

sig Knight extends Person {}
sig Knave extends Person {}

pred Puzzle {
  #Person = 2
  some disj A, B :Person {
    A in Knight <=> (A + B) in Knave
  }
}

run Puzzle for 10
```
