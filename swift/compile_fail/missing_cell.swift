//~ EXPECT: does not conform to protocol
//
// THE GUARANTEE, in Swift.
//
// `runningTick` is a HANDLE cell, so the generator emits a protocol
// requirement for it. Omitting the implementation is a plain conformance
// error from swiftc — not from tabula, which is what makes it survive even if
// the generator is bypassed.
//
// It rests on the oldest mechanism in the language, not on `switch`
// exhaustiveness, which a developer could defeat with `default:` — and which
// is why the dispatcher lives only in generated code.
import Tabula

enum S { case idle, running(since: Int) }
enum A { case start, tick(now: Int) }
enum F { case startClock }

struct Running { let since: Int }
struct Tick { let now: Int }
final class Ctx {}

protocol Cells {
    func idleStart(_ ctx: Ctx) -> Step<S, F>
    func runningTick(_ ctx: Ctx, _ state: Running, _ action: Tick) -> Step<S, F>
}

struct Hole: Cells {
    func idleStart(_ ctx: Ctx) -> Step<S, F> { .stay(effects: []) }
    // runningTick is missing.
}
