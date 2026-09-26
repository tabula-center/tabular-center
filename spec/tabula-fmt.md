# `tabula-fmt`

A formatter for `*.tb.rs`, `*.tb.kt` and `*.tb.swift`. It has exactly one job:
**pad cells so the columns line up.** Everything else it might plausibly do is
listed below as something it must not.

Written before the tool, for the reason `tabular-center-swift/macros/SURFACE.md` was: the
contract is the part that can be reviewed by reading, and a formatter's
contract is almost all of its risk.

## Why it is one tool and not three

A matrix looks different in each language:

```rust
Red    => [  GO!(Green),    GO!(Red)   ];
```
```kotlin
listOf(Cell.Go("Amber"), Cell.Ignore),
```
```swift
[ .go(target: "Unlocked", effects: []),  .ignore ],
```

They differ in punctuation and agree in structure: a run of sibling lines, each
a bracketed list of comma-separated cells. Alignment needs the structure and
not the punctuation, so one tool handles all three — and a language-specific
formatter would be three chances to get the same thing subtly differently.

It follows that `tabula-fmt` is **not a parser**. It does not know what a cell
means, which is the point: a tool that understood Rust would have to be updated
for Kotlin, and a tool that understands neither is correct for both.

## What it does

1. Find **runs**: two or more consecutive lines with the same leading
   indentation and the same bracket shape.
2. Split each into cells on top-level commas — top-level meaning outside
   brackets, parens and string literals. `GO!(Idle, StopClock)` is one cell.
3. Pad each cell to the widest in its column, leaving one space after the
   comma.
4. Leave every line not in a run exactly as it found it.

A run of one line is not a run. A single row has no column to align to, and
padding it to some remembered width is how a formatter starts having opinions.

## What it must not do

- **Reflow, wrap, or join lines.** One row per line is the shape; a formatter
  that wrapped a long row would destroy the artifact it was asked to protect.
- **Touch anything outside a run** — imports, attributes, comments, the
  `machine`/`states`/`actions` header lines.
- **Reorder cells.** Position is meaning. A cell's column *is* its action.
- **Parse or validate.** Arity is `tabula::row-arity`'s job, at compile time,
  with a better message than a formatter could give.
- **Rewrite a file it cannot confidently read.** See below.

## Failure is refusal, not best effort

If a run cannot be split — unbalanced brackets, an unterminated string, a cell
containing a comma the splitter cannot classify — `tabula-fmt` leaves the file
**untouched** and reports it.

This is the one rule worth arguing for. A formatter that half-understands a
file and writes it back anyway corrupts source, and it corrupts it in the file
the developer is least able to eyeball afterwards, because eyeballing is
exactly what the alignment was for. Refusing costs an unformatted file.
Guessing costs a matrix.

`--check` reports what would change and exits non-zero; that is what CI runs.
Refusal is a failure in `--check` too: a file the tool cannot read is a file
nobody is checking.

## Idempotence

`fmt(fmt(x)) == fmt(x)`, and the test suite should assert it on every fixture.
A formatter that is not idempotent turns every `--check` into a coin flip and
every review into a diff of whitespace.

## Where it lives

At the repository root, as `tabula-fmt/` — not inside `tabular-center-rust/`, `tabular-center-kotlin/` or
`tabular-center-swift/`.

That placement is the same argument as the tool being one tool. A formatter
that lived in `tabular-center-rust/` would be a Rust-workspace member that Kotlin and Swift
developers build in order to format their own files, and its home would imply
an ownership that is not true: it belongs to the `.tb.` format, which is
language-agnostic, and to `spec/matrix-files.md`, which is where that format is
defined.

It sits beside `spec/` and `tools/` for the same reason those do.

## Where it runs

`tools/verify fmt` on the `.tb.` files, alongside the language formatters on
everything else. The language formatters are already told to skip these files —
`#[rustfmt::skip]` in Rust, `[*.tb.kt]` in `.editorconfig`, an exclusion
wherever `swift-format` is invoked — so the two never fight over the same
bytes.
