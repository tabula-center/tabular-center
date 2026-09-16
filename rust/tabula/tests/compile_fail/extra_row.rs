//~ EXPECT: tabula::extra-row: row `Paused` does not correspond to a declared state
//
// The mirror of missing_row.rs, and the last of Rust's five compile-time
// diagnostics to get a UI test.
//
// Worth having separately rather than trusting the pair to be symmetric: the
// macro walks `states` and `rows` together, and the two arms that report a
// mismatch are reached at different points in that walk. `missing-row` fires
// when states remain and rows are exhausted; this one when rows remain and
// states are. Nothing in the macro makes one follow from the other, so a
// refactor can break either alone.
//
// The message names the declared states, so a reader who typed `Paused` for a
// state they called something else sees the candidates without going back to
// the declaration. The EXPECT line stops before that list on purpose --
// asserting on the states would make this fixture fail whenever the machine
// grows one, which is noise rather than signal.
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE, GO!(Idle) ];
    Done    => [ IGNORE, IGNORE, IGNORE ];
    Paused  => [ IGNORE, IGNORE, IGNORE ];
}
fn main() {}
