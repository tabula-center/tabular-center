//~ EXPECT: tabula::path-broken
//
// A route naming a transition the matrix does not have.
//
// The break is `busy -> idle`: row `busy` goes to `done` and nowhere else. Not
// the first hop -- `idle`'s only non-IGNORE cell is a `.handle`, which counts
// as a connection, because supplying a handled cell's target is exactly what a
// path is for.
//
// `@Path` sits beside `@Machine`, on the declaration. A path belongs to the
// machine; `@Row` hangs on a stored property because a row belongs to one
// state. Written inside the enum body it attaches to whatever member follows
// it, `MachineSyntax` never sees it on `decl.attributes`, and the machine is
// accepted with no paths at all -- which is how the first version of this
// fixture passed nothing while looking correct.
@Machine
@Path("back", [.busy, .idle])
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
