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
| Rust | `tabular-center` | runtime | `Step`, `Cell`, `Table`, `Driver`, lints, export, **and `transition_matrix!`** |
| | `tabular-center-conformance` | not published | the fixture harness; internal |
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

## What counts as a breaking change

One `VERSION` for all three languages, so a major bump in one is a major bump
in all: the conformance suite holds them to one behaviour, and a user reading
"tabular-center 2.0" should not have to ask *which* tabular-center.

The public API is larger than the runtime. **Generated code is API**: a
developer implements the members the generator demands, so what the generator
emits is a contract with every implementation of every machine.

The test for any change: **does an unchanged declaration, with an unchanged
implementation, still compile and still behave the same?** If not, it is
breaking.

| Change | Bump | Why |
|---|---|---|
| A generated member renamed, removed, or re-signatured (`idleStart`, `retryChildState`, a narrowed type, where a color is placed) | major | every implementation stops compiling |
| A new required member for a declaration that did not require it | major | the guarantee turned on an existing machine -- the one change that is breaking *because the library works* |
| A diagnostic that refuses a declaration which used to compile | major | the declaration is unchanged and no longer builds |
| A diagnostic that refuses what was already refused, now in tabular-center's words instead of the compiler's | patch | nothing that built stops building |
| A diagnostic **code** renamed or removed | major | codes are normative (`spec/diagnostics.md`); tooling matches on them |
| A diagnostic **message** reworded, code unchanged | patch | match on codes, not prose |
| New grammar that old declarations do not use (`paths`, `prototype`, `Emit`) | minor | additive: an old declaration generates the same code. `happy-paths.md`'s additive test is this rule, checked |
| A new runtime lint | minor | advisory; it never fails a build |
| A rendering's format (`.grid`, `.mmd`, `.lint`, `.cov`) | minor | not a build contract, but tooling may parse it; say so in the notes |
| A runtime type or function (`Step`, `Table`, `Driver`) | ordinary semver | the runtime is a library like any other |

Two consequences worth stating.

- **Rust's `macro_rules!` internals are not API.** `__tabula_*` helpers are
  `#[doc(hidden)]` and may change in any release; only `transition_matrix!`'s
  grammar and what it generates are.
- **A bug fix can be breaking.** If generated code was wrong in a way
  implementations had to work around -- a member that should not have been
  required -- removing it is still a signature change. It goes out as a major
  with a note, not as a patch that breaks a build nobody expected to break.

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
