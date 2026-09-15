# What we publish

Not one artifact per language. The pieces have different audiences and
different lifetimes, and shipping them together forces every consumer to take
all of them.

## The rule

**A dependency that reaches a user's production binary is a dependency they
cannot remove.** So the runtime is published alone, with nothing else in it,
and everything that exists only at build time or test time is a separate
artifact they can scope accordingly.

That is why `tabula-core` compiles against an *empty* classpath in
`tools/verify` — the zero-runtime-dependency rule enforced by construction
rather than asserted in a README.

## The artifacts

| Language | Artifact | Scope | Contents |
|---|---|---|---|
| Rust | `tabula` | runtime | `Step`, `Cell`, `Table`, `Driver`, lints, export, **and `transition_matrix!`** |
| | `tabula-conformance` | not published | the fixture harness; internal |
| | `tabula-examples` | not published | worked examples; internal |
| Kotlin | `tabula-core` | `implementation` | `Step`, `Cell`, `Table`, `Driver`, `Export`, `Lint` |
| | `tabula-annotations` | `compileOnly` | `@Machine`, `@Row`, `CellSpec` |
| | `tabula-codegen` | transitive of `ksp` | `MachineDesc`, validation, the emitter |
| | `tabula-ksp` | `ksp` | the processor |
| | `tabula-testing` | `testImplementation` | `.tbl`/`.trace` parser, `checkTable` |
| Swift | `Tabula` | runtime | the core |
| | `TabulaCodegen` | transitive of the plugin | `MachineDesc`, validation, the emitter |
| | `TabulaMacros` | build-time plugin | the macro implementation |
| | `TabulaTesting` | test target | the fixture harness |

### Why Rust is one crate and Kotlin is five

`transition_matrix!` is `macro_rules!`, which ships *inside* the library it is
declared in — there is nothing to separate. A Rust user gets the macro and the
runtime together because the language gives no way to take one without the
other, and no reason to want to.

Kotlin's generator is a compiler plugin, so it is genuinely a different
artifact with a different scope (`ksp` rather than `implementation`). The
annotations are `compileOnly` because they are `SOURCE`-retention: they exist
for the processor to read and are gone by the time anything runs. Publishing
them as `implementation` would put dead weight in every consumer's runtime
classpath.

This asymmetry is not a wart. It is the same shape as ARCHITECTURE §11.0:
where the languages differ, follow the language rather than forcing a uniform
answer nobody reads side by side.

### Why `tabula-testing` is separate

A machine in production has no use for a fixture parser. A test dependency
that ships to users is a test dependency nobody removes later.

## The boundaries are checked, not documented

`tools/verify kotlin` compiles each artifact against **only** its declared
dependencies:

```
core          empty classpath          proves it needs nothing
annotations   empty classpath          proves compile-time only
testing       core                     proves it needs neither of the others
```

A layering violation fails there rather than being discovered by a user with a
dependency graph.

## Releasing

```sh
nix run .#release -- 0.1.0   # VERSION, manifests, lockfiles, verify, tag
nix run .#publish            # dry run
nix run .#publish -- --execute
```

`release` writes the version and pushes nothing. `publish` is a dry run unless
told otherwise — because a bad release is a corrected commit, while a bad
publish is a version burned forever on crates.io, which does not allow
deletion.

Swift has no registry: the Package Index resolves from git tags, so publishing
is `git push --follow-tags`.
