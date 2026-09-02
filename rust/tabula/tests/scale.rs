// A 96-cell machine exceeds rustc's default macro recursion limit. The
// muncher recurses roughly once per cell, and 128 is the default.
//
// Consuming runs of IGNORE brought a realistic 8x12 machine from ~192 down to
// ~160; the remaining depth is irreducible without abandoning the muncher, and
// rustc's own error names the fix:
//
//   help: consider increasing the recursion limit by adding a
//   `#![recursion_limit = "256"]` attribute to your crate
//
// Recorded in ARCHITECTURE section 14 rather than engineered around. A macro
// that needs a crate attribute past a certain size is a real cost; hiding it
// behind more muncher tricks would trade a one-line fix for unreadable macro
// rules.
#![recursion_limit = "256"]

//! **A genuine 8x12 machine, to retire a risk the plan has been carrying.**
//!
//! `PLAN.md` lists "N x M cell count makes real machines unpleasant" with the
//! mitigation "measure on a genuine 8x12 machine before M4". This is that
//! measurement, and it is deliberately a machine someone might really write —
//! an order lifecycle — rather than a synthetic grid.
//!
//! Findings are asserted below rather than described, so they cannot rot.

use tabula::{transition_matrix, Handle, Perform, Step};

#[derive(Debug, Default)]
pub struct Ctx {
    pub items: u32,
    pub attempts: u32,
}

transition_matrix! {
    machine Order;
    context Ctx;
    state   State;
    action  Action;
    effects Effect {
        RequestPayment, ReleaseHold, NotifyExpired, ChargeCard,
        NotifyFailure, SchedulePickup, NotifyShipped, IssueRefund, NotifyDelivered
    }
    initial Draft;

    states {
        Draft, AwaitingPayment, PaymentFailed { code: u32 }, Paid,
        Preparing, Shipped { tracking: u64 }, Delivered, Cancelled
    }
    actions {
        AddItem, RemoveItem, Submit, PaidOk, PaidFail { code: u32 }, Retry,
        Cancel, Prepare, Ship { tracking: u64 }, Deliver, Refund, Expire
    }

    //                    AddItem  RemoveItem  Submit                                  PaidOk                     PaidFail  Retry   Cancel                          Prepare                       Ship                                   Deliver                                    Refund  Expire
    Draft           => [  HANDLE,  HANDLE,     GO!(AwaitingPayment, RequestPayment),   IGNORE,                    IGNORE,   IGNORE, GO!(Cancelled),                 IGNORE,                       IGNORE,                                IGNORE,                                    IGNORE, GO!(Cancelled, NotifyExpired) ];
    AwaitingPayment => [  IGNORE,  IGNORE,     IGNORE,                                 GO!(Paid, ChargeCard),     HANDLE,   IGNORE, GO!(Cancelled, ReleaseHold),    IGNORE,                       IGNORE,                                IGNORE,                                    IGNORE, GO!(Cancelled, ReleaseHold)   ];
    PaymentFailed   => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   HANDLE, GO!(Cancelled, ReleaseHold),    IGNORE,                       IGNORE,                                IGNORE,                                    IGNORE, GO!(Cancelled, ReleaseHold)   ];
    Paid            => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   IGNORE, GO!(Cancelled, IssueRefund),    GO!(Preparing, SchedulePickup), IGNORE,                               IGNORE,                                    GO!(Cancelled, IssueRefund), IGNORE ];
    Preparing       => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   IGNORE, HANDLE,                         IGNORE,                       HANDLE,                                IGNORE,                                    HANDLE, IGNORE ];
    Shipped         => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   IGNORE, IGNORE,                         IGNORE,                       IGNORE,                                GO!(Delivered, NotifyDelivered),           HANDLE, IGNORE ];
    Delivered       => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   IGNORE, IGNORE,                         IGNORE,                       IGNORE,                                IGNORE,                                    HANDLE, IGNORE ];
    Cancelled       => [  IGNORE,  IGNORE,     IGNORE,                                 IGNORE,                    IGNORE,   IGNORE, IGNORE,                         IGNORE,                       IGNORE,                                IGNORE,                                    IGNORE, IGNORE ];
}

// ---------------------------------------------------------------------------
// The measurement
// ---------------------------------------------------------------------------

#[test]
fn ninety_six_cells_cost_nine_implementations() {
    let c = TABLE.coverage();
    assert_eq!(c.total(), 96, "8 states x 12 actions");

    // The number that matters. 96 cells, but only the HANDLE ones become
    // members: the static kinds are resolved by the generator and cost one
    // word each in the declaration.
    assert_eq!(c.required_members(), 9);
    assert_eq!(c.handle, 9);
    assert_eq!(c.go, 12);
    assert_eq!(c.ignore, 75);

    // 78% of a realistic machine is IGNORE. That is the load-bearing fact
    // behind the whole design: if those 75 cells each needed a body, nobody
    // would write this. They need one word.
    assert_eq!(c.ignore_percent(), 78);
}

#[cfg(feature = "alloc")]
#[test]
fn a_realistic_machine_trips_the_ignore_heavy_lint() {
    // An honest finding, not a bug. At 78% IGNORE this machine crosses the 70%
    // threshold, and the lint is arguably right: the shipping half (Paid ->
    // Preparing -> Shipped -> Delivered) shares almost no alphabet with the
    // checkout half, and would be a cleaner pair of composed machines.
    //
    // Recorded rather than tuned. Moving the threshold to silence a machine
    // that really is two machines would be fitting the rule to the sample.
    let r = tabula::lint::report(&TABLE);
    assert!(r.contains("tabula::ignore-heavy"), "{r}");
    assert!(r.contains("78%"), "{r}");

    // `Cancelled` is genuinely terminal, and dead-row says so once.
    assert!(r.contains("every cell in row `Cancelled` ignores"), "{r}");
}

#[cfg(feature = "alloc")]
#[test]
fn the_grid_stays_readable_at_this_size() {
    let grid = tabula::export::to_grid(&TABLE);
    let lines: Vec<&str> = grid.lines().collect();
    assert_eq!(lines.len(), 9, "header plus one line per state");

    // Every line the same width means the columns still line up by eye, which
    // is the entire reason for preferring positional rows over named cells.
    let widest = lines.iter().map(|l| l.len()).max().unwrap();
    assert!(widest < 400, "grid line width {widest}");
    assert!(grid.contains("GO(AwaitingPayment, RequestPayment)"));
}

// ---------------------------------------------------------------------------
// The implementation cost, in full. Nine cells and nine effects.
// ---------------------------------------------------------------------------

struct Impl;

macro_rules! cell {
    ($sv:ty, $av:ty, |$s:pat_param, $a:pat_param, $c:pat_param| $body:expr) => {
        impl Handle<Order, $sv, $av> for Impl {
            fn handle(&mut self, $c: &mut Ctx, $s: $sv, $a: $av) -> Step<State, Effect> {
                $body
            }
        }
    };
}

cell!(Draft, AddItem, |_s, _a, c| {
    c.items += 1;
    Step::stay()
});
cell!(Draft, RemoveItem, |_s, _a, c| {
    c.items = c.items.saturating_sub(1);
    Step::stay()
});
cell!(AwaitingPayment, PaidFail, |_s, a, _c| {
    Step::go(State::PaymentFailed(PaymentFailed { code: a.code })).emit(NotifyFailure.into())
});
cell!(PaymentFailed, Retry, |_s, _a, c| {
    c.attempts += 1;
    if c.attempts > 3 {
        Step::go(State::Cancelled(Cancelled)).emit(ReleaseHold.into())
    } else {
        Step::go(State::AwaitingPayment(AwaitingPayment)).emit(RequestPayment.into())
    }
});
cell!(Preparing, Cancel, |_s, _a, _c| Step::go(State::Cancelled(
    Cancelled
))
.emit(IssueRefund.into()));
cell!(Preparing, Ship, |_s, a, _c| Step::go(State::Shipped(
    Shipped {
        tracking: a.tracking
    }
))
.emit(NotifyShipped.into()));
cell!(Preparing, Refund, |_s, _a, _c| Step::go(State::Cancelled(
    Cancelled
))
.emit(IssueRefund.into()));
cell!(Shipped, Refund, |_s, _a, _c| Step::stay()
    .emit(IssueRefund.into()));
cell!(Delivered, Refund, |_s, _a, _c| Step::stay()
    .emit(IssueRefund.into()));

macro_rules! effect {
    ($ev:ty) => {
        impl Perform<Order, $ev> for Impl {
            fn perform(&mut self, _c: &mut Ctx, _e: $ev) -> Option<Action> {
                None
            }
        }
    };
}

effect!(RequestPayment);
effect!(ReleaseHold);
effect!(NotifyExpired);
effect!(ChargeCard);
effect!(NotifyFailure);
effect!(SchedulePickup);
effect!(NotifyShipped);
effect!(IssueRefund);
effect!(NotifyDelivered);

#[test]
fn the_machine_actually_runs() {
    let mut c = Ctx::default();
    let mut m = Impl;

    let s = step(
        &mut m,
        &mut c,
        State::Draft(Draft),
        Action::AddItem(AddItem),
    );
    assert!(!s.is_ignored());
    assert_eq!(c.items, 1);

    let s = step(&mut m, &mut c, State::Draft(Draft), Action::Submit(Submit));
    assert_eq!(
        s.effects.iter().copied().collect::<Vec<_>>(),
        [Effect::RequestPayment(RequestPayment)]
    );

    // Three retries then give up -- the kind of logic a HANDLE cell exists for
    // and a matrix cannot express.
    c.attempts = 3;
    let s = step(
        &mut m,
        &mut c,
        State::PaymentFailed(PaymentFailed { code: 51 }),
        Action::Retry(Retry),
    );
    assert_eq!(s.outcome, tabula::Outcome::Go(State::Cancelled(Cancelled)));
}
