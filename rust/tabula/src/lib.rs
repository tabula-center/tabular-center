//! # tabula
//!
//! State machines whose declaration *is* the transition matrix.
//!
//! ## The one guarantee
//!
//! > Every cell of the state x action matrix is a required member.
//! > **An incomplete machine does not compile.**
//!
//! Note what this is *not* built on. Not pattern-matcher exhaustiveness --
//! that is defeated by `_`, `else`, `default`, and guard clauses. Not function
//! purity -- unenforceable in Kotlin and Swift, so any claim resting on it is
//! broken by a single `println`. It is built on the oldest mechanism in the
//! language: *you declared a required member and did not implement it.*
//!
//! In Rust the guarantee is doubled. [`transition_matrix!`] emits a
//! `match (state, action)` with **no wildcard arm**, so a missing row is caught
//! by `rustc`'s own exhaustiveness checker rather than by our macro. That half
//! is free and more trustworthy than anything we could write.
//!
//! ## Zero dependencies
//!
//! Not "few" -- none. [`transition_matrix!`] is `macro_rules!`, which is part
//! of the language, so there is no proc-macro crate, no `syn`, no `quote`, and
//! no build-graph cost. The core is `no_std` and allocation-free; only the
//! [`export`] module needs `alloc`.
//!
//! ## Escape hatch
//!
//! The macro expands to what a competent human would write. [`Step`],
//! [`Cell`], and the generated trait are all usable directly, and
//! `cargo expand` is a supported auditing path. `tests/reference_timer.rs` is
//! a hand-written machine kept building forever as the macro's specification.

#![cfg_attr(not(feature = "std"), no_std)]
#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod cell;
pub mod machine;
pub mod matrix;
pub mod step;
pub mod table;

#[cfg(feature = "alloc")]
pub mod export;

pub use cell::{Cell, CellKind};
pub use machine::{Handle, Machine};
pub use step::{CapacityError, Effects, Outcome, Step, DEFAULT_EFFECT_CAPACITY};
pub use table::{Coverage, Table};
