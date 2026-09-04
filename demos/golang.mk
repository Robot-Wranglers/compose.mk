#!/usr/bin/env -S make -f
# golang.mk: inline Go cross-build; classic-make twin of golang.cmk.

include compose.mk
$(call include.plugins, dsl.golang.cmk)

define golang
package main
import ("fmt"; "os")
func main() {
  who := "world"
  if len(os.Args) > 1 { who = os.Args[1] }
  fmt.Println("hi " + who + "!")
}
endef

# a hand-written go.mod, to override the generated default
define gomod
module greeter
go 1.24
endef

# run + argv targets over the inline Go.
golang:; $(call code.compiled.lambda, lang=dsl.golang src=golang)
golang/%:; $(call code.compiled.lambda, lang=dsl.golang src=golang args=$*)
# run.custom: build with the hand-written go.mod (mod= override).
run.custom:; $(call code.compiled.lambda, lang=dsl.golang src=golang mod=gomod)

__main__: golang golang/you run.custom
