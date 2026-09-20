import Tabula

/// The matrix, in a file of its own. See `spec/matrix-files.md`, and
/// `SpecCheck/Turnstile.tb.swift` for why only the `Table` literal moves: the
/// `.tb.` extension is what a formatter's exclusion can name, and exempting
/// the whole machine file would exempt its handler bodies too.
extension Retry {
    static let TABLE = Table(
        machine: "Retry",
        states: ["Ready", "Waiting", "Exhausted"],
        actions: ["Attempt", "Elapsed", "Abort"],
        cells: [
            [.handle, .ignore, .go(target: "Exhausted", effects: [])],
            [.ignore, .handle, .go(target: "Exhausted", effects: [])],
            [.ignore, .ignore, .ignore],
        ],
        initial: "Ready"
    )
}
