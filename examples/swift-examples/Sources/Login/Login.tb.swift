import Tabula

/// The matrix, in a file of its own. See `spec/matrix-files.md`, and
/// `SpecCheck/Turnstile.tb.swift` for why only the `Table` literal moves: the
/// `.tb.` extension is what a formatter's exclusion can name, and exempting
/// the whole machine file would exempt its handler bodies too.
///
/// Top-level, as it was in `Login.swift`: `Session` names the parent's types,
/// and the table is read as `SESSION_TABLE`.
let SESSION_TABLE = Table(
    machine: "Session",
    states: ["LoggedOut", "Active", "Banned"],
    actions: ["Credentials", "StartOver", "Logout"],
    cells: [
        [.delegate(child: "auth"), .delegate(child: "auth"), .ignore],
        [.ignore, .ignore, .go(target: "Banned", effects: ["Audit"])],
        [.ignore, .ignore, .ignore],
    ],
    initial: "LoggedOut"
)
