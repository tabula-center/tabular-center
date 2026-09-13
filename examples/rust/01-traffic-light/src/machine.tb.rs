//! The matrix, in a file of its own.
//!
//! `spec/matrix-files.md`: the cells are column-aligned and that alignment is
//! what a reader scans. On stable, `#[rustfmt::skip]` is the exemption —
//! `ignore` in `rustfmt.toml` is nightly-only and prints a warning per file
//! while formatting everything anyway.
//!
//! Rust is the awkward one of the three. `machine.tb.rs` is not a valid module
//! name, so `lib.rs` reaches it with `#[path]`; and because
//! `transition_matrix!` generates the state and action types, they are defined
//! *here* and re-exported there. Splitting a matrix out of Rust moves types,
//! not just text — which is why this was left until last.

use tabula::transition_matrix;

use crate::Ctx;

#[rustfmt::skip]
transition_matrix! {
    machine TrafficLight;
    context Ctx;
    state   State;
    action  Action;
    // An uninhabited enum: this machine emits nothing, and its cells do
    // whatever they need to do directly. A supported mode, not a degraded one.
    effects Effect { }
    initial Red;

    states  { Red, Green, Amber }
    actions { Advance, Fault }

    //           Advance        Fault
    Red    => [  GO!(Green),    GO!(Red)   ];
    Green  => [  GO!(Amber),    GO!(Red)   ];
    Amber  => [  HANDLE,        GO!(Red)   ];
}
