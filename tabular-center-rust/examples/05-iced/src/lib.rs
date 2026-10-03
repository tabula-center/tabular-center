//! A connection machine, a session that contains one, and the cells that
//! decide both.
//!
//! The library half knows nothing about iced: `src/main.rs` is the GUI, and
//! `tests/` drives these with no toolkit at all.
//!
//! Two machines in one crate means two modules, because each generates
//! `State`, `Action`, `step` and `TABLE` at module scope. The `#[path]`
//! declarations sit at the crate root -- a `#[path]` inside an inline module
//! resolves against a directory named after that module -- and each machine's
//! module re-exports what its matrix generated.

use tabular_center::{Driver, Handle, Lens, Perform, Step};

#[path = "connection.tb.rs"]
mod connection_matrix;

#[path = "session.tb.rs"]
mod session_matrix;

pub mod connection {
    /// What the child's cells are given. A clock, and somewhere to record
    /// what happened.
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub now: u32,
        pub log: Vec<String>,
    }

    pub use crate::connection_matrix::*;
}

pub mod session {
    /// Contains the child's context, so `child_ctx` is a field access.
    #[derive(Debug, Default)]
    pub struct Ctx {
        pub connection: super::connection::Ctx,
    }

    pub use crate::session_matrix::*;
}

/// One type satisfying both machines' surfaces.
///
/// The child's cells, the parent's, and the lens between them. `step` for the
/// session requires every one of these, so a hole in the CHILD is a build
/// error in the PARENT -- the composition property, in an application.
pub struct Cells;

impl Handle<connection::Connection, connection::Connecting, connection::Ready> for Cells {
    fn handle(
        &mut self,
        _ctx: &mut connection::Ctx,
        _state: connection::Connecting,
        action: connection::Ready,
    ) -> Step<connection::State, connection::Effect> {
        Step::go(connection::State::Live(connection::Live { since: action.at }))
    }
}

impl Perform<connection::Connection, connection::Dial> for Cells {
    fn perform(
        &mut self,
        ctx: &mut connection::Ctx,
        _effect: connection::Dial,
    ) -> Option<connection::Action> {
        ctx.log.push("dialling".into());
        Some(connection::Action::Ready(connection::Ready { at: ctx.now }))
    }
}

impl Perform<connection::Connection, connection::Hangup> for Cells {
    fn perform(
        &mut self,
        ctx: &mut connection::Ctx,
        _effect: connection::Hangup,
    ) -> Option<connection::Action> {
        ctx.log.push("hung up".into());
        None
    }
}

impl Perform<session::Session, session::Note> for Cells {
    fn perform(&mut self, ctx: &mut session::Ctx, _effect: session::Note) -> Option<session::Action> {
        ctx.connection.log.push("session ended".into());
        None
    }
}

impl Perform<session::Session, session::Dial> for Cells {
    fn perform(&mut self, ctx: &mut session::Ctx, _effect: session::Dial) -> Option<session::Action> {
        ctx.connection.log.push("dialling".into());
        Some(session::Action::Tap(session::Tap))
    }
}

impl Lens<session::Session, session::Running, connection::Marker> for Cells {
    fn child_state(&mut self, state: &session::Running) -> connection::State {
        state.child
    }

    fn embed(&mut self, _state: session::Running, child: connection::State) -> session::State {
        session::State::Running(session::Running { child })
    }

    fn lift(&mut self, effect: connection::Effect) -> session::Effect {
        match effect {
            connection::Effect::Dial(_) => session::Effect::Dial(session::Dial),
            connection::Effect::Hangup(_) => session::Effect::Note(session::Note),
        }
    }

    fn child_ctx<'a>(&mut self, ctx: &'a mut session::Ctx) -> &'a mut connection::Ctx {
        &mut ctx.connection
    }
}

impl tabular_center::Delegate<session::Session, session::Running, session::Tap, connection::Marker>
    for Cells
{
    fn to_child(
        &mut self,
        ctx: &mut session::Ctx,
        state: &session::Running,
        _action: session::Tap,
    ) -> Option<connection::Action> {
        match state.child {
            connection::State::Idle(_) => Some(connection::Action::Start(connection::Start)),
            connection::State::Connecting(_) => Some(connection::Action::Ready(connection::Ready {
                at: ctx.connection.now,
            })),
            connection::State::Live(_) => Some(connection::Action::Close(connection::Close)),
            connection::State::Failed(_) => Some(connection::Action::Retry(connection::Retry)),
        }
    }
}

/// The session, with its mailbox: what the GUI holds.
///
/// `Driver` is the whole host: an action goes in, the effects of the
/// resulting step are performed in order, and a follow-up action an effect
/// returns is enqueued rather than applied by reentering `step`. One press of
/// Tap in `Idle` therefore reaches `Live`, because the child's GO emits Dial
/// and Dial answers Ready -- through the parent, lens and all.
pub struct App {
    driver: Driver<session::State, session::Action, 8>,
    env: (Cells, session::Ctx),
}

impl Default for App {
    fn default() -> Self {
        Self {
            driver: Driver::new(session::State::Booting(session::Booting)),
            env: (Cells, session::Ctx::default()),
        }
    }
}

impl App {
    pub fn state(&self) -> session::State {
        self.driver.state()
    }

    pub fn log(&self) -> &[String] {
        &self.env.1.connection.log
    }

    pub fn set_now(&mut self, now: u32) {
        self.env.1.connection.now = now;
    }

    pub fn send(&mut self, action: session::Action) {
        let _ = self.driver.dispatch(
            &mut self.env,
            action,
            |(cells, ctx), s, a| session::step(cells, ctx, s, a),
            |(cells, ctx), e| session::perform(cells, ctx, e),
        );
    }

    pub fn grids(&self) -> (String, String) {
        (
            tabular_center::export::to_grid(&session::TABLE),
            tabular_center::export::to_grid(&connection::TABLE),
        )
    }

    pub fn describe(&self) -> (String, Option<(String, String)>) {
        match self.state() {
            session::State::Booting(_) => ("Booting".into(), None),
            session::State::Ended(_) => ("Session ended".into(), None),
            session::State::Running(session::Running { child }) => {
                let inner = match child {
                    connection::State::Idle(_) => ("Idle".into(), "Nothing connected.".into()),
                    connection::State::Connecting(_) => ("Connecting".into(), "Dialling...".into()),
                    connection::State::Live(connection::Live { since }) => {
                        ("Live".into(), format!("Connected at {since}."))
                    }
                    connection::State::Failed(_) => {
                        ("Failed".into(), "The connection dropped.".into())
                    }
                };
                ("Session running".into(), Some(inner))
            }
        }
    }
}
