//! **1. The minimum.**
//!
//! Three states, two actions, no payloads, no effects. Six cells, one of which
//! the developer writes.
//!
//! This is also the only example that exercises the degenerate cases:
//! `effects Effect { }` is an uninhabited enum, and because five of six cells
//! are static, `TABLE.is_fully_static()` is false only on account of the single
//! `HANDLE` — flip that to `GO!` and the reachability lint starts speaking.

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

#[cfg(test)]
mod tests {
    use super::*;
    use tabula::Outcome;

    #[test]
    fn a_full_cycle() {
        let mut ctx = Ctx { cycles: 0 };
        let mut c = Controller;
        let mut state = State::Red(Red);

        for _ in 0..2 {
            for _ in 0..3 {
                let s = step(&mut c, &mut ctx, state, Action::Advance(Advance));
                state = s.outcome.target().expect("every cell here transitions");
            }
        }
        assert_eq!(state, State::Red(Red));
        assert_eq!(ctx.cycles, 2);
    }

    #[test]
    fn a_fault_from_anywhere_goes_red() {
        let mut ctx = Ctx { cycles: 0 };
        let mut c = Controller;
        for from in [State::Red(Red), State::Green(Green), State::Amber(Amber)] {
            let s = step(&mut c, &mut ctx, from, Action::Fault(Fault));
            assert_eq!(s.outcome, Outcome::Go(State::Red(Red)));
        }
    }

    #[test]
    fn six_cells_cost_one_implementation() {
        let cov = TABLE.coverage();
        assert_eq!(cov.total(), 6);
        assert_eq!(cov.go, 5);
        assert_eq!(cov.required_members(), 1);
    }

    #[test]
    fn a_machine_with_no_effects_emits_nothing() {
        let mut ctx = Ctx { cycles: 0 };
        let s = step(
            &mut Controller,
            &mut ctx,
            State::Red(Red),
            Action::Advance(Advance),
        );
        assert!(s.effects.is_empty());
    }
}
