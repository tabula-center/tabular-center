//! Both machines, checked with no toolkit involved: the child on its own, and
//! the parent driving it through the lens.
//!
//! What this cannot verify is what is on the screen. `nix flake check` opens
//! no window, and `rust-gui` says so when it passes.

use iced_connection::{connection, session, App, Cells};
use tabular_center::{Outcome, Step};

#[test]
fn the_child_dials_and_answers_itself() {
    let mut cells = Cells;
    let mut ctx = connection::Ctx { now: 7, log: vec![] };

    let s = connection::step(
        &mut cells,
        &mut ctx,
        connection::State::Idle(connection::Idle),
        connection::Action::Start(connection::Start),
    );
    assert!(matches!(s.outcome, Outcome::Go(connection::State::Connecting(_))));
}

#[test]
fn a_tap_is_delegated_and_the_effect_is_lifted() {
    let mut app = App::default();
    app.set_now(7);
    app.send(session::Action::Boot(session::Boot));

    // One Tap, and four things happen without the UI knowing any of the
    // words: the prism narrows it to the child's Start; the child's GO emits
    // Dial; the LENS lifts that to the parent's Dial, because a composed
    // child's effects are the parent's to interpret; the parent answers with
    // its own Tap, which the mailbox delivers and the prism narrows to Ready.
    app.send(session::Action::Tap(session::Tap));

    let (status, inner) = app.describe();
    assert_eq!(status, "Session running");
    assert_eq!(inner, Some(("Live".to_string(), "Connected at 7.".to_string())));
    assert_eq!(app.log(), ["dialling"]);
}

#[test]
fn a_button_pressed_at_the_wrong_moment_is_a_decision() {
    let mut app = App::default();

    // Tap before the session has booted: IGNORE, decided in the parent's
    // table rather than by a disabled button in `view`.
    app.send(session::Action::Tap(session::Tap));

    assert_eq!(app.describe().0, "Booting");
    assert!(app.log().is_empty());
}

#[test]
fn the_parent_still_decides_its_own_actions() {
    let mut app = App::default();
    app.send(session::Action::Boot(session::Boot));
    app.send(session::Action::Finish(session::Finish));

    assert_eq!(app.describe().0, "Session ended");
    assert_eq!(app.log(), ["session ended"]);
}

#[test]
fn the_window_shows_both_matrices() {
    let app = App::default();
    let (session_grid, connection_grid) = app.grids();
    assert!(session_grid.contains("Session"));
    assert!(connection_grid.contains("Connection"));
}
