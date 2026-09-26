//~ EXPECT: the trait bound `T: AsyncHandle<Timer, Running, Tick>` is not satisfied
//
// The guarantee, colored. The prototype is `async`, so every HANDLE cell is an
// `AsyncHandle` bound. A plain `Handle` impl is not a substitute -- it is the
// wrong color -- and the error names the colored bound for the exact cell.
use tabula::{transition_matrix, AsyncHandle, Handle, Step};
include!("_prelude.rs");

transition_matrix! {
    machine Timer; context Ctx; prototype async fn handle; state State; action Action; effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running { since: u32 }, Done }
    actions { Start, Tick { now: u32 }, Cancel }
    Idle    => [ HANDLE, IGNORE, IGNORE ];
    Running => [ IGNORE, HANDLE, GO!(Idle, StopClock) ];
    Done    => [ GO!(Running { since: 0 }), IGNORE, IGNORE ];
}

struct T;
impl AsyncHandle<Timer, Idle, Start> for T {
    async fn handle(&mut self, _c: &mut Ctx, _s: Idle, _a: Start) -> Step<State, Effect> {
        Step::stay()
    }
}
// A colored machine, an uncolored impl: the mistake.
impl Handle<Timer, Running, Tick> for T {
    fn handle(&mut self, _c: &mut Ctx, _s: Running, _a: Tick) -> Step<State, Effect> {
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
