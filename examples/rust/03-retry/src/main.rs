//! Watch the driver run.
//!
//! The only example with a binary, and the reason is that a driver is a loop:
//! its interesting behaviour is the *order* things happen in, and an assertion
//! on a final state shows none of that. `cargo run -p retry` prints the
//! sequence `tests/retry.rs` asserts on, so a reader can see the follow-up
//! action arriving through the mailbox rather than take it on faith.
//!
//! It calls the same `run` the tests call. An example binary that reached for
//! the driver directly would be a second, untested copy of the thing being
//! demonstrated.

use retry::{run, State};

fn main() {
    for max_attempts in [1, 3] {
        let (state, ctx) = run(max_attempts);
        println!("max_attempts = {max_attempts}");
        for (i, done) in ctx.performed.iter().enumerate() {
            println!("  {i}. {done}");
        }
        println!("  ended in {state:?}");
        println!();
    }
    assert!(matches!(run(1).0, State::Exhausted(_)));
}
