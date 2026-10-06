//! Diagram and report rendering.
//!
//! Everything here is a pure function of [`Table`], which is why it costs
//! almost nothing to provide: the matrix already exists as data.
//!
//! Requires the `alloc` feature.
//!
//! - `edges`: Every drawable edge, in row-major matrix order.
//! - `to_mermaid`: Render as a Mermaid `stateDiagram-v2`.
//! - `to_dot`: Render as Graphviz DOT.
//! - `to_grid`: Render the matrix as an aligned ASCII grid.
//! - `to_coverage_report`: Render the build-time coverage report.

extern crate alloc;

use alloc::format;
use alloc::string::String;
use alloc::vec::Vec;

use crate::cell::Cell;
use crate::lint::{IGNORE_HEAVY_PERCENT, UNREACHABLE_HEAVY_PERCENT};
use crate::table::Table;

/// One drawable edge of the machine.
///
/// - `is_static`: Whether the generator resolved the target.
struct Edge {
    from: &'static str,
    to: &'static str,
    label: String,
    is_static: bool,
}

fn label(action: &str, effects: &[&str]) -> String {
    if effects.is_empty() {
        String::from(action)
    } else {
        format!("{} / {}", action, effects.join(", "))
    }
}

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
        line.push_str(&format!("{state:row_label_w$}"));
        for (j, text) in texts[i].iter().enumerate() {
            line.push_str(&format!("  {:w$}", text, w = col_w[j]));
        }
        s.push_str(line.trim_end());
        s.push('\n');
    }
    s
}

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
    if c.ignore_percent() >= IGNORE_HEAVY_PERCENT {
        s.push_str(&format!(
            "  warning: {}% of cells are IGNORE; consider splitting this machine\n",
            c.ignore_percent()
        ));
    }
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
    fn every_format_draws_the_same_edges_in_the_same_order() {
        let mermaid_edges: Vec<String> = to_mermaid(&T)
            .lines()
            .filter(|l| l.contains("-->") && !l.contains("[*]"))
            .map(|l| l.trim().replace(" --> ", "|").replace(": ", "|"))
            .collect();
        let dot_edges: Vec<String> = to_dot(&T)
            .lines()
            .filter(|l| l.contains("->") && !l.contains("__start"))
            .map(|l| {
                let l = l.trim();
                let (edge, rest) = l.split_once(" [label=\"").unwrap();
                let label = rest.split('"').next().unwrap();
                format!("{}|{}", edge.replace(" -> ", "|"), label)
            })
            .collect();
        assert_eq!(mermaid_edges, dot_edges);
        let want = ["Off|On|Flip / Light", "On|Off|Flip", "On|On|Poke / ?handle"];
        assert_eq!(mermaid_edges, want);
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
        assert!(!to_coverage_report(&U).contains("UNREACHABLE cell"));
    }

    #[test]
    fn report_does_not_claim_unreachability_when_cells_dispatch_dynamically() {
        assert!(!T.is_fully_static());
        let r = to_coverage_report(&T);
        assert!(!r.contains("no static incoming transition"));
    }
}
