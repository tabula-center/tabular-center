//! An async parent delegating to a child of either color.
//!
//! Color flows one way: a colorless child composes into a colored parent, and
//! the reverse is refused (`compile_fail/async_child_in_plain_parent.rs`).
//! What must hold here, where it is allowed:
//!
//! - an async parent delegates to a PLAIN child, whose `Step` is ready at once:
//!   one poll;
//! - an async parent delegates to an ASYNC child and really awaits it: the
//!   child suspends once, so the parent's `step` takes two polls.
//!
//! The parent's expansion cannot see the child's color and does not need to:
//! it awaits whatever the child's `step` returns, and a `Step` is `IntoFuture`.

mod common;

use common::{block_on, YieldOnce};
use tabular_center::{AsyncHandle, Delegate, Handle, Lens, Outcome, Step};

mod plain {
    use tabular_center::transition_matrix;

    pub struct Ctx;

    transition_matrix! {
        machine Plain;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Crossed }
        initial Low;

        states  { Low, High }
        actions { Bump }

        Low  => [  HANDLE  ];
        High => [  IGNORE  ];
    }
}

mod slow {
    use tabular_center::transition_matrix;

    pub struct Ctx;

    transition_matrix! {
        machine Slow;
        context Ctx;
        prototype async fn handle;
        state   State;
        action  Action;
        effects Effect { Crossed }
        initial Low;

        states  { Low, High }
        actions { Bump }

        Low  => [  HANDLE  ];
        High => [  IGNORE  ];
    }
}

mod over_plain {
    use super::plain;
    use tabular_center::transition_matrix;

    pub struct Ctx {
        pub child: plain::Ctx,
    }

    transition_matrix! {
        machine OverPlain;
        context Ctx;
        prototype async fn handle;
        state   State;
        action  Action;
        effects Effect { Note }
        initial Busy;

        states  { Busy { child: plain::State } }
        actions { Bump }

        Busy => [  DELEGATE!(plain)  ];
    }
}

mod over_slow {
    use super::slow;
    use tabular_center::transition_matrix;

    pub struct Ctx {
        pub child: slow::Ctx,
    }

    transition_matrix! {
        machine OverSlow;
        context Ctx;
        prototype async fn handle;
        state   State;
        action  Action;
        effects Effect { Note }
        initial Busy;

        states  { Busy { child: slow::State } }
        actions { Bump }

        Busy => [  DELEGATE!(slow)  ];
    }
}

// One type satisfying every surface: both children's cells, and both
// parents' lenses and prisms.
struct Impl;

impl Handle<plain::Plain, plain::Low, plain::Bump> for Impl {
    fn handle(
        &mut self,
        _c: &mut plain::Ctx,
        _s: plain::Low,
        _a: plain::Bump,
    ) -> Step<plain::State, plain::Effect> {
        Step::go(plain::State::High(plain::High)).emit(plain::Crossed.into())
    }
}

impl AsyncHandle<slow::Slow, slow::Low, slow::Bump> for Impl {
    async fn handle(
        &mut self,
        _c: &mut slow::Ctx,
        _s: slow::Low,
        _a: slow::Bump,
    ) -> Step<slow::State, slow::Effect> {
        YieldOnce(false).await;
        Step::go(slow::State::High(slow::High)).emit(slow::Crossed.into())
    }
}

impl Lens<over_plain::OverPlain, over_plain::Busy, plain::Marker> for Impl {
    fn child_state(&mut self, s: &over_plain::Busy) -> plain::State {
        s.child
    }

    fn embed(&mut self, _s: over_plain::Busy, child: plain::State) -> over_plain::State {
        over_plain::State::Busy(over_plain::Busy { child })
    }

    fn lift(&mut self, _e: plain::Effect) -> over_plain::Effect {
        over_plain::Effect::Note(over_plain::Note)
    }

    fn child_ctx<'a>(&mut self, ctx: &'a mut over_plain::Ctx) -> &'a mut plain::Ctx {
        &mut ctx.child
    }
}

impl Delegate<over_plain::OverPlain, over_plain::Busy, over_plain::Bump, plain::Marker> for Impl {
    fn to_child(
        &mut self,
        _c: &mut over_plain::Ctx,
        _s: &over_plain::Busy,
        _a: over_plain::Bump,
    ) -> Option<plain::Action> {
        Some(plain::Action::Bump(plain::Bump))
    }
}

impl Lens<over_slow::OverSlow, over_slow::Busy, slow::Marker> for Impl {
    fn child_state(&mut self, s: &over_slow::Busy) -> slow::State {
        s.child
    }

    fn embed(&mut self, _s: over_slow::Busy, child: slow::State) -> over_slow::State {
        over_slow::State::Busy(over_slow::Busy { child })
    }

    fn lift(&mut self, _e: slow::Effect) -> over_slow::Effect {
        over_slow::Effect::Note(over_slow::Note)
    }

    fn child_ctx<'a>(&mut self, ctx: &'a mut over_slow::Ctx) -> &'a mut slow::Ctx {
        &mut ctx.child
    }
}

impl Delegate<over_slow::OverSlow, over_slow::Busy, over_slow::Bump, slow::Marker> for Impl {
    fn to_child(
        &mut self,
        _c: &mut over_slow::Ctx,
        _s: &over_slow::Busy,
        _a: over_slow::Bump,
    ) -> Option<slow::Action> {
        Some(slow::Action::Bump(slow::Bump))
    }
}

#[test]
fn an_async_parent_delegates_to_a_plain_child() {
    let mut ctx = over_plain::Ctx { child: plain::Ctx };
    let start = over_plain::State::Busy(over_plain::Busy {
        child: plain::State::Low(plain::Low),
    });
    let (s, polls) = block_on(over_plain::step(
        &mut Impl,
        &mut ctx,
        start,
        over_plain::Action::Bump(over_plain::Bump),
    ));
    let want = over_plain::State::Busy(over_plain::Busy {
        child: plain::State::High(plain::High),
    });
    assert_eq!(s.outcome, Outcome::Go(want));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [over_plain::Effect::Note(over_plain::Note)]
    );
    assert_eq!(polls, 1, "a plain child's Step is ready at once");
}

#[test]
fn an_async_parent_awaits_an_async_child() {
    let mut ctx = over_slow::Ctx { child: slow::Ctx };
    let start = over_slow::State::Busy(over_slow::Busy {
        child: slow::State::Low(slow::Low),
    });
    let (s, polls) = block_on(over_slow::step(
        &mut Impl,
        &mut ctx,
        start,
        over_slow::Action::Bump(over_slow::Bump),
    ));
    let want = over_slow::State::Busy(over_slow::Busy {
        child: slow::State::High(slow::High),
    });
    assert_eq!(s.outcome, Outcome::Go(want));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [over_slow::Effect::Note(over_slow::Note)]
    );
    assert_eq!(polls, 2, "the parent must suspend where its child does");
}
