# Matrix files

**Put the matrix in its own file, named `*.tb.rs`, `*.tb.kt` or `*.tb.swift`,
and configure every ordinary formatter to leave those files alone.**

Recommended, not enforced. Nothing in the library reads the extension, and a
machine declared in an ordinary source file works exactly as well. This is a
convention for humans and for formatters.

## Why the matrix needs its own file

A matrix is column-aligned on purpose. The alignment is not decoration: it is
the thing a reader scans, and it is why a forty-cell machine can be reviewed at
all. `spec/cells.md` and `swift/macros/SURFACE.md` both make it normative that
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

**Swift** — `.swift-format`, via `swift-format`'s ignore file, or by excluding
the pattern from the formatter invocation. swift-format has no in-file
suppression comparable to rustfmt's `ignore`, so the exclusion belongs in
whatever runs it.

## One wrinkle, in Rust

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

## The formatter this anticipates

`tabula-fmt` is in `PLAN.md`'s backlog: a formatter that pads cells to align
columns and does nothing else. The extension is what would let it run
automatically without fighting the language's own formatter over the same
files, and it is worth adopting before that tool exists, because the exemption
is useful on its own.
