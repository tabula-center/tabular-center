//~ EXPECT: tabula::missing-row: state `Done` has no row
//
// Checked structurally during expansion. A `const` assertion would never run:
// the array-length mismatch on TABLE is a type error, and type errors abort
// before const evaluation.
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effect Effect; initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE, GO!(Idle) ];
}
fn main() {}
