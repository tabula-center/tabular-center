# What the emitted source is compiled against

`tools/verify swift-codegen` writes what `TabularCenterCodegen.emit` produces for each
machine in `Sources/TabularCenterCodegenCheck/main.swift` and then **compiles it**,
the way `kotlin-codegen` compiles Kotlin's. A golden diff alone proves only
that the emitter is deterministic; this proves the output is Swift and still
enforces the guarantee.

| file | role |
|---|---|
| `Types.swift` | the enums and narrowed structs developers declare, each machine's in its own enum |
| `complete/*.swift` | complete implementations. Compiled **together**, with every emitted machine |
| `compile_fail/<machine>_*.swift` | must be **refused** with the text on its `//~ EXPECT:` line |

Every emitted machine is compiled in one module with every complete
implementation. That is deliberate: the emitter namespaces what it generates
(`extension Timer { static func step ... }`), and two machines that could not
share a module would be a generator bug that compiling them one at a time
would hide.

A fixture names its machine by the part of its file name before the first
`_`. Machines the check marks *refused* are written to `refused/` and compiled
only with a fixture naming them: `job-mixed_*.swift` gets
`job-mixed.emitted.swift`, whose own generated code is the thing refused.

Emitted files are `<machine>.emitted.swift`, because swiftc refuses two inputs
with the same base name even from different directories.
