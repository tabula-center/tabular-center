//! The generated `TABLE` const and what can be computed from it.
//!
//! - `first_ident`: The leading identifier of a stringified expression.

use crate::cell::{Cell, CellKind};

/// State payload fields, as `(state, field, type)` in declaration order.
///
/// Emitted as a separate `PAYLOADS` const rather than folded into [`Table`]:
/// the table is the matrix, and this is metadata about the states. Keeping
/// them apart also means adding it did not break every hand-written `Table`
/// literal in the repository.
///
/// **Here rather than in `lint`, which is where it started.** `lint` is gated
/// on `alloc`, and `transition_matrix!` emits `PAYLOADS: &$crate::lint::…` for
/// every machine, so a machine built with `--no-default-features` failed to
/// compile on a path nothing exercised: the library's own `no-std` check
/// builds `-p tabular-center` without features, and a machine is a *consumer* of the
/// macro. `tabular-center-rust/examples/01-traffic-light` is that consumer, and it found this
/// on its first build.
///
/// The alias needs no allocation and never did; it was in `lint` because that
/// is the only thing that reads it.
pub type Payloads = [(&'static str, &'static str, &'static str)];

/// A machine's transition matrix, emitted as a `const` by the generator.
///
/// `N` states (rows) by `M` actions (columns). Row and column order match the
/// declaration order in the `states` and `actions` lists, which is what lets
/// diagram export and the conformance runner agree on cell identity across
/// languages.
///
/// - `machine`: Machine name, as declared.
/// - `states`: State variant names, in row order.
/// - `actions`: Action variant names, in column order.
/// - `cells`: Cells, indexed `[state][action]`.
/// - `initial`: Initial state variant name, if the machine declared one.
/// - `cell`: The cell at `(state_index, action_index)`.
/// - `state_index`: Row index of a state variant by name.
/// - `action_index`: Column index of an action variant by name.
/// - `coverage`: Counts by cell kind.
/// - `statically_unreached`: States that no cell can statically transition into, excluding the initial state.
/// - `is_fully_static`: Whether any cell dispatches dynamically, i.e.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Table<const N: usize, const M: usize> {
    pub machine: &'static str,
    pub states: [&'static str; N],
    pub actions: [&'static str; M],
    pub cells: [[Cell; M]; N],
    pub initial: Option<&'static str>,
}

/// Counts by cell kind, for the build-time coverage report.
///
/// - `ignore`: Cells declaring the action inapplicable.
/// - `go`: Unconditional transitions.
/// - `emit`: Stay-and-emit cells.
/// - `handle`: Cells the developer implements.
/// - `delegate`: Cells forwarding to a child machine.
/// - `unreachable`: Cells asserted impossible.
/// - `total`: Total cells, i.e.
/// - `required_members`: Cells the developer must implement.
/// - `ignore_percent`: Proportion of the matrix that is `IGNORE`, in percent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Coverage {
    pub ignore: usize,
    pub go: usize,
    pub emit: usize,
    pub handle: usize,
    pub delegate: usize,
    pub unreachable: usize,
}

impl Coverage {
    pub const fn total(&self) -> usize {
        self.ignore + self.go + self.emit + self.handle + self.delegate + self.unreachable
    }

    pub const fn required_members(&self) -> usize {
        self.handle + self.delegate
    }

    pub const fn ignore_percent(&self) -> usize {
        if self.total() == 0 {
            return 0;
        }
        self.ignore * 100 / self.total()
    }
}

impl<const N: usize, const M: usize> Table<N, M> {
    pub const fn cell(&self, state: usize, action: usize) -> Cell {
        self.cells[state][action]
    }

    pub fn state_index(&self, name: &str) -> Option<usize> {
        self.states.iter().position(|s| *s == name)
    }

    pub fn action_index(&self, name: &str) -> Option<usize> {
        self.actions.iter().position(|a| *a == name)
    }

    pub const fn coverage(&self) -> Coverage {
        let mut c = Coverage {
            ignore: 0,
            go: 0,
            emit: 0,
            handle: 0,
            delegate: 0,
            unreachable: 0,
        };
        let mut i = 0;
        while i < N {
            let mut j = 0;
            while j < M {
                match self.cells[i][j].kind() {
                    CellKind::Ignore => c.ignore += 1,
                    CellKind::Go => c.go += 1,
                    CellKind::Emit => c.emit += 1,
                    CellKind::Handle => c.handle += 1,
                    CellKind::Delegate => c.delegate += 1,
                    CellKind::Unreachable => c.unreachable += 1,
                }
                j += 1;
            }
            i += 1;
        }
        c
    }

    pub fn statically_unreached(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.states.iter().copied().filter(move |name| {
            if Some(*name) == self.initial {
                return false;
            }
            !self
                .cells
                .iter()
                .flatten()
                .any(|c| c.static_target() == Some(*name))
        })
    }

    pub fn is_fully_static(&self) -> bool {
        self.cells.iter().flatten().all(Cell::is_static)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: Table<3, 3> = Table {
        machine: "Timer",
        states: ["Idle", "Running", "Done"],
        actions: ["Start", "Tick", "Cancel"],
        initial: Some("Idle"),
        cells: [
            [Cell::Handle, Cell::Ignore, Cell::Ignore],
            [
                Cell::Ignore,
                Cell::Handle,
                Cell::Go {
                    target: "Idle",
                    effects: &["StopClock"],
                },
            ],
            [
                Cell::Go {
                    target: "Running",
                    effects: &["StartClock"],
                },
                Cell::Ignore,
                Cell::Ignore,
            ],
        ],
    };

    #[test]
    fn coverage_counts_every_cell() {
        let c = T.coverage();
        assert_eq!(c.total(), 9);
        assert_eq!(c.ignore, 5);
        assert_eq!(c.go, 2);
        assert_eq!(c.handle, 2);
        assert_eq!(c.required_members(), 2);
        assert_eq!(c.ignore_percent(), 55);
    }

    #[test]
    fn coverage_is_available_in_const_context() {
        const C: Coverage = T.coverage();
        const TOTAL: usize = C.total();
        assert_eq!(TOTAL, 9);
    }

    #[test]
    fn lookup_by_name() {
        assert_eq!(T.state_index("Running"), Some(1));
        assert_eq!(T.action_index("Cancel"), Some(2));
        assert_eq!(T.state_index("Nope"), None);
    }

    #[test]
    fn done_is_statically_unreached_because_only_a_handle_cell_leads_there() {
        let unreached: Vec<_> = T.statically_unreached().collect();
        assert_eq!(unreached, ["Done"]);
        assert!(!T.is_fully_static());
    }
}

pub const fn first_ident(s: &'static str) -> &'static str {
    let b = s.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        let is_ident = (c >= b'a' && c <= b'z')
            || (c >= b'A' && c <= b'Z')
            || (c >= b'0' && c <= b'9')
            || c == b'_';
        if !is_ident {
            break;
        }
        i += 1;
    }
    let (head, _) = b.split_at(i);
    match core::str::from_utf8(head) {
        Ok(v) => v,
        Err(_) => s,
    }
}

#[cfg(test)]
mod first_ident_tests {
    use super::first_ident;

    #[test]
    fn strips_struct_literals_and_calls() {
        assert_eq!(first_ident("Idle"), "Idle");
        assert_eq!(first_ident("Running { since: 0 }"), "Running");
        assert_eq!(first_ident("Running{since:0}"), "Running");
    }

    #[test]
    fn usable_in_const_context() {
        const N: &str = first_ident("Running { since: 0 }");
        assert_eq!(N, "Running");
    }
}
