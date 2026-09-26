//~ EXPECT: tabula::row-arity: row `Idle` has too many cells
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE, GO!(Idle) ];
    Done    => [ GO!(Running { since: 0 }), IGNORE, IGNORE ];
}
fn main() {}
