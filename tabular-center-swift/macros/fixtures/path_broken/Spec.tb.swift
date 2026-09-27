// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
//~ EXPECT: tabular-center::path-broken
//
// A hop naming a cell that cannot reach where the hop says.
//
// Cell (busy, start) is `.go(.done)`, and the hop claims `busy -start-> idle`.
// Because the path names the ACTION, this checks that one cell rather than
// asking whether anything in row `busy` reaches `idle` -- the imprecision a
// states-only spine could not avoid.
//
// `@Path` sits beside `@Machine`, on the declaration. A path belongs to the
// machine; `@Row` hangs on a stored property because a row belongs to one
// state. Written inside the enum body it attaches to whatever member follows
// it, `MachineSyntax` never sees it on `decl.attributes`, and the machine is
// accepted with no paths at all -- which is how the first version of this
// fixture passed nothing while looking correct.
@Machine
@Path("back", [.busy, .start, .idle])
enum PathBroken {
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
