//! The [`transition_matrix!`] macro.
//!
//! `macro_rules!` is part of the language, so there is no proc-macro crate, no
//! `syn`, no `quote`, and no build-graph cost. This is why Rust leads: it is
//! the only one of the three languages where the ideal syntax is free.
//!
//! # A language-forced divergence
//!
//! `macro_rules!` **cannot concatenate identifiers**. There is no stable
//! `concat_idents!`, so the macro cannot synthesize a member named
//! `idle_start` from the state `Idle` and the action `Start`.
//!
//! Rust therefore expresses the cell surface as *trait bounds* rather than
//! named members:
//!
//! ```ignore
//! impl Handle<Timer, Idle, Start> for MyTimer { /* ... */ }
//! ```
//!
//! A missing cell surfaces as `the trait bound `MyTimer: Handle<Timer, Idle,
//! Start>` is not satisfied`, which names the exact hole. The guarantee is
//! identical; the spelling is not. Kotlin and Swift keep named members, since
//! KSP and SwiftSyntax *can* build identifiers.
//!
//! This is worth knowing before reading the Kotlin implementation, and it is
//! the reason `spec/conformance` compares *behaviour* rather than generated
//! source.
//!
//! # The doubled guarantee
//!
//! Two independent mechanisms stack:
//!
//! 1. A missing `HANDLE` implementation is an unsatisfied trait bound.
//! 2. The generated dispatcher has **no wildcard arm**, so a missing *row* is
//!    caught by `rustc`'s own exhaustiveness checker.
//!
//! The second is free and more trustworthy than anything we could write.

/// Declare a state machine as a transition matrix.
///
/// # Syntax
///
/// ```
/// use tabula::transition_matrix;
///
/// pub struct Ctx { pub limit: u32 }
///
/// transition_matrix! {
///     machine Timer;
///     context Ctx;
///     state   State;
///     action  Action;
///     effects Effect { StartClock, StopClock { reason: u32 } }
///     initial Idle;
///
///     states  { Idle, Running { since: u32 }, Done }
///     actions { Start, Tick { now: u32 }, Cancel }
///
///     //            Start                              Tick     Cancel
///     Idle    => [  HANDLE,                            IGNORE,  IGNORE                          ];
///     Running => [  IGNORE,                            HANDLE,  GO!(Idle, StopClock { reason: 0 }) ];
///     Done    => [  GO!(Running { since: 0 }, StartClock), IGNORE, IGNORE                       ];
/// }
/// ```
///
/// # Effects are generated too
///
/// `effects` declares a sum type exactly as `states` and `actions` do, and for
/// the same reason: the generator can only produce one required member per
/// variant if it knows the variants. That yields a **total effect handler** —
/// add an effect and every handler stops compiling — which no other library in
/// this space offers, and which costs nothing once effects are generated.
///
/// `effects Fx { }` with no variants yields an uninhabited enum: a machine
/// that emits nothing, with cells doing IO directly. A fully supported mode,
/// not a degraded one.
///
/// # Reserved names
///
/// The macro emits `State`, `Action`, `Marker`, `Cells`, `Handlers`, `step`,
/// `perform`, and `TABLE` into the invoking module, plus one struct per state,
/// action, and effect variant.
/// Put each machine in its own module: the narrowed structs (`Idle`, `Start`)
/// would otherwise collide between machines, and `Cells` is a trait here, not
/// a name you can reuse.
///
/// # What it generates
///
/// - One narrowed struct per state and action variant (`Idle`, `Running`,
///   `Start`, `Tick`, ...), so cell implementations receive concrete,
///   already-destructured arguments.
/// - The `State` and `Action` enums, each variant newtyping its narrowed
///   struct, plus `From` impls.
/// - A machine marker type (`Timer`) implementing [`Machine`](crate::Machine).
/// - `step(...)`, whose `where` clause lists one
///   [`Handle`](crate::Handle) bound per `HANDLE` cell.
/// - `Handlers`, one [`Perform`](crate::Perform) bound per effect variant, and
///   `perform(...)` dispatching to them.
/// - `TABLE`, the matrix as inert data.
///
/// # Cell kinds
///
/// | Cell | Generates a member? | Meaning |
/// |---|---|---|
/// | `IGNORE` | no | action not applicable in this state |
/// | `GO!(target)` / `GO!(target, eff, ...)` | no | unconditional transition |
/// | `EMIT!(eff, ...)` | no | stay, emitting effects |
/// | `HANDLE` | **yes** | developer writes the body |
/// | `DELEGATE!(child_module)` | **yes** | run the child machine and fold the result back |
/// | `UNREACHABLE` | no | asserted impossible; compiles to a trap |
///
/// `EMIT!()` with no effects is rejected (`tabula::empty-emit`). It would mean
/// "handled, no transition, nothing emitted", which is `IGNORE` if the action
/// does not apply here and `HANDLE` if it does — and accepting it would make
/// those two indistinguishable in the table.
///
/// # Large machines need a raised recursion limit
///
/// The muncher recurses roughly once per cell, and rustc's default macro
/// recursion limit is 128. A realistic 8x12 machine (96 cells) exceeds it:
///
/// ```text
/// error: recursion limit reached while expanding `$crate::__tabula_arms!`
///   help: consider increasing the recursion limit by adding a
///   `#![recursion_limit = "256"]` attribute to your crate
/// ```
///
/// Add that attribute. Runs of `IGNORE` are consumed several at a time, which
/// is what keeps most machines under the default, but past roughly 7x10 the
/// attribute is needed. See `tests/scale.rs` for the measurement.
///
/// # `GO!` targets are statically constructible
///
/// The generated dispatcher binds its parameters under `__tabula_`-prefixed
/// names, so `ctx`, `state`, `action`, and `cells` are simply **not in scope**
/// inside a `GO!` expression. Rule R3 is enforced by construction rather than
/// by a lint: a target that needs runtime data will not compile, and the error
/// says the name cannot be found.
#[macro_export]
macro_rules! transition_matrix {
    // ---------------------------------------------------------------- entry
    (
        machine $m:ident;
        context $x:ident;
        state   $s:ident;
        action  $a:ident;
        effects $e:ident { $($ev:ident $({ $($eff:ident : $efft:ty),* $(,)? })? ),* $(,)? }
        initial $i:ident;

        states  { $($sv:ident $({ $($sf:ident : $sft:ty),* $(,)? })? ),* $(,)? }
        actions { $($av:ident $({ $($af:ident : $aft:ty),* $(,)? })? ),* $(,)? }

        $($row:ident => [ $($cell:tt)* ];)*
    ) => {
        // -- narrowed variant types --------------------------------------
        //
        // The piece that is impractical to write by hand at scale, and the
        // strongest argument for generating the dispatcher rather than
        // hand-writing a `match`.
        $( $crate::__tabula_struct!($sv $({ $($sf : $sft),* })?); )*
        $( $crate::__tabula_struct!($av $({ $($af : $aft),* })?); )*
        $( $crate::__tabula_struct!($ev $({ $($eff : $efft),* })?); )*

        // Emitted here, not in the terminal muncher rule: by the time the
        // rows have been walked, `$sv` is a bare ident list and the payload
        // field names are gone. Metadata has to be captured where it is bound.
        $crate::__tabula_payloads!(@go acc=[] rest=[$($sv $({ $($sf : $sft),* })?),*]);

        // -- the sum types, newtyping their narrowed structs -------------
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub enum $s { $( $sv($sv) ),* }

        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub enum $a { $( $av($av) ),* }

        /// This machine's effects.
        ///
        /// Declaring `effects Fx { }` with no variants yields an uninhabited
        /// enum: a machine that cannot emit anything, and cells that do IO
        /// directly. That is a fully supported mode, not a degraded one.
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub enum $e { $( $ev($ev) ),* }

        $( impl ::core::convert::From<$sv> for $s {
            fn from(v: $sv) -> Self { $s::$sv(v) }
        } )*
        $( impl ::core::convert::From<$av> for $a {
            fn from(v: $av) -> Self { $a::$av(v) }
        } )*
        $( impl ::core::convert::From<$ev> for $e {
            fn from(v: $ev) -> Self { $e::$ev(v) }
        } )*

        // -- machine marker ----------------------------------------------
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct $m;

        impl $crate::Machine for $m {
            type State = $s;
            type Action = $a;
            type Effect = $e;
            type Ctx = $x;
        }

        /// This machine's entire effect surface, as one bound.
        ///
        /// One `Perform` bound per effect variant. **Add a variant and every
        /// handler stops compiling** — the same required-member mechanism the
        /// transition side uses, applied to the other half of the machine.
        ///
        /// Unlike the cell surface, this needs no muncher: effect variants are
        /// a flat list, with no row/column zip to flatten.
        pub trait Handlers:
            $( $crate::Perform<$m, $ev> + )* ::core::marker::Sized
        {
        }

        impl<T> Handlers for T where
            T: $( $crate::Perform<$m, $ev> + )* ::core::marker::Sized
        {
        }

        /// Carry out one effect, returning any follow-up action.
        ///
        /// Pair with [`tabula::Driver`](crate::Driver), which enqueues the
        /// follow-up rather than recursing into `step`.
        #[allow(unused_variables, unreachable_code)]
        pub fn perform<H: Handlers>(
            __tabula_handlers: &mut H,
            __tabula_ctx: &mut $x,
            __tabula_effect: $e,
        ) -> ::core::option::Option<$a> {
            match __tabula_effect {
                $(
                    $e::$ev(__tabula_ev) => <H as $crate::Perform<$m, $ev>>::perform(
                        __tabula_handlers, __tabula_ctx, __tabula_ev,
                    ),
                )*
            }
        }

        // Check row count against state count *structurally*, before anything
        // is type-checked. A missing row otherwise surfaces as an array-length
        // mismatch on `TABLE`, and a `const` assertion would never run because
        // type errors abort first. Only a `compile_error!` emitted during
        // expansion gets to speak first.
        //
        // Passes through to `@bounds`, which collects one `Handle` bound per
        // HANDLE cell and then emits `step` and `TABLE`. Bounds are the only
        // thing needing accumulation across rows; arms and table rows are
        // generated per row in place.
        $crate::transition_matrix!(@check_rows
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*]
            actions=[$($av)*]
            rows_all=[$($row => [$($cell)*];)*]
            acc=[]
            rows=[$($row => [$($cell)*];)*]
            check_states=[$($sv)*]
            check_rows=[$($row)*]
        );
    };

    // ------------------------------------------------ row-count check
    (@check_rows
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[] check_rows=[]
    ) => {
        $crate::transition_matrix!(@bounds
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*]
            rows_all=[$($ra)*] acc=[$($acc)*] rows=[$($rw)*]
        );
    };

    (@check_rows
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[$cs:ident $($csr:ident)*] check_rows=[$cr:ident $($crr:ident)*]
    ) => {
        $crate::transition_matrix!(@check_rows
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*]
            rows_all=[$($ra)*] acc=[$($acc)*] rows=[$($rw)*]
            check_states=[$($csr)*] check_rows=[$($crr)*]
        );
    };

    (@check_rows
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[$cs:ident $($csr:ident)*] check_rows=[]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::missing-row: state `", ::core::stringify!($cs),
            "` has no row. Every state needs exactly one row, in declaration order. States: ",
            $(::core::stringify!($sv), " ",)*
        ));
    };

    (@check_rows
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[] check_rows=[$cr:ident $($crr:ident)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::extra-row: row `", ::core::stringify!($cr),
            "` does not correspond to a declared state. States: ",
            $(::core::stringify!($sv), " ",)*
        ));
    };

    // ------------------------------------------------- bound accumulation
    (@bounds
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*]
        actions=[$($av:ident)*]
        rows_all=[$($rs:ident => [$($rc:tt)*];)*]
        acc=[$($acc:tt)*]
        rows=[]
    ) => {
        /// This machine's marker type, under a fixed name.
        ///
        /// A parent delegating to this machine writes `DELEGATE!(module)` and
        /// the generator needs the marker's type without knowing what the
        /// child called it. `macro_rules!` cannot build an identifier, so the
        /// alias is the way to reach it by path.
        pub type Marker = $m;

        /// This machine's entire cell surface, as one bound.
        ///
        /// The point of bundling is composition: a parent's `DELEGATE` cell
        /// adds `child::Cells` to its own bounds, so a hole anywhere in the
        /// child breaks the *parent's* build. That is the composition
        /// property, and it costs one blanket impl.
        ///
        /// `step` keeps the expanded `where` clause rather than using this,
        /// because rustc then names the specific missing `Handle` rather than
        /// reporting `Cells` unsatisfied.
        pub trait Cells: $($acc)* ::core::marker::Sized {}

        impl<T> Cells for T where T: $($acc)* ::core::marker::Sized {}

        /// Dispatch one `(state, action)` pair.
        ///
        /// The `where` clause below is the cell surface: one bound per
        /// `HANDLE` cell. Omit an implementation and this call site fails
        /// with `the trait bound ... is not satisfied`, naming the hole.
        ///
        /// Note also the absence of a wildcard arm: a missing row is caught
        /// by `rustc`'s exhaustiveness checker, independently of us.
        pub fn step<C>(
            __tabula_cells: &mut C,
            __tabula_ctx: &mut $x,
            __tabula_state: $s,
            __tabula_action: $a,
        ) -> $crate::Step<$s, $e>
        where
            C: $($acc)* ::core::marker::Sized,
        {
            // Rows are walked by a muncher rather than by a repetition:
            // `$($av)*` and `$($rc)*` are at different nesting depths, and
            // macro_rules cannot iterate two independent repetitions in
            // lockstep. Munching flattens them to depth zero.
            //
            // The binding names are threaded as `ident` arguments rather than
            // written literally in the helper macros. macro_rules is hygienic:
            // an identifier minted inside `__tabula_arms!` is a *different*
            // identifier from one minted here, even spelled the same. Passing
            // them preserves their syntax context.
            $crate::__tabula_arms!(@rows
                s=$s a=$a m=$m et=$e
                bind=[__tabula_state __tabula_action __tabula_cells __tabula_ctx __tabula_s]
                actions=[$($av)*]
                rows=[$($rs => [$($rc)*];)*]
                acc=[]
            )
        }

        /// State payload fields, as `(state, field, type)`.
        ///
        /// A separate const rather than a field on `TABLE`: the table is the
        /// matrix, and this is metadata about the states. Keeping them apart
        /// also means adding it broke no existing `Table` literal.
        ///
        /// Feeds `tabula::payload-hoist`, which asks whether a field repeated
        /// across states is really context in disguise. See rule R4.
        /// The matrix as inert data. Diagram export, coverage reporting, and
        /// reachability analysis are pure functions of this.
        pub const TABLE: $crate::Table<
            { $crate::__tabula_count!($($sv)*) },
            { $crate::__tabula_count!($($av)*) },
        > = $crate::Table {
            machine: ::core::stringify!($m),
            states: [$(::core::stringify!($sv)),*],
            actions: [$(::core::stringify!($av)),*],
            initial: ::core::option::Option::Some(::core::stringify!($i)),
            cells: [$( $crate::__tabula_cells!(@go cells=[$($rc)*] acc=[]) ),*],
        };
    };

    (@bounds
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*]
        actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*]
        rows=[$rs:ident => [$($rc:tt)*]; $($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*]
            actions=[$($av)*]
            rows_all=[$($ra)*]
            acc=[$($acc)*]
            st=$rs
            cur_actions=[$($av)*]
            cur_cells=[$($rc)*]
            rows=[$($rest)*]
        );
    };

    // row exhausted, both lists empty -> next row
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident cur_actions=[] cur_cells=[]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bounds
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] rows=[$($rest)*]
        );
    };

    // ---- arity diagnostics (tabula::row-arity) ----
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$missing:ident $($mrest:ident)*] cur_cells=[]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::row-arity: row `", ::core::stringify!($st),
            "` has too few cells; missing a cell for action `",
            ::core::stringify!($missing),
            "`. Expected columns: ",
            $(::core::stringify!($av), " ",)*
        ));
    };

    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[] cur_cells=[$extra:tt $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::row-arity: row `", ::core::stringify!($st),
            "` has too many cells; unexpected `", ::core::stringify!($extra),
            "`. Expected columns: ",
            $(::core::stringify!($av), " ",)*
        ));
    };

    // ---- cell separator ----
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$($ca:ident)*] cur_cells=[, $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($ca)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ---- HANDLE: the only cell kind that contributes a bound ----
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[HANDLE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)* $crate::Handle<$m, $st, $ca> +] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ---- DELEGATE: contributes the delegate bound AND the child's whole
    // cell surface. This is what makes a total child compose into a total
    // parent, checked by the compiler rather than asserted in a doc.
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*]
        cur_cells=[DELEGATE ! ($ch:ident) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*
                $crate::Delegate<$m, $st, $ca, $ch::Marker> +
                $crate::Lens<$m, $st, $ch::Marker> +
                $ch::Cells +
            ] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ---- static cells: consume a column, contribute nothing ----
    // A run of four IGNOREs in one step.
    //
    // Not premature: an 8x12 order machine is 78% IGNORE and blew the default
    // `recursion_limit` of 128, because the muncher recursed once per cell.
    // Consuming runs cuts the depth on a realistic machine by roughly four.
    // The design's central claim -- that IGNORE dominates real matrices -- is
    // what makes this the right place to optimise.
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$c1:ident $c2:ident $c3:ident $c4:ident $($carest:ident)*]
        cur_cells=[IGNORE, IGNORE, IGNORE, IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ...and two, for rows where a GO or HANDLE breaks the run.
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$c1:ident $c2:ident $($carest:ident)*]
        cur_cells=[IGNORE, IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[UNREACHABLE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[GO ! ($($g:tt)*) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ---- EMIT!() with no effects (tabula::empty-emit) ----
    //
    // Must precede the general EMIT arm below: `$($g:tt)*` matches zero
    // tokens, so it would otherwise swallow this and the cell would expand to
    // `Step::stay()` with an empty effect list.
    //
    // That is what it did until now, which is why Kotlin and Swift rejected
    // `EMIT()` and Rust quietly accepted it -- a divergence the conformance
    // suite structurally cannot catch, since no fixture would ever write a
    // cell the spec forbids.
    //
    // `$(,)?` rather than a bare `()`, so `EMIT!(,)` is caught too. It parses
    // as an empty effect list for the same reason and means the same thing.
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[EMIT ! ($(,)?) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::empty-emit: cell (", ::core::stringify!($st), ", ",
            ::core::stringify!($ca),
            ") uses EMIT with no effects. Use IGNORE if the action is not \
             applicable in this state, or HANDLE if it is handled deliberately."
        ));
    };

    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[EMIT ! ($($g:tt)*) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    // ---- unknown cell kind (tabula::unknown-cell) ----
    (@bound_row
        m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[$bad:tt $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabula::unknown-cell: `", ::core::stringify!($bad),
            "` in row `", ::core::stringify!($st), "`, column `",
            ::core::stringify!($ca),
            "`. Expected one of: IGNORE, HANDLE, UNREACHABLE, GO!(..), EMIT!(..), DELEGATE!(..)."
        ));
    };
}

/// Emits a narrowed variant struct. Two rules, because
/// `pub struct Foo { .. };` with a trailing semicolon is not valid Rust and
/// `$({ .. })?` cannot conditionally drop one.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_struct {
    ($n:ident) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct $n;
    };
    ($n:ident { $($f:ident : $t:ty),* $(,)? }) => {
        // Deliberately no `Default`: deriving it would impose `Default` on
        // every payload type for no benefit, and a state whose payload is a
        // child machine's state (composition) rarely has one.
        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        pub struct $n { $(pub $f: $t),* }
    };
}

/// Counts tokens in a const context.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_count {
    ($($x:tt)*) => { <[()]>::len(&[$($crate::__tabula_unit!($x)),*]) };
}

#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_unit {
    ($x:tt) => {
        ()
    };
}

/// Builds the outer `match state { .. }`, in expression position.
///
/// This exists because `macro_rules!` cannot iterate two repetitions of
/// different nesting depth in lockstep. The action list is at depth 0 and each
/// row's cell list is at depth 2, so the rows are munched one at a time; each
/// invocation then has both at depth 0 and can hand them to
/// [`__tabula_row!`](crate::__tabula_row).
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_arms {
    (@rows s=$s:ident a=$a:ident m=$m:ident et=$et:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($av:ident)*] rows=[] acc=[$($acc:tt)*]
    ) => {
        // No wildcard arm: a missing row is caught by rustc's own
        // exhaustiveness checker, independently of this macro.
        match $bs { $($acc)* }
    };

    (@rows s=$s:ident a=$a:ident m=$m:ident et=$et:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($av:ident)*]
        rows=[$rs:ident => [$($rc:tt)*]; $($rest:tt)*]
        acc=[$($acc:tt)*]
    ) => {
        $crate::__tabula_arms!(@rows s=$s a=$a m=$m et=$et
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($av)*]
            rows=[$($rest)*]
            acc=[$($acc)*
                $s::$rs($bsv) => $crate::__tabula_row!(@go
                    m=$m s=$s a=$a et=$et st=$rs
                    bind=[$bs $ba $bc $bx $bsv]
                    actions=[$($av)*]
                    cells=[$($rc)*]
                    arms=[]
                ),
            ]
        )
    };
}

/// Builds one row's inner `match action { .. }`, in expression position.
///
/// Because this is generated per row, no accumulator has to be threaded
/// across rows -- only the `Handle` bounds need that.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_row {
    // done
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[] cells=[] arms=[$($arm:tt)*]
    ) => {
        match $ba { $($arm)* }
    };

    // separator
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($ca:ident)*] cells=[, $($crest:tt)*] arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($ca)*] cells=[$($crest)*] arms=[$($arm)*])
    };

    // IGNORE, four at a time. See the note in `transition_matrix!`.
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$c1:ident $c2:ident $c3:ident $c4:ident $($carest:ident)*]
        cells=[IGNORE, IGNORE, IGNORE, IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)*
                $a::$c1(_) => $crate::Step::ignored(),
                $a::$c2(_) => $crate::Step::ignored(),
                $a::$c3(_) => $crate::Step::ignored(),
                $a::$c4(_) => $crate::Step::ignored(),
            ])
    };

    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$c1:ident $c2:ident $($carest:ident)*]
        cells=[IGNORE, IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)*
                $a::$c1(_) => $crate::Step::ignored(),
                $a::$c2(_) => $crate::Step::ignored(),
            ])
    };

    // IGNORE
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => $crate::Step::ignored(),])
    };

    // HANDLE -- dispatches into developer code with narrowed arguments
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[HANDLE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(__tabula_a) => {
                <C as $crate::Handle<$m, $st, $ca>>::handle($bc, $bx, $bsv, __tabula_a)
            },])
    };

    // UNREACHABLE
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[UNREACHABLE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => ::core::unreachable!(::core::concat!(
                "tabula: ", ::core::stringify!($st), " x ", ::core::stringify!($ca),
                " was declared UNREACHABLE but occurred"
            )),])
    };

    // GO!(target) / GO!(target, effects..)
    //
    // The dispatcher's bindings are `__tabula_`-prefixed, so `ctx`, `state`,
    // `action`, and `cells` are not in scope here. Rule R3 is enforced by
    // construction: a target needing runtime data fails to resolve.
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[GO ! ($t:expr $(, $ef:expr)* $(,)?) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => {
                let __tabula_step = $crate::Step::go(<$s as ::core::convert::From<_>>::from($t));
                $( let __tabula_step = __tabula_step.emit(
                    <$et as ::core::convert::From<_>>::from($ef),
                ); )*
                __tabula_step
            },])
    };

    // DELEGATE!(child_module)
    //
    // Runs the child's `step` and folds the result back through the lens.
    //
    // No `.await`: the macro has no prototype colors yet, so every `step` is
    // uncolored and one-way color flow holds only vacuously. When colors land,
    // this call is where the child's color must meet the parent's. See PLAN,
    // September 2026 audit.
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[DELEGATE ! ($ch:ident) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(__tabula_a) => {
                let __child_action = <C as $crate::Delegate<$m, $st, $ca, $ch::Marker>>::to_child(
                    $bc, $bx, &$bsv, __tabula_a,
                );
                match __child_action {
                    // The child's alphabet does not contain this action.
                    // `Ignored`, not `Stay`: nothing was handled.
                    ::core::option::Option::None => $crate::Step::ignored(),
                    ::core::option::Option::Some(__ca) => {
                        // The lens is per (parent state, child); only the
                        // action prism above is per cell.
                        let __cs =
                            <C as $crate::Lens<$m, $st, $ch::Marker>>::child_state($bc, &$bsv);
                        let __cx =
                            <C as $crate::Lens<$m, $st, $ch::Marker>>::child_ctx($bc, $bx);
                        let __cstep = $ch::step($bc, __cx, __cs, __ca);
                        let mut __out = match __cstep.outcome {
                            $crate::Outcome::Go(__next) => $crate::Step::go(
                                <C as $crate::Lens<$m, $st, $ch::Marker>>::embed($bc, $bsv, __next),
                            ),
                            $crate::Outcome::Stay => $crate::Step::stay(),
                            $crate::Outcome::Ignored => $crate::Step::ignored(),
                        };
                        for __ef in __cstep.effects {
                            __out = __out.emit(
                                <C as $crate::Lens<$m, $st, $ch::Marker>>::lift($bc, __ef),
                            );
                        }
                        __out
                    }
                }
            },])
    };

    // EMIT!(effects..)
    (@go m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[EMIT ! ($($ef:expr),* $(,)?) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => {
                let __tabula_step = $crate::Step::stay();
                $( let __tabula_step = __tabula_step.emit(
                    <$et as ::core::convert::From<_>>::from($ef),
                ); )*
                __tabula_step
            },])
    };
}

/// Builds one row of the `TABLE` const.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_cells {
    (@go cells=[] acc=[$($c:tt)*]) => { [$($c)*] };

    (@go cells=[, $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)*])
    };

    (@go cells=[IGNORE, IGNORE, IGNORE, IGNORE $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)*
            $crate::Cell::Ignore, $crate::Cell::Ignore,
            $crate::Cell::Ignore, $crate::Cell::Ignore,
        ])
    };

    (@go cells=[IGNORE, IGNORE $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*]
            acc=[$($c)* $crate::Cell::Ignore, $crate::Cell::Ignore,])
    };

    (@go cells=[IGNORE $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Ignore,])
    };

    (@go cells=[HANDLE $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Handle,])
    };

    (@go cells=[UNREACHABLE $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Unreachable,])
    };

    (@go cells=[DELEGATE ! ($ch:ident) $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Delegate {
            child: ::core::stringify!($ch),
        },])
    };

    (@go cells=[GO ! ($t:expr $(, $ef:expr)* $(,)?) $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Go {
            target: $crate::__tabula_target_name!($t),
            effects: &[$($crate::table::first_ident(::core::stringify!($ef))),*],
        },])
    };

    (@go cells=[EMIT ! ($($ef:expr),* $(,)?) $($r:tt)*] acc=[$($c:tt)*]) => {
        $crate::__tabula_cells!(@go cells=[$($r)*] acc=[$($c)* $crate::Cell::Emit {
            // Normalised like GO targets: `StopClock { reason: 0 }` appears as
            // `StopClock`, so grids and diagrams stay readable.
            effects: &[$($crate::table::first_ident(::core::stringify!($ef))),*],
        },])
    };
}

/// Emits the `PAYLOADS` const, one state at a time.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_payloads {
    (@go acc=[$($acc:tt)*] rest=[]) => {
        /// State payload fields, as `(state, field, type)`.
        ///
        /// A separate const rather than a field on `TABLE`: the table is the
        /// matrix, and this is metadata about the states. Keeping them apart
        /// also means adding it broke no existing `Table` literal.
        ///
        /// Feeds `tabula::payload-hoist`, which asks whether a field repeated
        /// across states is really context in disguise. See rule R4.
        pub const PAYLOADS: &$crate::table::Payloads = &[$($acc)*];
    };

    (@go acc=[$($acc:tt)*] rest=[, $($r:tt)*]) => {
        $crate::__tabula_payloads!(@go acc=[$($acc)*] rest=[$($r)*]);
    };

    (@go acc=[$($acc:tt)*] rest=[$sv:ident {$($sf:ident : $sft:ty),* $(,)?} $($r:tt)*]) => {
        $crate::__tabula_payloads!(@go
            acc=[$($acc)* $((
                ::core::stringify!($sv),
                ::core::stringify!($sf),
                ::core::stringify!($sft),
            ),)*]
            rest=[$($r)*]
        );
    };

    (@go acc=[$($acc:tt)*] rest=[$sv:ident $($r:tt)*]) => {
        $crate::__tabula_payloads!(@go acc=[$($acc)*] rest=[$($r)*]);
    };
}

/// Renders a `GO!` target expression as the bare variant name.
///
/// `GO!(Running { since: 0 })` should appear in the table as `Running`, not as
/// the whole struct literal, so diagrams and grids stay readable.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_target_name {
    ($t:expr) => {
        $crate::table::first_ident(::core::stringify!($t))
    };
}
