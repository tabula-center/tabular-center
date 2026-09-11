//! Diagram and report rendering.
//!
//! Everything here is a pure function of [`Table`], which is why it costs
//! almost nothing to provide: the matrix already exists as data.
//!
//! Requires the `alloc` feature.

extern crate alloc;

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::cell::Cell;
use crate::lint::{IGNORE_HEAVY_PERCENT, UNREACHABLE_HEAVY_PERCENT};
use crate::table::Table;

/// One drawable edge of the machine.
struct Edge {
    from: &'static str,
    to: &'static str,
    label: String,
    /// Whether the generator resolved the target.
    ///
    /// A dynamic edge is a self-loop annotated with what will run, not a
    /// guess at where it goes. Only DOT renders the distinction, but every
    /// format needs it available.
    is_static: bool,
}

fn label(action: &str, effects: &[&str]) -> String {
    if effects.is_empty() {
        String::from(action)
    } else {
        format!("{} / {}", action, effects.join(", "))
    }
}

/// Every drawable edge, in row-major matrix order.
///
/// One walk feeding all three diagram formats, so a machine renders in the
/// same order whichever you ask for and a new format cannot invent its own.
///
/// It is one walk for a second reason. Mermaid used to be rendered here in two
/// passes -- every `GO` edge, then every self-loop -- while Kotlin and Swift
/// interleaved them in cell order. Same edge set, different line order, in
/// three implementations that are supposed to agree. Nothing caught it because
/// nothing compares diagram output; `.grid` and `.lint` have goldens and the
/// diagrams do not. Row-major is the order the matrix is read in, so that is
/// the one all three now use.
///
/// `IGNORE` and `UNREACHABLE` draw nothing. Neither is a transition: one says
/// the action does not apply, the other says the pair cannot occur.
fn edges<const N: usize, const M: usize>(t: &Table<N, M>) -> Vec<Edge> {
    let mut out = Vec::new();
    for (i, row) in t.cells.iter().enumerate() {
        let from = t.states[i];
        for (j, cell) in row.iter().enumerate() {
            let action = t.actions[j];
            match cell {
                Cell::Go { target, effects } => out.push(Edge {
                    from,
                    to: target,
                    label: label(action, effects),
                    is_static: true,
                }),
                Cell::Emit { effects } => out.push(Edge {
                    from,
                    to: from,
                    label: label(action, effects),
                    is_static: true,
                }),
                Cell::Handle => out.push(Edge {
                    from,
                    to: from,
                    label: format!("{action} / ?handle"),
                    is_static: false,
                }),
                Cell::Delegate { child } => out.push(Edge {
                    from,
                    to: from,
                    label: format!("{action} / >{child}"),
                    is_static: false,
                }),
                Cell::Ignore | Cell::Unreachable => {}
            }
        }
    }
    out
}

/// Render as a Mermaid `stateDiagram-v2`.
///
/// Only statically-known transitions become real edges. Cells that dispatch
/// into developer code (`HANDLE`, `DELEGATE`) are rendered as self-loops
/// annotated with what will run, because the target is not knowable at build
/// time. Pretending otherwise would produce a diagram that quietly lies.
pub fn to_mermaid<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let mut s = String::from("stateDiagram-v2\n");
    if let Some(initial) = t.initial {
        s.push_str(&format!("    [*] --> {initial}\n"));
    }
    for e in edges(t) {
        s.push_str(&format!("    {} --> {}: {}\n", e.from, e.to, e.label));
    }
    s
}

/// Render as Graphviz DOT.
pub fn to_dot<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let mut s = format!("digraph {} {{\n    rankdir=LR;\n", t.machine);
    s.push_str("    node [shape=box, style=rounded];\n");
    if let Some(initial) = t.initial {
        s.push_str("    __start [shape=point];\n");
        s.push_str(&format!("    __start -> {initial};\n"));
    }
    for e in edges(t) {
        let style = if e.is_static { "" } else { ", style=dashed" };
        s.push_str(&format!(
            "    {} -> {} [label=\"{}\"{}];\n",
            e.from, e.to, e.label, style
        ));
    }
    s.push_str("}\n");
    s
}

/// Render as a PlantUML state diagram.
///
/// The third format, and the last of the three ARCHITECTURE section 10
/// promises. It costs a dozen lines because it is the same walk as the other
/// two with a different separator -- which is the argument for having built
/// `edges` first rather than writing a third independent renderer.
///
/// `hide empty description` suppresses the empty compartment PlantUML draws
/// under every state that has no description, which is all of them here.
pub fn to_plantuml<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let mut s = String::from("@startuml\nhide empty description\n");
    if let Some(initial) = t.initial {
        s.push_str(&format!("[*] --> {initial}\n"));
    }
    for e in edges(t) {
        s.push_str(&format!("{} --> {} : {}\n", e.from, e.to, e.label));
    }
    s.push_str("@enduml\n");
    s
}

/// Render the matrix as an aligned ASCII grid.
///
/// This is the artifact `tools/table-diff` snapshots: a PR that changes
/// machine behaviour then shows a table diff, not just a code diff.
pub fn to_grid<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    fn cell_text(c: &Cell) -> String {
        match c {
            Cell::Ignore => String::from("IGNORE"),
            Cell::Go { target, effects } if effects.is_empty() => format!("GO({target})"),
            Cell::Go { target, effects } => format!("GO({}, {})", target, effects.join("+")),
            Cell::Emit { effects } => format!("EMIT({})", effects.join("+")),
            Cell::Handle => String::from("HANDLE"),
            Cell::Delegate { child, .. } => format!("DELEGATE({child})"),
            Cell::Unreachable => String::from("UNREACHABLE"),
        }
    }

    let texts: Vec<Vec<String>> = t
        .cells
        .iter()
        .map(|row| row.iter().map(cell_text).collect())
        .collect();

    // The header's first column holds the machine name, so it participates in
    // the width calculation -- otherwise a long machine name pushes the header
    // out of alignment with its own rows.
    let row_label_w = t
        .states
        .iter()
        .map(|s| s.len())
        .chain(core::iter::once(t.machine.len()))
        .max()
        .unwrap_or(0);
    let mut col_w = [0usize; M];
    for (j, w) in col_w.iter_mut().enumerate() {
        *w = t.actions[j].len();
        for row in &texts {
            *w = (*w).max(row[j].len());
        }
    }

    // Lines are right-trimmed. The padding on the last column is invisible,
    // gets flagged by every whitespace check, and makes the golden snapshots
    // noisy in `git am`. Alignment only needs the padding *between* columns.
    let mut s = String::new();
    let mut line = String::new();

    line.push_str(&format!("{:w$}", t.machine, w = row_label_w));
    for (j, action) in t.actions.iter().enumerate() {
        line.push_str(&format!("  {:w$}", action, w = col_w[j]));
    }
    s.push_str(line.trim_end());
    s.push('\n');

    for (i, state) in t.states.iter().enumerate() {
        line.clear();
        line.push_str(&format!("{:w$}", state, w = row_label_w));
        for (j, text) in texts[i].iter().enumerate() {
            line.push_str(&format!("  {:w$}", text, w = col_w[j]));
        }
        s.push_str(line.trim_end());
        s.push('\n');
    }
    s
}

/// Render the build-time coverage report.
pub fn to_coverage_report<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let c = t.coverage();
    let mut s = format!(
        "{}: {} cells ({}x{}), {} required members\n",
        t.machine,
        c.total(),
        N,
        M,
        c.required_members()
    );
    s.push_str(&format!(
        "  ignore {} | go {} | emit {} | handle {} | delegate {} | unreachable {}\n",
        c.ignore, c.go, c.emit, c.handle, c.delegate, c.unreachable
    ));
    // The thresholds are the lint's, imported rather than repeated. This
    // report and `lint::report` are two views of one matrix and must not
    // disagree about what is worth warning about -- and they did, for as long
    // as the report had no golden and no second implementation to answer to.
    if c.ignore_percent() >= IGNORE_HEAVY_PERCENT {
        s.push_str(&format!(
            "  warning: {}% of cells are IGNORE; consider splitting this machine\n",
            c.ignore_percent()
        ));
    }
    // Was `c.unreachable > 0`, which fired on a single deliberate assertion --
    // the exact case `spec/cells.md` says must stay silent, and the case the
    // toggle fixture exists to document. `tabula::unreachable-heavy` had the
    // rule right; this had a copy of it that drifted.
    let unreachable_percent = if c.total() == 0 {
        0
    } else {
        c.unreachable * 100 / c.total()
    };
    if unreachable_percent >= UNREACHABLE_HEAVY_PERCENT {
        s.push_str(&format!(
            "  warning: {} UNREACHABLE cell(s); usually a modelling error\n",
            c.unreachable
        ));
    }
    // Gated on is_fully_static for the same reason the lint gates it: with any
    // dynamic cell present, `statically_unreached` is an approximation, and a
    // state reached only from a HANDLE cell is legitimately absent from it.
    if t.is_fully_static() {
        for state in t.statically_unreached() {
            s.push_str(&format!(
                "  warning: `{state}` has no static incoming transition\n"
            ));
        }
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: Table<2, 2> = Table {
        machine: "Toggle",
        states: ["Off", "On"],
        actions: ["Flip", "Poke"],
        initial: Some("Off"),
        cells: [
            [
                Cell::Go {
                    target: "On",
                    effects: &["Light"],
                },
                Cell::Ignore,
            ],
            [
                Cell::Go {
                    target: "Off",
                    effects: &[],
                },
                Cell::Handle,
            ],
        ],
    };

    #[test]
    fn mermaid_has_initial_and_static_edges() {
        let m = to_mermaid(&T);
        assert!(m.contains("[*] --> Off"));
        assert!(m.contains("Off --> On: Flip / Light"));
        assert!(m.contains("On --> Off: Flip"));
    }

    #[test]
    fn handle_cells_are_drawn_as_self_loops_not_invented_edges() {
        let m = to_mermaid(&T);
        assert!(m.contains("On --> On: Poke / ?handle"));
    }

    #[test]
    fn dot_is_well_formed() {
        let d = to_dot(&T);
        assert!(d.starts_with("digraph Toggle {"));
        assert!(d.trim_end().ends_with('}'));
    }

    #[test]
    fn dot_marks_dynamic_edges_dashed_and_static_edges_solid() {
        let d = to_dot(&T);
        assert!(
            d.contains(r#"On -> On [label="Poke / ?handle", style=dashed];"#),
            "{d}"
        );
        assert!(d.contains(r#"Off -> On [label="Flip / Light"];"#), "{d}");
    }

    #[test]
    fn plantuml_is_well_formed() {
        let p = to_plantuml(&T);
        assert!(p.starts_with("@startuml\n"));
        assert!(p.trim_end().ends_with("@enduml"));
        assert!(p.contains("[*] --> Off"));
        assert!(p.contains("Off --> On : Flip / Light"));
    }

    #[test]
    fn plantuml_draws_handle_cells_as_self_loops_too() {
        // Same rule as mermaid and dot: the target of a HANDLE cell is not
        // knowable at build time, so annotate a self-loop rather than invent
        // an edge.
        assert!(to_plantuml(&T).contains("On --> On : Poke / ?handle"));
    }

    #[test]
    fn every_format_draws_the_same_edges_in_the_same_order() {
        // The three renderers share one walk, so this is close to a tautology
        // today. It is here because it was not always true: mermaid used to
        // emit every GO edge before every self-loop while Kotlin and Swift
        // interleaved them in cell order, and nothing compared diagram output
        // so nothing failed. Independent renderers drift; this fails if one
        // grows its own walk again.
        let pairs = |s: &str, sep: &str| -> Vec<String> {
            s.lines()
                .filter(|l| l.contains("-->") && !l.contains("[*]"))
                .map(|l| l.trim().replace(sep, "|"))
                .collect()
        };
        let m = pairs(&to_mermaid(&T), ": ");
        let p = pairs(&to_plantuml(&T), " : ");
        assert_eq!(m, p);
        let want = [
            "Off --> On|Flip / Light",
            "On --> Off|Flip",
            "On --> On|Poke / ?handle",
        ];
        assert_eq!(m, want);
    }

    #[test]
    fn ignore_and_unreachable_draw_nothing() {
        const U: Table<1, 2> = Table {
            machine: "U",
            states: ["A"],
            actions: ["X", "Y"],
            initial: Some("A"),
            cells: [[Cell::Ignore, Cell::Unreachable]],
        };
        // Only the initial-state marker survives.
        assert_eq!(
            to_mermaid(&U).lines().filter(|l| l.contains("-->")).count(),
            1
        );
    }

    #[test]
    fn grid_lines_have_no_trailing_padding() {
        for line in to_grid(&T).lines() {
            assert_eq!(line, line.trim_end(), "trailing space in |{line}|");
        }
    }

    #[test]
    fn grid_columns_align() {
        let g = to_grid(&T);
        let lines: Vec<&str> = g.lines().collect();
        assert_eq!(lines.len(), 3);
        let poke = lines[0].find("Poke").unwrap();
        assert!(lines[2][poke..].starts_with("HANDLE"));
    }

    #[test]
    fn report_counts_and_warns() {
        let r = to_coverage_report(&T);
        assert!(r.contains("4 cells (2x2), 1 required members"));
        assert!(!r.contains("UNREACHABLE cell"));
    }

    #[test]
    fn report_stays_silent_on_one_deliberate_unreachable() {
        // The same rule as `tabula::unreachable-heavy`, and the same rule
        // `spec/cells.md` states: one or two deliberate assertions are what
        // the kind is for. The report used to warn on any UNREACHABLE at all,
        // which contradicted both.
        const U: Table<2, 4> = Table {
            machine: "U",
            states: ["A", "B"],
            actions: ["W", "X", "Y", "Z"],
            initial: Some("A"),
            cells: [
                [
                    Cell::Go {
                        target: "B",
                        effects: &[],
                    },
                    Cell::Ignore,
                    Cell::Ignore,
                    Cell::Unreachable,
                ],
                [
                    Cell::Go {
                        target: "A",
                        effects: &[],
                    },
                    Cell::Ignore,
                    Cell::Ignore,
                    Cell::Ignore,
                ],
            ],
        };
        // 1 of 8 cells is 12%, under the 25% threshold.
        assert!(!to_coverage_report(&U).contains("UNREACHABLE cell"));
    }

    #[test]
    fn report_does_not_claim_unreachability_when_cells_dispatch_dynamically() {
        // T's Off state is reached only via `GO(Off)`, so it is fine; the
        // point is the gate itself. With a HANDLE cell present the matrix is
        // not fully static, so reachability is an approximation and the
        // report must not present it as a result. The lint has always gated
        // this; the report did not.
        assert!(!T.is_fully_static());
        let r = to_coverage_report(&T);
        assert!(!r.contains("no static incoming transition"));
    }
}
