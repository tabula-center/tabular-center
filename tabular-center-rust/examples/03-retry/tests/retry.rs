use retry::*;

#[test]
fn the_machine_backs_off_and_gives_up_on_its_own() {
    // One dispatch. Everything after it is follow-up actions the handler
    // returned, queued and stepped by the driver.
    let (state, ctx) = run(3);
    assert_eq!(state, State::Exhausted(Exhausted));
    assert_eq!(
        ctx.performed,
        ["sleep:100", "sleep:200", "sleep:300", "give-up"]
    );
}

#[test]
fn backoff_grows_with_the_attempt() {
    let (_, ctx) = run(4);
    assert_eq!(
        ctx.performed,
        [
            "sleep:100",
            "sleep:200",
            "sleep:300",
            "sleep:400",
            "give-up"
        ]
    );
}

#[test]
fn a_single_attempt_gives_up_immediately() {
    let (state, ctx) = run(1);
    assert_eq!(state, State::Exhausted(Exhausted));
    assert_eq!(ctx.performed, ["sleep:100", "give-up"]);
}

#[test]
fn abort_is_static_and_needs_no_handler() {
    let mut ctx = Ctx {
        max_attempts: 5,
        performed: Vec::new(),
    };
    let s = step(
        &mut Impl,
        &mut ctx,
        State::Waiting(Waiting { attempt: 2 }),
        Action::Abort(Abort),
    );
    assert_eq!(s.outcome.target(), Some(State::Exhausted(Exhausted)));
    assert!(s.effects.is_empty());
    assert!(ctx.performed.is_empty());
}

#[test]
fn exhausted_ignores_everything() {
    let mut ctx = Ctx::default();
    for a in [
        Action::Attempt(Attempt),
        Action::Elapsed(Elapsed),
        Action::Abort(Abort),
    ] {
        let s = step(&mut Impl, &mut ctx, State::Exhausted(Exhausted), a);
        assert!(s.is_ignored());
    }
}
