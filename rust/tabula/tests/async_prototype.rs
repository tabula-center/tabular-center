//! `prototype async fn handle;`: the machine's color, in Rust.
//!
//! The same timer as `timer_matrix.rs`, colored. What must hold:
//!
//! - HANDLE cells are `AsyncHandle` impls, and `step` really awaits them: a
//!   handler that suspends once makes the executor poll `step` more than once.
//! - Static cells need no developer code, colored or not.
//! - Effects are `AsyncPerform` impls, awaited by an `async fn perform`.
//! - `prototype fn handle;` spells out the uncolored default.
//!
//! No executor dependency: `tabula` has no dependencies, so neither do its
//! tests. `common::block_on` is the whole executor these need.

mod common;

use common::{block_on, YieldOnce};

mod colored {
    use super::{block_on, YieldOnce};
    use tabula::{transition_matrix, AsyncHandle, AsyncPerform, Outcome, Step};

    #[derive(Debug, Default)]
    pub struct Ctx {
        pub limit: u32,
        pub ticks_seen: u32,
        pub clocks: u32,
    }

    transition_matrix! {
        machine Timer;
        context Ctx;
        prototype async fn handle;
        state   State;
        action  Action;
        effects Effect { StartClock, StopClock { reason: u32 } }
        initial Idle;

        states  { Idle, Running { since: u32 }, Done }
        actions { Start, Tick { now: u32 }, Cancel }

        //            Start                                  Tick      Cancel
        Idle    => [  HANDLE,                                IGNORE,   IGNORE                             ];
        Running => [  IGNORE,                                HANDLE,   GO!(Idle, StopClock { reason: 0 }) ];
        Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE,   IGNORE                             ];
    }

    #[derive(Default)]
    struct TimerImpl;

    impl AsyncHandle<Timer, Idle, Start> for TimerImpl {
        async fn handle(
            &mut self,
            _ctx: &mut Ctx,
            _state: Idle,
            _action: Start,
        ) -> Step<State, Effect> {
            Step::go(State::Running(Running { since: 0 })).emit(StartClock.into())
        }
    }

    impl AsyncHandle<Timer, Running, Tick> for TimerImpl {
        async fn handle(
            &mut self,
            ctx: &mut Ctx,
            state: Running,
            action: Tick,
        ) -> Step<State, Effect> {
            // Suspends before deciding -- the point of a colored cell.
            YieldOnce(false).await;
            ctx.ticks_seen += 1;
            if action.now.saturating_sub(state.since) >= ctx.limit {
                Step::go(State::Done(Done)).emit(StopClock { reason: 1 }.into())
            } else {
                Step::stay()
            }
        }
    }

    impl AsyncPerform<Timer, StartClock> for TimerImpl {
        async fn perform(&mut self, ctx: &mut Ctx, _effect: StartClock) -> Option<Action> {
            YieldOnce(false).await;
            ctx.clocks += 1;
            None
        }
    }

    impl AsyncPerform<Timer, StopClock> for TimerImpl {
        async fn perform(&mut self, ctx: &mut Ctx, effect: StopClock) -> Option<Action> {
            ctx.clocks = ctx.clocks.saturating_sub(1);
            (effect.reason == 0).then_some(Action::Start(Start))
        }
    }

    fn ctx(limit: u32) -> Ctx {
        Ctx {
            limit,
            ..Ctx::default()
        }
    }

    #[test]
    fn a_handle_cell_is_awaited() {
        let (mut m, mut c) = (TimerImpl, ctx(5));
        let (s, _) = block_on(step(
            &mut m,
            &mut c,
            State::Idle(Idle),
            Action::Start(Start),
        ));
        assert_eq!(s.outcome, Outcome::Go(State::Running(Running { since: 0 })));
        assert_eq!(
            s.effects.iter().copied().collect::<Vec<_>>(),
            [Effect::StartClock(StartClock)]
        );
    }

    #[test]
    fn step_suspends_where_its_cell_suspends() {
        let (mut m, mut c) = (TimerImpl, ctx(100));
        let (s, polls) = block_on(step(
            &mut m,
            &mut c,
            State::Running(Running { since: 0 }),
            Action::Tick(Tick { now: 1 }),
        ));
        assert_eq!(s.outcome, Outcome::Stay);
        assert_eq!(c.ticks_seen, 1);
        // One poll to reach the cell's YieldOnce, one to finish. A `step` that
        // did not await its cell could not have been Pending at all.
        assert_eq!(polls, 2, "step must propagate the cell's suspension");
    }

    #[test]
    fn static_cells_need_no_developer_code() {
        let (mut m, mut c) = (TimerImpl, ctx(5));
        let (s, polls) = block_on(step(
            &mut m,
            &mut c,
            State::Running(Running { since: 3 }),
            Action::Cancel(Cancel),
        ));
        assert_eq!(s.outcome, Outcome::Go(State::Idle(Idle)));
        assert_eq!(polls, 1, "a GO cell has nothing to await");
        let (s, _) = block_on(step(
            &mut m,
            &mut c,
            State::Done(Done),
            Action::Tick(Tick { now: 1 }),
        ));
        assert!(s.is_ignored());
    }

    #[test]
    fn perform_is_awaited_per_effect() {
        let (mut m, mut c) = (TimerImpl, ctx(5));
        let (follow, polls) = block_on(perform(&mut m, &mut c, Effect::StartClock(StartClock)));
        assert_eq!((follow, c.clocks, polls), (None, 1, 2));
        let (follow, _) = block_on(perform(
            &mut m,
            &mut c,
            Effect::StopClock(StopClock { reason: 0 }),
        ));
        assert_eq!((follow, c.clocks), (Some(Action::Start(Start)), 0));
    }

    #[test]
    fn the_table_does_not_know_the_color() {
        // Color is how the cells are called, not what the matrix says: the
        // same rows, the same TABLE, the same coverage as the plain timer.
        assert_eq!(TABLE.machine, "Timer");
        assert_eq!(TABLE.coverage().required_members(), 2);
    }
}

mod plain_prototype {
    use tabula::{transition_matrix, Handle, Outcome, Step};

    pub struct Ctx;

    // The uncolored default, spelled out.
    transition_matrix! {
        machine Toggle;
        context Ctx;
        prototype fn handle;
        state   State;
        action  Action;
        effects Effect { }
        initial Off;

        states  { Off, On }
        actions { Flip }

        //         Flip
        Off => [   GO!(On)   ];
        On  => [   HANDLE    ];
    }

    struct Impl;

    impl Handle<Toggle, On, Flip> for Impl {
        fn handle(&mut self, _ctx: &mut Ctx, _state: On, _action: Flip) -> Step<State, Effect> {
            Step::go(State::Off(Off))
        }
    }

    #[test]
    fn an_explicit_plain_prototype_is_the_default() {
        let s = step(&mut Impl, &mut Ctx, State::On(On), Action::Flip(Flip));
        assert_eq!(s.outcome, Outcome::Go(State::Off(Off)));
    }
}
