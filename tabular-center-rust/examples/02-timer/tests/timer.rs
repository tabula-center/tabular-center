use tabular_center::Outcome;
use timer::*;

fn ctx(limit: u64) -> Ctx {
    Ctx {
        limit,
        ..Default::default()
    }
}

#[test]
fn a_tick_below_the_limit_stays_and_is_not_ignored() {
    let mut c = ctx(10);
    let s = step(
        &mut Impl,
        &mut c,
        State::Running(Running { since: 0 }),
        Action::Tick(Tick { now: 1 }),
    );
    assert_eq!(s.outcome, Outcome::Stay);
    assert!(!s.is_ignored(), "a tick while running is meaningful");
}

#[test]
fn the_limit_finishes_the_timer() {
    let mut c = ctx(3);
    let s = step(
        &mut Impl,
        &mut c,
        State::Running(Running { since: 2 }),
        Action::Tick(Tick { now: 9 }),
    );
    assert_eq!(s.outcome, Outcome::Go(State::Done(Done)));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StopClock(StopClock {
            reason: Reason::Elapsed
        })]
    );
}

#[test]
fn the_same_effect_carries_different_reasons() {
    // Cancelling and elapsing both stop the clock; the payload is what
    // tells a handler which happened.
    let mut c = ctx(100);
    let cancelled = step(
        &mut Impl,
        &mut c,
        State::Running(Running { since: 0 }),
        Action::Cancel(Cancel),
    );
    assert_eq!(
        cancelled.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::StopClock(StopClock {
            reason: Reason::Cancelled
        })]
    );
}

#[test]
fn effect_handlers_receive_narrowed_payloads() {
    let mut c = ctx(1);
    perform(
        &mut Impl,
        &mut c,
        StopClock {
            reason: Reason::Elapsed,
        }
        .into(),
    );
    assert_eq!(c.log, ["stop:Elapsed"]);
}

#[test]
fn actions_that_mean_nothing_here_are_ignored() {
    let mut c = ctx(1);
    for (st, ac) in [
        (State::Idle(Idle), Action::Tick(Tick { now: 1 })),
        (State::Idle(Idle), Action::Cancel(Cancel)),
        (State::Done(Done), Action::Cancel(Cancel)),
    ] {
        assert!(step(&mut Impl, &mut c, st, ac).is_ignored());
    }
}
