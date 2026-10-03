//~ EXPECT: does not conform to protocol
//
// The effect surface, same mechanism. Add an effect variant to a shipped
// machine and every handler stops compiling.
import TabularCenter

enum S { case idle }
enum A { case start }
enum F { case startClock, stopClock }

final class Ctx {}

protocol Cells {
    func startClock(_ ctx: Ctx) -> A?
    func stopClock(_ ctx: Ctx) -> A?
}

struct NoStop: Cells {
    func startClock(_ ctx: Ctx) -> A? { nil }
}
