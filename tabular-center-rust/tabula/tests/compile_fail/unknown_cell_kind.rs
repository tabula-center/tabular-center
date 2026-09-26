//~ EXPECT: tabula::unknown-cell: `MAYBE` in row `Idle`, column `Start`
use tabula::transition_matrix;
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ MAYBE, IGNORE, IGNORE ];
    Running => [ IGNORE, IGNORE, GO!(Idle) ];
    Done    => [ IGNORE, IGNORE, IGNORE ];
}
fn main() {}
