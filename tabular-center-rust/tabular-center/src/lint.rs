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
//!
//! - `IGNORE_HEAVY_PERCENT`: Percentage of `IGNORE` cells above which [`Finding::IgnoreHeavy`] fires.
//! - `UNREACHABLE_HEAVY_PERCENT`: Percentage of `UNREACHABLE` cells above which [`Finding::Unreachables`] fires.
//! - `PAYLOAD_HOIST_STATES`: Number of states a payload field must appear in before [`Finding::PayloadHoist`] fires.
//! - `canonical_type`: Map a Rust payload type name onto the spec vocabulary.
//! - `payload_hoist`: Fields repeated across [`PAYLOAD_HOIST_STATES`] or more states.
//! - `lint`: Every finding for a machine, in a stable order.
//! - `report`: Findings rendered one per line, prefixed with the machine name.
//! - `report_with_payloads`: [`report`] plus the payload findings, which need the machine's `PAYLOADS`.

extern crate alloc;

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::cell::Cell;
use crate::table::Table;

/// One thing worth a second look.
///
/// - `NoStaticEntry`: Nothing can transition into this state.
/// - `NoStaticEntry.state`: The unreachable state.
/// - `NoStaticExit`: No cell in this row can leave the state.
/// - `NoStaticExit.state`: The state nothing can statically leave.
/// - `IgnoreHeavy`: The matrix is overwhelmingly `IGNORE`.
/// - `IgnoreHeavy.percent`: Share of the matrix that is `IGNORE`.
/// - `Unreachables`: `UNREACHABLE` cells make up a large share of the matrix.
/// - `Unreachables.count`: Number of `UNREACHABLE` cells.
/// - `Unreachables.percent`: Share of the matrix they occupy.
/// - `DeadRow`: A whole row is inert: every cell ignores.
/// - `DeadRow.state`: The state whose row is entirely `IGNORE`.
/// - `PayloadHoist`: The same payload field appears in several states.
/// - `PayloadHoist.field`: The repeated field name.
/// - `PayloadHoist.ty`: Its type.
/// - `PayloadHoist.states`: The states carrying it, in declaration order.
/// - `DeadColumn`: A whole column is inert: no state responds to this action.
/// - `DeadColumn.action`: The action no state responds to.
/// - `code`: Stable diagnostic code, matching `spec/diagnostics.md`.
/// - `message`: Human-readable message, remedy included.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Finding {
    NoStaticEntry {
        state: &'static str,
    },

    NoStaticExit {
        state: &'static str,
    },

    IgnoreHeavy {
        percent: usize,
    },

    Unreachables {
        count: usize,
        percent: usize,
    },

    DeadRow {
        state: &'static str,
    },

    PayloadHoist {
        field: &'static str,
        ty: &'static str,
        states: Vec<&'static str>,
    },

    DeadColumn {
        action: &'static str,
    },
}

impl Finding {
    pub fn code(&self) -> &'static str {
        match self {
            Finding::NoStaticEntry { .. } => "tabular-center::no-static-entry",
            Finding::NoStaticExit { .. } => "tabular-center::no-static-exit",
            Finding::IgnoreHeavy { .. } => "tabular-center::ignore-heavy",
            Finding::Unreachables { .. } => "tabular-center::unreachable-heavy",
            Finding::DeadRow { .. } => "tabular-center::dead-row",
            Finding::DeadColumn { .. } => "tabular-center::dead-column",
            Finding::PayloadHoist { .. } => "tabular-center::payload-hoist",
        }
    }

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
            Finding::PayloadHoist { field, ty, states } => format!(
                "`{}: {}` appears in the payloads of {}; consider hoisting it to Context",
                field,
                ty,
                states.join(", ")
            ),
        }
    }
}

pub const IGNORE_HEAVY_PERCENT: usize = 70;

pub const UNREACHABLE_HEAVY_PERCENT: usize = 25;

pub const PAYLOAD_HOIST_STATES: usize = 3;

pub use crate::table::Payloads;

pub fn canonical_type(ty: &str) -> &str {
    match ty {
        "i8" | "i16" | "i32" | "i64" | "i128" | "isize" | "u8" | "u16" | "u32" | "u64" | "u128"
        | "usize" => "int",
        "f32" | "f64" => "float",
        "bool" => "bool",
        "String" | "&str" | "&'static str" => "string",
        "char" => "char",
        other => other,
    }
}

pub fn payload_hoist(payloads: &Payloads) -> Vec<Finding> {
    let mut out = Vec::new();
    let mut seen: Vec<(&'static str, &'static str)> = Vec::new();

    for &(_, field, ty) in payloads {
        let ty = canonical_type(ty);
        if seen.contains(&(field, ty)) {
            continue;
        }
        seen.push((field, ty));

        let states: Vec<&'static str> = payloads
            .iter()
            .filter(|(_, f, t)| *f == field && canonical_type(t) == ty)
            .map(|(s, _, _)| *s)
            .collect();

        if states.len() >= PAYLOAD_HOIST_STATES {
            out.push(Finding::PayloadHoist { field, ty, states });
        }
    }
    out
}

pub fn lint<const N: usize, const M: usize>(t: &Table<N, M>) -> Vec<Finding> {
    let mut out = Vec::new();

    if t.is_fully_static() {
        for state in t.statically_unreached() {
            out.push(Finding::NoStaticEntry { state });
        }
    }

    for (i, row) in t.cells.iter().enumerate() {
        let dead = row.iter().all(|c| matches!(c, Cell::Ignore));
        if dead {
            out.push(Finding::DeadRow { state: t.states[i] });
            continue;
        }
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

pub fn report<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    render(t.machine, &lint(t))
}

pub fn report_with_payloads<const N: usize, const M: usize>(
    t: &Table<N, M>,
    payloads: &Payloads,
) -> String {
    let mut findings = lint(t);
    findings.extend(payload_hoist(payloads));
    render(t.machine, &findings)
}

fn render(machine: &str, findings: &[Finding]) -> String {
    let mut s = String::new();
    for f in findings {
        s.push_str(&format!(
            "warning[{}]: {}: {}\n",
            f.code(),
            machine,
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
        let f = lint(&DEAD);
        assert!(f.contains(&Finding::DeadRow { state: "A" }));
        assert!(!f.iter().any(|x| matches!(x, Finding::NoStaticExit { .. })));
    }

    #[test]
    fn no_static_entry_is_silent_once_any_cell_is_dynamic() {
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
        let f = lint(&DEAD);
        assert!(!f.contains(&Finding::NoStaticEntry { state: "A" }));
    }

    #[test]
    fn a_row_escaping_only_through_handle_is_not_flagged() {
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
    fn a_field_in_three_states_is_flagged() {
        const P: &Payloads = &[
            ("Connecting", "retry_count", "u32"),
            ("Backoff", "retry_count", "u32"),
            ("Backoff", "until", "Instant"),
            ("Reconnecting", "retry_count", "u32"),
        ];
        let f = payload_hoist(P);
        assert_eq!(f.len(), 1);
        assert_eq!(
            f[0],
            Finding::PayloadHoist {
                field: "retry_count",
                ty: "int",
                states: vec!["Connecting", "Backoff", "Reconnecting"],
            }
        );
    }

    #[test]
    fn two_states_is_a_coincidence_not_a_pattern() {
        const P: &Payloads = &[("A", "n", "u32"), ("B", "n", "u32")];
        assert!(payload_hoist(P).is_empty());
    }

    #[test]
    fn the_same_name_at_different_types_is_not_the_same_field() {
        const P: &Payloads = &[
            ("A", "count", "u32"),
            ("B", "count", "String"),
            ("C", "count", "u32"),
        ];
        assert!(payload_hoist(P).is_empty());
    }

    #[test]
    fn widths_of_the_same_primitive_are_one_field() {
        const P: &Payloads = &[("A", "n", "u32"), ("B", "n", "usize"), ("C", "n", "u8")];
        let f = payload_hoist(P);
        assert_eq!(f.len(), 1);
        assert_eq!(
            f[0],
            Finding::PayloadHoist {
                field: "n",
                ty: "int",
                states: vec!["A", "B", "C"],
            }
        );
    }

    #[test]
    fn an_unrecognised_type_passes_through_unchanged() {
        const P: &Payloads = &[
            ("A", "amount", "Money"),
            ("B", "amount", "Money"),
            ("C", "amount", "Money"),
        ];
        let f = payload_hoist(P);
        assert_eq!(f.len(), 1);
        let msg = f[0].message();
        assert!(msg.contains("`amount: Money`"), "{msg}");
    }

    #[test]
    fn each_repeated_field_is_reported_once() {
        const P: &Payloads = &[
            ("A", "n", "u32"),
            ("B", "n", "u32"),
            ("C", "n", "u32"),
            ("A", "m", "String"),
            ("B", "m", "String"),
            ("C", "m", "String"),
        ];
        assert_eq!(payload_hoist(P).len(), 2);
    }

    #[test]
    fn report_carries_the_code_and_the_machine() {
        let r = report(&DEAD);
        assert!(
            r.contains("warning[tabular-center::dead-row]: Dead:"),
            "{r}"
        );
    }
}
