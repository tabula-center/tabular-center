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
use crate::table::Table;

/// One statically-known edge of the machine.
struct Edge {
    from: &'static str,
    to: &'static str,
    action: &'static str,
    effects: &'static [&'static str],
}

fn static_edges<const N: usize, const M: usize>(t: &Table<N, M>) -> Vec<Edge> {
    let mut out = Vec::new();
    for (i, row) in t.cells.iter().enumerate() {
        for (j, cell) in row.iter().enumerate() {
            if let Cell::Go { target, effects } = cell {
                out.push(Edge {
                    from: t.states[i],
                    to: target,
                    action: t.actions[j],
                    effects,
                });
            }
        }
    }
    out
}

fn label(action: &str, effects: &[&str]) -> String {
    if effects.is_empty() {
        String::from(action)
    } else {
        format!("{} / {}", action, effects.join(", "))
    }
}

/// Render as a Mermaid `stateDiagram-v2`.
///
/// Only statically-known transitions become edges. Cells that dispatch into
/// developer code (`HANDLE`, `DELEGATE`) are rendered as self-loops annotated
/// with the member name, because the target is not knowable at build time.
/// Pretending otherwise would produce a diagram that quietly lies.
pub fn to_mermaid<const N: usize, const M: usize>(t: &Table<N, M>) -> String {
    let mut s = String::from("stateDiagram-v2\n");
    if let Some(initial) = t.initial {
        s.push_str(&format!("    [*] --> {initial}\n"));
    }
    for e in static_edges(t) {
        s.push_str(&format!(
            "    {} --> {}: {}\n",
            e.from,
            e.to,
            label(e.action, e.effects)
        ));
    }
    for (i, row) in t.cells.iter().enumerate() {
        for (j, cell) in row.iter().enumerate() {
            match cell {
                Cell::Handle => s.push_str(&format!(
                    "    {} --> {}: {} / ?handle\n",
                    t.states[i], t.states[i], t.actions[j]
                )),
                Cell::Delegate { child, .. } => s.push_str(&format!(
                    "    {} --> {}: {} / >{}\n",
                    t.states[i], t.states[i], t.actions[j], child
                )),
                Cell::Emit { effects } => s.push_str(&format!(
                    "    {} --> {}: {}\n",
                    t.states[i],
                    t.states[i],
                    label(t.actions[j], effects)
                )),
                _ => {}
            }
        }
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
    for e in static_edges(t) {
        s.push_str(&format!(
            "    {} -> {} [label=\"{}\"];\n",
            e.from,
            e.to,
            label(e.action, e.effects)
        ));
    }
    for (i, row) in t.cells.iter().enumerate() {
        for (j, cell) in row.iter().enumerate() {
            if matches!(cell, Cell::Handle) {
                s.push_str(&format!(
                    "    {} -> {} [label=\"{} / ?handle\", style=dashed];\n",
                    t.states[i], t.states[i], t.actions[j]
                ));
            }
        }
    }
    s.push_str("}\n");
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
    if c.ignore_percent() >= 70 {
        s.push_str(&format!(
            "  warning: {}% of cells are IGNORE; consider splitting this machine\n",
            c.ignore_percent()
        ));
    }
    if c.unreachable > 0 {
        s.push_str(&format!(
            "  warning: {} UNREACHABLE cell(s); usually a modelling error\n",
            c.unreachable
        ));
    }
    for state in t.statically_unreached() {
        s.push_str(&format!(
            "  warning: `{state}` has no static incoming transition\n"
        ));
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
}
