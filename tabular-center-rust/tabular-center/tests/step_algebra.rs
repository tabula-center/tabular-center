//! The laws of `Step`'s composition operations (spec/cells.md 6), checked by
//! exhaustive enumeration: every step over a small domain -- each outcome,
//! with zero, one and two effects -- against continuations that between them
//! return every outcome. The cases every implementation replays are
//! spec/conformance/step-algebra.cases; these are the laws behind them.

use tabular_center::{EmitError, Outcome, Step};

type St = Step<u8, char, 8>;
type Continuation = Box<dyn Fn(u8) -> St>;

fn build(outcome: Outcome<u8>, effects: &[char]) -> St {
    let mut step = match outcome {
        Outcome::Go(n) => Step::go(n),
        Outcome::Stay => Step::stay(),
        Outcome::Ignored => Step::ignored(),
    };
    for &e in effects {
        step = step.emit(e);
    }
    step
}

fn steps() -> Vec<St> {
    let effect_sets: [&[char]; 3] = [&[], &['a'], &['a', 'b']];
    let mut all = vec![Step::ignored()];
    for effects in effect_sets {
        for n in 0..3 {
            all.push(build(Outcome::Go(n), effects));
        }
        all.push(build(Outcome::Stay, effects));
    }
    all
}

fn continuations() -> Vec<Continuation> {
    vec![
        Box::new(|n| Step::go(n + 1)),
        Box::new(|n| Step::go(n).emit('x')),
        Box::new(|_| Step::stay().emit('y')),
        Box::new(|_| Step::stay()),
        Box::new(|_| Step::ignored()),
        Box::new(|n| {
            if n % 2 == 0 {
                Step::go(n * 2).emit('z').emit('w')
            } else {
                Step::ignored()
            }
        }),
    ]
}

fn effects_of<S>(step: &Step<S, char, 8>) -> Vec<char> {
    step.effects.iter().copied().collect()
}

fn never_called(_: u8) -> St {
    panic!("called on a step with no target")
}

#[test]
fn map_preserves_identity() {
    for m in steps() {
        assert_eq!(m.clone().map(|x| x), m);
    }
}

#[test]
fn map_composes() {
    let f = |x: u8| x + 3;
    let g = |x: u8| x * 2;
    for m in steps() {
        assert_eq!(m.clone().map(f).map(g), m.map(|x| g(f(x))));
    }
}

#[test]
#[allow(deprecated)]
fn map_state_is_map() {
    for m in steps() {
        assert_eq!(m.clone().map_state(|x| x + 1), m.map(|x| x + 1));
    }
}

#[test]
fn and_then_left_identity() {
    for a in 0..3 {
        for f in continuations() {
            assert_eq!(St::go(a).and_then(&*f), f(a));
        }
    }
}

#[test]
fn and_then_right_identity() {
    for m in steps() {
        assert_eq!(m.clone().and_then(Step::go), m);
    }
}

#[test]
fn and_then_is_associative() {
    let fs = continuations();
    for m in steps() {
        for f in &fs {
            for g in &fs {
                let left = m.clone().and_then(&**f).and_then(&**g);
                let right = m.clone().and_then(|x| f(x).and_then(&**g));
                assert_eq!(left, right);
            }
        }
    }
}

#[test]
fn and_then_short_circuits_without_calling_the_continuation() {
    for m in steps() {
        if m.is_transition() {
            continue;
        }
        let after = m.clone().and_then(never_called);
        assert_eq!(after, m);
    }
}

#[test]
fn ignored_absorbs_and_emits_nothing() {
    let emitted = St::go(1).emit('a').emit('b');
    let step: St = emitted.and_then(|_| Step::ignored());
    assert!(step.is_ignored());
    assert!(step.effects.is_empty());
}

#[test]
fn zip_with_is_and_then_over_map() {
    let h = |x: u8, y: u8| x * 10 + y;
    for m in steps() {
        for n in steps() {
            let zipped = m.clone().zip_with(n.clone(), h);
            let derived = m.clone().and_then(|x| n.clone().map(|y| h(x, y)));
            assert_eq!(zipped, derived);
        }
    }
}

#[test]
fn zip_pairs_targets_and_concatenates_effects() {
    let step = St::go(1).emit('a').zip(St::go(2).emit('b'));
    assert_eq!(step.outcome, Outcome::Go((1, 2)));
    assert_eq!(effects_of(&step), ['a', 'b']);
}

#[test]
fn zip_drops_the_right_effects_when_the_left_does_not_move() {
    let step = St::stay().emit('a').zip(St::go(2).emit('b'));
    assert_eq!(step.outcome, Outcome::Stay);
    assert_eq!(effects_of(&step), ['a']);
}

#[test]
#[should_panic(expected = "an ignored step emits nothing")]
fn emit_on_ignored_panics() {
    let _ = St::ignored().emit('a');
}

#[test]
fn try_emit_on_ignored_hands_the_effect_back() {
    let mut step = St::ignored();
    match step.try_emit('a') {
        Err(EmitError::Ignored(e)) => assert_eq!(e, 'a'),
        other => panic!("expected EmitError::Ignored, got {other:?}"),
    }
    assert!(step.effects.is_empty());
}

#[test]
#[should_panic(expected = "effect capacity 2 exceeded")]
fn and_then_past_capacity_panics() {
    let step: Step<u8, char, 2> = Step::go(0).emit('a').emit('b');
    let _ = step.and_then(|n| Step::go(n).emit('c'));
}

#[test]
fn try_and_then_past_capacity_returns_the_rejected_effect() {
    let step: Step<u8, char, 2> = Step::go(0).emit('a').emit('b');
    match step.try_and_then(|n| Step::go(n).emit('c')) {
        Err(e) => {
            assert_eq!(e.rejected, 'c');
            assert_eq!(e.capacity, 2);
        }
        Ok(_) => panic!("three effects fit in a capacity of two"),
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Door {
    Open,
    Ajar,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Signal {
    Chime,
    Buzz,
}

fn enter(door: Door) -> Step<Door, Signal> {
    match door {
        Door::Open => Step::go(Door::Open).emit(Signal::Chime),
        other => Step::go(other),
    }
}

fn unlock(code_ok: bool) -> Step<Door, Signal> {
    let decided = if code_ok {
        Step::go(Door::Open)
    } else {
        Step::stay().emit(Signal::Buzz)
    };
    decided.and_then(enter)
}

fn open_both(left_ok: bool, right_ok: bool) -> Step<(Door, Door), Signal> {
    unlock(left_ok).zip(unlock(right_ok))
}

#[test]
fn composing_a_cell() {
    let opened = unlock(true);
    assert_eq!(opened.outcome, Outcome::Go(Door::Open));
    assert!(opened.effects.iter().eq([Signal::Chime].iter()));
    let refused = unlock(false);
    assert_eq!(refused.outcome, Outcome::Stay);
    assert!(refused.effects.iter().eq([Signal::Buzz].iter()));
    let both = open_both(true, true);
    assert_eq!(both.outcome, Outcome::Go((Door::Open, Door::Open)));
    assert_eq!(both.effects.len(), 2);
    let half = open_both(false, true);
    assert!(half.effects.iter().eq([Signal::Buzz].iter()));
    let _ = Door::Ajar;
}
