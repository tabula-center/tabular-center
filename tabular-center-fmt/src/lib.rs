//! Pads the cells of `.tb.` matrix rows so their columns line up.
//!
//! The contract is `spec/tabular-center-fmt.md`, and this file keeps to it:
//! one job, alignment, and a refusal rather than a guess whenever a line
//! cannot be read with confidence.
//!
//! It is not a parser. A row is recognised by structure alone -- a line that
//! ends in a bracketed, comma-separated list -- so the same code aligns
//! `Red => [GO!(Green), GO!(Red)];`, `listOf(Cell.Handle, Cell.Ignore),`,
//! `@Row(S.Idle::class, [CellSpec(Kind.HANDLE), ...])` and
//! `[.handle, .ignore],` without knowing Rust, Kotlin or Swift.
//!
//! Where the contract left a choice open, the answer came from running a
//! prototype over every `.tb.` file in the repository:
//!
//! - **Columns never shrink.** A column is as wide as its widest cell or its
//!   widest current slot, whichever is larger, so a hand-aligned matrix -- and
//!   the column-header comment above it -- survives. Padding only grows to
//!   fix misalignment.
//! - **Closers are the author's.** If a run's closing brackets are already
//!   aligned, they stay aligned; otherwise each row's last cell and whatever
//!   follows it are left exactly as written. The tool aligns where cells
//!   start, which is what reading a grid needs.
//! - **Header lines are not rows.** A line whose prefix is a `.tb.` header key
//!   (`states:`, `actions =`, ...) or a `@Path` spine is never part of a run,
//!   even when it has a row's shape.

#![forbid(unsafe_code)]

use std::fmt;

/// Why a file was left untouched. `line` is 1-based.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Refusal {
    pub line: usize,
    pub reason: String,
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "line {}: {}", self.line, self.reason)
    }
}

const HEADER_KEYS: [&str; 8] = [
    "machine", "states", "actions", "effects", "initial", "context", "paths", "cells",
];

pub fn format(text: &str) -> Result<String, Refusal> {
    let lines: Vec<Vec<char>> = text.split('\n').map(|l| l.chars().collect()).collect();
    let parsed: Vec<Line> = lines.iter().map(|l| classify(l)).collect();
    let mut out: Vec<String> = lines.iter().map(|l| l.iter().collect()).collect();

    let mut i = 0;
    while i < lines.len() {
        let Line::Row(first) = &parsed[i] else {
            i += 1;
            continue;
        };
        let key = first.shape();
        let mut j = i + 1;
        while j < lines.len() {
            match &parsed[j] {
                Line::Row(r) if r.shape() == key => j += 1,
                _ => break,
            }
        }
        if j - i >= 2 {
            for k in [i.checked_sub(1), Some(j)].into_iter().flatten() {
                if let Some(Line::Unreadable(reason)) = parsed.get(k) {
                    if same_indent(&lines[k], &first.indent) {
                        return Err(Refusal {
                            line: k + 1,
                            reason: format!("{reason}, beside a run of rows"),
                        });
                    }
                }
            }
            let rows: Vec<&Row> = parsed[i..j]
                .iter()
                .map(|l| match l {
                    Line::Row(r) => r,
                    _ => unreachable!("a run holds only rows"),
                })
                .collect();
            let formatted = format_run(&rows).map_err(|reason| Refusal {
                line: i + 1,
                reason,
            })?;
            out.splice(i..j, formatted).for_each(drop);
        }
        i = j;
    }
    Ok(out.join("\n"))
}

/// A line as the run finder sees it.
enum Line {
    Row(Row),
    Unreadable(String),
    Other,
}

/// A line that ends in a bracketed list of cells:
/// `indent prefix OPEN inner CLOSE suffix [sep comment]`.
struct Row {
    indent: String,
    prefix: Vec<char>,
    open: char,
    inner: Vec<char>,
    close: char,
    suffix: String,
    sep: String,
    comment: String,
}

impl Row {
    fn shape(&self) -> (String, char, char, String, usize) {
        (
            self.indent.clone(),
            self.open,
            self.close,
            self.suffix.trim().to_string(),
            cells(&self.inner).len(),
        )
    }
}

fn same_indent(line: &[char], indent: &str) -> bool {
    let n = indent.chars().count();
    line.len() >= n
        && line[..n].iter().copied().eq(indent.chars())
        && line.get(n).is_none_or(|c| *c != ' ')
}

fn classify(line: &[char]) -> Line {
    match row(line) {
        Ok(Some(r)) => Line::Row(r),
        Ok(None) => Line::Other,
        Err(reason) => Line::Unreadable(reason),
    }
}

/// A bracket group within one line: its opener, the positions of its
/// brackets, its nesting depth, and how many commas sit directly inside it.
struct Group {
    open: char,
    start: usize,
    end: usize,
    depth: usize,
    commas: usize,
}

fn closer_of(open: char) -> char {
    match open {
        '[' => ']',
        '(' => ')',
        _ => '}',
    }
}

fn groups(code: &[char]) -> Result<Option<Vec<Group>>, String> {
    let mut stack: Vec<(char, usize, usize)> = Vec::new();
    let mut commas: Vec<usize> = Vec::new();
    let mut found = Vec::new();
    let mut in_string = false;
    let mut i = 0;
    while i < code.len() {
        let c = code[i];
        if in_string {
            if c == '\\' {
                i += 2;
                continue;
            }
            if c == '"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        match c {
            '"' => {
                if code[i..].starts_with(&['"', '"', '"']) {
                    return Err("a triple-quoted string".to_string());
                }
                in_string = true;
            }
            '\'' | '`' => return Err(format!("a `{c}` quote")),
            '#' if code.get(i + 1) == Some(&'"') => return Err("a raw string".to_string()),
            '[' | '(' | '{' => {
                stack.push((c, i, stack.len()));
                commas.push(0);
            }
            ']' | ')' | '}' => match stack.pop() {
                Some((open, start, depth)) if closer_of(open) == c => {
                    let n = commas.pop().unwrap_or(0);
                    found.push(Group {
                        open,
                        start,
                        end: i,
                        depth,
                        commas: n,
                    });
                }
                _ => return Ok(None),
            },
            ',' => {
                if let Some(n) = commas.last_mut() {
                    *n += 1;
                }
            }
            _ => {}
        }
        i += 1;
    }
    if in_string {
        return Err("an unterminated string".to_string());
    }
    Ok(if stack.is_empty() { Some(found) } else { None })
}

fn split_comment(body: &[char]) -> (Vec<char>, Vec<char>) {
    let mut in_string = false;
    let mut i = 0;
    while i < body.len() {
        let c = body[i];
        if in_string {
            if c == '\\' {
                i += 2;
                continue;
            }
            if c == '"' {
                in_string = false;
            }
        } else if c == '"' {
            in_string = true;
        } else if c == '/' && body.get(i + 1) == Some(&'/') {
            return (body[..i].to_vec(), body[i..].to_vec());
        }
        i += 1;
    }
    (body.to_vec(), Vec::new())
}

fn is_header(prefix: &str) -> bool {
    let p = prefix.trim();
    p.starts_with("@Path")
        || HEADER_KEYS.iter().any(|key| {
            p.strip_prefix(key).is_some_and(|rest| {
                let rest = rest.trim_start();
                rest.starts_with(':') || rest.starts_with('=')
            })
        })
}

fn row(line: &[char]) -> Result<Option<Row>, String> {
    let n = line.iter().take_while(|c| matches!(c, ' ' | '\t')).count();
    let indent: String = line[..n].iter().collect();
    let body = &line[n..];
    let starts = |s: &str| body.iter().copied().take(s.len()).eq(s.chars());
    if body.is_empty() || starts("//") || starts("/*") || starts("*") {
        return Ok(None);
    }
    let (code, comment) = split_comment(body);
    let trimmed = code
        .iter()
        .rposition(|c| !c.is_whitespace())
        .map_or(0, |p| p + 1);
    let sep: String = if comment.is_empty() {
        String::new()
    } else {
        code[trimmed..].iter().collect()
    };
    let code = &code[..trimmed];

    let Some(all) = groups(code)? else {
        return Ok(None);
    };
    let tail_ok = |g: &&Group| {
        code[g.end + 1..]
            .iter()
            .all(|c| matches!(c, ']' | ')' | '}' | ';' | ',') || c.is_whitespace())
    };
    let chain: Vec<&Group> = all.iter().filter(tail_ok).collect();
    let Some(g) = list_of(&chain) else {
        return Ok(None);
    };
    let prefix = code[..g.start].to_vec();
    if is_header(&prefix.iter().collect::<String>()) {
        return Ok(None);
    }
    Ok(Some(Row {
        indent,
        prefix,
        open: g.open,
        inner: code[g.start + 1..g.end].to_vec(),
        close: code[g.end],
        suffix: code[g.end + 1..].iter().collect(),
        sep,
        comment: comment.iter().collect(),
    }))
}

fn list_of<'a>(chain: &[&'a Group]) -> Option<&'a Group> {
    let square = |g: &&Group| g.open == '[';
    if let Some(g) = shallowest(chain.iter().copied().filter(square)) {
        return Some(g);
    }
    let paren = |g: &&Group| g.open == '(' && g.commas >= 1;
    shallowest(chain.iter().copied().filter(paren))
}

fn shallowest<'a>(groups: impl Iterator<Item = &'a Group>) -> Option<&'a Group> {
    let mut best: Option<&Group> = None;
    for g in groups {
        if best.is_none_or(|b| g.depth < b.depth) {
            best = Some(g);
        }
    }
    best
}

fn cells(inner: &[char]) -> Vec<(usize, String)> {
    let mut segments = Vec::new();
    let mut depth = 0usize;
    let mut in_string = false;
    let mut start = 0;
    let mut i = 0;
    while i < inner.len() {
        let c = inner[i];
        if in_string {
            if c == '\\' {
                i += 2;
                continue;
            }
            if c == '"' {
                in_string = false;
            }
        } else {
            match c {
                '"' => in_string = true,
                '(' | '[' | '{' => depth += 1,
                ')' | ']' | '}' => depth = depth.saturating_sub(1),
                ',' if depth == 0 => {
                    segments.push((start, &inner[start..i]));
                    start = i + 1;
                }
                _ => {}
            }
        }
        i += 1;
    }
    segments.push((start, &inner[start..]));
    segments
        .into_iter()
        .map(|(s, seg)| {
            let lead = seg.iter().take_while(|c| **c == ' ').count();
            let text: String = seg.iter().collect();
            (s + lead, text.trim_matches(' ').to_string())
        })
        .collect()
}

fn pad(s: &str, width: usize) -> String {
    let n = s.chars().count();
    let mut out = s.to_string();
    out.push_str(&" ".repeat(width.saturating_sub(n)));
    out
}

fn trailing_spaces(chars: &[char]) -> usize {
    chars.iter().rev().take_while(|c| **c == ' ').count()
}

fn format_run(rows: &[&Row]) -> Result<Vec<String>, String> {
    let split: Vec<Vec<(usize, String)>> = rows.iter().map(|r| cells(&r.inner)).collect();
    if split.iter().flatten().any(|(_, t)| t.is_empty()) {
        return Err("an empty cell, which the splitter cannot place".to_string());
    }
    let n = split[0].len();
    let prefix_col = rows.iter().map(|r| r.prefix.len()).max().unwrap_or(0);
    let lead = split.iter().map(|c| c[0].0).max().unwrap_or(0);
    let tail = rows
        .iter()
        .map(|r| trailing_spaces(&r.inner))
        .min()
        .unwrap_or(0);

    let width: Vec<usize> = (0..n)
        .map(|j| {
            rows.iter()
                .zip(&split)
                .map(|(r, c)| {
                    let own = c[j].1.chars().count();
                    let slot = if j + 1 < n {
                        (c[j + 1].0 - c[j].0).saturating_sub(2)
                    } else {
                        (r.inner.len() - c[j].0).saturating_sub(tail)
                    };
                    own.max(slot)
                })
                .max()
                .unwrap_or(0)
        })
        .collect();

    let closers_aligned = {
        let first = rows[0].prefix.len() + rows[0].inner.len();
        rows.iter().all(|r| r.prefix.len() + r.inner.len() == first)
    };

    Ok(rows
        .iter()
        .zip(&split)
        .map(|(r, c)| {
            let mut line = r.indent.clone();
            let prefix: String = r.prefix.iter().collect();
            line.push_str(&pad(prefix.trim_end_matches(' '), prefix_col));
            line.push(r.open);
            line.push_str(&" ".repeat(lead));
            for (j, (_, text)) in c[..n - 1].iter().enumerate() {
                line.push_str(&pad(&format!("{text},"), width[j] + 1));
                line.push(' ');
            }
            if closers_aligned {
                line.push_str(&pad(&c[n - 1].1, width[n - 1]));
                line.push_str(&" ".repeat(tail));
            } else {
                line.extend(r.inner[c[n - 1].0..].iter());
            }
            line.push(r.close);
            line.push_str(&r.suffix);
            if !r.comment.is_empty() {
                line.push_str(&r.sep);
                line.push_str(&r.comment);
            }
            line
        })
        .collect())
}

#[cfg(test)]
mod tests;
