# Which implementation emits which diagnostic

Machine-readable, and read by `tools/verify diagnostics-coverage`. Every code
in `spec/diagnostics.md` appears here, with the implementations that emit it.
The check compares this table against what the source actually contains and
fails on any disagreement in either direction.

It exists because nothing compared the three. The divergence below was found by
looking, not by a check, after this file's absence had let it sit: Rust emits
twelve of the sixteen codes and Kotlin and Swift emit all sixteen. The gap is
defensible — see the notes — but "defensible" and "nobody noticed" are
different states, and only one of them survives a refactor.

```coverage
tabula::color-mismatch     -
tabula::dead-column        rust kotlin swift
tabula::dead-row           rust kotlin swift
tabula::empty-emit         rust kotlin swift
tabula::extra-row          rust kotlin swift
tabula::go-target          kotlin swift
tabula::ignore-heavy       rust kotlin swift
tabula::missing-row        rust kotlin swift
tabula::no-static-entry    rust kotlin swift
tabula::no-static-exit     rust kotlin swift
tabula::payload-hoist      rust kotlin swift
tabula::row-arity          rust kotlin swift
tabula::unknown-cell       rust kotlin swift
tabula::unknown-child      kotlin swift
tabula::unknown-effect     kotlin swift
tabula::unknown-state      kotlin swift
tabula::unreachable-heavy  rust kotlin swift
```

## Why Rust emits four fewer, and why that is not a bug

`tabula::go-target`, `tabula::unknown-state`, `tabula::unknown-effect` and
`tabula::unknown-child` all say the same kind of thing: a cell names something
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

## `tabula::color-mismatch` is emitted by nobody

It has a section in `spec/diagnostics.md` and no implementation. Prototype
modifiers are copied rather than enumerated, so a mismatch between a
prototype's color and a handler's is a type error before any check runs — the
same argument as above, in all three languages this time.

Either it is unimplementable by design and the spec should say so, or there is
a case none of the three covers. Listed as `-` until somebody answers that,
because a documented diagnostic no implementation emits is a promise to a
reader that nothing keeps.
