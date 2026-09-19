# What the emitted source is compiled against

`tools/verify swift-codegen` writes what `TabulaCodegen.emit` produces for each
machine in `Sources/TabulaCodegenCheck/main.swift` and then **compiles it**,
the way `kotlin-codegen` compiles Kotlin's. A golden diff alone proves only
that the emitter is deterministic; this proves the output is Swift and still
enforces the guarantee.

| file | role |
|---|---|
| `TimerTypes.swift` | the enums and narrowed structs a developer declares; every emitted timer names them |
| `complete/<machine>.swift` | a complete implementation. Must compile with `<machine>.swift` |
| `compile_fail/<machine>_*.swift` | must be **refused** with the text on its `//~ EXPECT:` line |

A fixture names its machine by the part of its file name before the first
`_`, so `timer-async_missing_effect_handler.swift` is compiled against the
emitted `timer-async.emitted.swift` -- a suffix, because swiftc refuses two
inputs with the same base name, and `complete/timer-async.swift` is one. Each emitted machine is compiled on its own: the
emitter still writes `step`, `perform` and `TABLE` at file scope, so two
machines in one module collide (PLAN, September 2026 audit).
