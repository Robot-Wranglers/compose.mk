#!/usr/bin/env -S make -f
# rust.mk: inline Rust cross-build; classic-make twin of rust.cmk.

include compose.mk
$(call include.plugins, dsl.rust.cmk)

define my_rust
fn main() {
  let who = std::env::args().nth(1).unwrap_or("world".to_string());
  println!("hi {}!", who);
}
endef

# a hand-written Cargo.toml, to override the generated default
define cargotoml
[package]
name = "greeter"
version = "0.1.0"
edition = "2021"
endef

# run + argv targets over the inline Rust.
my_rust:; $(call code.compiled.lambda, lang=dsl.rust src=my_rust)
my_rust/%:; $(call code.compiled.lambda, lang=dsl.rust src=my_rust args=$*)
# run.custom: build with the hand-written Cargo.toml (cargo=).
run.custom:; $(call code.compiled.lambda, lang=dsl.rust src=my_rust cargo=cargotoml)

__main__: my_rust my_rust/you run.custom
