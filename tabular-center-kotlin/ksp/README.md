# tabula-ksp

KSP is a Maven artifact. The environment this was first written in could not
reach Maven, so `TabulaProcessor.kt` was written unverified while **everything
it feeds into was already covered**. It now runs under `nix flake check` against
the artifact set pinned in `tabular-center-kotlin/nix/gradle-lock.json` (see below).

The arrangement is kept because it paid: the work went into making this file as
small and as dumb as possible.

| | where | verified |
|---|---|---|
| `KSP API -> RawMachine` | `ksp/` | `kotlin-ksp` (goldens), `kotlin-ksp-compile-fail`, `kotlin-ksp-incremental` |
| validation + every declaration diagnostic | `codegen/Raw.kt` | yes, 14 cases |
| source emission | `codegen/Emit.kt` | yes: golden, then compiled |
| the emitted code still enforces the guarantee | `codegen/compile_fail/` | yes |

A bug here is an *extraction* bug — a wrong argument name, a missing null check
— not a logic bug. It surfaces as an obviously wrong `RawMachine` rather than as
subtly wrong generated code.

## It ran

`gradle build` in `examples/kotlin/06-generated` succeeded. The processor read
`@Machine` and `@Row` off `Machine.tb.kt`, built a `MachineDesc`, handed it to
`TabulaCodegen`, and the emitted dispatcher compiled — with `Impl.kt`
satisfying a `Cells` interface that did not exist until the build ran.

This file used to add "and the behavioural checks passing against it". They
were compiled and never executed: `test/*.kt` are `main` functions, and
Gradle's `test` task is a JUnit runner that found nothing to run and passed.
`build.gradle.kts` now registers one `JavaExec` per check and hangs them off
`check`, so `gradle build` runs `GeneratedTestKt` and `GateTestKt` and fails if
either does.

This file used to hold four predictions about what would break first. Keeping
score, because the scoring is the useful part:

1. **`getDeclaredFunctions` could not compile.** Correct, and fixed before the
   first run: the shim called a KSP extension by fully-qualified name with the
   receiver as an argument, which is not Kotlin.
2. **`CellSpec` needs an `args` parameter.** Wrong — already there, and the
   prediction was stale. Removed.
3. **Annotation argument shapes.** Did not bite. `classes()` now throws on a
   shape it cannot read rather than dropping it silently, so if a future KSP
   version changes the shape it will say so instead of producing a machine with
   no states.
4. **`DELEGATE` is not wired.** Was true until September 2026, when
   `childrenOf` landed. A cell names the child's annotated declaration --
   `CellSpec(Kind.DELEGATE, child = RetrySpec::class)` -- and the processor
   reads the rest from that class: the package its generated code lands in,
   the alias the parent's members are named from, its types, its context. A
   parent declares nothing else about its child. `Retry.tb.kt` and `Job.tb.kt`
   in the example are the pair, and `kspTwins` diffs both.

   One limit, named by `tabula::unknown-child`: a child must be compiled with
   its parent, because `@Machine` is `SOURCE`-retention and a child from a
   prebuilt module has no annotation left to read.

The two bugs that actually stopped it were in `build.gradle.kts`, not the
processor — `files()` where sources were meant, and undeclared source sets —
and both were found by reading. The third, a missing harness on the test path,
took a real run.

## Building it

`build.gradle.kts` was written from the KSP documentation rather than from a
successful run, and got the same read the processor did, which turned up one
near-certain bug.

It used to depend on the generator with `implementation(files("../codegen"))`.
`files()` puts a path on the compile classpath as a directory of **class**
files, and `../codegen` holds `.kt` sources, so every `import codegen.*` in
`TabulaProcessor.kt` would have failed to resolve. Those sources are compiled
into this module instead.

Filtered with exclude patterns rather than by listing files, because `srcDir`
takes a directory. Without them the build would sweep in `Main.kt` (a CLI entry
point), `Tests.kt` (the golden-diff suite, which reads paths relative to the
repository root), and `compile_fail/` — fixtures that are *supposed* not to
compile.

Two notes, one of which stopped being a note:

- There **is** a `settings.gradle.kts` now. It was missing, and the entry here
  said Gradle would synthesise one and take the project name from the
  directory — `ksp` — which was "harmless for a build, wrong for publication".
  It stopped being harmless when the offline repository landed: an included
  build resolves its plugins through its *own* `pluginManagement`, and a
  synthesised settings file defaults to the plugin portal. So this build would
  have gone on reaching for the network however the example was configured,
  and failed on a line naming a plugin rather than a repository. Writing the
  file fixed the publication half as a side effect.
- The KSP version is pinned to `2.1.20-1.0.32`, matching the Kotlin version.
  KSP releases are tied to a specific Kotlin compiler build, so this pair moves
  together or not at all.

What the processor must extract is stated by hand in `kspTwins`
(`codegen/Main.kt`), one description per example machine, and
`tools/verify kotlin-ksp` diffs the twins' emitted source against what KSP
generated -- both produced at check time. Generated code is not committed;
this replaced `ksp/golden/`, which held the same expectation as committed
output.

## Where the artifacts come from

Not from Maven, under nix. `tabular-center-kotlin/nix/gradle-lock.json` pins every artifact this
build and the example need, by URL and hash; `tabular-center-kotlin/nix/gradle-repo.nix` turns that
into a directory; `TABULA_MAVEN_REPO` points both builds at it. Nothing
resolves over the network inside a nix build, which is what the fixed-output
derivation this replaced kept failing to do.

Regenerating the lock needs network and is not a derivation:

```
./tabular-center-kotlin/tools/gradle-lock          # rewrites tabular-center-kotlin/nix/gradle-lock.json
./tabular-center-kotlin/tools/gradle-lock --check  # CI: is the committed lock still complete?
```

Run it after changing a version in either `build.gradle.kts`, and commit the
result. `ci.yml`'s `check` job runs `nix run .#gradle-lock -- --check`: `nix
run` is not sandboxed, so that job has both the flake's pinned Gradle and a
network, which is what the question needs. (It used to be `check-no-nix`,
whose own Gradle version would have reported version skew as staleness.)
