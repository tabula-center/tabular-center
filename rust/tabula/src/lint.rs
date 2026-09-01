//! Findings computable from a machine's `TABLE`.
//!
//! All of this is a pure function of the matrix, which is the payoff for
//! emitting the table as data alongside the dispatcher: none of it needed to
//! be built as a feature.
//!
//! Everything here is a **warning**, never an error. Each rule is a judgement
//! call with legitimate exceptions, and a lint that fails the build on a
//! judgement call teaches people to disable lints.
//!
//! Requires the `alloc` feature.

extern crate alloc;

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::cell::Cell;
use crate::table::Table;

/// One thing worth a second look.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Finding {
    /// Nothing can transition into this state.
    ///
    /// Only reported for a **fully static** matrix. As soon as one `HANDLE`
    /// or `DELEGATE` cell exists, its target is unknowable at build time and
    /// any state might be reachable through it — so on a normal machine this
    /// rule could only guess, and a lint that fires on every healthy machine
    /// is a lint people turn off.
    NoStaticEntry {
        /// The unreachable state.
        state: &'static str,
    },

    /// No cell in this row can leave the state.
    ///
    /// A terminal state is a real design; a state that is terminal *by
    /// accident* is a bug, and the two look identical from outside.
    NoStaticExit {
        /// The state nothing can statically leave.
        state: &'static str,
    },

    /// The matrix is overwhelmingly `IGNORE`.
    ///
    /// Usually several machines wearing one coat. The threshold is a
    /// heuristic and deliberately generous.
    IgnoreHeavy {
        /// Share of the matrix that is `IGNORE`.
        percent: usize,
    },

    /// `UNREACHABLE` cells make up a large share of the matrix.
    ///
    /// Each one is a claim about the surrounding system, and one or two are
    /// exactly what the cell kind is for. Only a *concentration* of them
    /// suggests the state or action alphabet is wrong. The plain count always
    /// appears in the coverage report; this fires only past a threshold.
    Unreachables {
        /// Number of `UNREACHABLE` cells.
        count: usize,
        /// Share of the matrix they occupy.
        percent: usize,
    },

    /// A whole row is inert: every cell ignores.
    ///
    /// A terminal state is a legitimate design, and this fires on those too —
    /// intentionally. An intended terminal state and a forgotten row are
    /// indistinguishable from the matrix, and one line of output is a fair
    /// price for catching the second. Confirm and move on.
    DeadRow {
        /// The state whose row is entirely `IGNORE`.
        state: &'static str,
    },

    /// A whole column is inert: no state responds to this action.
    ///
    /// Either the action is dead code or a row was forgotten.
    DeadColumn {
        /// The action no state responds to.
        action: &'static str,
    },
}

impl Finding {
    /// Stable diagnostic code, matching `spec/diagnostics.md`.
    pub fn code(&self) -> &'static str {
        match self {
            Finding::NoStaticEntry { .. } => "tabula::no-static-entry",
            Finding::NoStaticExit { .. } => "tabula::no-static-exit",
            Finding::IgnoreHeavy { .. } => "tabula::ignore-heavy",
            Finding::Unreachables { .. } => "tabula::unreachable-heavy",
            Finding::DeadRow { .. } => "tabula::dead-row",
            Finding::DeadColumn { .. } => "tabula::dead-column",
        }
    }

    /// Human-readable message, remedy included.
    pub fn message(&self) -> String {
        match self {
            Finding::NoStaticEntry { state } => format!(
                "nothing can transition into `{state}`; \
                 every cell in this matrix is static, so it is genuinely unreachable"
            ),
            Finding::NoStaticExit { state } => format!(
                "no cell in row `{state}` can leave it statically; \
                 confirm this state is meant to be terminal"
            ),
            Finding::IgnoreHeavy { percent } => {
                format!("{percent}% of cells are IGNORE; consider splitting this machine")
            }
            Finding::Unreachables { count, percent } => format!(
                "{count} UNREACHABLE cells ({percent}% of the matrix); \
                 a concentration this high usually means the alphabet is wrong"
            ),
            Finding::DeadRow { state } => format!(
                "every cell in row `{state}` ignores; \
                 confirm this state is meant to be terminal"
            ),
            Finding::DeadColumn { action } => {
                format!("no state responds to `{action}`; the action is dead or a row was missed")
            }
        }
    }
}

/// Percentage of `IGNORE` cells above which [`Finding::IgnoreHeavy`] fires.
pub const IGNORE_HEAVY_PERCENT: usize = 70;

/// Percentage of `UNREACHABLE` cells above which [`Finding::Unreachables`]
/// fires. One or two deliberate assertions must stay silent.
pub const UNREACHABLE_HEAVY_PERCENT: usize = 25;

/// Every finding for a machine, in a stable order.
pub fn lint<const N: usize, const M: usize>(t: &Table<N, M>) -> Vec<Finding> {
    let mut out = Vec::new();

    // Only meaningful when every cell is static; otherwise a HANDLE cell
    // could reach anything and the rule would be guessing.
    if t.is_fully_static() {
        for state in t.statically_unreached() {
            out.push(Finding::NoStaticEntry { state });
        }
    }

    for (i, row) in t.cells.iter().enumerate() {
        let dead = row.iter().all(|c| matches!(c, Cell::Ignore));
        if dead {
            // DeadRow subsumes NoStaticExit. Reporting both for the same row
            // is two warnings for one problem, which is how a lint earns its
            // reputation for noise.
            out.push(Finding::DeadRow { state: t.states[i] });
            continue;
        }
        // A row whose only escape is a HANDLE cell is not flagged: the target
        // is unknowable at build time and guessing would make the lint lie.
        let can_leave = row
            .iter()
            .any(|c| c.static_target().is_some() || !c.is_static());
        if !can_leave {
            out.push(Finding::NoStaticExit { state: t.states[i] });
        }
    }

    for j in 0..M {
        if (0..N).all(|i| matches!(t.cells[i][j], Cell::Ignore)) {
            out.push(Finding::DeadColumn {
                action: t.actions[j],
            });
        }
    }

    let c = t.coverage();
    if c.ignore_percent() >= IGNORE_HEAVY_PERCENT {
        out.push(Finding::IgnoreHeavy {
            percent: c.ignore_percent(),
        });
    }
    let unreachable_percent = if c.total() == 0 {
        0
    } else {
        c.unreachable * 100 / c.total()
    };
    if unreachable_percent >= UNREACHABLE_HEAVY_PERCENT {
        out.push(Finding::Unreachables {
            count: c.unreachable,
            percent: unreachable_percent,
        });
    }
    out
}

/// Findings rendered one per line, prefixed with the machine name.
pub fn report<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let mut s = String::new();
    for f in lint(t) {
        s.push_str(&format!(
            "warning[{}]: {}: {}\n",
            f.code(),
            t.machine,
            f.message()
        ));
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const DEAD: Table<2, 2> = Table {
        machine: "Dead",
        states: ["A", "B"],
        actions: ["X", "Y"],
        initial: Some("A"),
        cells: [[Cell::Ignore, Cell::Ignore], [Cell::Ignore, Cell::Ignore]],
    };

    const LIVE: Table<2, 2> = Table {
        machine: "Live",
        states: ["A", "B"],
        actions: ["X", "Y"],
        initial: Some("A"),
        cells: [
            [
                Cell::Go {
                    target: "B",
                    effects: &[],
                },
                Cell::Handle,
            ],
            [
                Cell::Go {
                    target: "A",
                    effects: &[],
                },
                Cell::Handle,
            ],
        ],
    };

    #[test]
    fn a_wholly_ignoring_machine_is_all_findings() {
        let f = lint(&DEAD);
        assert!(f.contains(&Finding::DeadRow { state: "A" }));
        assert!(f.contains(&Finding::DeadRow { state: "B" }));
        assert!(f.contains(&Finding::DeadColumn { action: "X" }));
        assert!(f.contains(&Finding::NoStaticEntry { state: "B" }));
        assert!(f.contains(&Finding::IgnoreHeavy { percent: 100 }));
    }

    #[test]
    fn dead_row_subsumes_no_static_exit() {
        // Two warnings for one problem is how a lint earns a reputation for
        // noise and gets switched off.
        let f = lint(&DEAD);
        assert!(f.contains(&Finding::DeadRow { state: "A" }));
        assert!(!f.iter().any(|x| matches!(x, Finding::NoStaticExit { .. })));
    }

    #[test]
    fn no_static_entry_is_silent_once_any_cell_is_dynamic() {
        // `B` is reachable only through the HANDLE cell, which is normal.
        // Firing here would put a warning on nearly every healthy machine.
        const MIXED: Table<2, 2> = Table {
            machine: "Mixed",
            states: ["A", "B"],
            actions: ["X", "Y"],
            initial: Some("A"),
            cells: [
                [Cell::Handle, Cell::Ignore],
                [
                    Cell::Go {
                        target: "A",
                        effects: &[],
                    },
                    Cell::Ignore,
                ],
            ],
        };
        assert!(!lint(&MIXED)
            .iter()
            .any(|f| matches!(f, Finding::NoStaticEntry { .. })));
    }

    #[test]
    fn one_deliberate_unreachable_stays_silent() {
        const ONE: Table<2, 3> = Table {
            machine: "One",
            states: ["A", "B"],
            actions: ["X", "Y", "Z"],
            initial: Some("A"),
            cells: [
                [
                    Cell::Go {
                        target: "B",
                        effects: &[],
                    },
                    Cell::Handle,
                    Cell::Ignore,
                ],
                [
                    Cell::Go {
                        target: "A",
                        effects: &[],
                    },
                    Cell::Handle,
                    Cell::Unreachable,
                ],
            ],
        };
        assert!(!lint(&ONE)
            .iter()
            .any(|f| matches!(f, Finding::Unreachables { .. })));
    }

    #[test]
    fn a_healthy_machine_produces_nothing() {
        assert_eq!(lint(&LIVE), []);
    }

    #[test]
    fn the_initial_state_is_never_flagged_for_having_no_entry() {
        // `A` is initial, so having no incoming edge is expected.
        let f = lint(&DEAD);
        assert!(!f.contains(&Finding::NoStaticEntry { state: "A" }));
    }

    #[test]
    fn a_row_escaping_only_through_handle_is_not_flagged() {
        // The target of a HANDLE cell is unknowable at build time. Flagging
        // it would make the lint lie about a machine that is perfectly fine.
        const H: Table<1, 1> = Table {
            machine: "H",
            states: ["A"],
            actions: ["X"],
            initial: Some("A"),
            cells: [[Cell::Handle]],
        };
        assert!(!lint(&H)
            .iter()
            .any(|f| matches!(f, Finding::NoStaticExit { .. })));
    }

    #[test]
    fn report_carries_the_code_and_the_machine() {
        let r = report(&DEAD);
        assert!(r.contains("warning[tabula::dead-row]: Dead:"), "{r}");
    }
}
