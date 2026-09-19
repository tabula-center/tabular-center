# What this golden is for

`TurnstileGenerated.kt.golden` is what the processor must emit for
`examples/kotlin/06-generated/src/Machine.tb.kt`. `tools/verify kotlin-ksp`
diffs it against the real output after Gradle runs.

## Why the example compiling was not enough

Until this landed, the only thing holding the processor to account was that
`examples/kotlin/06-generated` built. That is a weaker claim than it looks. It
proves the emitted `Cells` interface has a member `Impl.kt` can override and
that `step` type-checks — nothing about the *table*. The processor could read
the rows in the wrong order, drop an effect from a `GO` cell, or resolve
`initial` to the wrong state, and every one of those still compiles. `TABLE`
and `PAYLOADS` are inert data that nothing in the example reads at all.

That matters more here than elsewhere because of how the processor is built.
All the logic lives in `codegen/` — `buildDesc` validates, `emit` renders, both
covered by `kotlin-codegen` with `kotlinc` alone. `TabulaProcessor.kt` only
turns KSP's view of the annotations into a `RawMachine`. So the untested
surface was never the emitter; it was extraction, and extraction bugs are
exactly the ones that produce a well-formed machine that says the wrong thing.

## What it does prove

The two front-ends converge. `codegen/golden/` holds the output of the same
`emit` driven by a hand-built `MachineDesc`; this holds its output driven by
KSP reading annotations. One emitter, two callers, and a change to either that
does not reach the other now shows up as a diff rather than as a silence.

## When it fails

Read the diff before re-blessing it. A change to `emit` legitimately moves both
this file and `codegen/golden/*`, and if only one moved, the interesting
question is why. A diff confined to `TABLE`, `PAYLOADS` or the order of members
is the extraction path drifting — which is the failure this file exists to
catch, and not one to paper over by copying the new output on top.

## `StopwatchGenerated.kt.golden`

Byte-identical to `codegen/golden/stopwatch.kt.golden`, on purpose: the same
machine reached through KSP and through a hand-built `MachineDesc`. It is the
first golden where the two front-ends are compared on the SAME machine rather
than on the same emitter, and it covers the two things extraction used to drop
without a sound -- the prototype's extension receiver (qualified, because the
generated file imports nothing but `dev.tabula`) and the annotated
declaration's `internal`.

If this one diffs and `codegen/golden/stopwatch.kt.golden` does not, the
processor read the declaration differently from how the description states
it. That is the bug, not the golden.
