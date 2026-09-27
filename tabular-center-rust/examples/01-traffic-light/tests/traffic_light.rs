use tabular_center::Outcome;
use traffic_light::*;

#[test]
fn a_full_cycle() {
    let mut ctx = Ctx { cycles: 0 };
    let mut c = Controller;
    let mut state = State::Red(Red);

    for _ in 0..2 {
        for _ in 0..3 {
            let s = step(&mut c, &mut ctx, state, Action::Advance(Advance));
            state = s.outcome.target().expect("every cell here transitions");
        }
    }
    assert_eq!(state, State::Red(Red));
    assert_eq!(ctx.cycles, 2);
}

#[test]
fn a_fault_from_anywhere_goes_red() {
    let mut ctx = Ctx { cycles: 0 };
    let mut c = Controller;
    for from in [State::Red(Red), State::Green(Green), State::Amber(Amber)] {
        let s = step(&mut c, &mut ctx, from, Action::Fault(Fault));
        assert_eq!(s.outcome, Outcome::Go(State::Red(Red)));
    }
}

#[test]
fn six_cells_cost_one_implementation() {
    let cov = TABLE.coverage();
    assert_eq!(cov.total(), 6);
    assert_eq!(cov.go, 5);
    assert_eq!(cov.required_members(), 1);
}

#[test]
fn a_machine_with_no_effects_emits_nothing() {
    let mut ctx = Ctx { cycles: 0 };
    let s = step(
        &mut Controller,
        &mut ctx,
        State::Red(Red),
        Action::Advance(Advance),
    );
    assert!(s.effects.is_empty());
}
