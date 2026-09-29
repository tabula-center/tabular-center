# Which implementation emits which diagnostic

Machine-readable, and read by `tools/verify diagnostics-coverage`. Every code
in `spec/diagnostics.md` appears here, with the implementations that emit it.
The check compares this table against what the source actually contains and
fails on any disagreement in either direction.

It exists because nothing compared the three. The divergence below was found by
looking, not by a check, after this file's absence had let it sit: of the
twenty-two codes then, Rust emitted thirteen, and Kotlin and Swift twenty each.
(A twenty-third, `tabular-center::composable-transition`, came later and is
Kotlin's alone; see the note under the table.)
Two are emitted by nobody, each for a stated reason:
`tabular-center::color-mismatch` by decision (see the last section), and
`tabular-center::unsupported-color` because only Rust can have it, and does. The gaps
are defensible — see the notes — but "defensible" and "nobody noticed" are
different states, and only one of them survives a refactor.

```coverage
tabular-center::color-mismatch     -
tabular-center::composable-transition  kotlin
tabular-center::dead-column        rust kotlin swift
tabular-center::dead-row           rust kotlin swift
tabular-center::empty-emit         rust kotlin swift
tabular-center::extra-row          rust kotlin swift
tabular-center::go-target          kotlin swift
tabular-center::ignore-heavy       rust kotlin swift
tabular-center::missing-row        rust kotlin swift
tabular-center::no-static-entry    rust kotlin swift
tabular-center::no-static-exit     rust kotlin swift
tabular-center::path-broken        rust kotlin swift
tabular-center::path-duplicate     kotlin swift
tabular-center::path-unknown-state rust kotlin swift
tabular-center::path-unterminated  rust kotlin swift
tabular-center::payload-hoist      rust kotlin swift
tabular-center::row-arity          rust kotlin swift
tabular-center::unknown-cell       rust kotlin swift
tabular-center::unknown-child      kotlin swift
tabular-center::unknown-effect     kotlin swift
tabular-center::unknown-state      kotlin swift
tabular-center::unreachable-heavy  rust kotlin swift
tabular-center::unsupported-color  rust
```

`composable-transition` is Kotlin's alone: it warns about `@Composable`, which
only a Kotlin prototype can carry. It is the one warning in the table, tested by
a KSP fixture that must BUILD (`//~ BUILDS`) and print it.

`unsupported-color` is Rust's alone, and cannot be otherwise: Kotlin and Swift
copy prototype modifiers verbatim, so every modifier their compiler accepts is
a color they support. Rust needs a colored twin of `Handle` per color, and
stable Rust offers one, `async`.

## Which lints a conformance fixture actually trips

The table above says the three implementations emit the same codes. It does not
say any of them is ever *exercised* by a fixture, and that turned out to be a
different and worse question.

The rendered `.lint` output is the only cross-language check on lint
behaviour: each implementation renders `report(table, payloads)` and all three
must produce the same bytes. Nothing is committed -- `renderings-agree` renders
from every implementation present and diffs them -- and that step also checks
the table below against the lints it just rendered. When this section was
written, two codes appeared across all six fixtures; across today's eleven, all
seven runtime lints do.

```fixtures
tabular-center::dead-column        dead-column
tabular-center::dead-row           nested-delegate retry
tabular-center::ignore-heavy       ignore-heavy
tabular-center::no-static-entry    no-static-entry
tabular-center::no-static-exit     no-static-exit
tabular-center::payload-hoist      payload-hoist
tabular-center::unreachable-heavy  unreachable-heavy
```

No runtime lint is now implemented three times and compared never. Five were
-- `dead-column`, `ignore-heavy`, `no-static-exit`, `no-static-entry` and
`unreachable-heavy` -- each covered by its implementation's own unit tests
and by nothing that compared the three, because no fixture happened to cross
its line. Each closed the same way: a fixture shaped so that its lint is the
only finding, a `.tbl`, four goldens, a trace, and three adapters.

The table stays, because what it catches now is regression: a fixture edited
so that it stops tripping its lint, or starts tripping a second one.

Listed as `-` rather than silently absent so that closing one is a diff to this
file, and so nobody rediscovers the gap by finding a bug it would have caught.

## The four `path-*` codes are Kotlin and Swift only, for the same reason

`spec/happy-paths.md` is the feature. Rust has no `RawMachine` and no
`buildDesc` -- its matrix is `macro_rules!`, expanded straight to types and a
dispatcher -- so there is no intermediate model for a spine to be validated in.
`@Path` in Rust is a macro arm, and its rejections are `compile_error!` the way
`extra-row` already is.

Same guarantee, different mechanism, and the same shape as the four codes
below.

## Why Rust emits four fewer, and why that is not a bug

`tabular-center::go-target`, `tabular-center::unknown-state`, `tabular-center::unknown-effect` and
`tabular-center::unknown-child` all say the same kind of thing: a cell names something
the machine does not declare.

In Kotlin and Swift the matrix is read by a processor — KSP, or
`MachineSyntax` — which sees names as strings and must check them itself.
Nothing downstream would catch `GO(Typo)`: the emitter would render
`S.Typo` and the error would surface as a compiler message about generated
code the user never wrote, which `spec/diagnostics.md` rules out.

In Rust the matrix is `macro_rules!`, and `GO!(Typo)` expands to a path that
does not resolve. rustc's error names the token in the user's own file, points
at their line, and suggests the states that do exist. A `compile_error!`
checking the same thing first would replace a better message with a worse one.

So the absence is the language doing the work, which is the same argument
`RELEASING.md` makes for Rust being one crate where Kotlin is five. What it is
not is an accident, and the table is what keeps it from becoming one.

## `tabular-center::color-mismatch` is emitted by nobody, by decision

It has a section in `spec/diagnostics.md` and no implementation. That was an
open question here until September 2026: either unimplementable by design, or
a case none of the three covers.

It is the first. Every generator puts the **parent's** color on the delegate
call, so a colored child under a colorless parent is refused by the language —
rustc, kotlinc, swiftc — before any check of ours could run. Each of the three
now has a compile-fail fixture proving it, listed in `spec/diagnostics.md`.
The `-` is no longer a question mark: it is the entry that would change if a
generator ever stopped carrying the color, and the fixtures are what would
fail first.
