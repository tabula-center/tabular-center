//! The generated `TABLE` const and what can be computed from it.

use crate::cell::{Cell, CellKind};

/// A machine's transition matrix, emitted as a `const` by the generator.
///
/// `N` states (rows) by `M` actions (columns). Row and column order match the
/// declaration order in the `states` and `actions` lists, which is what lets
/// diagram export and the conformance runner agree on cell identity across
/// languages.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Table<const N: usize, const M: usize> {
    /// Machine name, as declared.
    pub machine: &'static str,
    /// State variant names, in row order.
    pub states: [&'static str; N],
    /// Action variant names, in column order.
    pub actions: [&'static str; M],
    /// Cells, indexed `[state][action]`.
    pub cells: [[Cell; M]; N],
    /// Initial state variant name, if the machine declared one.
    pub initial: Option<&'static str>,
}

/// Counts by cell kind, for the build-time coverage report.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Coverage {
    /// Cells declaring the action inapplicable.
    pub ignore: usize,
    /// Unconditional transitions.
    pub go: usize,
    /// Stay-and-emit cells.
    pub emit: usize,
    /// Cells the developer implements.
    pub handle: usize,
    /// Cells forwarding to a child machine.
    pub delegate: usize,
    /// Cells asserted impossible.
    pub unreachable: usize,
}

impl Coverage {
    /// Total cells, i.e. `N * M`.
    pub const fn total(&self) -> usize {
        self.ignore + self.go + self.emit + self.handle + self.delegate + self.unreachable
    }

    /// Cells the developer must implement.
    ///
    /// `unreachable` is excluded: writing `UNREACHABLE` *is* the
    /// implementation.
    pub const fn required_members(&self) -> usize {
        self.handle + self.delegate
    }

    /// Proportion of the matrix that is `IGNORE`, in percent.
    ///
    /// A machine that is overwhelmingly `IGNORE` is usually several machines
    /// wearing one coat. The build surfaces this rather than failing on it,
    /// because the threshold is a judgement call.
    pub const fn ignore_percent(&self) -> usize {
        if self.total() == 0 {
            return 0;
        }
        self.ignore * 100 / self.total()
    }
}

impl<const N: usize, const M: usize> Table<N, M> {
    /// The cell at `(state_index, action_index)`.
    pub const fn cell(&self, state: usize, action: usize) -> Cell {
        self.cells[state][action]
    }

    /// Row index of a state variant by name.
    pub fn state_index(&self, name: &str) -> Option<usize> {
        self.states.iter().position(|s| *s == name)
    }

    /// Column index of an action variant by name.
    pub fn action_index(&self, name: &str) -> Option<usize> {
        self.actions.iter().position(|a| *a == name)
    }

    /// Counts by cell kind.
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

    /// States that no cell can statically transition into, excluding the
    /// initial state.
    ///
    /// Only static targets are knowable at build time, so a state reached only
    /// from a `HANDLE` cell will appear here. That is why the reachability
    /// check is a *warning* and not an error: unreachable-by-construction is
    /// legitimate, and so is reached-only-dynamically.
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

    /// Whether any cell dispatches dynamically, i.e. whether
    /// [`Table::statically_unreached`] can be trusted as a real reachability
    /// result rather than an approximation.
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
        // `Idle` is initial; `Running` is reached by Done/Start. `Done` is
        // only reachable through `running_tick`, which is opaque at build
        // time -- exactly the case the warning exists to flag, and exactly why
        // it must not be an error.
        let unreached: Vec<_> = T.statically_unreached().collect();
        assert_eq!(unreached, ["Done"]);
        assert!(!T.is_fully_static());
    }
}

/// The leading identifier of a stringified expression.
///
/// `GO!(Running { since: 0 })` should appear in the table as `Running`, not as
/// the whole struct literal, so diagrams and grids stay readable. Runs in
/// `const` context because `TABLE` is a `const`.
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
