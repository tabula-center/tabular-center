use login::*;
use tabula::Outcome;

// `SessionCtx` is a private alias inside the crate -- `use session::Ctx as
// SessionCtx`, written there so the lens impls read well. A `mod tests` at the
// bottom of lib.rs saw it through `use super::*`; an integration test is a
// separate crate and sees only what is public.
//
// Naming the real path is the better outcome anyway: a reader copying this
// example gets `session::Ctx`, which is what their own code will say.
use login::session::Ctx as SessionCtx;

fn fresh() -> session::State {
    session::State::LoggedOut(session::LoggedOut {
        auth: auth::State::AwaitingCredentials(auth::AwaitingCredentials { attempts: 0 }),
    })
}

fn ctx(max_attempts: u32) -> SessionCtx {
    SessionCtx {
        auth: auth::Ctx { max_attempts },
        logins: 0,
    }
}

#[test]
fn a_good_credential_promotes_the_parent_out_of_logged_out() {
    let mut c = ctx(3);
    let s = session::step(
        &mut Impl,
        &mut c,
        fresh(),
        session::Action::Credentials(session::Credentials { ok: 1 }),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(session::State::Active(session::Active))
    );
}

#[test]
fn a_bad_credential_keeps_the_parent_where_it_is_and_lifts_the_effect() {
    let mut c = ctx(3);
    let s = session::step(
        &mut Impl,
        &mut c,
        fresh(),
        session::Action::Credentials(session::Credentials { ok: 0 }),
    );
    // auth::Prompt became session::Redirect on the way up.
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [session::Effect::Redirect(session::Redirect)]
    );
    match s.outcome {
        Outcome::Go(session::State::LoggedOut(l)) => {
            assert_eq!(
                l.auth,
                auth::State::AwaitingCredentials(auth::AwaitingCredentials { attempts: 1 })
            );
        }
        other => panic!("expected to stay logged out, got {other:?}"),
    }
}

#[test]
fn exhausting_the_child_bans_the_session() {
    let mut c = ctx(1);
    let s = session::step(
        &mut Impl,
        &mut c,
        fresh(),
        session::Action::Credentials(session::Credentials { ok: 0 }),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(session::State::Banned(session::Banned))
    );
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [session::Effect::Warn(session::Warn)]
    );
}

#[test]
fn coverage_is_not_inherited_silently() {
    use tabula::Cell;
    // The LoggedOut row still lists all three columns. Two delegate, one
    // does not, and the table says which.
    assert_eq!(session::TABLE.cell(0, 0), Cell::Delegate { child: "auth" });
    assert_eq!(session::TABLE.cell(0, 1), Cell::Delegate { child: "auth" });
    assert_eq!(session::TABLE.cell(0, 2), Cell::Ignore);
}

#[test]
fn the_child_is_a_machine_in_its_own_right() {
    let mut c = auth::Ctx { max_attempts: 2 };
    let s = auth::step(
        &mut Impl,
        &mut c,
        auth::State::AwaitingCredentials(auth::AwaitingCredentials { attempts: 0 }),
        auth::Action::Submit(auth::Submit { ok: 1 }),
    );
    assert_eq!(
        s.outcome,
        Outcome::Go(auth::State::Authenticated(auth::Authenticated))
    );
}
