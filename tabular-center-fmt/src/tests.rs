//! The contract, as cases. Each expected output was produced by the prototype
//! that was run over every `.tb.` file in the repository before this crate was
//! written, so these tests also say the two implementations agree.

use super::format;

/// Formats, and checks the result is a fixed point: `fmt(fmt(x)) == fmt(x)`.
fn formats_to(input: &str, expected: &str) {
    let once = format(input).expect("formats");
    assert_eq!(once, expected, "formatted output");
    assert_eq!(format(&once).expect("formats again"), once, "idempotent");
}

/// Kotlin `listOf` rows written compactly: the first column is aligned; the last cell, whose
/// closers were never aligned, is left as written.
#[test]
fn kotlin_compact_rows_align() {
    formats_to(
        r#"    rows = listOf(
        listOf(Cell.Go("Amber"), Cell.Go("Red")),
        listOf(Cell.Handle, Cell.Go("Red")),
        listOf(Cell.Go("Green"), Cell.Ignore),
    ),"#,
        r#"    rows = listOf(
        listOf(Cell.Go("Amber"), Cell.Go("Red")),
        listOf(Cell.Handle,      Cell.Go("Red")),
        listOf(Cell.Go("Green"), Cell.Ignore),
    ),"#,
    );
}

/// A hand-aligned Rust matrix whose closers line up is already formatted, and stays exactly as it
/// is.
#[test]
fn rust_aligned_closers_stay() {
    formats_to(
        r#"    Idle    => [  HANDLE,                                IGNORE,  IGNORE          ];
    Running => [  IGNORE,                                HANDLE,  GO!(Idle, Stop) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,  IGNORE          ];"#,
        r#"    Idle    => [  HANDLE,                                IGNORE,  IGNORE          ];
    Running => [  IGNORE,                                HANDLE,  GO!(Idle, Stop) ];
    Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,  IGNORE          ];"#,
    );
}

/// KSP `@Row` annotations: the cell list is the `[...]` inside `@Row(...)`, and the state column
/// aligns too.
#[test]
fn kotlin_annotation_rows() {
    formats_to(
        r#"@Row(S.Idle::class, [CellSpec(Kind.HANDLE), CellSpec(Kind.IGNORE)])
@Row(S.Running::class, [CellSpec(Kind.IGNORE), CellSpec(Kind.GO, to = S.Idle::class)])"#,
        r#"@Row(S.Idle::class,    [CellSpec(Kind.HANDLE), CellSpec(Kind.IGNORE)])
@Row(S.Running::class, [CellSpec(Kind.IGNORE), CellSpec(Kind.GO, to = S.Idle::class)])"#,
    );
}

/// `@Path` spines have a row's shape and are not rows.
#[test]
fn paths_untouched() {
    formats_to(
        r#"@Path("go", [S.Idle::class, A.Start::class, S.Busy::class])
@Path("stop", [S.Idle::class, A.Stop::class, S.Done::class])"#,
        r#"@Path("go", [S.Idle::class, A.Start::class, S.Busy::class])
@Path("stop", [S.Idle::class, A.Stop::class, S.Done::class])"#,
    );
}

/// A run of one line is not a run: nothing to align it to.
#[test]
fn single_row_untouched() {
    formats_to(
        r#"    Idle => [HANDLE,   IGNORE];"#,
        r#"    Idle => [HANDLE,   IGNORE];"#,
    );
}

/// Rows of different arity never form a run; arity is `row-arity`'s job, at compile time.
#[test]
fn arity_mismatch_untouched() {
    formats_to(
        r#"    Idle => [HANDLE, IGNORE];
    Busy => [IGNORE, HANDLE, IGNORE];"#,
        r#"    Idle => [HANDLE, IGNORE];
    Busy => [IGNORE, HANDLE, IGNORE];"#,
    );
}

/// A trailing comment rides along, its spacing kept.
#[test]
fn trailing_comment_kept() {
    formats_to(
        r#"            [.handle, .ignore],   // idle
            [.go(target: "Idle", effects: []), .ignore], // busy"#,
        r#"            [.handle,                          .ignore],   // idle
            [.go(target: "Idle", effects: []), .ignore], // busy"#,
    );
}

/// Swift: the rows align; the `states:` and `actions:` header lines have a row's shape and are
/// left alone.
#[test]
fn swift_rows_align_headers_do_not() {
    formats_to(
        r#"        states: ["Idle", "Running", "Done"],
        actions: ["Start", "Tick", "Cancel"],
        cells: [
            [.handle, .ignore, .ignore],
            [.go(target: "Idle", effects: []), .handle, .ignore],
        ],"#,
        r#"        states: ["Idle", "Running", "Done"],
        actions: ["Start", "Tick", "Cancel"],
        cells: [
            [.handle,                          .ignore, .ignore],
            [.go(target: "Idle", effects: []), .handle, .ignore],
        ],"#,
    );
}

/// An unterminated string beside a run: the run's edge cannot be trusted, so
/// the file is refused rather than half-formatted.
#[test]
fn unterminated_string_beside_a_run_is_refused() {
    let input = r#"            [.handle, .ignore],
            [.ignore, .handle],
            [.go(target: "Idle, .ignore],"#;
    let refusal = format(input).expect_err("refused");
    assert_eq!(refusal.line, 3);
}

/// An empty cell cannot be placed in a column; refused, not guessed at.
#[test]
fn an_empty_cell_is_refused() {
    let input = "    Idle => [HANDLE, , IGNORE];\n    Busy => [IGNORE, HANDLE, IGNORE];";
    let refusal = format(input).expect_err("refused");
    assert_eq!(refusal.line, 1);
}

/// Text with no rows at all comes back byte for byte.
#[test]
fn text_without_rows_is_returned_unchanged() {
    let input = "import Foo\n\n// a comment, with [brackets, and commas]\nfn main() {}\n";
    formats_to(input, input);
}
