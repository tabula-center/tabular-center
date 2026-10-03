//! Dispatch cost: the matrix against hand-written dispatch.
//!
//! PLAN.md's claim is "identical after monomorphization". This measures it
//! with three versions of one machine -- the Timer, three states by three
//! actions, exercising `HANDLE`, `GO!` and `IGNORE` cells:
//!
//! - `matrix`: `tests/timer_matrix.rs`, declared with `transition_matrix!`.
//! - `reference`: `tests/reference_timer.rs`, the dispatcher written out by
//!   hand in exactly the shape the macro expands to.
//! - `plain`: below, what someone writes with no library at all -- one
//!   `match`, no traits, no `Step`, returning `(State, Option<Effect>)`.
//!
//! The first two are included from the test files rather than copied, so the
//! machines timed here are the machines the test suite checks. Before timing,
//! all three are run over the same actions and must visit the same states;
//! a benchmark of three machines that disagree would measure nothing.
//!
//! Timing is not a check: it varies with the machine running it, so nothing
//! in `nix flake check` runs this. `cargo clippy --all-targets` compiles it,
//! which keeps it building. Run it with `nix run .#bench`, or
//! `cargo bench --bench dispatch` from `tabular-center-rust/`.

use std::hint::black_box;
use std::time::Instant;

#[allow(dead_code, unused_imports)]
#[path = "../tests/timer_matrix.rs"]
mod matrix;

#[allow(dead_code, unused_imports)]
#[path = "../tests/reference_timer.rs"]
mod reference;

/// The Timer with no library: what the other two are measured against.
mod plain {
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum State {
        Idle,
        Running(u32),
        Done,
    }

    #[derive(Clone, Copy, Debug)]
    pub enum Action {
        Start,
        Tick(u32),
        Cancel,
    }

    // The payload is built, to do the same work as the other two versions,
    // and never read: only whether an effect was emitted is counted.
    #[allow(dead_code)]
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    pub enum Effect {
        StartClock,
        StopClock(u32),
    }

    pub struct Ctx {
        pub limit: u32,
        pub ticks_seen: u32,
    }

    /// The same cells as `tests/timer_matrix.rs`, including the handler
    /// bodies, so the only difference being timed is how dispatch is written.
    pub fn step(ctx: &mut Ctx, state: State, action: Action) -> (State, Option<Effect>) {
        match (state, action) {
            (State::Idle, Action::Start) => (State::Running(0), Some(Effect::StartClock)),
            (State::Idle, Action::Tick(_) | Action::Cancel) => (state, None),
            (State::Running(_), Action::Start) => (state, None),
            (State::Running(since), Action::Tick(now)) => {
                ctx.ticks_seen += 1;
                if now.saturating_sub(since) >= ctx.limit {
                    (State::Done, Some(Effect::StopClock(1)))
                } else {
                    (state, None)
                }
            }
            (State::Running(_), Action::Cancel) => (State::Idle, Some(Effect::StopClock(0))),
            (State::Done, Action::Start) => (State::Running(0), Some(Effect::StartClock)),
            (State::Done, Action::Tick(_) | Action::Cancel) => (state, None),
        }
    }
}

/// Timer limit for every version: three quiet ticks, then one that finishes.
const LIMIT: u32 = 5;

/// One cycle through the machine: every kind of cell, back to `Idle`.
///
/// Idle -Start-> Running(0) -Tick 1-> stay -Tick 2-> stay -Tick 9-> Done
/// -Start-> Running(0) -Cancel-> Idle -Tick 3-> ignored.
const CYCLE: [(u8, u32); 7] = [(0, 0), (1, 1), (1, 2), (1, 9), (0, 0), (2, 0), (1, 3)];

/// States as a common code, so three different `State` types can be compared.
const IDLE: u8 = 0;
const RUNNING: u8 = 1;
const DONE: u8 = 2;

fn matrix_action(kind: u8, now: u32) -> matrix::Action {
    match kind {
        0 => matrix::Action::Start(matrix::Start),
        1 => matrix::Action::Tick(matrix::Tick { now }),
        _ => matrix::Action::Cancel(matrix::Cancel),
    }
}

fn reference_action(kind: u8, now: u32) -> reference::Action {
    match kind {
        0 => reference::Action::Start,
        1 => reference::Action::Tick { now },
        _ => reference::Action::Cancel,
    }
}

fn plain_action(kind: u8, now: u32) -> plain::Action {
    match kind {
        0 => plain::Action::Start,
        1 => plain::Action::Tick(now),
        _ => plain::Action::Cancel,
    }
}

fn matrix_code(s: &matrix::State) -> u8 {
    match s {
        matrix::State::Idle(_) => IDLE,
        matrix::State::Running(_) => RUNNING,
        matrix::State::Done(_) => DONE,
    }
}

fn reference_code(s: &reference::State) -> u8 {
    match s {
        reference::State::Idle => IDLE,
        reference::State::Running(_) => RUNNING,
        reference::State::Done => DONE,
    }
}

fn plain_code(s: &plain::State) -> u8 {
    match s {
        plain::State::Idle => IDLE,
        plain::State::Running(_) => RUNNING,
        plain::State::Done => DONE,
    }
}

/// Runs `cycles` cycles; returns the states visited on the first cycle and a
/// count of effects emitted, which every version must consume so none of
/// them can have its work optimized away.
type Run = fn(u32) -> (Vec<u8>, usize);

fn run_matrix(cycles: u32) -> (Vec<u8>, usize) {
    let mut cells = matrix::TimerImpl;
    let mut ctx = matrix::Ctx {
        limit: LIMIT,
        ticks_seen: 0,
    };
    let mut state = matrix::State::Idle(matrix::Idle);
    let mut visited = Vec::new();
    let mut effects = 0;
    for cycle in 0..cycles {
        for &(kind, now) in black_box(&CYCLE) {
            let s = matrix::step(&mut cells, &mut ctx, state, matrix_action(kind, now));
            effects += s.effects.len();
            if let tabular_center::Outcome::Go(next) = s.outcome {
                state = next;
            }
            if cycle == 0 {
                visited.push(matrix_code(&state));
            }
        }
    }
    (visited, black_box(effects))
}

fn run_reference(cycles: u32) -> (Vec<u8>, usize) {
    let mut cells = reference::TimerImpl;
    let mut ctx = reference::Ctx {
        limit: LIMIT,
        ..Default::default()
    };
    let mut state = reference::State::Idle;
    let mut visited = Vec::new();
    let mut effects = 0;
    for cycle in 0..cycles {
        for &(kind, now) in black_box(&CYCLE) {
            let s = reference::step(&mut cells, &mut ctx, state, reference_action(kind, now));
            effects += s.effects.len();
            if let tabular_center::Outcome::Go(next) = s.outcome {
                state = next;
            }
            if cycle == 0 {
                visited.push(reference_code(&state));
            }
        }
    }
    (visited, black_box(effects))
}

fn run_plain(cycles: u32) -> (Vec<u8>, usize) {
    let mut ctx = plain::Ctx {
        limit: LIMIT,
        ticks_seen: 0,
    };
    let mut state = plain::State::Idle;
    let mut visited = Vec::new();
    let mut effects = 0;
    for cycle in 0..cycles {
        for &(kind, now) in black_box(&CYCLE) {
            let (next, effect) = plain::step(&mut ctx, state, plain_action(kind, now));
            effects += usize::from(effect.is_some());
            state = next;
            if cycle == 0 {
                visited.push(plain_code(&state));
            }
        }
    }
    (visited, black_box(effects))
}

/// Cycles per timed round, and rounds per version.
const CYCLES: u32 = 200_000;
const ROUNDS: usize = 21;

fn main() {
    // Parity first. The three must visit the same states and emit the same
    // number of effects, or the numbers below compare different machines.
    let expected = [RUNNING, RUNNING, RUNNING, DONE, RUNNING, IDLE, IDLE];
    let runs: [(&str, Run); 3] = [
        ("matrix", run_matrix),
        ("reference", run_reference),
        ("plain", run_plain),
    ];
    for (name, run) in runs {
        let (visited, effects) = run(1);
        assert_eq!(visited, expected, "{name} visited different states");
        assert_eq!(effects, 4, "{name} emitted a different number of effects");
    }

    // Rounds interleaved across versions, so drift in the machine's speed
    // during the run lands on all three rather than on whichever went last.
    let mut samples: Vec<Vec<f64>> = vec![Vec::new(); runs.len()];
    for _ in 0..ROUNDS {
        for (i, (_, run)) in runs.iter().enumerate() {
            let start = Instant::now();
            // The runner's own `black_box` on its effect count is what keeps
            // the work from being optimized away; the result itself is spare.
            let _ = run(black_box(CYCLES));
            let steps = f64::from(CYCLES) * CYCLE.len() as f64;
            samples[i].push(start.elapsed().as_nanos() as f64 / steps);
        }
    }

    println!("dispatch cost, ns per step ({ROUNDS} rounds of {CYCLES} cycles)");
    println!();
    println!("  version         min   median");
    for ((name, _), times) in runs.iter().zip(samples.iter_mut()) {
        times.sort_by(|a, b| a.total_cmp(b));
        let median = times[times.len() / 2];
        println!("  {name:<10} {:>8.2} {median:>8.2}", times[0]);
    }
    println!();
    println!("`matrix` and `reference` should be indistinguishable: the claim is that");
    println!("they are the same code after monomorphization, which timing cannot");
    println!("settle. `plain` is expected to be faster: it returns");
    println!("`(State, Option<Effect>)` where the");
    println!("other two return a `Step` with an inline effects array. Read the");
    println!("minimums: they are the least disturbed by everything else on the machine.");
}
