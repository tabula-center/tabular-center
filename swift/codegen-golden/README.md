# Golden emitted source

What `TabulaCodegen.emit` produces, committed so a change to the generator shows
up as a diff of the *generated code* rather than only of the emitter.

```sh
./tools/verify swift-codegen                # diff against these
./tools/verify swift-codegen -- --bless     # accept after an intended change
```

A missing golden is reported as a **skip**, not a failure: the first one can
only be written by running the generator, and a check that must fail once before
it can pass is a check people learn to ignore.

The shape these files must reproduce is fixed by
`Sources/TabulaCheck/ReferenceTimer.swift`, which is hand-written and kept
building forever.
