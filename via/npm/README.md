# via/npm — install compose.mk on your PATH (via npm)

A tiny npm packaging shim that installs the repo-root `compose.mk` as an executable on your `PATH`. 

## Install

From a checkout of this repo:

```bash
# global `compose.mk` on PATH
$ npm install -g ./via/npm        
```

## Use after install

```bash
compose.mk flux.ok                 # tool mode
compose.mk mk.interpret! foo.cmk   # run a .cmk anywhere (CMK_SUPERVISOR=1)
```
In a project Makefile (library mode):

```make
include $(shell which compose.mk)
```