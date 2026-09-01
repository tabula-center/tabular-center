//! `tabula::payload-hoist`: rule R4, asked as a question.
//!
//! Payload is state-local; anything outliving transitions belongs in Context.
//! A field repeated across states is usually context that got copied into
//! payloads one state at a time — but not always, so this warns and never
//! errors.

use tabula::transition_matrix;

pub struct Ctx;

mod leaky {
    use super::*;

    transition_matrix! {
        machine Conn;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Log }
        initial Connecting;

        states {
            Connecting { retry_count: u32 },
            Backoff { retry_count: u32, until: u64 },
            Reconnecting { retry_count: u32 },
        }
        actions { Fail }

        Connecting   => [ HANDLE ];
        Backoff      => [ HANDLE ];
        Reconnecting => [ HANDLE ];
    }
}

mod tidy {
    use super::*;

    transition_matrix! {
        machine Conn;
        context Ctx;
        state   State;
        action  Action;
        effects Effect { Log }
        initial Idle;

        states { Idle, Working { started: u64 }, Done }
        actions { Go }

        Idle    => [ HANDLE ];
        Working => [ HANDLE ];
        Done    => [ HANDLE ];
    }
}

#[test]
fn the_macro_records_payload_fields() {
    assert_eq!(
        leaky::PAYLOADS,
        &[
            ("Connecting", "retry_count", "u32"),
            ("Backoff", "retry_count", "u32"),
            ("Backoff", "until", "u64"),
            ("Reconnecting", "retry_count", "u32"),
        ]
    );
    // Payload-free states contribute nothing.
    assert_eq!(tidy::PAYLOADS, &[("Working", "started", "u64")]);
}

#[test]
fn a_field_in_three_states_is_flagged() {
    let r = tabula::lint::report_with_payloads(&leaky::TABLE, leaky::PAYLOADS);
    assert!(r.contains("tabula::payload-hoist"), "{r}");
    assert!(
        r.contains(
            "`retry_count: u32` appears in the payloads of Connecting, Backoff, Reconnecting"
        ),
        "{r}"
    );
    // `until` appears once and must stay silent.
    assert!(!r.contains("until"), "{r}");
}

#[test]
fn a_healthy_machine_says_nothing_about_payloads() {
    let r = tabula::lint::report_with_payloads(&tidy::TABLE, tidy::PAYLOADS);
    assert!(!r.contains("payload-hoist"), "{r}");
}
