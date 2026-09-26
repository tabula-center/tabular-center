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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Cell {
    /// No-op. The action is not applicable in this state.
    Ignore,

    /// Unconditional transition. The target must be statically constructible:
    /// payload-free, or built from literals. See ARCHITECTURE.md rule R3.
    Go {
        /// Target state variant.
        target: &'static str,
        /// Effects emitted on the way.
        effects: &'static [&'static str],
    },

    /// Remain in the current state, emitting the listed effects.
    Emit {
        /// Effects emitted.
        effects: &'static [&'static str],
    },

    /// Generates a required member; the developer writes the body.
    ///
    /// Carries no member name: Rust names cells by trait bound rather than by
    /// identifier (see [`crate::machine`]), and the row/column position
    /// already identifies the cell in every language.
    Handle,

    /// Forward to a composed child machine.
    ///
    /// Written out explicitly, one cell at a time: a parent never inherits
    /// coverage wholesale from a child. See ARCHITECTURE.md section 8.
    Delegate {
        /// Child machine name.
        child: &'static str,
    },

    /// The developer asserts this pair cannot occur. Compiles to a trap.
    ///
    /// A load-bearing declaration, not a shortcut: it says *if this fires, the
    /// surrounding system has a bug.* It generates no member -- writing
    /// `UNREACHABLE` *is* the developer's statement of intent -- but the
    /// coverage report counts them, because a machine with many usually has a
    /// modelling error.
    Unreachable,
}

/// Discriminant of a [`Cell`], for counting and reporting.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CellKind {
    /// See [`Cell::Ignore`].
    Ignore,
    /// See [`Cell::Go`].
    Go,
    /// See [`Cell::Emit`].
    Emit,
    /// See [`Cell::Handle`].
    Handle,
    /// See [`Cell::Delegate`].
    Delegate,
    /// See [`Cell::Unreachable`].
    Unreachable,
}

impl CellKind {
    /// Lowercase name, as used in diagnostics and the conformance format.
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
    /// This cell's kind.
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

    /// Whether the generator resolves this cell entirely, with no developer
    /// code involved.
    pub const fn is_static(&self) -> bool {
        matches!(self, Cell::Ignore | Cell::Go { .. } | Cell::Emit { .. })
    }

    /// Whether this cell contributes a required member to the cell surface.
    ///
    /// This is the predicate the guarantee rests on: sum it over the matrix and
    /// you have the number of things the developer must implement.
    pub const fn generates_member(&self) -> bool {
        matches!(self, Cell::Handle | Cell::Delegate { .. })
    }

    /// The target state variant, if this cell transitions unconditionally.
    ///
    /// `Handle` and `Delegate` cells may also transition, but not knowably at
    /// build time, so they report `None` and diagram export marks them
    /// dynamic.
    pub const fn static_target(&self) -> Option<&'static str> {
        match self {
            Cell::Go { target, .. } => Some(target),
            _ => None,
        }
    }

    /// Effects this cell emits unconditionally.
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
        // It traps rather than calling into user code, so there is nothing for
        // the developer to implement -- writing UNREACHABLE *is* the
        // implementation. It still counts in the coverage report.
        assert!(!Cell::Unreachable.is_static());
        assert!(!Cell::Unreachable.generates_member());
    }
}
