//! Parses `spec/conformance` and checks an implementation against it.
//!
//! Deliberately hand-rolled rather than pulled from a JSON or TOML crate: the
//! harness has to run offline in a Nix sandbox, and a dependency here would be
//! the first one in the repository. The `.tbl` format parses in about sixty
//! lines and is diffable by eye, which is also what `table-diff` needs.

use std::collections::BTreeMap;
use std::fmt;
use std::path::Path;

use tabular_center::{Cell, Table};

pub mod machines;

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// A cell as the fixture declares it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CellSpec {
    Ignore,
    Handle,
    Unreachable,
    Go {
        target: String,
        effects: Vec<String>,
    },
    Emit {
        effects: Vec<String>,
    },
    Delegate {
        child: String,
    },
}

impl fmt::Display for CellSpec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            CellSpec::Ignore => write!(f, "IGNORE"),
            CellSpec::Handle => write!(f, "HANDLE"),
            CellSpec::Unreachable => write!(f, "UNREACHABLE"),
            CellSpec::Go { target, effects } if effects.is_empty() => write!(f, "GO({target})"),
            CellSpec::Go { target, effects } => {
                write!(f, "GO({}, {})", target, effects.join(", "))
            }
            CellSpec::Emit { effects } => write!(f, "EMIT({})", effects.join(", ")),
            CellSpec::Delegate { child } => write!(f, "DELEGATE({child})"),
        }
    }
}

impl CellSpec {
    /// The cell as a `.grid` golden spells it.
    ///
    /// Not `Display`, which spells cells the way a `.tbl` fixture does. The
    /// two formats join effect lists differently -- `GO(T, A, B)` authored by
    /// hand, `GO(T, A+B)` generated -- which `spec/cells.md` records as
    /// deliberate rather than as drift.
    ///
    /// `table-diff` needs this one. Its whole job is to put a fixture's grid
    /// beside a generated grid so a reviewer can compare them, and it used
    /// `Display`: for any cell with two effects the two grids would have
    /// disagreed in both text and column width, in a tool whose only output is
    /// the comparison. No fixture has such a cell yet, which is exactly why
    /// nothing caught it.
    pub fn grid_text(&self) -> String {
        match self {
            CellSpec::Ignore => String::from("IGNORE"),
            CellSpec::Handle => String::from("HANDLE"),
            CellSpec::Unreachable => String::from("UNREACHABLE"),
            CellSpec::Go { target, effects } if effects.is_empty() => format!("GO({target})"),
            CellSpec::Go { target, effects } => {
                format!("GO({}, {})", target, effects.join("+"))
            }
            CellSpec::Emit { effects } => format!("EMIT({})", effects.join("+")),
            CellSpec::Delegate { child } => format!("DELEGATE({child})"),
        }
    }
}

/// A parsed `.tbl` fixture.
#[derive(Debug, Clone)]
pub struct Spec {
    pub machine: String,
    pub initial: String,
    pub states: Vec<String>,
    pub actions: Vec<String>,
    pub cells: Vec<Vec<CellSpec>>,
}

/// What a trace step expects.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Expect {
    Go {
        state: String,
        fields: BTreeMap<String, i64>,
    },
    Stay,
    Ignored,
}

impl fmt::Display for Expect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Expect::Go { state, fields } if fields.is_empty() => write!(f, "go {state}"),
            Expect::Go { state, fields } => {
                let fs: Vec<String> = fields.iter().map(|(k, v)| format!("{k}={v}")).collect();
                write!(f, "go {} {}", state, fs.join(" "))
            }
            Expect::Stay => write!(f, "stay"),
            Expect::Ignored => write!(f, "ignored"),
        }
    }
}

/// One line of a trace.
#[derive(Debug, Clone)]
pub struct TraceStep {
    pub action: String,
    pub args: BTreeMap<String, i64>,
    pub expect: Expect,
    pub effects: Vec<String>,
}

/// A parsed `.trace` block.
#[derive(Debug, Clone)]
pub struct Trace {
    pub name: String,
    pub ctx: BTreeMap<String, i64>,
    pub from: String,
    /// Payload fields of the starting state.
    ///
    /// `go` accepted fields from the start and `from` did not, which silently
    /// dropped `from Retrying child_attempt=1` and made a composition trace
    /// start in the wrong child state. The two are now symmetric.
    pub from_fields: BTreeMap<String, i64>,
    pub steps: Vec<TraceStep>,
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Reduce an effect or state rendering to its bare variant name.
///
/// Three shapes reach this, and all three must land on `StopClock`:
///
/// | Input | From |
/// |---|---|
/// | `StopClock` | a fixture, or Kotlin |
/// | `Effect::StopClock` / `F.StopClock` | a qualified path |
/// | `StopClock(StopClock { reason: 0 })` | `{:?}` on a generated newtype enum |
///
/// Order matters. Taking the last path segment first breaks on the third,
/// because `{ reason: 0 }` contains a colon. So the payload is stripped first,
/// then the path is split.
pub fn last_segment(s: &str) -> &str {
    let head = match s.find(['(', '{', ' ']) {
        Some(i) => &s[..i],
        None => s,
    };
    head.rsplit(['.', ':']).next().unwrap_or(head).trim()
}

fn strip(line: &str) -> &str {
    match line.find('#') {
        Some(i) => line[..i].trim(),
        None => line.trim(),
    }
}

fn parse_cell(text: &str, at: &str) -> Result<CellSpec, String> {
    let t = text.trim();
    if t == "IGNORE" {
        return Ok(CellSpec::Ignore);
    }
    if t == "HANDLE" {
        return Ok(CellSpec::Handle);
    }
    if t == "UNREACHABLE" {
        return Ok(CellSpec::Unreachable);
    }
    let split = |inner: &str| -> Vec<String> {
        inner
            .split(',')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect()
    };
    if let Some(inner) = t.strip_prefix("GO(").and_then(|r| r.strip_suffix(')')) {
        let parts = split(inner);
        let (target, effects) = parts
            .split_first()
            .ok_or_else(|| format!("{at}: GO() needs a target"))?;
        return Ok(CellSpec::Go {
            target: target.clone(),
            effects: effects.to_vec(),
        });
    }
    if let Some(inner) = t.strip_prefix("EMIT(").and_then(|r| r.strip_suffix(')')) {
        return Ok(CellSpec::Emit {
            effects: split(inner),
        });
    }
    if let Some(inner) = t
        .strip_prefix("DELEGATE(")
        .and_then(|r| r.strip_suffix(')'))
    {
        return Ok(CellSpec::Delegate {
            child: inner.trim().to_string(),
        });
    }
    Err(format!(
        "{at}: unknown cell `{t}`; expected IGNORE, HANDLE, UNREACHABLE, GO(..), EMIT(..), DELEGATE(..)"
    ))
}

/// Parse a `.tbl` fixture.
pub fn parse_spec(src: &str, origin: &str) -> Result<Spec, String> {
    let (mut machine, mut initial) = (None, None);
    let (mut states, mut actions): (Vec<String>, Vec<String>) = (vec![], vec![]);
    let mut cells: Vec<Vec<CellSpec>> = vec![];

    for (n, raw) in src.lines().enumerate() {
        let line = strip(raw);
        if line.is_empty() {
            continue;
        }
        let at = format!("{origin}:{}", n + 1);
        let words: Vec<&str> = line.split_whitespace().collect();

        match words[0] {
            "machine" => machine = Some(words[1].to_string()),
            "initial" => initial = Some(words[1].to_string()),
            "states" => states = words[1..].iter().map(|s| s.to_string()).collect(),
            "actions" => actions = words[1..].iter().map(|s| s.to_string()).collect(),
            _ => {
                let mut parts = line.split('|');
                let row = parts
                    .next()
                    .ok_or_else(|| format!("{at}: empty row"))?
                    .trim()
                    .to_string();
                let idx = cells.len();
                let expected = states.get(idx).cloned().unwrap_or_default();
                if row != expected {
                    return Err(format!(
                        "{at}: row {idx} is `{row}` but `states` says `{expected}`; \
                         row order must match state order"
                    ));
                }
                let mut r = vec![];
                for (j, p) in parts.enumerate() {
                    r.push(parse_cell(p, &format!("{at} col {j}"))?);
                }
                if r.len() != actions.len() {
                    return Err(format!(
                        "{at}: row `{row}` has {} cells, expected {} ({})",
                        r.len(),
                        actions.len(),
                        actions.join(" ")
                    ));
                }
                cells.push(r);
            }
        }
    }

    let machine = machine.ok_or_else(|| format!("{origin}: no `machine` line"))?;
    let initial = initial.ok_or_else(|| format!("{origin}: no `initial` line"))?;
    if cells.len() != states.len() {
        return Err(format!(
            "{origin}: {} rows for {} states",
            cells.len(),
            states.len()
        ));
    }
    Ok(Spec {
        machine,
        initial,
        states,
        actions,
        cells,
    })
}

fn parse_kv(words: &[&str], at: &str) -> Result<BTreeMap<String, i64>, String> {
    let mut m = BTreeMap::new();
    for w in words {
        let (k, v) = w
            .split_once('=')
            .ok_or_else(|| format!("{at}: `{w}` is not key=value"))?;
        let v: i64 = v
            .parse()
            .map_err(|_| format!("{at}: `{v}` is not an integer"))?;
        m.insert(k.to_string(), v);
    }
    Ok(m)
}

/// Parse a `.trace` file, which may hold several traces.
pub fn parse_traces(src: &str, origin: &str) -> Result<Vec<Trace>, String> {
    let mut out: Vec<Trace> = vec![];

    for (n, raw) in src.lines().enumerate() {
        let line = strip(raw);
        if line.is_empty() {
            continue;
        }
        let at = format!("{origin}:{}", n + 1);
        let words: Vec<&str> = line.split_whitespace().collect();

        if words[0] == "trace" {
            out.push(Trace {
                name: words.get(1).unwrap_or(&"unnamed").to_string(),
                ctx: BTreeMap::new(),
                from: String::new(),
                from_fields: BTreeMap::new(),
                steps: vec![],
            });
            continue;
        }

        let t = out
            .last_mut()
            .ok_or_else(|| format!("{at}: content before any `trace` line"))?;

        match words[0] {
            "ctx" => t.ctx = parse_kv(&words[1..], &at)?,
            "from" => {
                t.from = words[1].to_string();
                t.from_fields = parse_kv(&words[2..], &at)?;
            }
            _ => {
                let (lhs, rhs) = line
                    .split_once("=>")
                    .ok_or_else(|| format!("{at}: step needs `=>`"))?;
                let lw: Vec<&str> = lhs.split_whitespace().collect();
                let action = lw[0].to_string();
                let args = parse_kv(&lw[1..], &at)?;

                let (outcome, effects) = match rhs.split_once('!') {
                    Some((o, e)) => (
                        o.trim(),
                        e.split_whitespace().map(|s| s.to_string()).collect(),
                    ),
                    None => (rhs.trim(), vec![]),
                };
                let ow: Vec<&str> = outcome.split_whitespace().collect();
                let expect = match ow.first().copied() {
                    Some("stay") => Expect::Stay,
                    Some("ignored") => Expect::Ignored,
                    Some("go") => Expect::Go {
                        state: ow
                            .get(1)
                            .ok_or_else(|| format!("{at}: `go` needs a state"))?
                            .to_string(),
                        fields: parse_kv(&ow[2..], &at)?,
                    },
                    _ => return Err(format!("{at}: expected `go <State>`, `stay`, or `ignored`")),
                };
                t.steps.push(TraceStep {
                    action,
                    args,
                    expect,
                    effects,
                });
            }
        }
    }
    Ok(out)
}

/// Load a fixture and its traces from `spec/conformance`.
/// A fixture's cells, column-aligned exactly as `tabular_center::export::to_grid`
/// renders a generated table.
///
/// Lived in `bin/table-diff.rs` until now, which meant it could not be tested:
/// a binary's private functions are reachable from nothing. It is a hand-copy
/// of `to_grid`'s layout -- the same padding, the same right-trimming -- and
/// the whole point of the tool is that its output diffs cleanly against the
/// real thing. A hand-copy that nothing compares to its original is the shape
/// every finding in this project has taken.
pub fn spec_grid(s: &Spec) -> String {
    let texts: Vec<Vec<String>> = s
        .cells
        .iter()
        .map(|r| r.iter().map(CellSpec::grid_text).collect())
        .collect();

    let label_w = s
        .states
        .iter()
        .map(String::len)
        .chain(std::iter::once(s.machine.len()))
        .max()
        .unwrap_or(0);

    let col_w: Vec<usize> = (0..s.actions.len())
        .map(|j| {
            texts
                .iter()
                .map(|r| r[j].len())
                .chain(std::iter::once(s.actions[j].len()))
                .max()
                .unwrap_or(0)
        })
        .collect();

    let mut out = String::new();
    let mut line = format!("{:w$}", s.machine, w = label_w);
    for (j, a) in s.actions.iter().enumerate() {
        line.push_str(&format!("  {:w$}", a, w = col_w[j]));
    }
    out.push_str(line.trim_end());
    out.push('\n');
    for (i, st) in s.states.iter().enumerate() {
        line = format!("{:w$}", st, w = label_w);
        for (j, t) in texts[i].iter().enumerate() {
            line.push_str(&format!("  {:w$}", t, w = col_w[j]));
        }
        out.push_str(line.trim_end());
        out.push('\n');
    }
    out
}

pub fn load(root: &Path, name: &str) -> Result<(Spec, Vec<Trace>), String> {
    let tbl = root.join(format!("{name}.tbl"));
    let trc = root.join("traces").join(format!("{name}.trace"));
    let spec = parse_spec(
        &std::fs::read_to_string(&tbl).map_err(|e| format!("{}: {e}", tbl.display()))?,
        &tbl.display().to_string(),
    )?;
    let traces = parse_traces(
        &std::fs::read_to_string(&trc).map_err(|e| format!("{}: {e}", trc.display()))?,
        &trc.display().to_string(),
    )?;
    Ok((spec, traces))
}

// ---------------------------------------------------------------------------
// Table conformance
// ---------------------------------------------------------------------------

fn cell_matches(got: &Cell, want: &CellSpec) -> bool {
    fn eff(v: &[&'static str]) -> Vec<&'static str> {
        v.iter().map(|e| last_segment(e)).collect()
    }
    fn want_eff(v: &[String]) -> Vec<&str> {
        v.iter().map(|e| last_segment(e)).collect()
    }

    match (got, want) {
        (Cell::Ignore, CellSpec::Ignore) => true,
        (Cell::Handle, CellSpec::Handle) => true,
        (Cell::Unreachable, CellSpec::Unreachable) => true,
        (
            Cell::Go { target, effects },
            CellSpec::Go {
                target: t,
                effects: e,
            },
        ) => last_segment(target) == last_segment(t) && eff(effects) == want_eff(e),
        (Cell::Emit { effects }, CellSpec::Emit { effects: e }) => eff(effects) == want_eff(e),
        (Cell::Delegate { child }, CellSpec::Delegate { child: c }) => {
            last_segment(child) == last_segment(c)
        }
        _ => false,
    }
}

/// Compare a generated `TABLE` against a fixture, cell by cell.
///
/// Catches a generator that mis-parses a cell kind -- a class of bug that
/// trace replay can miss entirely, because several wrong tables produce right
/// answers on any one trace.
pub fn check_table<const N: usize, const M: usize>(got: &Table<N, M>, want: &Spec) -> Vec<String> {
    let mut errs = vec![];

    if got.machine != want.machine {
        errs.push(format!(
            "machine name: got `{}`, want `{}`",
            got.machine, want.machine
        ));
    }
    if got.initial != Some(want.initial.as_str()) {
        errs.push(format!(
            "initial: got {:?}, want `{}`",
            got.initial, want.initial
        ));
    }
    if got.states.as_slice() != want.states.as_slice() {
        errs.push(format!(
            "states: got {:?}, want {:?}",
            got.states, want.states
        ));
        return errs; // indices below would be meaningless
    }
    if got.actions.as_slice() != want.actions.as_slice() {
        errs.push(format!(
            "actions: got {:?}, want {:?}",
            got.actions, want.actions
        ));
        return errs;
    }

    for (i, row) in want.cells.iter().enumerate() {
        for (j, spec) in row.iter().enumerate() {
            let got_cell = got.cell(i, j);
            if !cell_matches(&got_cell, spec) {
                errs.push(format!(
                    "cell ({}, {}): got {:?}, want {}",
                    want.states[i], want.actions[j], got_cell, spec
                ));
            }
        }
    }
    errs
}

#[cfg(test)]
mod tests {
    #[test]
    fn spec_grid_matches_the_generated_grid_for_every_fixture() {
        // `table-diff` prints a fixture's grid so a reviewer can compare it
        // with the generated one. If the two renderers disagree the tool
        // produces exactly the misleading output it exists to prevent, and
        // nothing checked them against each other: `spec_grid` lived in a
        // binary, where a test cannot reach it.
        //
        // So compare the two renderers against each other directly, on every
        // fixture: `spec_grid` reads the `.tbl` contract, `Adapter::grid`
        // renders the machine's own TABLE, and they must agree. This went
        // through the committed `.grid` goldens until those were removed;
        // comparing the renderers is what the goldens were standing in for.
        let root =
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/conformance");
        let mut checked = 0;
        for entry in std::fs::read_dir(&root).expect("spec/conformance") {
            let path = entry.expect("dir entry").path();
            if path.extension().and_then(|e| e.to_str()) != Some("tbl") {
                continue;
            }
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .expect("fixture name")
                .to_string();
            let (spec, _) = super::load(&root, &name).expect(&name);
            let adapter = super::machines::all()
                .into_iter()
                .find(|a| a.name() == name)
                .unwrap_or_else(|| panic!("no adapter for {name}"));
            assert_eq!(
                super::spec_grid(&spec),
                adapter.grid(),
                "spec_grid and Adapter::grid drifted for {name}"
            );
            checked += 1;
        }
        // Discovered rather than listed, so a new fixture is covered the
        // moment it lands. The floor guards against the walk silently finding
        // nothing.
        assert!(checked >= 5, "expected every fixture, checked {checked}");
    }

    #[test]
    fn the_two_spellings_of_a_cell_are_different_on_purpose() {
        // `.tbl` is authored by hand and reads as a list; `.grid` is generated
        // and has to stay narrow enough to keep columns aligned. Recorded as
        // normative in spec/cells.md, and asserted here because the difference
        // looks like a bug to anyone meeting it for the first time -- which is
        // how `table-diff` came to use the wrong one.
        let cell = super::CellSpec::Go {
            target: "Idle".into(),
            effects: vec!["A".into(), "B".into()],
        };
        assert_eq!(cell.to_string(), "GO(Idle, A, B)");
        assert_eq!(cell.grid_text(), "GO(Idle, A+B)");
    }

    use super::*;

    #[test]
    fn parses_a_table() {
        let s = parse_spec(
            "machine T\ninitial A\nstates A B\nactions X Y\n\
             A | HANDLE | GO(B, Eff)\nB | EMIT(E1, E2) | UNREACHABLE\n",
            "t.tbl",
        )
        .unwrap();
        assert_eq!(s.machine, "T");
        assert_eq!(s.cells[0][0], CellSpec::Handle);
        assert_eq!(
            s.cells[0][1],
            CellSpec::Go {
                target: "B".into(),
                effects: vec!["Eff".into()]
            }
        );
        assert_eq!(
            s.cells[1][0],
            CellSpec::Emit {
                effects: vec!["E1".into(), "E2".into()]
            }
        );
        assert_eq!(s.cells[1][1], CellSpec::Unreachable);
    }

    #[test]
    fn row_order_must_match_state_order() {
        let e = parse_spec(
            "machine T\ninitial A\nstates A B\nactions X\nB | HANDLE\nA | HANDLE\n",
            "t.tbl",
        )
        .unwrap_err();
        assert!(e.contains("row order must match state order"), "{e}");
    }

    #[test]
    fn row_arity_is_checked_in_the_fixture_too() {
        let e = parse_spec(
            "machine T\ninitial A\nstates A\nactions X Y\nA | HANDLE\n",
            "t.tbl",
        )
        .unwrap_err();
        assert!(e.contains("has 1 cells, expected 2"), "{e}");
    }

    #[test]
    fn parses_traces_with_effects_and_fields() {
        let ts = parse_traces(
            "trace one\n  ctx limit=3\n  from A\n  \
             Start => go B since=0 ! E1 E2\n  Tick now=1 => stay\n  Z => ignored\n",
            "t.trace",
        )
        .unwrap();
        assert_eq!(ts.len(), 1);
        let t = &ts[0];
        assert_eq!(t.ctx["limit"], 3);
        assert_eq!(t.from, "A");
        assert!(t.from_fields.is_empty());
        assert_eq!(t.steps[0].effects, ["E1", "E2"]);
        // `since=0` sits on the expectation (`go B since=0`), not on the
        // action. Action arguments and expected-state fields are separate
        // namespaces and must not be conflated.
        assert!(t.steps[0].args.is_empty());
        assert_eq!(
            t.steps[0].expect,
            Expect::Go {
                state: "B".into(),
                fields: BTreeMap::from([("since".to_string(), 0)]),
            }
        );
        assert_eq!(t.steps[1].args["now"], 1);
        assert_eq!(t.steps[1].expect, Expect::Stay);
        assert_eq!(t.steps[2].expect, Expect::Ignored);
    }

    #[test]
    fn from_accepts_payload_fields_like_go_does() {
        let ts = parse_traces("trace t\n  from Retrying child_attempt=2\n", "t.trace").unwrap();
        assert_eq!(ts[0].from, "Retrying");
        assert_eq!(ts[0].from_fields["child_attempt"], 2);
    }

    #[test]
    fn check_table_reports_the_cell_that_drifted() {
        // A green suite that cannot fail is worthless. This asserts the
        // checker actually catches a wrong cell kind, which trace replay can
        // miss entirely -- several wrong tables produce right answers on any
        // one trace.
        let spec = parse_spec(
            "machine T\ninitial A\nstates A\nactions X\nA | HANDLE\n",
            "t.tbl",
        )
        .unwrap();
        let got: Table<1, 1> = Table {
            machine: "T",
            states: ["A"],
            actions: ["X"],
            initial: Some("A"),
            cells: [[Cell::Ignore]],
        };
        let errs = check_table(&got, &spec);
        assert_eq!(errs.len(), 1);
        assert!(errs[0].contains("cell (A, X)"), "{}", errs[0]);
        assert!(errs[0].contains("want HANDLE"), "{}", errs[0]);
    }

    #[test]
    fn check_table_tolerates_effect_qualification() {
        let spec = parse_spec(
            "machine T\ninitial A\nstates A\nactions X\nA | GO(A, Stop)\n",
            "t.tbl",
        )
        .unwrap();
        let got: Table<1, 1> = Table {
            machine: "T",
            states: ["A"],
            actions: ["X"],
            initial: Some("A"),
            cells: [[Cell::Go {
                target: "A",
                effects: &["Effect::Stop"],
            }]],
        };
        assert!(check_table(&got, &spec).is_empty());
    }

    #[test]
    fn effect_names_reduce_to_the_bare_variant() {
        assert_eq!(last_segment("StopClock"), "StopClock");
        assert_eq!(last_segment("Effect::StopClock"), "StopClock");
        assert_eq!(last_segment("F.StopClock"), "StopClock");
        // `{:?}` on a generated newtype enum. Stripping the payload must come
        // first: `{ reason: 0 }` contains a colon, so splitting on the path
        // separator first would yield ` 0 }`.
        assert_eq!(
            last_segment("StopClock(StopClock { reason: 0 })"),
            "StopClock"
        );
        assert_eq!(
            last_segment("Effect::StopClock(StopClock { reason: 0 })"),
            "StopClock"
        );
        assert_eq!(last_segment("Log(Log)"), "Log");
    }
}
