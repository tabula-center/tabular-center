# A GUI, with the transitions in a table

The same connection machine as `examples/kotlin/07-compose`, so the two GUI
examples read side by side: same states, same effects, different hosts.

Run it with `cargo run` (from this directory — it is not a member of
`examples/rust`'s workspace; see `Cargo.toml` for why).

## What the window shows

Its own matrix. `TABLE` is inert data the macro generated beside the
dispatcher, so `view` renders the machine it is running:

```
              Start          Ready    Close          Retry
Idle          ->Connecting   .        .              .
Connecting    .              HANDLE   ->Failed       .
Live          .              .        ->Idle         .
Failed        .              .        .              ->Connecting
```

That grid is not a diagram someone drew and has to remember to update. Change
a cell in `src/machine.tb.rs` and the window changes with it, because both the
picture and the dispatch come from the same table.

## The substitution

An iced application is `update` and `view`. The hand-written `update` for this
machine would be the usual nest:

```rust
fn update(state: &mut State, message: Message) {
    match message {
        Message::Start => {
            if let State::Idle = state {          // which states may start?
                *state = State::Connecting;       // and what does it become?
                dial();                           // and what happens then?
            }
        }
        Message::Close => match state {
            State::Live { .. } => { *state = State::Idle; hangup(); }
            State::Connecting => *state = State::Failed,
            _ => {}                               // <- the hole
        },
        // ...
    }
}
```

The `_ => {}` is the hole this library exists to remove: it is where "Retry
while Live" lives, undecided, and it grows every time a state or a message is
added. Here `update` is three lines and decides nothing:

```rust
fn update(app: &mut Connected, message: Message) {
    app.send(match message {
        Message::Start => Action::Start(Start),
        Message::Close => Action::Close(Close),
        Message::Retry => Action::Retry(Retry),
    });
}
```

Every `(state, action)` pair has an answer in `machine.tb.rs`, and the four
cells that say `IGNORE` say so on purpose. A button pressed at the wrong
moment is a decision in the table rather than a disabled button in `view`.

## What drives it

`tabula::Driver`, which is the whole host: an action goes in, the effects of
the resulting step are performed in order, and a follow-up action an effect
returns is **enqueued** rather than applied by reentering `step`. One press of
Start therefore takes Idle to Live — GO emits `Dial`, `Dial` answers `Ready`,
and the mailbox delivers it — and the effect log in the window shows it
happening.

## What is checked

`tests/connection.rs` drives the machine with no toolkit: every transition,
the follow-up arriving through the mailbox, and the text the window shows,
since `describe` is shared between the tests and `view`.

Nothing asserts what is on the screen. `nix flake check` opens no window, and
`rust-gui` says as much when it passes: *the machine checked, the window
compiled, not opened*.
