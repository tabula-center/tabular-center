# Matrix files

**Put the matrix in its own file, named `*.tb.rs`, `*.tb.kt` or `*.tb.swift`,
and configure every ordinary formatter to leave those files alone.**

Recommended, not enforced. Nothing in the library reads the extension, and a
machine declared in an ordinary source file works exactly as well. This is a
convention for humans and for formatters.

## Why the matrix needs its own file

A matrix is column-aligned on purpose. The alignment is not decoration: it is
the thing a reader scans, and it is why a forty-cell machine can be reviewed at
all. `spec/cells.md` and `tabular-center-swift/macros/SURFACE.md` both make it normative that
rows line up.

General-purpose formatters do not know that. Their job is to normalise
whitespace, and normalising whitespace is precisely what destroys a matrix —
collapsing the padding turns a rectangle into a list of transitions, which is
what a `switch` already gives you. This repository already carries a workaround
for it, in `.editorconfig`:

```
[*.kt]
ktlint_standard_no-multi-spaces = disabled
```

That disabled alignment rules for **every** Kotlin file in the project, to
protect the handful that hold matrices — a wide exemption for a narrow problem,
paid for by giving up formatting on all the ordinary code. It is now scoped to
`*.tb.kt`, and ordinary Kotlin is formatted normally again.

It also gives a reviewer a signal before they open anything. A diff touching a
`.tb.` file is a diff that changes the machine's shape, which is the review
this design exists to make possible.

## Configuring the formatters

Exempting by extension, per language. Each of these tells a general-purpose
formatter to skip the file so a matrix-aware one can own it:

**Rust** — **not** `rustfmt.toml`. `ignore` is a nightly-only option; on stable
rustfmt prints

```
Warning: can't set `ignore = ...`, unstable features are only available in
nightly channel.
```

once per file and formats everything anyway. A setting that does nothing and
says so twenty times is worse than no setting. On stable the exemption is
per-item and silent:

```rust
#[rustfmt::skip]
transition_matrix! {
    // ...
}
```

In practice rustfmt already leaves `macro_rules!` invocation bodies alone,
which is why the matrices in this repository survive without it. `#[rustfmt::skip]`
is the guarantee rather than the observation, and it is worth writing for a
matrix declared any other way.

**Kotlin** — `.editorconfig`:

```
[*.tb.kt]
ktlint_standard_no-multi-spaces = disabled
ktlint_standard_argument-list-wrapping = disabled
ktlint_standard_indent = disabled
```

**Swift** — `// swift-format-ignore-file`, the first line of the file:

```swift
// swift-format-ignore-file
```

It does have an in-file suppression comparable to rustfmt's `ignore`, contrary
to what this paragraph said until September 2026, and it is the better of the
two mechanisms available: swift-format has no per-glob rule configuration, so
the alternative is excluding the pattern from whatever invokes the formatter —
one more thing to remember in every invocation, and invisible from the file it
protects. `swift-format-config` requires the directive on every `.tb.swift`,
which holds whether or not a config exists and whether or not anyone has run a
formatter yet.

## Rust moves types, not just text

`machine.tb.rs` is not a valid module name, so `mod machine.tb;` does not
exist. Two ways round it, and the first is preferable:

```rust
#[path = "machine.tb.rs"]
mod machine;
```

```rust
include!("machine.tb.rs");
```

`#[path]` keeps the file a real module with its own namespace; `include!`
splices it into the current one. Kotlin and Swift have no equivalent problem —
neither derives module structure from file names.

There is a second consequence, and it is the reason Rust was done last.
`transition_matrix!` **generates the state and action types**, so moving the
invocation moves `State`, `Action` and every variant struct into the new
module. The crate that had them at its root needs them back:

```rust
#[path = "machine.tb.rs"]
mod machine;

pub use machine::*;
```

Splitting a matrix out of a Rust file is therefore a change to the crate's
namespace, not a move of text. Worth knowing before starting, and worth the
`pub use` being deliberate rather than discovered.

## Where it is used

Two examples carry it, one per language that can:

- `tabular-center-kotlin/examples/06-generated/src/Machine.tb.kt` — the annotated declaration
  KSP reads.
- `tabular-center-kotlin/examples/01`–`05` — each hand-written example's `Table` literal, in
  `<Name>.tb.kt` beside the handlers. `04-login` holds two, as top-level
  `AUTH_TABLE` and `SESSION_TABLE`, because an `object` cannot span files;
  `auth.TABLE` and `session.TABLE` still name them. `kotlin-matrix-stable`
  checks every `.tb.kt`, `Cell.` rows included, and fails one with no rows.
- `tabular-center-swift/examples/Sources/SpecCheck/Turnstile.tb.swift` — the `Table`
  literal, moved out of `Turnstile.swift` into an extension. `TrafficLight`,
  `Retry`, `ObservableCounter` and `Timer` the same way; `Login`'s table was
  a top-level `SESSION_TABLE` and stays one, in `Login.tb.swift`. None is
  checked for formatter stability yet: `swift-matrix-stable` waits on
  swift-format. Each carries `// swift-format-ignore-file`, as do the eleven
  macro fixtures. `swift-matrix-stable` runs swift-format over every one and
  requires it back byte for byte; `swift-format-config` requires the directive
  itself, and holds where no toolchain exists.
- `tabular-center-rust/examples/01-traffic-light/src/machine.tb.rs` — the
  `transition_matrix!` invocation, reached with `#[path]`. Every Rust example
  now: `02-timer` and `03-retry` the same way, and `04-login`'s two matrices
  as `auth.tb.rs` and `session.tb.rs`, private modules at the crate root
  re-exported by `pub mod auth` and `pub mod session` -- a `#[path]` inside
  an inline module resolves against a directory named after that module,
  and one rule for every example is simpler than a directory per matrix.
- `tabular-center-kotlin/test/TimerSpec.tb.kt` — the reference machine's declaration, and the
  one piece of *library* code carrying the convention. Split out of
  `ReferenceTimer.kt` when `kotlin-matrix-stable` was first switched on.

Examples rather than library code, deliberately: they are read as templates, so
a convention appearing in none of them is one nobody adopts.

**Note what the Swift one does not do.** It moves *only* the matrix. Renaming
`Turnstile.swift` wholesale would have been less work and would have exempted
the handler bodies from formatting too — the same over-broad exemption the
`[*.kt]` block had before it was narrowed. A `.tb.` file earns its exemption by
containing nothing that wants formatting.

Kotlin's has now moved: `tabular-center-kotlin/test/TimerSpec.tb.kt` holds the `@Machine` and
`@Row` declarations that used to sit in `ReferenceTimer.kt`. It moved because
it had to — `kotlin-matrix-stable` runs ktlint's formatter over a copy of
`tabular-center-kotlin/` and compares the matrix rows, and with the declaration in an
ordinary `.kt` file the `[*.tb.kt]` exemption did not reach it. The check had
never executed (see `PLAN.md`), so nothing said so.

That is the argument for the convention restated as evidence: the exemption is
not a nicety, and a matrix outside a `.tb.` file is one collapse away from
being a list of transitions.

Swift's and Rust's have not. In Swift that is a rename; in Rust it needs the
`#[path]` above, and the `transition_matrix!` invocation generates the state
and action types, so splitting it out of `lib.rs` moves those into a submodule
and every `Handle` impl has to follow. Worth doing, and worth doing as its own
patch rather than inside this one.

## The formatter this anticipates

`tabula-fmt` is in `PLAN.md`'s backlog: a formatter that pads cells to align
columns and does nothing else. The extension is what would let it run
automatically without fighting the language's own formatter over the same
files, and it is worth adopting before that tool exists, because the exemption
is useful on its own.
