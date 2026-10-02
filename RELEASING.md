# What we publish

Not one artifact per language. The pieces have different audiences and
different lifetimes, and shipping them together forces every consumer to take
all of them.

## The rule

**A dependency that reaches a user's production binary is a dependency they
cannot remove.** So the runtime is published alone, with nothing else in it,
and everything that exists only at build time or test time is a separate
artifact they can scope accordingly.

That is why `tabular-center-core` compiles against an *empty* classpath in
`tools/verify` — the zero-runtime-dependency rule enforced by construction
rather than asserted in a README.

## The artifacts

| Language | Artifact | Scope | Contents |
|---|---|---|---|
| Rust | `tabular-center` | runtime | `Step`, `Cell`, `Table`, `Driver`, lints, export, **and `transition_matrix!`** |
| | `tabular-center-conformance` | not published | the fixture harness; internal |
| | `tabular-center-examples` | not published | worked examples; internal |
| Kotlin | `tabular-center-core` | `implementation` | `Step`, `Cell`, `Table`, `Driver`, `Export`, `Lint` |
| | `tabular-center-annotations` | `compileOnly` | `@Machine`, `@Row`, `CellSpec` |
| | `tabular-center-codegen` | transitive of `ksp` | `MachineDesc`, validation, the emitter |
| | `tabular-center-ksp` | `ksp` | the processor |
| | `tabular-center-testing` | `testImplementation` | `.tbl`/`.trace` parser, `checkTable` |
| Swift | `TabularCenter` | runtime | the core |
| | `TabularCenterCodegen` | transitive of the plugin | `MachineDesc`, validation, the emitter |
| | `TabularCenterMacros` | build-time plugin | the macro implementation |
| | `TabularCenterTesting` | test target | the fixture harness |

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

### Why `tabular-center-testing` is separate

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

Swift has no registry: SwiftPM and the Swift Package Index resolve from a git
repository with `Package.swift` at its root, and this repository's is in
`tabular-center-swift/`. So Swift is published through a **mirror**,
`tabula-center/tabular-center-swift`: pushing the release tag runs
`.github/workflows/swift-mirror.yml`, which splits `tabular-center-swift/` out
with `git subtree split` -- that directory and its history, nothing else -- and
pushes it to the mirror's `main`, tagged with the bare version (`0.1.0`, not
`v0.1.0`: SwiftPM wants semver). A Swift user depends on the mirror and clones
only Swift:

```swift
.package(url: "https://github.com/tabula-center/tabular-center-swift", from: "0.1.0")
```

Before the first release, once: create the empty mirror repository, add a
fine-grained token with `contents: write` on it (and nothing else) as this
repository's `SWIFT_MIRROR_TOKEN` secret, and register the mirror -- not this
repository -- with the Swift Package Index. The workflow refuses a tag that
disagrees with `VERSION`.

That the mirror would build is checked on every push, not discovered at
release: `swift-standalone` copies `tabular-center-swift/` somewhere with
nothing beside it -- what a mirror clone holds -- and builds it. Rust's
equivalent is `rust-package`: `cargo package` builds the crate from the archive
crates.io would receive, which likewise holds the crate directory and nothing
above it. Kotlin publishes compiled jars and needs neither.

## Publishing from CI

`.github/workflows/publish.yml` runs on the release tag and does what
`nix run .#publish -- --execute` does, one registry per job, each holding only
its own credentials. The order of work is still: `nix run .#release -- X.Y.Z`
by hand, review, `git push --follow-tags`. The tag starts `publish` (crates.io,
and Maven Central once enabled) and `swift-mirror` (Swift).

### crates.io: no stored secret

crates.io supports **trusted publishing**: the `crates-io` job's GitHub OIDC
identity is exchanged, by `rust-lang/crates-io-auth-action`, for a token
crates.io revokes when the job ends. Nothing long-lived exists to leak.
Once, by hand:

1. The **first** release of a crate cannot use trusted publishing -- the crate
   must exist first, and crates.io has no "create crate" button: a crate comes
   into being with its first `cargo publish`. crates.io also refuses to publish
   from an account without a **verified email** (Account Settings), which a
   GitHub sign-in does not verify for you. Create a crates.io API token scoped to `publish-new`, for
   the crate name `tabular-center` only, with the shortest expiry offered;
   then `CARGO_REGISTRY_TOKEN=... nix run .#publish -- --execute --only rust`
   from a clean checkout of the tag, and revoke the token.
2. On crates.io, the crate's Settings -> Trusted Publishing: repository
   `tabula-center/tabular-center`, workflow `publish.yml`, environment
   `crates-io`.
3. In this repository, create the `crates-io` environment, allowing only `v*`
   tags to deploy to it.

**Signing:** crates.io has no artifact signatures to upload. Integrity is the
registry's checksum -- the index records each `.crate`'s SHA-256, cargo
verifies every download against it, and `Cargo.lock` pins it. Provenance is the
trusted-publishing record: crates.io knows which repository, workflow and
environment published each version.

### Maven Central: stored secrets, so the strongest guard

Central has **no** OIDC publishing, and requires every artifact to carry a
detached PGP signature. So this is the one place with long-lived secrets, and
they live only in the `maven-central` environment:

1. **Namespace.** Central requires proof of the group's namespace, which is a
   domain reversed. The project owns `tabula.center`, so the namespace is
   **`center.tabula`**: register it in the Central Portal, which hands back a
   verification key to publish as a DNS TXT record on `tabula.center`. The
   Kotlin group today is `dev.tabularcenter`, which that domain cannot prove,
   so it becomes `center.tabula` before the first release (PLAN.md) -- after
   it, coordinates never change.
2. **POM metadata.** Central rejects a POM without a name, description, url,
   licenses, developers and scm. The url is the project site,
   `https://tabula.center`; scm points at
   `https://github.com/tabula-center/tabular-center`.
3. **User token.** Generate a Central Portal *user token* (not the portal
   login) -> secrets `MAVEN_CENTRAL_USERNAME`, `MAVEN_CENTRAL_PASSWORD`.
4. **Signing key.** Keep the primary key offline, used only to certify; give CI
   a **signing subkey** with an expiry, passphrase-protected:
   `gpg --armor --export-secret-subkeys <SUBKEY-ID>!` -> secret `SIGNING_KEY`,
   its passphrase -> `SIGNING_KEY_PASSWORD`. Publish the public key to
   `keys.openpgp.org` and `keyserver.ubuntu.com`, where Central looks; keep a
   revocation certificate offline. A leaked subkey is revoked and replaced
   without touching the identity the primary key carries.
5. **Environment.** `maven-central`: required reviewers, only `v*` tags. Then
   set the repository variable `MAVEN_CENTRAL_ENABLED=true` -- once the Kotlin
   Gradle publication exists (PLAN.md); until then the job is skipped, so the
   secrets are never loaded.

### Swift: tags only

There is nothing to sign or upload: SwiftPM resolves a tag and records the
commit it found in `Package.resolved`, so a moved tag is caught on the next
resolve rather than trusted. Protect the mirror's tags with a ruleset, so only
the mirror token can create them and nothing can move or delete them.

## The site

`https://tabula.center` is built from every push to `main` by
`.github/workflows/pages.yml`: `tools/docs` generates `doc/` (build output,
never committed), GitHub's Jekyll action renders it, and the result is
deployed as a Pages artifact. The generated `doc/` is the site, so
`doc/index.md` is the front page. Once, in Settings -> Pages:

- **Source: GitHub Actions.** This is the setting an earlier version of the
  workflow failed on: left on "Deploy from a branch", Pages ignores the
  workflow and renders `README.md`, and every other page is a 404. The deploy
  step now fails, visibly, if it is wrong.
- **Custom domain: `tabula.center`**, then **Enforce HTTPS** once the
  certificate is issued. No `CNAME` file: an Actions deployment takes the
  domain from this setting.
