---
layout: default
title: Cells
---

<!-- Generated from spec/cells.md by tools/docs. Do not edit. -->

[Home](./) · [Rust](rust) · [Kotlin](kotlin) · [Swift](swift) · [Migrating](migrating) · [Cells](cells) · [Diagnostics](diagnostics) · [Matrix files](matrix-files) · [Source](https://github.com/tabula-center/tabular-center)

# Cells

Normative across all three implementations.

A cell is one entry of the state × action matrix. This file defines what each
kind means: what the generator must emit for it, what it evaluates to at run
time, and how it appears in the shared conformance and golden formats.

`ARCHITECTURE.md` explains *why* the set is what it is. This file is what a
fourth implementation would be written from, so it states obligations rather
than reasons. Where the two disagree, this file wins for behaviour and
`ARCHITECTURE.md` wins for rationale.

Companion documents: `diagnostics.md` for error codes, `conformance/README.md`
for the fixture and trace formats.

---

## 1. `Step`, and the vocabulary cells are defined in terms of

Every cell evaluates to a `Step`, which is an outcome plus an ordered,
bounded collection of effects.

| Outcome | Meaning |
|---|---|
| `Go(next)` | transition to `next` |
| `Stay` | handled; remain in the current state |
| `Ignored` | not applicable in this state; nothing happened |

`Stay` and `Ignored` are **behaviourally identical and must remain distinct
values**. Collapsing them is a conformance failure, not an optimisation: the
trace format asserts on them separately, the coverage report counts them
separately, and `tabular-center::dead-row` is computed from `IGNORE` cells alone.

Effects are ordered. A cell emitting `[A, B]` and one emitting `[B, A]` are
different cells, and the conformance harness compares emission order.

---

## 2. The six kinds

Three are **static** — resolved entirely by the generator, no developer code,
no required member. Three are **dynamic or structural** — each produces
something the developer must write, or a trap.

| Kind | Static | Required member | Outcome |
|---|---|---|---|
| `IGNORE` | yes | no | always `Ignored` |
| `GO(target, effects…)` | yes | no | always `Go(target)` |
| `EMIT(effects…)` | yes | no | always `Stay` |
| `HANDLE` | no | **yes** | whatever the developer returns |
| `DELEGATE(child)` | no | **yes** | derived from the child's `Step` |
| `UNREACHABLE` | no | no | does not return; traps |

The static/dynamic split is the property that makes a large matrix survivable,
and implementations must preserve it exactly. A generator that emitted a
required member for `IGNORE` would be conformant on every trace and wrong on
the thing the library is for.

---

### 2.1 `IGNORE`

**Declaration.** The bare word, no arguments.

**Generator obligation.** Emit no member. The dispatcher arm evaluates to
`Ignored` with no effects.

**Runtime.** `Step { outcome: Ignored, effects: [] }`.

**Meaning.** *The developer asserts this action is not applicable in this
state.* This is a claim about the alphabet, not about the handler.

**`IGNORE` versus a `HANDLE` cell returning `stay()`.** Both leave the state
unchanged and emit nothing, and they are still not interchangeable:

- `IGNORE` says the pair is meaningless. It costs one word, generates no
  member, and counts toward `tabular-center::ignore-heavy` and `tabular-center::dead-row`.
- `stay()` says the developer received the action, did something about it, and
  chose not to move. It comes from a `HANDLE` cell, which the developer wrote.

A trace step asserting `ignored` must fail against a machine returning `Stay`,
and vice versa. Implementations must not normalise one into the other anywhere
— not in the dispatcher, not in the driver, and not in the conformance
adapter.

---

### 2.2 `GO(target)` / `GO(target, effects…)`

**Declaration.** A target state, then zero or more effects.

**Generator obligation.** Emit no member. The dispatcher arm constructs
`target` and evaluates to `Go(target)` carrying the listed effects in
declaration order.

**Runtime.** `Step { outcome: Go(target), effects: [...] }`.

**Rule R3 — the target must be statically constructible.** The generator
resolves the cell completely, so it must be able to build the target state
without developer code: the target is payload-free, or every payload field is
given as a literal.

Enforcement is by construction wherever the language allows it. Rust binds the
dispatcher's parameters under `__tabula_`-prefixed names, so `ctx`, `state`,
`action`, and `cells` are simply not in scope inside a `GO!` expression and a
target reaching for runtime data fails to resolve. Where construction cannot do
the job, emit `tabular-center::go-target` (see `diagnostics.md`). Both are conformant;
the by-construction form is preferred because it cannot be circumvented.

**Effects.** Named by variant. Qualification is spelling: a table holding
`Effect::StopClock` and a fixture saying `StopClock` are the same cell, because
effect names are compared by their last path segment.

**An empty effect list is legal**, and is the plain `GO(target)` form.

---

### 2.3 `EMIT(effects…)`

**Declaration.** One or more effects.

**Generator obligation.** Emit no member. The dispatcher arm evaluates to
`Stay` carrying the listed effects in declaration order.

**Runtime.** `Step { outcome: Stay, effects: [...] }`.

**An empty effect list is an error**, `tabular-center::empty-emit`. `EMIT()` means
"handled, no transition, no effects", which is `stay()` — and a cell that wants
that is either `IGNORE` (not applicable) or `HANDLE` (handled deliberately).
Silently accepting `EMIT()` would make the two indistinguishable in the table.

**`EMIT` is not `GO` to the same state.** `EMIT` produces `Stay`; a
self-targeting `GO` produces `Go(self)`. The distinction is visible to the
driver and to the trace format, and implementations must not fold one into the
other.

---

### 2.4 `HANDLE`

**Declaration.** The bare word, no arguments. The cell is identified by its
row and column position, never by a name written into the matrix.

**Generator obligation.** Emit exactly one required member, and dispatch to it.

The member must be:

- **required** — declared, not defaulted. This is the guarantee. An
  implementation that emits a member with a body has forfeited it, however
  sensible the body.
- **narrowed** — it receives the concrete state variant and the concrete action
  variant, already destructured, not the two union types. The dispatcher has
  already matched; passing the union back would make the developer re-match,
  and at forty cells that is the difference between a usable library and an
  unusable one.
- **colored by the prototype** — every modifier, attribute, receiver, and
  effect specifier on the `handle` prototype is copied verbatim onto the
  member. See `ARCHITECTURE.md` §5.

**How the member is named is deliberately not specified.** Rust expresses the
cell surface as trait bounds (`Handle<Timer, Idle, Start>`) because
`macro_rules!` cannot concatenate identifiers; Kotlin and Swift emit named
members (`idleStart`). Both deliver the same guarantee. `spec/conformance`
therefore compares behaviour and never generated source.

**Runtime.** Whatever `Step` the developer returns, unmodified. The generator
must not inspect, rewrite, or validate it.

---

### 2.5 `DELEGATE(child)`

**Declaration.** The alias of a declared child machine.

**Generator obligation.** Emit a required member, and a dispatcher arm that
**calls the child's `step`**. This is the whole point of the kind and it is
what distinguishes it from `HANDLE`: because the generated arm calls into the
child, the parent's bound set includes the child's entire cell surface, so a
hole anywhere in the child breaks the *parent's* build. A hand-written `HANDLE`
body is free to ignore the child, so no bound propagates and the hole goes
unnoticed.

**The composition property**, which every implementation must deliver:

> Scoping a total child into a total parent yields a total parent, and the
> compiler proves it by the same mechanism as everything else: unimplemented
> required members.

Each implementation carries a compile-fail fixture that removes a cell from a
*child* and asserts the error appears at the *parent*.

**Coverage is never inherited.** The parent row still lists every column. There
is no "everything else goes to the child" form, and adding one would be the
wildcard this library exists to remove wearing a different hat.

**The four lens operations are per `(parent state, child)`, not per cell:**
read the child's state out of the parent's, put it back, lift a child effect
into the parent's vocabulary, and hand the child its context. Only the action
prism — mapping a parent action to a child action — is per cell. A second
`DELEGATE` cell in the same row to the same child reuses the lens.

**Runtime.**

1. Map the parent action to a child action. If the child's alphabet has no
   counterpart, the cell reports **`Ignored`** — not `Stay`. The action was
   not handled, and the distinction is load-bearing for the reachability
   linter.
2. Otherwise run the child's `step`, then embed the resulting child state back
   into the parent's and lift the child's effects into the parent's
   vocabulary, preserving order.

**Embedding returns the full parent state**, not the narrowed row variant: a
child reaching its terminal state is usually the parent's cue to leave.

**Color flows one way.** A colorless child composes into a colored parent; the
reverse is an error. Where the generated delegate arm carries the parent's
color and calls the child's colored `step`, the language compiler rejects it by
construction — Kotlin's and Swift's generators both do exactly this, and so
does Rust's, where an async parent awaits its child and a plain one cannot.
Each language has a compile-fail fixture proving it, so `tabular-center::color-mismatch`
is reserved and emitted by nobody — it is the answer for a generator that
cannot put the parent's color on the call, and none of the three is that.

---

### 2.6 `UNREACHABLE`

**Declaration.** The bare word, no arguments.

**Generator obligation.** Emit **no** member. The dispatcher arm traps.

Writing `UNREACHABLE` *is* the developer's statement of intent, so there is
nothing left to implement. An earlier draft of `ARCHITECTURE.md` said the kind
both generated a required member and compiled to a trap; those conflict, and
the trap wins.

**Runtime.** The arm does not return. It panics, traps, or aborts, by whatever
the language's idiom is — `unreachable!()` in Rust, `error(...)` in Kotlin,
`fatalError(...)` in Swift.

**The trap message is normative**, because it is the one piece of runtime text
a developer will ever see from this kind:

```
tabular-center: <State> x <Action> was declared UNREACHABLE but occurred
```

`<State>` and `<Action>` are the declared variant names, spelled as declared.

**Counting.** `UNREACHABLE` cells are neither static nor member-generating.
They always appear in the coverage report, and a *concentration* of them fires
`tabular-center::unreachable-heavy` — one or two deliberate assertions are exactly what
the kind is for and must stay silent.

---

## 3. `EXPAND` is not a cell kind

`EXPAND(Running)` is a **row** directive, not a cell: it generates one sub-row
per direct subvariant of a nested sealed hierarchy. It is one level deep; nest
it to go further. Nested hierarchies do not auto-flatten (rule R5), because
defaulting to flatten would let a matrix explode without the declaration
visibly growing.

`EXPAND` does not appear in `Cell`, in `TABLE`, or in the `.tbl` format — by
the time the table exists, expansion has already happened and the sub-rows are
ordinary rows.

---

## 4. Serialised forms

Two shared text formats mention cells, and they spell effect lists
differently. This is not an accident to be tidied up: the `.tbl` form is
authored by hand and reads as a list, the `.grid` form is generated and must
stay narrow enough to keep columns aligned.

| Kind | `.tbl` (fixture) | `.grid` (golden) |
|---|---|---|
| `IGNORE` | `IGNORE` | `IGNORE` |
| `GO`, no effects | `GO(Target)` | `GO(Target)` |
| `GO`, with effects | `GO(Target, A, B)` | `GO(Target, A+B)` |
| `EMIT` | `EMIT(A, B)` | `EMIT(A+B)` |
| `HANDLE` | `HANDLE` | `HANDLE` |
| `DELEGATE` | `DELEGATE(child)` | `DELEGATE(child)` |
| `UNREACHABLE` | `UNREACHABLE` | `UNREACHABLE` |

The `.grid` renderer is byte-for-byte normative: the golden files in
`spec/conformance` are written by the Rust harness and **read** by every other
implementation, which never blesses. Three renderers agreeing covers the
padding rules, the right-trimming, and the cell text for all six kinds — the
details that rot silently.

The kind names used in diagnostics and coverage output are lowercase:
`ignore`, `go`, `emit`, `handle`, `delegate`, `unreachable`.

---

## 5. What this file does not specify

- **Member names and shapes.** See §2.4. Behaviour is compared; source is not.
- **Diagnostic message text**, except for the codes tabular-center itself authors. The
  missing-implementation error belongs to each language's own compiler, reads
  differently in each, and must not be intercepted or normalised. See
  `diagnostics.md`.
- **Effect capacity.** Rust bounds a `Step`'s effects at a const-generic `K` so
  the type is allocation-free under `no_std`; Kotlin and Swift use a list. A
  machine that exceeds a capacity is a Rust-specific runtime error, not a
  conformance property.
- **Whether the table is a true compile-time constant.** Rust emits a `const`;
  the other two emit a value. Both satisfy every consumer of `TABLE`.
