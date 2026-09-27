//! Renders a machine's matrix as a diffable grid, and diffs it against the
//! fixture.
//!
//! A PR that changes machine behaviour should show the *table* diff, not just
//! the code diff. Reviewing a matrix is what this library is for; reviewing a
//! `match` arm is what it exists to avoid.

use std::process::ExitCode;

use tabular_center_conformance::machines::all;
use tabular_center_conformance::spec_grid;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let want = args.first().map(String::as_str);

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../spec/conformance");
    let mut any = false;

    for adapter in all() {
        let name = adapter.name();
        if want.is_some_and(|w| w != name) {
            continue;
        }
        any = true;

        match tabular_center_conformance::load(&root, name) {
            Ok((spec, _)) => {
                println!("{}", spec_grid(&spec));
                let errs = adapter.check_table(&spec);
                if errs.is_empty() {
                    println!("  (matches the generated table)\n");
                } else {
                    println!("  DIFFERS from the generated table:");
                    for e in errs {
                        println!("    {e}");
                    }
                    println!();
                }
            }
            Err(e) => println!("{name}: {e}"),
        }
    }

    if !any {
        eprintln!(
            "no such fixture; known: {:?}",
            all().iter().map(|a| a.name()).collect::<Vec<_>>()
        );
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
