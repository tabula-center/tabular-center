//! **1. The minimum.**
//!
//! Three states, two actions, no payloads, no effects. Six cells, one of which
//! the developer writes.
//!
//! This is also the only example that exercises the degenerate cases:
//! `effects Effect { }` is an uninhabited enum, and because five of six cells
//! are static, `TABLE.is_fully_static()` is false only on account of the single
//! `HANDLE` — flip that to `GO!` and the reachability lint starts speaking.

// No std. Nothing here needs it: the generated dispatcher is `match` and
// struct construction, and `Step` is a fixed-capacity value rather than a Vec.
#![no_std]

use tabula::{transition_matrix, Handle, Step};

/// Cross-state data. A machine with nothing to remember still needs a type
/// here; a unit struct is the honest answer.
pub struct Ctx {
    pub cycles: u32,
}

transition_matrix! {
    machine TrafficLight;
    context Ctx;
    state   State;
    action  Action;
    // An uninhabited enum: this machine emits nothing, and its cells do
    // whatever they need to do directly. A supported mode, not a degraded one.
    effects Effect { }
    initial Red;

    states  { Red, Green, Amber }
    actions { Advance, Fault }

    //           Advance        Fault
    Red    => [  GO!(Green),    GO!(Red)   ];
    Green  => [  GO!(Amber),    GO!(Red)   ];
    Amber  => [  HANDLE,        GO!(Red)   ];
}

pub struct Controller;

impl Handle<TrafficLight, Amber, Advance> for Controller {
    /// The one cell with a decision in it: leaving amber counts a cycle.
    ///
    /// It could have been `GO!(Red)` — it is `HANDLE` because it touches
    /// context, and a static cell cannot. That boundary is the whole reason
    /// both kinds exist.
    fn handle(&mut self, ctx: &mut Ctx, _s: Amber, _a: Advance) -> Step<State, Effect> {
        ctx.cycles += 1;
        Step::go(State::Red(Red))
    }
}
