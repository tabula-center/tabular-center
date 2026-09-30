//! `tabular-center-fmt [--check] [PATH...]`
//!
//! Aligns the cells of every `*.tb.rs`, `*.tb.kt` and `*.tb.swift` under the
//! given paths -- files or directories; the current directory when none are
//! given. With `--check`, writes nothing, lists what would change, and exits
//! non-zero if anything would. A file the formatter refuses to read is left
//! untouched and reported, and is a failure in both modes: a file the tool
//! cannot read is a file nobody is checking. See spec/tabular-center-fmt.md.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

/// Directories that hold build output, never source.
const SKIP: [&str; 5] = [".git", "target", "build", ".build", ".gradle"];

fn is_matrix_file(path: &Path) -> bool {
    let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
    [".tb.rs", ".tb.kt", ".tb.swift"]
        .iter()
        .any(|ext| name.ends_with(ext))
}

fn collect(path: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    if path.is_file() {
        if is_matrix_file(path) {
            out.push(path.to_path_buf());
        }
        return Ok(());
    }
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let child = entry.path();
        let name = entry.file_name();
        if child.is_dir() && SKIP.iter().any(|s| name == *s) {
            continue;
        }
        collect(&child, out)?;
    }
    Ok(())
}

fn main() -> ExitCode {
    let mut check = false;
    let mut roots = Vec::new();
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--check" => check = true,
            "-h" | "--help" => {
                println!("usage: tabular-center-fmt [--check] [PATH...]");
                return ExitCode::SUCCESS;
            }
            flag if flag.starts_with('-') => {
                eprintln!("tabular-center-fmt: unknown option {flag}");
                return ExitCode::from(2);
            }
            path => roots.push(PathBuf::from(path)),
        }
    }
    if roots.is_empty() {
        roots.push(PathBuf::from("."));
    }

    let mut files = Vec::new();
    for root in &roots {
        if let Err(e) = collect(root, &mut files) {
            eprintln!("tabular-center-fmt: {}: {e}", root.display());
            return ExitCode::from(2);
        }
    }
    files.sort();

    let (mut changed, mut refused) = (0, 0);
    for file in &files {
        let text = match fs::read_to_string(file) {
            Ok(t) => t,
            Err(e) => {
                eprintln!("tabular-center-fmt: {}: {e}", file.display());
                return ExitCode::from(2);
            }
        };
        match tabular_center_fmt::format(&text) {
            Err(refusal) => {
                refused += 1;
                println!("refused  {}: {refusal}", file.display());
            }
            Ok(formatted) if formatted != text => {
                changed += 1;
                if check {
                    println!("unaligned {}", file.display());
                    let before = text.lines().zip(formatted.lines());
                    for (n, (a, b)) in before.enumerate().filter(|(_, (a, b))| a != b) {
                        println!("  {}:{}", file.display(), n + 1);
                        println!("    - {a}");
                        println!("    + {b}");
                    }
                } else if let Err(e) = fs::write(file, &formatted) {
                    eprintln!("tabular-center-fmt: {}: {e}", file.display());
                    return ExitCode::from(2);
                } else {
                    println!("aligned  {}", file.display());
                }
            }
            Ok(_) => {}
        }
    }

    let verb = if check { "unaligned" } else { "aligned" };
    println!(
        "tabular-center-fmt: {} file(s), {changed} {verb}, {refused} refused",
        files.len()
    );
    if refused > 0 || (check && changed > 0) {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}
