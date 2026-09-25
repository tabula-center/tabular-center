//! The machine, checked with no toolkit involved.
//!
//! This is what `nix flake check` verifies about the GUI example: every
//! transition, the effect answering with a follow-up action, and what the
//! window would say. What it cannot verify is what is on the screen -- it
//! opens no window, and an example claiming otherwise would cover less than
//! it said.

use iced_connection::{Action, Close, Connected, Retry, Start, State};

#[test]
fn dialling_answers_with_ready_through_the_mailbox() {
    let mut app = Connected::default();
    app.set_now(7);

    app.send(Action::Start(Start));

    // One send: GO to Connecting emits Dial, Dial answers Ready, and the
    // driver applies that follow-up rather than the handler recursing.
    assert!(matches!(app.state(), State::Live(_)));
    assert_eq!(app.describe().0, "Live");
    assert_eq!(app.describe().1, "Connected at 7.");
    assert_eq!(app.ctx().log, ["dialling"]);
}

#[test]
fn a_button_pressed_at_the_wrong_moment_is_a_decision() {
    let mut app = Connected::default();

    // Retry in Idle: IGNORE, decided in the table rather than by a disabled
    // button in `view`.
    app.send(Action::Retry(Retry));
    assert!(matches!(app.state(), State::Idle(_)));
    assert!(app.ctx().log.is_empty());
}

#[test]
fn dropping_a_live_connection_hangs_up() {
    let mut app = Connected::default();
    app.set_now(3);
    app.send(Action::Start(Start));

    app.send(Action::Close(Close));

    assert!(matches!(app.state(), State::Idle(_)));
    assert_eq!(app.ctx().log, ["dialling", "hung up"]);
}
