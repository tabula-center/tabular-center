# The declaration surface

What a user writes, and what `MachineMacro` must read out of it. Written before
the macro because the macro is a mapping and this is its input half; getting
this wrong costs a rewrite of the traversal, and no toolchain available here
can compile the traversal to tell us.

The output half is already fixed: `RawMachine` in `TabularCenterCodegen`, which
validates into a `MachineDesc` with every declaration diagnostic and emits
the source.
**The macro's entire job is syntax to `RawMachine`.** Nothing below describes
generated code, because none of it is the macro's decision.

## The declaration

In a file named `Turnstile.tb.swift` — see `spec/matrix-files.md`. The rows
are column-aligned and general-purpose formatters exist to normalise exactly
that, so the extension is what lets one be told to keep away.

**The block below is executed.** `TabularCenterMacroSyntaxCheck` reads this file,
takes the first ```swift fence, and runs the traversal over it. Edit it and
the checks run against the edit; edit it into something `MachineSyntax` cannot
read and they go red. A specification that describes a surface nothing parses
is a specification that has already stopped being true, and the only way to
know is to make the document the input.

```swift
@Machine
enum Turnstile {
    enum S { case locked, unlocked }
    enum A { case coin, push }
    enum F { case click }

    final class Ctx { var admitted = 0 }

    static let initial = S.locked

    //                        Coin                        Push
    @Row(.locked)   static let l = [ .go(.unlocked, [.click]),  .ignore ]
    @Row(.unlocked) static let u = [ .ignore,                   .handle ]

    // Carries the color and the return type. Every required member the
    // generator emits is stamped from this one line.
    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
```

## The mapping, field by field

| `RawMachine` | Read from |
|---|---|
| `machine` | the attached declaration's name |
| `stateType`, `actionType`, `effectType`, `ctxType` | nested type names, defaulting to `S`, `A`, `F`, `Ctx` |
| `initial` | the `static let initial` initializer |
| `states`, `actions`, `effects` | the cases of each nested enum, **in declaration order** |
| `rows` | one per `@Row`, in source order; the attribute names the state |
| `prototypeModifiers` | every modifier and effect specifier on `handle` |
| `children` | `Cell.delegate(...)` targets |

Four of those are worth stating as rules rather than rows in a table.

**Order is meaning.** A row's cells are positional — they line up with the
action enum's cases — which is what makes a matrix reviewable and what
`tabular-center::row-arity` checks. So the macro must read enum cases and array
elements in *source order*, and any traversal that sorts or uses a dictionary
loses the property the library exists for.

The corollary for the macro: **whitespace inside a row is not its business.**
The padding that aligns the columns is what a reader scans, and a macro that
normalised it, or a diagnostic that quoted a row with the alignment stripped,
would be destroying the artifact it was asked to read.

**The `handle` prototype is copied verbatim, not interpreted.** `async`,
`throws`, attributes, `@MainActor` — whatever is written there is stamped onto
every generated member. The macro must not decide which modifiers are
meaningful; that is how a colored machine stays colored end to end, and the
Rust and Kotlin generators both work this way.

**Diagnostics are not the macro's.** It does not check arity, unknown states,
or `GO` targets. It builds a `RawMachine` and hands it over; `TabularCenterCodegen`
already produces the normative text, and duplicating any of it here would mean
two messages for one error that drift apart. The macro's own errors are only
about syntax it cannot read at all — a `@Row` with no state, a tuple where a
cell was expected.

**A shape the macro cannot read is an error, never a skip — and the error has
to be worth reading.** Failing fast is half of it; the half that matters to
someone stuck is what the message says. `tabular-center-kotlin/ksp` recorded the first half
the hard way: its `classes()` used `filterIsInstance`, so an unrecognised
annotation shape was dropped silently and produced a machine with no states and
no error.

The bar, matching `spec/diagnostics.md`: name **what was found**, **where**, and
**what was expected instead**. Not `malformed @Row` but

```
@Row(.locked): expected 2 cells to match the 2 cases of `A`, found 3
@Row: expected an array literal of cells, found a tuple
@Machine: `Turnstile` has no `static let initial`; the macro cannot guess
          which state a machine starts in
```

A diagnostic that names only the attribute sends the developer to re-read the
documentation. One that names the mismatch sends them to the line.

## Why an array, and why it is written on one line

An earlier draft of this file used a labelled tuple per row —
`(coin: .go(...), push: .ignore)` — on the argument that labelling each cell
with the action it answers lets a reviewer see the pairing without counting
columns, and buys a check the other languages do not get.

That was wrong, and wrong against the point of the library. Labels make every
row a different width. A matrix whose rows do not line up is a list of
transitions, and a list of transitions is what a `switch` already gives you.
The whole claim here is that a reader takes in the machine **in one scan**, and
that requires columns that are columns.

So: an array literal, one row per line, cells padded to align down the page,
with the action names in a comment above the first row. That is the same shape
Rust and Kotlin use, and it is the reason `.editorconfig` disables ktlint's
alignment rules for `*.tb.kt` — the matrices are aligned on purpose and a
formatter must not touch them. `*.tb.kt`, not `*.kt`: the exemption is scoped
to matrix files precisely so that ordinary Kotlin stays formatted, which is
also why `tabular-center-kotlin/test/TimerSpec.tb.kt` had to be split out of
`ReferenceTimer.kt` before `kotlin-matrix-stable` could run at all.

The pairing a reviewer needs comes from the header comment and from the
alignment, not from repeating the action name on every cell. What labels would
have caught — a cell in the wrong column — `tabular-center::row-arity` catches anyway
when the count is wrong, and a reviewer catches by eye when it is not, which is
precisely the capability alignment exists to give them.

## Open, and deliberately

- **Whether `@Row` attaches to a stored property at all.** Swift macros cannot
  attach to arbitrary declarations in every position; if `@Row` on a `static
  let` turns out not to be expressible, the fallback is a single
  `@Machine(rows:)` argument holding everything, which reads worse and loses
  the per-row diff.
- **Whether the nested enums can be read from the attached declaration's
  members** or must be named in the attribute. The former is nicer and depends
  on what `MemberMacro` receives.

Both are answerable in an hour with a toolchain that can compile a macro, and
by nothing at all without one. That is why this file exists and the traversal
does not.
