//~ EXPECT: tabular-center::row-arity: row `Running` has too few cells; missing a cell for action `Cancel`
use tabular_center::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE ];
    Done    => [ GO!(Running { since: 0 }), IGNORE, IGNORE ];
}
fn main() {}
