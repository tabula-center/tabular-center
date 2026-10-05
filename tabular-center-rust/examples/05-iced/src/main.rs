//! The window: iced renders what the machines decided.
//!
//! Two machines, nested: a session containing a connection. The window shows
//! both matrices, because both are inert data beside their dispatchers.
//!
//! Note what this file cannot do. It has no transitions and no `match` over a
//! state deciding what happens next -- it sends an action and draws the
//! result. Tap while the connection is dialling does nothing, and that is the
//! prism's decision, recorded in `lib.rs` beside the table, not a disabled
//! button here.

use iced::widget::{button, column, row, text};
use iced::{Element, Font};
use iced_connection::session::{Action, Boot, Finish, Tap};
use iced_connection::App;

#[derive(Debug, Clone, Copy)]
enum Message {
    Boot,
    Tap,
    Finish,
}

fn update(app: &mut App, message: Message) {
    app.send(match message {
        Message::Boot => Action::Boot(Boot),
        Message::Tap => Action::Tap(Tap),
        Message::Finish => Action::Finish(Finish),
    });
}

fn view(app: &App) -> Element<'_, Message> {
    let (status, inner) = app.describe();
    let (session_grid, connection_grid) = app.grids();
    let log = if app.log().is_empty() {
        "(no effects yet)".to_string()
    } else {
        app.log().join("\n")
    };

    let (child_status, child_detail) = inner.unwrap_or_default();

    column![
        text(status).size(28),
        text(child_status).size(20),
        text(child_detail),
        row![
            button("Boot").on_press(Message::Boot),
            button("Tap").on_press(Message::Tap),
            button("Finish").on_press(Message::Finish),
        ]
        .spacing(8),
        text("The session's matrix:").size(16),
        text(session_grid).font(Font::MONOSPACE).size(12),
        text("The connection's, inside it:").size(16),
        text(connection_grid).font(Font::MONOSPACE).size(12),
        text("Effects performed:").size(16),
        text(log).font(Font::MONOSPACE).size(12),
    ]
    .spacing(12)
    .padding(24)
    .into()
}

fn main() -> iced::Result {
    iced::application(App::default, update, view)
      .title("tabular-center :: session")
      .run()
}
