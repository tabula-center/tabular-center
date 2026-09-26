//~ EXPECT: the trait bound `T: tabula::Handle<Timer, Running, Tick>` is not satisfied
//
// The guarantee. `Running x Tick` is HANDLE, so `step` requires the bound;
// omitting the impl names the exact hole. This error comes from rustc, not
// from tabula, which is why it survives even if the macro is bypassed.
use tabula::{transition_matrix, Handle, Step};
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE, GO!(Idle, StopClock) ];
    Done    => [ GO!(Running { since: 0 }), IGNORE, IGNORE ];
}

struct T;
impl Handle<Timer, Idle, Start> for T {
    fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Start) -> Step<State, Effect> {
        Step::stay()
    }
}

fn main() {
    let _ = step(
        &mut T,
        &mut Ctx { limit: 1 },
        State::Idle(Idle),
        Action::Start(Start),
    );
}
