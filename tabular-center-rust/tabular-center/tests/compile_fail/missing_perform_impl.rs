//~ EXPECT: Perform<Timer, StopClock>
//
// The effect surface, same guarantee as the cell surface. `StopClock` is a
// declared effect variant with no `Perform` impl, so `perform` will not
// compile. Add an effect to a shipped machine and every handler in the
// codebase stops building -- which is the point.
use tabular_center::{transition_matrix, Perform};

pub struct Ctx;

transition_matrix! {
    machine Timer; context Ctx; state State; action Action;
    effects Effect { StartClock, StopClock } initial Idle;
    states  { Idle, Running }
    actions { Start, Cancel }
    Idle    => [ GO!(Running, StartClock), IGNORE                ];
    Running => [ IGNORE,                   GO!(Idle, StopClock)  ];
}

struct Impl;

impl Perform<Timer, StartClock> for Impl {
    fn perform(&mut self, _c: &mut Ctx, _e: StartClock) -> Option<Action> {
        None
    }
}

fn main() {
    let _ = perform(&mut Impl, &mut Ctx, Effect::StartClock(StartClock));
}
