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

use tabular_center::{Handle, Step};

/// Cross-state data. A machine with nothing to remember still needs a type
/// here; a unit struct is the honest answer.
pub struct Ctx {
    pub cycles: u32,
}

#[path = "machine.tb.rs"]
mod machine;

pub use machine::*;

pub struct Controller;

impl Handle<TrafficLight, Amber, Advance> for Controller {
    fn handle(&mut self, ctx: &mut Ctx, _s: Amber, _a: Advance) -> Step<State, Effect> {
        ctx.cycles += 1;
        Step::go(State::Red(Red))
    }
}
