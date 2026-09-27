//~ EXPECT: must be exhaustive
//
// The free second guarantee: Swift's own exhaustiveness checking on the
// generated `switch`, the counterpart of rustc's on the Rust macro's `match`
// and kotlinc's on the Kotlin `when`.
//
// Adding a state breaks the generated dispatcher, so a stale generated file
// cannot silently ignore a new state. Reproduced inline, because the real
// dispatcher is regenerated from the declaration and would simply grow a case.
import TabularCenter

enum S { case idle, running, paused }  // paused added after generation
enum A { case go }

func step(_ s: S, _ a: A) -> Step<S, Never> {
    switch (s, a) {
    case (.idle, .go): return .go(.running, effects: [])
    case (.running, .go): return .go(.idle, effects: [])
    }
}
