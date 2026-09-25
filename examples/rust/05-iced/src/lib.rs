//! A connection machine, and the cells that decide it.
//!
//! The library half knows nothing about iced: it is the machine, its one
//! handled cell, and its effect handlers. `src/main.rs` is the GUI, and
//! `tests/connection.rs` drives this half with no toolkit at all -- which is
//! the point worth demonstrating, because it is what a matrix buys.

use tabula::{Driver, Handle, Perform, Step};

/// What the cells are given. A clock, and somewhere to record what happened.
#[derive(Debug, Default)]
pub struct Ctx {
    pub now: u32,
    pub log: Vec<String>,
}

// The matrix lives in `machine.tb.rs`, per `spec/matrix-files.md`.
#[path = "machine.tb.rs"]
mod machine;

pub use machine::*;

/// The one cell the table leaves to code. Everything else is a GO or an
/// IGNORE, decided where a reader can see it.
pub struct Cells;

impl Handle<Connection, Connecting, Ready> for Cells {
    fn handle(
        &mut self,
        _ctx: &mut Ctx,
        _state: Connecting,
        action: Ready,
    ) -> Step<State, Effect> {
        Step::go(State::Live(Live { since: action.at }))
    }
}

impl Perform<Connection, Dial> for Cells {
    fn perform(&mut self, ctx: &mut Ctx, _effect: Dial) -> Option<Action> {
        ctx.log.push("dialling".into());
        // A real one would connect and answer later. Answering here keeps the
        // shape honest: an effect may produce a follow-up action, and the
        // driver enqueues it rather than recursing into `step`.
        Some(Action::Ready(Ready { at: ctx.now }))
    }
}

impl Perform<Connection, Hangup> for Cells {
    fn perform(&mut self, ctx: &mut Ctx, _effect: Hangup) -> Option<Action> {
        ctx.log.push("hung up".into());
        None
    }
}

/// The machine, with its mailbox: what the GUI holds.
///
/// `Driver` is tabula's, and it is the whole host: an action goes in, effects
/// are performed in order, and a follow-up action is enqueued rather than
/// applied by reentering `step`.
pub struct Connected {
    driver: Driver<State, Action, 8>,
    /// The cells and the context together, because `dispatch` takes ONE
    /// environment and hands it to both closures. Two closures capturing
    /// `&mut self.cells` separately do not borrow-check -- which is the bug
    /// `03-retry` was restructured around, and the reason its `run` looks
    /// like this too.
    env: (Cells, Ctx),
}

impl Default for Connected {
    fn default() -> Self {
        Self {
            driver: Driver::new(State::Idle(Idle)),
            env: (Cells, Ctx::default()),
        }
    }
}

impl Connected {
    pub fn state(&self) -> State {
        self.driver.state()
    }

    pub fn ctx(&self) -> &Ctx {
        &self.env.1
    }

    pub fn set_now(&mut self, now: u32) {
        self.env.1.now = now;
    }

    /// Send one action. Errors are the mailbox's, not the machine's: the
    /// matrix has an answer for every pair, so there is nothing else to fail.
    pub fn send(&mut self, action: Action) {
        let _ = self.driver.dispatch(
            &mut self.env,
            action,
            |(cells, ctx), s, a| step(cells, ctx, s, a),
            |(cells, ctx), e| perform(cells, ctx, e),
        );
    }

    /// What the effects have done, most recent last.
    pub fn log(&self) -> &[String] {
        &self.env.1.log
    }

    /// The matrix itself, rendered.
    ///
    /// `TABLE` is inert data the macro generated beside the dispatcher, so an
    /// application can show the machine it is running. The window does: the
    /// grid on screen is not a picture someone drew and has to keep current,
    /// it is the same table `step` dispatches through.
    pub fn grid(&self) -> String {
        tabula::export::to_grid(&TABLE)
    }

    /// How to describe the current state to a human. Shared with the tests,
    /// so what the window says is what the checks assert.
    pub fn describe(&self) -> (String, String) {
        match self.state() {
            State::Idle(_) => ("Idle".into(), "Nothing connected.".into()),
            State::Connecting(_) => ("Connecting".into(), "Dialling...".into()),
            State::Live(Live { since }) => ("Live".into(), format!("Connected at {since}.")),
            State::Failed(_) => ("Failed".into(), "The connection dropped.".into()),
        }
    }
}
