# Golden emitted source

What `TabulaCodegen.emit` produces, committed so a change to the generator shows
up as a diff of the *generated code* rather than only of the emitter.

```sh
./tools/verify swift-codegen                # diff against these
TABULA_BLESS=1 ./tools/verify swift-codegen # accept after an intended change
```

A missing golden is reported as a **skip**, not a failure: the first one can
only be written by running the generator, and a check that must fail once before
it can pass is a check people learn to ignore.

The shape these files must reproduce is fixed by
`Sources/TabulaCheck/ReferenceTimer.swift`, which is hand-written and kept
building forever.

Bless outside the nix sandbox -- inside it the tree is a read-only copy -- and
commit what it writes: `timer.swift.golden` and `timer-async.swift.golden`.
A golden says the output did not change; `../codegen-support/` is what says
the output is Swift, by compiling it.
