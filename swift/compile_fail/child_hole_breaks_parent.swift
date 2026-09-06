//~ EXPECT: does not conform to protocol
//
// THE COMPOSITION PROPERTY:
//
//   Scoping a total child into a total parent yields a total parent, and the
//   compiler proves it by the same mechanism as everything else.
//
// `authSubmit` is a cell of the CHILD. The type below implements every cell of
// the PARENT and still fails, because `protocol SessionCells: AuthCells`.
//
// Protocols are Swift's trait bounds, exactly as interfaces are Kotlin's — and
// a protocol rather than a base class for the same reason: a class extends one
// parent, which would cap composition at a single child.
//
// A hand-written HANDLE body could never give this: it is free to ignore the
// child, so no requirement would propagate.
import Tabula

enum AuthS { case awaiting, authenticated }
enum AuthA { case submit }
enum AuthF { case prompt }
final class AuthCtx {}

protocol AuthCells {
    func authSubmit(_ ctx: AuthCtx) -> Step<AuthS, AuthF>
}

enum SessionS { case loggedOut, active }
enum SessionA { case credentials }
enum SessionF { case audit }
final class SessionCtx {}

protocol SessionCells: AuthCells {
    func loggedOutCredentials(_ ctx: SessionCtx) -> Step<SessionS, SessionF>
}

struct ChildHole: SessionCells {
    func loggedOutCredentials(_ ctx: SessionCtx) -> Step<SessionS, SessionF> {
        .stay(effects: [])
    }
    // authSubmit is missing — a CHILD cell.
}
