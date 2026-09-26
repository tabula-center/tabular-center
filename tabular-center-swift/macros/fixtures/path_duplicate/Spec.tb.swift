// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabula::path-duplicate
//
// Two routes, one name.
//
// The shape a copied `@Path` leaves behind: the states were edited and the name
// was not. A narrowed call site names the path it narrows to, so two paths
// answering to one name is an ambiguity the generator cannot resolve.
//
// `@Path` sits beside `@Machine`, on the declaration. A path belongs to the
// machine; `@Row` hangs on a stored property because a row belongs to one
// state. Written inside the enum body it attaches to whatever member follows
// it, `MachineSyntax` never sees it on `decl.attributes`, and the machine is
// accepted with no paths at all -- which is how the first version of this
// fixture passed nothing while looking correct.
@Machine
@Path("go", [.idle, .start, .busy, .start, .done])
@Path("go", [.busy, .start, .done])
enum PathDuplicate {
    enum S { case idle, busy, done }
    enum A { case start, stop }
    enum F { case beep }

    final class Ctx {}

    static let initial = S.idle

    //                            start             stop
    @Row(.idle) static let i = [ .handle,          .ignore ]
    @Row(.busy) static let b = [ .go(.done),       .ignore ]
    @Row(.done) static let d = [ .ignore,          .ignore ]

    func handle(_ ctx: Ctx, _ state: S, _ action: A) -> Step<S, F> { fatalError() }
}
