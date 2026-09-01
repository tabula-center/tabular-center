# Diagnostics

Normative across all three implementations. The three code generators will
drift unless something pins them, and error messages are the part developers
actually read.

Every code below has a fixture under the implementation's compile-fail suite
(`rust/tabula/tests/compile_fail/`, later KSP compile-testing and
swift-macro-testing). A diagnostic without a fixture is not shipped.

## Format

```
tabula::<code>: <what is wrong>. <what to do about it>. <context>
```

The remedy is part of the message, not something to look up. A developer who
hits `tabula::go-target` should not have to open this file to learn that the
fix is `HANDLE`.

---

## `tabula::row-arity`

A row has a different number of cells than the machine has actions.

```
tabula::row-arity: row `Running` has too few cells; missing a cell for
action `Cancel`. Expected columns: Start Tick Cancel
```

```
tabula::row-arity: row `Idle` has too many cells; unexpected `IGNORE`.
Expected columns: Start Tick Cancel
```

Names the *first* offending column rather than counting, because "expected 3,
found 2" makes the developer count columns by hand.

**Status:** implemented (Rust).

---

## `tabula::missing-row` / `tabula::extra-row`

A declared state has no row, or a row names something that is not a declared
state.

```
tabula::missing-row: state `Done` has no row. Every state needs exactly one
row, in declaration order. States: Idle Running Done
```

Must be emitted **during macro expansion**, not as a `const` assertion. In
Rust a missing row also produces an array-length mismatch on `TABLE`, and type
errors abort before const evaluation, so a const check never gets to speak.
Whichever mechanism a language uses, this diagnostic has to win the race
against the incidental one.

**Status:** implemented (Rust).

---

## `tabula::unknown-cell`

A cell is not one of the six kinds.

```
tabula::unknown-cell: `MAYBE` in row `Idle`, column `Start`. Expected one of:
IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..).
```

Names row *and* column. In a 8x12 matrix, "unknown cell `MAYBE`" is not enough
to find it.

**Status:** implemented (Rust). `DELEGATE!` joins the accepted list in Phase 6.

---

## `tabula::go-target`

A `GO` cell names a target that cannot be constructed without runtime data.

Rust enforces this **by construction** rather than by checking: the generated
dispatcher binds its parameters under `__tabula_`-prefixed names, so `ctx`,
`state`, `action`, and `cells` are not in scope inside a `GO!` expression. The
resulting message is rustc's own:

```
error[E0425]: cannot find value `ctx` in this scope
  |     Idle => [ GO!(Running { since: ctx.limit }), IGNORE, IGNORE ];
  |                                    ^^^ not found in this scope
```

Enforcement-by-construction is preferred where available: it cannot be
circumvented and it costs no implementation. Where a language cannot do it,
emit the explicit form:

```
tabula::go-target: cell (Done, Start) uses GO to `Running`, which requires
`since: u32` that cannot be derived from a literal. Use HANDLE.
```

Without this rule `GO` quietly becomes the lazy option and developers stuff
zero values into payloads to avoid writing a cell.

**Status:** implemented (Rust, by construction).

---

## The missing-implementation error is not ours

The library's central guarantee produces a message we do not author:

```
error[E0277]: the trait bound `T: tabula::Handle<Timer, Running, Tick>`
              is not satisfied
```

This is deliberate. The error comes from `rustc` / `kotlinc` / `swiftc`
themselves, so it survives even if the generator is bypassed, and it names the
exact `(state, action)` pair. Implementations must not intercept or reword it.

Kotlin and Swift produce their own equivalents ("abstract member not
implemented"), which read differently and must not be normalized. Behaviour is
what `spec/conformance` compares; message text is normative only for
diagnostics tabula itself authors.

---

## `tabula::color-mismatch` (Phase 6)

```
tabula::color-mismatch: machine `Timer` (prototype: `fun handle`) delegates to
`Retry` (prototype: `suspend fun handle`). A suspending child cannot be driven
from a non-suspending parent.
```

---

## `tabula::payload-hoist` (warning, Phase 8)

```
warning[tabula::payload-hoist]: `retryCount: Int` appears in payloads of
`Connecting`, `Backoff`, `Reconnecting`. Consider hoisting to Context.
```

Warning, never an error: rule R4 is a judgement call, and three is a heuristic.
