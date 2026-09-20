# Golden emitted source

What `TabulaCodegen.emit` produces, committed so a change to the generator shows
up as a diff of the *generated code* rather than only of the emitter.

```sh
./tools/verify swift-codegen                # diff against these
cd swift && swift run tabula-codegen-check codegen-golden --bless   # accept after an intended change
```

A missing golden is reported as a **skip**, not a failure: the first one can
only be written by running the generator, and a check that must fail once before
it can pass is a check people learn to ignore.

The shape these files must reproduce is fixed by
`Sources/TabulaCheck/ReferenceTimer.swift`, which is hand-written and kept
building forever.

Blessing is a direct call to the check, never a mode of `tools/verify`: that
script is the definition of green, and only compares. The same split Rust
(`cargo run -p tabula-conformance -- --bless`) and Kotlin (`codegen/Main.kt
--bless`) use. Bless outside the nix sandbox -- inside it the tree is a
read-only copy -- read the diff, and commit what it writes: one `<machine>.swift.golden` per machine in
`TabulaCodegenCheck`, the refused `job-mixed` included -- a refused machine's
output is pinned like any other.
A golden says the output did not change; `../codegen-support/` is what says
the output is Swift, by compiling it.
