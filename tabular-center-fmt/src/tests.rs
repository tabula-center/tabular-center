//! The contract, as cases. Each expected output was produced by the prototype
//! that was run over every `.tb.` file in the repository before this crate was
//! written, so these tests also say the two implementations agree.

use super::format;

fn formats_to(input: &str, expected: &str) {
    let once = format(input).expect("formats");
    assert_eq!(once, expected, "formatted output");
    assert_eq!(format(&once).expect("formats again"), once, "idempotent");
}

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

#[test]
fn kotlin_annotation_rows() {
    formats_to(
        r#"@Row(S.Idle::class, [CellSpec(Kind.HANDLE), CellSpec(Kind.IGNORE)])
@Row(S.Running::class, [CellSpec(Kind.IGNORE), CellSpec(Kind.GO, to = S.Idle::class)])"#,
        r#"@Row(S.Idle::class,    [CellSpec(Kind.HANDLE), CellSpec(Kind.IGNORE)])
@Row(S.Running::class, [CellSpec(Kind.IGNORE), CellSpec(Kind.GO, to = S.Idle::class)])"#,
    );
}

#[test]
fn paths_untouched() {
    formats_to(
        r#"@Path("go", [S.Idle::class, A.Start::class, S.Busy::class])
@Path("stop", [S.Idle::class, A.Stop::class, S.Done::class])"#,
        r#"@Path("go", [S.Idle::class, A.Start::class, S.Busy::class])
@Path("stop", [S.Idle::class, A.Stop::class, S.Done::class])"#,
    );
}

#[test]
fn single_row_untouched() {
    formats_to(
        r#"    Idle => [HANDLE,   IGNORE];"#,
        r#"    Idle => [HANDLE,   IGNORE];"#,
    );
}

#[test]
fn arity_mismatch_untouched() {
    formats_to(
        r#"    Idle => [HANDLE, IGNORE];
    Busy => [IGNORE, HANDLE, IGNORE];"#,
        r#"    Idle => [HANDLE, IGNORE];
    Busy => [IGNORE, HANDLE, IGNORE];"#,
    );
}

#[test]
fn trailing_comment_kept() {
    formats_to(
        r#"            [.handle, .ignore],   // idle
            [.go(target: "Idle", effects: []), .ignore], // busy"#,
        r#"            [.handle,                          .ignore],   // idle
            [.go(target: "Idle", effects: []), .ignore], // busy"#,
    );
}

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

#[test]
fn unterminated_string_beside_a_run_is_refused() {
    let input = r#"            [.handle, .ignore],
            [.ignore, .handle],
            [.go(target: "Idle, .ignore],"#;
    let refusal = format(input).expect_err("refused");
    assert_eq!(refusal.line, 3);
}

#[test]
fn an_empty_cell_is_refused() {
    let input = "    Idle => [HANDLE, , IGNORE];\n    Busy => [IGNORE, HANDLE, IGNORE];";
    let refusal = format(input).expect_err("refused");
    assert_eq!(refusal.line, 1);
}

#[test]
fn text_without_rows_is_returned_unchanged() {
    let input = "import Foo\n\n// a comment, with [brackets, and commas]\nfn main() {}\n";
    formats_to(input, input);
}
