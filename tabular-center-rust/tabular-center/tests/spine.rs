//! A spine, in Rust: `paths { .. }` in `transition_matrix!`.
//!
//! The same machine as `spine_of` in Kotlin's and Swift's additive tests:
//! `Idle -Start-> Connecting -Ready-> Live`, with a HANDLE on `Connecting x Drop`
//! that no hop names. What must hold, per `spec/happy-paths.md`:
//!
//! - A HANDLE named by a hop becomes a GO to the hop's next state. So the two
//!   hop cells need no `Handle` impl -- `Impl` below provides exactly one, for
//!   the cell the spine does not name, and this file would not compile if
//!   derivation had failed to happen.
//! - A spine-derived machine and the same machine written longhand are
//!   indistinguishable downstream: the same `TABLE`.
//! - Without the path, the same rows are a different machine. The control,
//!   so a derivation that did nothing could not pass the test above by the
//!   longhand twin being wrong.

use tabular_center::{Handle, Outcome, Step};

pub struct Ctx;

mod spine {
    use super::Ctx;
    use tabular_center::transition_matrix;

    transition_matrix! {
        machine Spine;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { }
        initial Idle;

        states  { Idle, Connecting, Live, Failed }
        actions { Start, Ready, Drop }

        paths {
            connect: [Idle, Start, Connecting, Ready, Live];
        }

        //              Start     Ready     Drop
        Idle       => [ HANDLE,   IGNORE,   IGNORE ];
        Connecting => [ IGNORE,   HANDLE,   HANDLE ];
        Live       => [ IGNORE,   IGNORE,   IGNORE ];
        Failed     => [ IGNORE,   IGNORE,   IGNORE ];
    }
}

mod longhand {
    use super::Ctx;
    use tabular_center::transition_matrix;

    transition_matrix! {
        machine Spine;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { }
        initial Idle;

        states  { Idle, Connecting, Live, Failed }
        actions { Start, Ready, Drop }

        //              Start              Ready         Drop
        Idle       => [ GO!(Connecting),   IGNORE,       IGNORE ];
        Connecting => [ IGNORE,            GO!(Live),    HANDLE ];
        Live       => [ IGNORE,            IGNORE,       IGNORE ];
        Failed     => [ IGNORE,            IGNORE,       IGNORE ];
    }
}

mod no_path {
    use super::Ctx;
    use tabular_center::transition_matrix;

    transition_matrix! {
        machine Spine;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { }
        initial Idle;

        states  { Idle, Connecting, Live, Failed }
        actions { Start, Ready, Drop }

        //              Start     Ready     Drop
        Idle       => [ HANDLE,   IGNORE,   IGNORE ];
        Connecting => [ IGNORE,   HANDLE,   HANDLE ];
        Live       => [ IGNORE,   IGNORE,   IGNORE ];
        Failed     => [ IGNORE,   IGNORE,   IGNORE ];
    }
}

/// The same route, walked in both directions.
///
/// `back Back` names the action that reverses each hop, so `(Connecting, Back)`
/// goes to `Idle` and `(Live, Back)` to `Connecting` -- derived, like the
/// forward direction, from HANDLE cells only. Nothing here implements those
/// cells, which is what proves they were derived.
mod both_ways {
    use super::Ctx;
    use tabular_center::transition_matrix;

    transition_matrix! {
        machine Spine;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { }
        initial Idle;

        states  { Idle, Connecting, Live }
        actions { Start, Ready, Back }

        paths {
            connect: [Idle, Start, Connecting, Ready, Live] back Back;
        }

        //              Start     Ready     Back
        Idle       => [ HANDLE,   IGNORE,   IGNORE ];
        Connecting => [ IGNORE,   HANDLE,   HANDLE ];
        Live       => [ IGNORE,   IGNORE,   HANDLE ];
    }
}

/// Implements the one cell the spine does not name, and nothing else.
struct Impl;

impl Handle<spine::Spine, spine::Connecting, spine::Drop> for Impl {
    fn handle(
        &mut self,
        _ctx: &mut Ctx,
        _state: spine::Connecting,
        _action: spine::Drop,
    ) -> Step<spine::State, spine::Effect> {
        Step::go(spine::State::Failed(spine::Failed))
    }
}

#[test]
fn a_hop_is_a_go_with_no_handler() {
    let s = spine::step(
        &mut Impl,
        &mut Ctx,
        spine::State::Idle(spine::Idle),
        spine::Action::Start(spine::Start),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(spine::State::Connecting(spine::Connecting))
    );

    let s = spine::step(
        &mut Impl,
        &mut Ctx,
        spine::State::Connecting(spine::Connecting),
        spine::Action::Ready(spine::Ready),
    );
    assert_eq!(s.outcome, Outcome::Go(spine::State::Live(spine::Live)));
}

#[test]
fn a_handle_no_hop_names_is_left_alone() {
    let s = spine::step(
        &mut Impl,
        &mut Ctx,
        spine::State::Connecting(spine::Connecting),
        spine::Action::Drop(spine::Drop),
    );
    assert_eq!(s.outcome, Outcome::Go(spine::State::Failed(spine::Failed)));
}

#[test]
fn a_spine_derived_machine_equals_its_longhand_twin() {
    assert_eq!(spine::TABLE, longhand::TABLE);
    assert_eq!(spine::TABLE.coverage().required_members(), 1);
}

#[test]
fn without_the_path_the_same_rows_are_a_different_machine() {
    assert_ne!(no_path::TABLE, longhand::TABLE);
    assert_eq!(no_path::TABLE.coverage().required_members(), 3);
}

#[test]
fn a_path_may_be_walked_backwards() {
    // No `Handle` impl exists for this machine at all: every cell is derived,
    // forwards or back, so `Impl` satisfies it by implementing nothing.
    let s = both_ways::step(
        &mut Impl,
        &mut Ctx,
        both_ways::State::Connecting(both_ways::Connecting),
        both_ways::Action::Back(both_ways::Back),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(both_ways::State::Idle(both_ways::Idle))
    );

    // Including at the path's end: walking back is not leaving, so this is a
    // cell rather than `tabular-center::path-unterminated`.
    let s = both_ways::step(
        &mut Impl,
        &mut Ctx,
        both_ways::State::Live(both_ways::Live),
        both_ways::Action::Back(both_ways::Back),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(both_ways::State::Connecting(both_ways::Connecting))
    );

    // And the forward direction is unchanged.
    let s = both_ways::step(
        &mut Impl,
        &mut Ctx,
        both_ways::State::Idle(both_ways::Idle),
        both_ways::Action::Start(both_ways::Start),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(both_ways::State::Connecting(both_ways::Connecting))
    );
}
