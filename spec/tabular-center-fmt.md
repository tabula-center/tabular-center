# `tabular-center-fmt`

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

It follows that `tabular-center-fmt` is **not a parser**. It does not know what a cell
means, which is the point: a tool that understood Rust would have to be updated
for Kotlin, and a tool that understands neither is correct for both.

## What it does

1. Find **runs**: two or more consecutive lines with the same leading
   indentation and the same bracket shape -- the same brackets, the same
   trailing punctuation, and the same number of cells.
2. Split each into cells on top-level commas — top-level meaning outside
   brackets, parens and string literals. `GO!(Idle, StopClock)` is one cell.
3. Pad each cell so its column lines up, leaving one space after the comma.
4. Leave every line not in a run exactly as it found it.

A run of one line is not a run. A single row has no column to align to, and
padding it to some remembered width is how a formatter starts having opinions.

### Decided by running it

Points 1 and 3 left choices open. Each was settled by running a prototype over
every `.tb.` file in the repository before the tool was written -- 52 files,
idempotent on all of them, none refused -- and each answer is what that run
showed:

- **Which list is the row.** The shallowest `[` among the brackets that close
  at the end of the line; with no `[`, the shallowest `(` with a comma in it.
  So in `@Row(S.Idle::class, [CellSpec(...), ...])` the row is the `[...]`,
  never `@Row`'s parentheses, and never one cell's own arguments -- which
  "the group with the most commas" got wrong for one-cell rows such as
  `[CellSpec(Kind.GO, to = S.Busy::class)]`.
- **Columns never shrink.** A column is as wide as its widest cell or its
  widest *current* slot, whichever is larger. Most matrices here carry a
  hand-aligned column-header comment (`//   Start   Tick   Cancel`), and
  padding only to the widest cell would pull every cell out from under it on
  the first run. Misaligned rows grow to match; nothing is compacted.
- **Closers belong to the author.** If a run's closing brackets are already
  aligned -- Rust's matrices align theirs -- they stay aligned. Otherwise each
  row's last cell and whatever follows it are left exactly as written: Kotlin
  and Swift tables close compactly, and padding their last cells only to line
  up `]` produced runs of spaces nobody would write.
- **Header lines are never rows.** "The `machine`/`states`/`actions` header
  lines" above is enforced by name: a line whose prefix is a `.tb.` header key
  -- `machine`, `states`, `actions`, `effects`, `initial`, `context`, `paths`,
  `cells` -- followed by `:` or `=`, or a `@Path` spine, never joins a run,
  even with a row's shape. Swift's `states: [...]` and `actions: [...]` have
  exactly that shape, one after the other. These are the format's own words,
  not a parse of any language. `@Path` also matters for another reason: the
  compile-fail fixtures that exercise paths match their `//~ AT:` markers by
  line content, and realigning a path would silently break them.

## What it must not do

- **Reflow, wrap, or join lines.** One row per line is the shape; a formatter
  that wrapped a long row would destroy the artifact it was asked to protect.
- **Touch anything outside a run** — imports, attributes, comments, the
  `machine`/`states`/`actions` header lines.
- **Reorder cells.** Position is meaning. A cell's column *is* its action.
- **Parse or validate.** Arity is `tabular-center::row-arity`'s job, at compile time,
  with a better message than a formatter could give.
- **Rewrite a file it cannot confidently read.** See below.

## Failure is refusal, not best effort

If a run cannot be split — unbalanced brackets, an unterminated string, a cell
containing a comma the splitter cannot classify — `tabular-center-fmt` leaves the file
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

At the repository root, as `tabular-center-fmt/` — not inside `tabular-center-rust/`, `tabular-center-kotlin/` or
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
