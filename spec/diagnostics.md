# Diagnostics

Normative across all three implementations. The three code generators will
drift unless something pins them, and error messages are the part developers
actually read.

Every code below has a fixture under the implementation's compile-fail suite:
`rust/tabula/tests/compile_fail/`, `kotlin/compile_fail/`,
`kotlin/codegen/compile_fail/`, and `swift/compile_fail/`. A diagnostic without
a fixture is not shipped.

All three suites are driven by `tools/verify`, reading a `//~ EXPECT:` line
from each fixture — not by `trybuild`, KSP compile-testing, or
swift-macro-testing. Each of those would have been the project's only
dependency in its language, to do something a few lines of bash already does.

A fixture passes only if the compiler **refused** it *and* the refusal contains
the expected text. Both halves are load-bearing, and the first was missing for
a while: all four loops inferred "it compiled" from empty stderr, so a fixture
that compiled with a warning fell through to the message match, and a warning
containing the expected string would have reported it green. The suite is what
makes "a diagnostic without a fixture is not shipped" mean anything, so it is
worth being exact about what its green means.

Cell semantics are specified separately, in `cells.md`.

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

**Status:** implemented in all three (Rust `matrix.rs`, Kotlin `codegen/Raw.kt`,
Swift `TabulaCodegen/Raw.swift`).

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

**Status:** implemented in all three.

---

## `tabula::unknown-cell`

A cell is not one of the six kinds.

```
tabula::unknown-cell: `MAYBE` in row `Idle`, column `Start`. Expected one of:
IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..).
```

Names row *and* column. In a 8x12 matrix, "unknown cell `MAYBE`" is not enough
to find it.

**Status:** implemented in all three. `DELEGATE!` joined the accepted list in
Phase 6, so the Rust message now reads
`IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..), DELEGATE!(..)`.

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

**Status:** implemented in all three — Rust by construction, Kotlin and Swift
as the explicit form, since neither generator can put the target expression
somewhere the runtime bindings are out of scope.

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

## Declaration diagnostics

These concern the *declaration* rather than the generated code, so they fire
before any compiler plugin is involved. In Kotlin they live in
`codegen/Raw.kt` — deliberately outside the KSP processor, so each one has a
test rather than living in code that needs Maven to run.

| Code | Fires when |
|---|---|
| `tabula::row-arity` | a row has the wrong number of cells |
| `tabula::missing-row` | a state has no row, or rows are out of declaration order |
| `tabula::extra-row` | a row names something that is not a declared state |
| `tabula::unknown-cell` | a cell is not one of the six kinds |
| `tabula::unknown-state` | `GO` targets, or `initial` names, an undeclared state |
| `tabula::unknown-effect` | a cell emits an undeclared effect |
| `tabula::unknown-child` | `DELEGATE` names an undeclared child |
| `tabula::go-target` | `GO` targets a payload state with no literal arguments |
| `tabula::empty-emit` | `EMIT` lists no effects; use `IGNORE` or `HANDLE` |

Rows are identified by **position**, so an out-of-order row is reported as
`missing-row` rather than accepted as a reordering: it is a row for the wrong
state, not the right row in the wrong place.

**Rust emits five of these, and the four it omits are conformant.**
`unknown-state`, `unknown-effect`, `unknown-child`, and `go-target` are all
name resolution in Rust: the macro splices the identifier into an expression
and `rustc` rejects it, naming the same thing our message would have. Emitting
our own on top would mean intercepting a better error to replace it with a
worse one.

`empty-emit` is different, and was a real gap rather than a delegation. Nothing
resolves `EMIT!()` — it parses as an empty effect list and expands to
`Step::stay()`, so Rust silently accepted a cell the spec forbids while Kotlin
and Swift rejected it. The conformance suite is structurally unable to catch
that: it compares behaviour, and no fixture writes a forbidden cell.

| Code | Rust | Kotlin | Swift |
|---|---|---|---|
| `row-arity` | yes | yes | yes |
| `missing-row` / `extra-row` | yes | yes | yes |
| `unknown-cell` | yes | yes | yes |
| `unknown-state` | by rustc | yes | yes |
| `unknown-effect` | by rustc | yes | yes |
| `unknown-child` | by rustc | yes | yes |
| `go-target` | by construction | yes | yes |
| `empty-emit` | yes | yes | yes |

### `tabula::empty-emit`

```
tabula::empty-emit: cell (Off, Poke) uses EMIT with no effects. Use IGNORE if
the action is not applicable in this state, or HANDLE if it is handled
deliberately.
```

Names both remedies, because which one is right depends on something the
generator cannot know: whether the developer means the pair is meaningless or
means it is handled. Both are one word.

In Rust the check must be a muncher arm placed *before* the general `EMIT!`
arm — `$($g:tt)*` matches zero tokens, so the general arm would otherwise
swallow it. Another instance of the rule in `ARCHITECTURE.md` §11.1: the useful
diagnostic has to be emitted earlier than the incidental one.

## `tabula::color-mismatch` (Phase 6)

```
tabula::color-mismatch: machine `Timer` (prototype: `fun handle`) delegates to
`Retry` (prototype: `suspend fun handle`). A suspending child cannot be driven
from a non-suspending parent.
```

---

## Lints (warnings, from `TABLE`)

Everything below is computed from the matrix as a pure function, which is the
payoff for emitting it as data. All are **warnings**, never errors: each is a
judgement call with legitimate exceptions, and a lint that fails a build on a
judgement call teaches people to disable lints.

Two rules govern the set, learned by writing it:

- **A lint that fires on healthy machines is a lint people turn off.**
  `no-static-entry` originally fired on nearly every machine, because a state
  reached only through a `HANDLE` cell looks unreachable from the table. It now
  reports only for a *fully static* matrix, where the answer is knowable.
  `unreachable-heavy` likewise fires on a concentration, not on the one or two
  deliberate assertions the cell kind exists for.
- **Two warnings for one problem is noise.** `dead-row` subsumes
  `no-static-exit`; a row that is entirely `IGNORE` reports once.

| Code | Fires when |
|---|---|
| `tabula::no-static-entry` | nothing can transition into a state, in a fully static matrix |
| `tabula::no-static-exit` | no cell in a row can statically leave it |
| `tabula::dead-row` | every cell in a row is `IGNORE` |
| `tabula::dead-column` | no state responds to an action |
| `tabula::ignore-heavy` | `IGNORE` is at least 70% of the matrix |
| `tabula::unreachable-heavy` | `UNREACHABLE` is at least 25% of the matrix |

`dead-row` fires on genuinely terminal states, intentionally: an intended
terminal state and a forgotten row are indistinguishable from the matrix, and
one line of output is a fair price for catching the second.

**Status:** implemented in all three, and *checked* across all three: the lint
output is a golden file (`spec/conformance/<name>.lint`) that Rust blesses and
the other two only read. Until that existed the three implementations printed
their warnings side by side with nothing asserting they agreed, and the lints
hold the most per-language logic in the project — the 70% and 25% thresholds,
the `dead-row` subsumption, the fully-static gate on reachability.

---

## `tabula::payload-hoist`

```
warning[tabula::payload-hoist]: Conn: `retry_count: u32` appears in the
payloads of Connecting, Backoff, Reconnecting; consider hoisting it to Context
```

Warning, never an error: rule R4 is a judgement call, and three is a heuristic.

Two details that keep it from crying wolf:

- **Name *and* type must match.** A `count: Int` and a `count: String` are two
  different ideas that happen to share a word.
- **Three states, not two.** Two is a coincidence; three is a pattern.

The field list is metadata about the states, so it is emitted as a separate
`PAYLOADS` const rather than folded into the table — the table is the matrix.
A generator that cannot resolve a field's type degrades this one lint rather
than the machine.

**Status:** implemented in all three, and all three adapters now supply their
payloads. It remains the one lint with **no shared fixture**, and the reason is
in the message rather than in the metadata.

**The type name is spelled by the implementation's own language.** The same
field is `since: u32` in Rust, `since: Long` in Kotlin and `since: Int` in
Swift. A golden `.lint` file is compared byte for byte by all three, so a
fixture that fires this lint cannot have one.

Picking a type the three spell identically does not rescue it. `String` is the
obvious candidate — and generated state enums derive `Copy`, so a Rust machine
cannot hold a `String` payload at all. No type is both spelled the same in all
three *and* `Copy` in Rust, so the constraint is not a naming inconvenience; it
has no solution at the fixture level.

Three ways out, none of them free, and the choice is deliberately still open:

1. **Drop the type from the message.** Cheapest, and it loses the thing the
   type is there for: the lint already compares name *and* type, precisely so
   that `count: u32` and `count: String` are treated as two ideas sharing a
   word. Two findings that both say `` `count` `` would be worse output than
   one that says `` `count: u32` ``.
2. **Canonicalise type names** into a spec vocabulary (`int`, `string`, `bool`)
   that each generator maps onto. Correct, and it is a new normative table in
   this file plus a mapping in three generators, for one lint.
3. **Let the lint golden be per-language** for this fixture alone. Narrow, and
   it puts a hole in the property that makes the goldens worth having.

Until one is chosen, the lint is verified by unit tests inside each
implementation, which do not have the cross-language problem.
