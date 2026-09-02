//! **4. Composition.**
//!
//! A login session that delegates its authentication to a child machine.
//!
//! The property being demonstrated:
//!
//! > Scoping a total child into a total parent yields a total parent, and the
//! > compiler proves it by the same mechanism as everything else.
//!
//! `Session`'s `step` carries `auth::Cells` in its bound set, so leaving any
//! cell of the child unimplemented breaks the *parent's* build. A hand-written
//! `HANDLE` could not give that: it is free to ignore the child entirely.

use tabula::{transition_matrix, Delegate, Handle, Lens, Outcome, Step};

/// The child: authentication, written knowing nothing about sessions.
pub mod auth {
    use super::*;

    #[derive(Debug, Default)]
    pub struct Ctx {
        pub max_attempts: u32,
    }

    transition_matrix! {
        machine Auth;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Prompt, Lockout }
        initial AwaitingCredentials;

        states  { AwaitingCredentials { attempts: u32 }, Authenticated, LockedOut }
        actions { Submit { ok: u32 }, Reset }

        //                            Submit    Reset
        AwaitingCredentials  => [     HANDLE,   GO!(AwaitingCredentials { attempts: 0 }, Prompt) ];
        Authenticated        => [     IGNORE,   GO!(AwaitingCredentials { attempts: 0 }, Prompt) ];
        LockedOut            => [     IGNORE,   IGNORE                                          ];
    }
}

pub mod session {
    use super::*;

    /// The parent's context **contains** the child's, so `child_ctx` is a
    /// field access and the child never sees session data it has no business
    /// with.
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub auth: super::auth::Ctx,
        pub logins: u32,
    }

    transition_matrix! {
        machine Session;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Audit, Warn, Redirect }
        initial LoggedOut;

        states  { LoggedOut { auth: super::auth::State }, Active, Banned }
        actions { Credentials { ok: u32 }, StartOver, Logout }

        //                 Credentials         StartOver           Logout
        LoggedOut  => [     DELEGATE!(auth),   DELEGATE!(auth),    IGNORE                    ];
        Active     => [     IGNORE,            IGNORE,             GO!(Banned, Audit)        ];
        Banned     => [     IGNORE,            IGNORE,             IGNORE                    ];
    }
}

use session::Ctx as SessionCtx;

/// One object satisfying both machines' surfaces — the same shape the Kotlin
/// version gets from `interface Cells : auth.Cells`.
#[derive(Default)]
pub struct Impl;

impl Handle<auth::Auth, auth::AwaitingCredentials, auth::Submit> for Impl {
    fn handle(
        &mut self,
        c: &mut auth::Ctx,
        s: auth::AwaitingCredentials,
        a: auth::Submit,
    ) -> Step<auth::State, auth::Effect> {
        if a.ok == 1 {
            Step::go(auth::State::Authenticated(auth::Authenticated))
        } else if s.attempts + 1 >= c.max_attempts {
            Step::go(auth::State::LockedOut(auth::LockedOut)).emit(auth::Lockout.into())
        } else {
            Step::go(auth::State::AwaitingCredentials(auth::AwaitingCredentials {
                attempts: s.attempts + 1,
            }))
            .emit(auth::Prompt.into())
        }
    }
}

// The lens: once per (parent state, child), however many cells delegate.
impl Lens<session::Session, session::LoggedOut, auth::Marker> for Impl {
    fn child_state(&mut self, s: &session::LoggedOut) -> auth::State {
        s.auth
    }

    /// A child transition can be a parent transition: authenticating leaves
    /// `LoggedOut` entirely, and locking out bans the session.
    fn embed(&mut self, _s: session::LoggedOut, child: auth::State) -> session::State {
        match child {
            auth::State::Authenticated(_) => session::State::Active(session::Active),
            auth::State::LockedOut(_) => session::State::Banned(session::Banned),
            still_trying => session::State::LoggedOut(session::LoggedOut { auth: still_trying }),
        }
    }

    fn lift(&mut self, e: auth::Effect) -> session::Effect {
        match e {
            auth::Effect::Prompt(_) => session::Effect::Redirect(session::Redirect),
            auth::Effect::Lockout(_) => session::Effect::Warn(session::Warn),
        }
    }

    fn child_ctx<'a>(&mut self, ctx: &'a mut SessionCtx) -> &'a mut auth::Ctx {
        &mut ctx.auth
    }
}

// The prisms: one per delegate cell, and the only genuinely per-cell part.
impl Delegate<session::Session, session::LoggedOut, session::Credentials, auth::Marker> for Impl {
    fn to_child(
        &mut self,
        _ctx: &mut SessionCtx,
        _s: &session::LoggedOut,
        a: session::Credentials,
    ) -> Option<auth::Action> {
        Some(auth::Action::Submit(auth::Submit { ok: a.ok }))
    }
}

impl Delegate<session::Session, session::LoggedOut, session::StartOver, auth::Marker> for Impl {
    fn to_child(
        &mut self,
        _ctx: &mut SessionCtx,
        _s: &session::LoggedOut,
        _a: session::StartOver,
    ) -> Option<auth::Action> {
        Some(auth::Action::Reset(auth::Reset))
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

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
}
