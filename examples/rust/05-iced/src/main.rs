//! The window: iced renders what the machine decided.
//!
//! Note what this file cannot do. It has no transitions and no `match` over
//! the state deciding what happens next -- it sends an action and draws the
//! result. A button pressed at the wrong moment is not a bug to defend
//! against here, because the table already has an answer for that pair,
//! usually IGNORE.

use iced::widget::{button, column, row, text};
use iced::{Element, Font};
use iced_connection::{Action, Close, Connected, Retry, Start};

/// What the GUI sends. One variant per button, mapped to the machine's own
/// actions: the toolkit's message type and the machine's alphabet are
/// separate vocabularies, and this is where they meet.
#[derive(Debug, Clone, Copy)]
enum Message {
    Start,
    Close,
    Retry,
}

fn update(app: &mut Connected, message: Message) {
    app.send(match message {
        Message::Start => Action::Start(Start),
        Message::Close => Action::Close(Close),
        Message::Retry => Action::Retry(Retry),
    });
}

fn view(app: &Connected) -> Element<'_, Message> {
    let (status, detail) = app.describe();
    let log = if app.log().is_empty() {
        "(no effects yet)".to_string()
    } else {
        app.log().join("\n")
    };

    column![
        text(status).size(28),
        text(detail),
        row![
            button("Start").on_press(Message::Start),
            button("Close").on_press(Message::Close),
            button("Retry").on_press(Message::Retry),
        ]
        .spacing(8),
        // The machine on screen, rendered from the same `TABLE` the
        // dispatcher uses. Not a diagram someone drew and has to keep
        // current: if a cell changes, this changes with it.
        text("The matrix this window is running:").size(16),
        text(app.grid()).font(Font::MONOSPACE).size(12),
        text("Effects performed:").size(16),
        text(log).font(Font::MONOSPACE).size(12),
    ]
    .spacing(12)
    .padding(24)
    .into()
}

fn main() -> iced::Result {
    iced::run("tabula :: connection", update, view)
}
