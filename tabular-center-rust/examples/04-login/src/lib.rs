//! **4. Composition.**
//!
//! A login session that delegates its authentication to a child machine.
//!
//! Two modules, `auth` and `session`, in a file named for neither: `mod
//! session` inside `mod session` is `clippy::module_inception`, and the lint
//! is right that it reads badly.
//!
//! The property being demonstrated:
//!
//! > Scoping a total child into a total parent yields a total parent, and the
//! > compiler proves it by the same mechanism as everything else.
//!
//! `Session`'s `step` carries `auth::Cells` in its bound set, so leaving any
//! cell of the child unimplemented breaks the *parent's* build. A hand-written
//! `HANDLE` could not give that: it is free to ignore the child entirely.

use tabula::{Delegate, Handle, Lens, Step};

// Each matrix lives in its own `.tb.rs`, per `spec/matrix-files.md`, as a
// private module re-exported by the public one named for its machine.
#[path = "auth.tb.rs"]
mod auth_matrix;
#[path = "session.tb.rs"]
mod session_matrix;

/// The child: authentication, written knowing nothing about sessions.
pub mod auth {
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub max_attempts: u32,
    }

    pub use crate::auth_matrix::*;
}

pub mod session {
    /// The parent's context **contains** the child's, so `child_ctx` is a
    /// field access and the child never sees session data it has no business
    /// with.
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub auth: super::auth::Ctx,
        pub logins: u32,
    }

    pub use crate::session_matrix::*;
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
            Step::go(auth::State::AwaitingCredentials(
                auth::AwaitingCredentials {
                    attempts: s.attempts + 1,
                },
            ))
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
