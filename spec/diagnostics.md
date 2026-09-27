# Diagnostics

Normative across all three implementations. The three code generators will
drift unless something pins them, and error messages are the part developers
actually read.

## Every message ends with its page

Messages carry their remedy inline — that rule does not change, and a message
that only says "see the docs" has failed. The link is an **addition**: a last
line, after the remedy, for the reader who wants the reasoning rather than the
fix.

```
tabular-center::row-arity: row `Running` has 2 cells; `actions` declares 3.
  The first missing column is `Cancel`.
  https://tabula-center.github.io/tabular-center/doc/diagnostics#tabular-center-row-arity
```

The anchor is injected by `tools/docs`, not derived from the heading text.
Jekyll and GitHub generate heading anchors by rules that differ from each other
and change between versions, and this is a link a developer follows *from an
error they are already stuck on* — the one place a rotted link costs most.

`doc/` is generated from this file by `tools/docs` and committed, because
GitHub Pages serves it from the branch. It is never edited by hand, and
`tools/verify docs` fails when it is not exactly what `tools/docs` renders --
a second copy of normative text is only safe if something checks it.

Every code below has a fixture under the implementation's compile-fail suite:
`tabular-center-rust/tabular-center/tests/compile_fail/`, `tabular-center-kotlin/compile_fail/`,
`tabular-center-kotlin/codegen/compile_fail/`, and `tabular-center-swift/compile_fail/`. A diagnostic without
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
tabular-center::<code>: <what is wrong>. <what to do about it>. <context>
```

The remedy is part of the message, not something to look up. A developer who
hits `tabular-center::go-target` should not have to open this file to learn that the
fix is `HANDLE`.

---

## `tabular-center::row-arity`

A row has a different number of cells than the machine has actions.

```
tabular-center::row-arity: row `Running` has too few cells; missing a cell for
action `Cancel`. Expected columns: Start Tick Cancel
```

```
tabular-center::row-arity: row `Idle` has too many cells; unexpected `IGNORE`.
Expected columns: Start Tick Cancel
```

Names the *first* offending column rather than counting, because "expected 3,
found 2" makes the developer count columns by hand.

**Status:** implemented in all three (Rust `matrix.rs`, Kotlin `codegen/Raw.kt`,
Swift `TabularCenterCodegen/Raw.swift`).

---

## `tabular-center::missing-row` / `tabular-center::extra-row`

A declared state has no row, or a row names something that is not a declared
state.

```
tabular-center::missing-row: state `Done` has no row. Every state needs exactly one
row, in declaration order. States: Idle Running Done
```

Must be emitted **during macro expansion**, not as a `const` assertion. In
Rust a missing row also produces an array-length mismatch on `TABLE`, and type
errors abort before const evaluation, so a const check never gets to speak.
Whichever mechanism a language uses, this diagnostic has to win the race
against the incidental one.

**Status:** implemented in all three.

---

## `tabular-center::unknown-cell`

A cell is not one of the six kinds.

```
tabular-center::unknown-cell: `MAYBE` in row `Idle`, column `Start`. Expected one of:
IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..).
```

Names row *and* column. In a 8x12 matrix, "unknown cell `MAYBE`" is not enough
to find it.

**Status:** implemented in all three. `DELEGATE!` joined the accepted list in
Phase 6, so the Rust message now reads
`IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..), DELEGATE!(..)`.

---

## `tabular-center::go-target`

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
tabular-center::go-target: cell (Done, Start) uses GO to `Running`, which requires
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
error[E0277]: the trait bound `T: tabular_center::Handle<Timer, Running, Tick>`
              is not satisfied
```

This is deliberate. The error comes from `rustc` / `kotlinc` / `swiftc`
themselves, so it survives even if the generator is bypassed, and it names the
exact `(state, action)` pair. Implementations must not intercept or reword it.

Kotlin and Swift produce their own equivalents ("abstract member not
implemented"), which read differently and must not be normalized. Behaviour is
what `spec/conformance` compares; message text is normative only for
diagnostics tabular-center itself authors.

---

## Declaration diagnostics

These concern the *declaration* rather than the generated code, so they fire
before any compiler plugin is involved. In Kotlin they live in
`codegen/Raw.kt` — deliberately outside the KSP processor, so each one has a
test rather than living in code that needs Maven to run.

| Code | Fires when |
|---|---|
| `tabular-center::row-arity` | a row has the wrong number of cells |
| `tabular-center::missing-row` | a state has no row, or rows are out of declaration order |
| `tabular-center::extra-row` | a row names something that is not a declared state |
| `tabular-center::unknown-cell` | a cell is not one of the six kinds |
| `tabular-center::unknown-state` | `GO` targets, or `initial` names, an undeclared state |
| `tabular-center::unknown-effect` | a cell emits an undeclared effect |
| `tabular-center::unknown-child` | `DELEGATE` names an undeclared child, or (KSP) one that is not a machine |
| `tabular-center::go-target` | `GO` targets a payload state with no literal arguments |
| `tabular-center::empty-emit` | `EMIT` lists no effects; use `IGNORE` or `HANDLE` |
| `tabular-center::unsupported-color` | a Rust prototype other than `fn handle` or `async fn handle` |

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
| `unsupported-color` | yes | n/a | n/a |
| `path-unknown-state` | yes | yes | yes |
| `path-broken` | yes | yes | yes |
| `path-unterminated` | yes | yes | yes |
| `path-duplicate` | by rustc | yes | yes |

### `tabular-center::unsupported-color`

```
tabular-center::unsupported-color: machine `Timer` has a prototype Rust cannot color.
Write `prototype fn handle;` or `prototype async fn handle;` -- `async` is the
only color a Rust trait method can carry on stable.
```

Rust only, and by design. Kotlin and Swift copy the prototype's modifiers onto
generated declarations, so any modifier their compiler accepts is a color.
Rust's cell surface is a library trait, so each color needs a colored twin of
it, and `async` is the only one a trait method can carry on stable. Named,
rather than left to `no rules expected the token`, because the right fix is a
different prototype, and the generic error would not say which.

### `tabular-center::empty-emit`

```
tabular-center::empty-emit: cell (Off, Poke) uses EMIT with no effects. Use IGNORE if
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

### Happy-path diagnostics

The four below come from `@Path`, and all four are *declaration* diagnostics
rather than lints: a broken spine is rejected by `buildDesc` before a `TABLE`
exists, so there is nothing for a lint to read. See `spec/happy-paths.md`.

Kotlin and Swift emit them. Rust does not, and that is not a gap — Rust has no
`RawMachine` and no `buildDesc`, so `@Path` there is a macro arm and its
rejections are `compile_error!`, exactly as `extra-row` already is.
`spec/diagnostics-coverage.md` records it.

### `tabular-center::path-broken`

```
tabular-center::path-broken: path `connect` goes `Connecting` -`Ready`-> `Live`, and
cell (Connecting, Ready) cannot reach `Live`
```

The check that lets a path be declared away from the rows it describes. Without
it the objection to a separate `@Path` annotation would stand: a route stated
somewhere a matrix reader will not look could drift from the matrix silently.
With it, the two cannot disagree — a spine naming a transition the table does
not have is not a warning, it is a machine that does not build.

A `HANDLE` counts as a connection. Its target is not knowable from the matrix,
and supplying that target is the entire point of the path; refusing it would
reject the only cell kind the feature exists to shorten.

A one-state path reports here too. A route that goes nowhere is broken in the
same sense, and inventing a fifth code for it would split one idea across two
pages a reader has to find separately.

### `tabular-center::path-unterminated`

```
tabular-center::path-unterminated: path `connect` ends at `Live`, which can still be
left; a path ends where the machine is done.
```

A path that never ends is a loop with a name. The test is the same one
`tabular-center::no-static-exit` uses — a `GO` elsewhere, a `HANDLE`, or a `DELEGATE` —
so the two agree about what "can be left" means rather than each deciding.

### `tabular-center::path-unknown-state`

```
tabular-center::path-unknown-state: path `connect` names state `Livee`, which is not
declared. States: Idle Connecting Live Failed
```

Lists the declared states, so a typo is fixed from the message. Separate from
`tabular-center::unknown-state`, which is about a cell's target: the two have different
remedies, and a shared code would mean a shared doc page explaining both.

### `tabular-center::path-duplicate`

```
tabular-center::path-duplicate: two paths are named `connect`; a narrowed call site
names the path it narrows to, so names must be unique.
```

The message says why rather than just what. A developer reading it has probably
copied a `@Path` and edited the states without the name, and the reason names
must be unique is the thing that makes the fix obvious.

## `tabular-center::color-mismatch` — reserved, emitted by nobody

**Decided (September 2026): no implementation emits this, and none should.**
The message a generator would print is the one above the decision:

```
tabular-center::color-mismatch: machine `Timer` (prototype: `fun handle`) delegates to
`Retry` (prototype: `suspend fun handle`). A suspending child cannot be driven
from a non-suspending parent.
```

Nothing prints it, because every generator refuses the case earlier and by
construction — the generated delegate arm carries the **parent's** color and
calls the child's `step`, so a colored child under a colorless parent is a
call the language itself will not accept:

| | what refuses it | fixture |
|---|---|---|
| Rust | an async child's `step` is a future where a `Step` is required | `tabular-center-rust/tabular-center/tests/compile_fail/async_child_in_plain_parent.rs` |
| Kotlin | a `suspend` call from a plain function | `tabular-center-kotlin/codegen/compile_fail/jobmixed_colored_child_in_uncolored_parent.kt` |
| Swift | an `async` call in a function that does not support concurrency | `tabular-center-swift/codegen-support/compile_fail/job-mixed_colored_child_in_uncolored_parent.swift` |

Treated like a missing implementation, which this file also leaves to the
compiler: a check that fired first would replace a message about the
developer's own code with one about generated code they never wrote, and would
have to be kept correct forever beside a compiler that is already right.

The code stays reserved rather than deleted. It is the answer for a language
whose generator cannot put the parent's color on the call — where color would
have to be compared rather than carried. None of the three is that language,
and the table above is what would notice if one became it.

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
| `tabular-center::no-static-entry` | nothing can transition into a state, in a fully static matrix |
| `tabular-center::no-static-exit` | no cell in a row can statically leave it |
| `tabular-center::dead-row` | every cell in a row is `IGNORE` |
| `tabular-center::dead-column` | no state responds to an action |
| `tabular-center::ignore-heavy` | `IGNORE` is at least 70% of the matrix |
| `tabular-center::unreachable-heavy` | `UNREACHABLE` is at least 25% of the matrix |

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

## `tabular-center::payload-hoist`

```
warning[tabular-center::payload-hoist]: Conn: `retry_count: u32` appears in the
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

**Status:** implemented in all three, and all three adapters supply their
payloads.

#### Payload types are canonicalised

The message names the field's **type**, and each language spells its own: one
field is `since: u32` in Rust, `since: Long` in Kotlin, `since: Int` in Swift.
A `.lint` golden is compared byte for byte by all three, so without a shared
vocabulary this lint could never have a shared fixture, and no fixture-level
trick rescues it — `String` is the only type the three spell alike, and
generated state enums derive `Copy`, so a Rust machine cannot hold one.

Dropping the type from the message would have been cheaper and would have lost
the distinction the lint exists to draw: it compares name *and* type precisely
so `count: u32` and `count: String` are two ideas sharing a word.

**Implementations map their own type names onto this vocabulary before
comparing or rendering.** Canonicalising before the comparison, not only before
the message, is what makes the three agree — Rust grouping `u32` separately
from `usize` while Kotlin groups `Int` with `Long` would produce different
findings from the same machine.

| Canonical | Rust | Kotlin | Swift |
|---|---|---|---|
| `int` | `i8`…`i128`, `u8`…`u128`, `isize`, `usize` | `Byte`, `Short`, `Int`, `Long`, and the `U`-prefixed forms | `Int`, `Int8`…`Int64`, `UInt`, `UInt8`…`UInt64` |
| `float` | `f32`, `f64` | `Float`, `Double` | `Float`, `Double` |
| `bool` | `bool` | `Boolean` | `Bool` |
| `string` | `String`, `&str`, `&'static str` | `String`, `CharSequence` | `String`, `Substring` |
| `char` | `char` | `Char` | `Character` |

**A name not in the table passes through unchanged.** That is the rule for user
types and it is deliberate rather than a fallback: a domain type is usually
spelled the same in all three ports, so passing `Money` through is both correct
and what a reader expects. It also means the table can grow without a
migration — an unmapped primitive renders as itself and produces a golden
mismatch, which is a visible failure rather than a silent one.

Width is why the vocabulary stops where it does. `u8` and `u64` both become
`int`, which loses information the lint was never using: the suggestion is
*this field belongs to the machine rather than to any one state*, and that is
true at every width.
