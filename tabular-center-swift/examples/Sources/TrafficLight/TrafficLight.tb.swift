// swift-format-ignore-file
//
// The rows below are a grid, and swift-format has no per-glob configuration:
// this directive is the entire exemption, which is why it lives in the file
// rather than in a config nobody reads. `swift-format-config` requires it on
// every `.tb.swift`; `swift-matrix-stable` runs the formatter over this file
// and compares the rows.
import TabularCenter

/// The matrix, in a file of its own. See `spec/matrix-files.md`, and
/// `SpecCheck/Turnstile.tb.swift` for why only the `Table` literal moves: the
/// `.tb.` extension is what a formatter's exclusion can name, and exempting
/// the whole machine file would exempt its handler bodies too.
extension TrafficLight {
    static let TABLE = Table(
        machine: "TrafficLight",
        states: ["Red", "Green", "Amber"],
        actions: ["Advance", "Fault"],
        cells: [
            [.go(target: "Green", effects: []), .go(target: "Red", effects: [])],
            [.go(target: "Amber", effects: []), .go(target: "Red", effects: [])],
            [.handle, .go(target: "Red", effects: [])],
        ],
        initial: "Red"
    )
}
