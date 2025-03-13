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
    display_name: z3_py
    language: ''
    name: kernel.z3_py
---

## Z3 Demo (with python bindings)
-------------------

Examples from:

* [socrates @ z3 official](https://github.com/Z3Prover/z3/blob/master/examples/python/socrates.py)
* [8 queens @ philzooks](https://github.com/philzook58/z3_tutorial/blob/master/Z3%20Tutorial.ipynb)
-------------------


```python
from z3 import *

Object = DeclareSort("Object")
Human = Function("Human", Object, BoolSort())
Mortal = Function("Mortal", Object, BoolSort())

# a well known philosopher
socrates = Const("socrates", Object)

# free variables used in forall must be declared Const in python
x = Const("x", Object)

axioms = [ForAll([x], Implies(Human(x), Mortal(x))), Human(socrates)]
s = Solver()
s.add(axioms)

# prints sat so axioms are coherent
print(s.check())

# classical refutation
s.add(Not(Mortal(socrates)))

# prints unsat so socrates is Mortal
print(s.check())
```


```python
from z3 import *

# 8 queens
# We know each queen must be in a different row.
# So, we represent each queen by a single integer: the column position
Q = [Int(f"Q_{row + 1}") for row in range(8)]

# Each queen is in a column {1, ... 8 }
val_c = [And(1 <= Q[row], Q[row] <= 8) for row in range(8)]

# At most one queen per column
col_c = [Distinct(Q)]

# Diagonal constraint
diag_c = [
    If(i == j, True, And(Q[i] - Q[j] != i - j, Q[i] - Q[j] != j - i))
    for i in range(8)
    for j in range(i)
]

solve(val_c + col_c + diag_c)
```
