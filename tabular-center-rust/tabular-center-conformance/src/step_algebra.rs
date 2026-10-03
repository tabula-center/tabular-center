//! Replays spec/conformance/step-algebra.cases against Rust's `Step`: each
//! case's input steps are built, the operation applied, and the result
//! written back in the file's spelling and compared as text. The file must
//! also hold every outcome combination for every operation, so losing a case
//! fails rather than passing on less. Format: spec/conformance/README.md.

use std::collections::BTreeSet;
use std::path::Path;

use tabular_center::{Outcome, Step};

type One = Step<i64, String, 8>;
type Pair = Step<(i64, i64), String, 8>;
type Evaluated = (String, String, (String, Kind, Kind));

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
enum Kind {
    Go,
    Stay,
    Ignored,
}

#[derive(Clone, Copy, Debug)]
enum Target {
    Literal(i64),
    InputPlus(i64),
}

#[derive(Clone, Debug)]
struct Written {
    kind: Kind,
    targets: Vec<Target>,
    effects: Vec<String>,
}

fn parse_target(text: &str) -> Result<Target, String> {
    let bad = || format!("bad target `{text}`");
    if text == "s" {
        return Ok(Target::InputPlus(0));
    }
    if let Some(offset) = text.strip_prefix("s+") {
        let offset = offset.parse().map_err(|_| bad())?;
        return Ok(Target::InputPlus(offset));
    }
    let literal = text.parse().map_err(|_| bad())?;
    Ok(Target::Literal(literal))
}

fn parse_effects(text: &str) -> Result<Vec<String>, String> {
    if text.is_empty() {
        return Ok(Vec::new());
    }
    let bad = || format!("bad effects `{text}`");
    let inner = text.strip_prefix('[').ok_or_else(bad)?;
    let inner = inner.strip_suffix(']').ok_or_else(bad)?;
    if inner.is_empty() {
        return Err("write no effects as nothing, not `[]`".to_string());
    }
    Ok(inner.split(',').map(str::to_string).collect())
}

fn parse_step(text: &str) -> Result<Written, String> {
    if let Some(rest) = text.strip_prefix("ignored") {
        if !rest.is_empty() {
            return Err(format!("`{text}`: an ignored step has no effects"));
        }
        return Ok(Written {
            kind: Kind::Ignored,
            targets: Vec::new(),
            effects: Vec::new(),
        });
    }
    if let Some(rest) = text.strip_prefix("stay") {
        return Ok(Written {
            kind: Kind::Stay,
            targets: Vec::new(),
            effects: parse_effects(rest)?,
        });
    }
    let rest = match text.strip_prefix("go(") {
        Some(rest) => rest,
        None => return Err(format!("`{text}` is not a step")),
    };
    let close = match rest.find(')') {
        Some(close) => close,
        None => return Err(format!("`{text}`: unclosed target")),
    };
    let mut targets = Vec::new();
    for part in rest[..close].split(',') {
        targets.push(parse_target(part)?);
    }
    Ok(Written {
        kind: Kind::Go,
        targets,
        effects: parse_effects(&rest[close + 1..])?,
    })
}

fn build(written: &Written, input: i64) -> Result<One, String> {
    let mut step = match written.kind {
        Kind::Go => match written.targets.as_slice() {
            [Target::Literal(n)] => Step::go(*n),
            [Target::InputPlus(k)] => Step::go(input + k),
            _ => return Err("an input step has exactly one target".to_string()),
        },
        Kind::Stay => Step::stay(),
        Kind::Ignored => Step::ignored(),
    };
    for effect in &written.effects {
        if let Err(e) = step.try_emit(effect.clone()) {
            return Err(format!("cannot build the step: {e}"));
        }
    }
    Ok(step)
}

fn render<S>(step: &Step<S, String, 8>, target: impl Fn(&S) -> String) -> String {
    let head = match &step.outcome {
        Outcome::Go(s) => format!("go({})", target(s)),
        Outcome::Stay => "stay".to_string(),
        Outcome::Ignored => "ignored".to_string(),
    };
    let effects: Vec<&str> = step.effects.iter().map(String::as_str).collect();
    if effects.is_empty() {
        head
    } else {
        format!("{head}[{}]", effects.join(","))
    }
}

fn render_one(step: &One) -> String {
    render(step, |n| n.to_string())
}

fn render_pair(step: &Pair) -> String {
    render(step, |(a, b)| format!("{a},{b}"))
}

fn evaluate(tokens: &[&str]) -> Result<Evaluated, String> {
    match tokens {
        ["map", lhs, "=>", expected] => {
            let lhs = parse_step(lhs)?;
            let actual = build(&lhs, 0)?.map(|n| n + 10);
            let kinds = ("map".to_string(), lhs.kind, Kind::Go);
            Ok((render_one(&actual), expected.to_string(), kinds))
        }
        ["and_then", lhs, "then", next, "=>", expected] => {
            let lhs = parse_step(lhs)?;
            let next = parse_step(next)?;
            build(&next, 0)?;
            let actual =
                build(&lhs, 0)?.and_then(|s| build(&next, s).unwrap_or_else(|_| Step::ignored()));
            let kinds = ("and_then".to_string(), lhs.kind, next.kind);
            Ok((render_one(&actual), expected.to_string(), kinds))
        }
        ["zip", lhs, rhs, "=>", expected] => {
            let lhs = parse_step(lhs)?;
            let rhs = parse_step(rhs)?;
            let actual = build(&lhs, 0)?.zip(build(&rhs, 0)?);
            let kinds = ("zip".to_string(), lhs.kind, rhs.kind);
            Ok((render_pair(&actual), expected.to_string(), kinds))
        }
        _ => Err("not a case in the documented shape".to_string()),
    }
}

fn required() -> BTreeSet<(String, Kind, Kind)> {
    let all = [Kind::Go, Kind::Stay, Kind::Ignored];
    let mut required = BTreeSet::new();
    for lhs in all {
        required.insert(("map".to_string(), lhs, Kind::Go));
        for rhs in all {
            required.insert(("and_then".to_string(), lhs, rhs));
            required.insert(("zip".to_string(), lhs, rhs));
        }
    }
    required
}

pub fn replay(root: &Path) -> Result<(usize, Vec<String>), String> {
    let path = root.join("step-algebra.cases");
    let text = std::fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut failures = Vec::new();
    let mut seen = BTreeSet::new();
    let mut cases = 0;
    for (index, line) in text.lines().enumerate() {
        let tokens: Vec<&str> = line.split_whitespace().collect();
        if tokens.is_empty() {
            continue;
        }
        cases += 1;
        match evaluate(&tokens) {
            Ok((actual, expected, kinds)) => {
                seen.insert(kinds);
                if actual != expected {
                    failures.push(format!(
                        "line {}: `{}` gave {actual}, expected {expected}",
                        index + 1,
                        line.trim()
                    ));
                }
            }
            Err(e) => failures.push(format!("line {}: {e}", index + 1)),
        }
    }
    for (op, lhs, rhs) in required().difference(&seen) {
        failures.push(format!("no case for {op} with {lhs:?} and {rhs:?}"));
    }
    Ok((cases, failures))
}
