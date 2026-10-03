//! The matrix as inert data.
//!
//! Every generated machine emits a `TABLE` const alongside its dispatcher.
//! Because the table exists as data, diagram export, coverage reporting, and
//! reachability analysis are pure functions of it rather than features that
//! have to be built separately.
//!
//! Cells hold `&'static str` rather than owned strings so `TABLE` can be a
//! genuine `const` and live in ROM under `no_std`.

/// One entry in the transition matrix.
///
/// Six kinds, split three and three. The *static* kinds ([`Cell::Ignore`],
/// [`Cell::Go`], [`Cell::Emit`]) are resolved entirely by the generator and
/// produce no required member. This is what makes a large matrix survivable:
/// the boring 60-70% of cells that just mean "not applicable here" cost one
/// word each.
///
/// The remaining kinds each generate a required member, which is where the
/// library's guarantee comes from.
///
/// - `Ignore`: No-op.
/// - `Go`: Unconditional transition.
/// - `Go.target`: Target state variant.
/// - `Go.effects`: Effects emitted on the way.
/// - `Emit`: Remain in the current state, emitting the listed effects.
/// - `Emit.effects`: Effects emitted.
/// - `Handle`: Generates a required member; the developer writes the body.
/// - `Delegate`: Forward to a composed child machine.
/// - `Delegate.child`: Child machine name.
/// - `Unreachable`: The developer asserts this pair cannot occur.
/// - `kind`: This cell's kind.
/// - `is_static`: Whether the generator resolves this cell entirely, with no developer code involved.
/// - `generates_member`: Whether this cell contributes a required member to the cell surface.
/// - `static_target`: The target state variant, if this cell transitions unconditionally.
/// - `static_effects`: Effects this cell emits unconditionally.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Cell {
    Ignore,

    Go {
        target: &'static str,
        effects: &'static [&'static str],
    },

    Emit {
        effects: &'static [&'static str],
    },

    Handle,

    Delegate {
        child: &'static str,
    },

    Unreachable,
}

/// Discriminant of a [`Cell`], for counting and reporting.
///
/// - `as_str`: Lowercase name, as used in diagnostics and the conformance format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CellKind {
    Ignore,
    Go,
    Emit,
    Handle,
    Delegate,
    Unreachable,
}

impl CellKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            CellKind::Ignore => "ignore",
            CellKind::Go => "go",
            CellKind::Emit => "emit",
            CellKind::Handle => "handle",
            CellKind::Delegate => "delegate",
            CellKind::Unreachable => "unreachable",
        }
    }
}

impl Cell {
    pub const fn kind(&self) -> CellKind {
        match self {
            Cell::Ignore => CellKind::Ignore,
            Cell::Go { .. } => CellKind::Go,
            Cell::Emit { .. } => CellKind::Emit,
            Cell::Handle => CellKind::Handle,
            Cell::Delegate { .. } => CellKind::Delegate,
            Cell::Unreachable => CellKind::Unreachable,
        }
    }

    pub const fn is_static(&self) -> bool {
        matches!(self, Cell::Ignore | Cell::Go { .. } | Cell::Emit { .. })
    }

    pub const fn generates_member(&self) -> bool {
        matches!(self, Cell::Handle | Cell::Delegate { .. })
    }

    pub const fn static_target(&self) -> Option<&'static str> {
        match self {
            Cell::Go { target, .. } => Some(target),
            _ => None,
        }
    }

    pub const fn static_effects(&self) -> &'static [&'static str] {
        match self {
            Cell::Go { effects, .. } | Cell::Emit { effects } => effects,
            _ => &[],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn static_kinds_generate_no_members() {
        for c in [
            Cell::Ignore,
            Cell::Go {
                target: "Idle",
                effects: &[],
            },
            Cell::Emit { effects: &["Tick"] },
        ] {
            assert!(c.is_static(), "{c:?}");
            assert!(!c.generates_member(), "{c:?}");
        }
    }

    #[test]
    fn dynamic_kinds_generate_members() {
        for c in [Cell::Handle, Cell::Delegate { child: "Retry" }] {
            assert!(!c.is_static(), "{c:?}");
            assert!(c.generates_member(), "{c:?}");
        }
    }

    #[test]
    fn unreachable_is_neither_static_nor_a_member() {
        assert!(!Cell::Unreachable.is_static());
        assert!(!Cell::Unreachable.generates_member());
    }
}
