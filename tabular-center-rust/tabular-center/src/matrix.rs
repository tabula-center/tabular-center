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
/// use tabular_center::transition_matrix;
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
/// `EMIT!()` with no effects is rejected (`tabular-center::empty-emit`). It would mean
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
    (
        machine $m:ident;
        context $x:ident;
        prototype fn handle;
        $($rest:tt)*
    ) => {
        $crate::transition_matrix!(@main c=Plain machine $m; context $x; $($rest)*);
    };
    (
        machine $m:ident;
        context $x:ident;
        prototype async fn handle;
        $($rest:tt)*
    ) => {
        $crate::transition_matrix!(@main c=Async machine $m; context $x; $($rest)*);
    };
    (
        machine $m:ident;
        context $x:ident;
        prototype $($rest:tt)*
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::unsupported-color: machine `",
            ::core::stringify!($m),
            "` has a prototype Rust cannot color. Write `prototype fn handle;` or ",
            "`prototype async fn handle;` -- `async` is the only color a Rust trait ",
            "method can carry on stable."
        ));
    };
    (machine $($rest:tt)*) => {
        $crate::transition_matrix!(@main c=Plain machine $($rest)*);
    };

    (@main c=$c:tt
        machine $m:ident;
        context $x:ident;
        state   $s:ident;
        action  $a:ident;
        effects $e:ident { $($ev:ident $({ $($eff:ident : $efft:ty),* $(,)? })? ),* $(,)? }
        initial $i:ident;

        states  { $($sv:ident $({ $($sf:ident : $sft:ty),* $(,)? })? ),* $(,)? }
        actions { $($av:ident $({ $($af:ident : $aft:ty),* $(,)? })? ),* $(,)? }

        paths { $($pn:ident : [ $($pe:ident),* $(,)? ] $(back $pb:ident)? ;)+ }

        $($row:ident => [ $($cell:tt)* ];)*
    ) => {
        $crate::__tabula_define_known! { ($) states=[$($sv)*] actions=[$($av)*] }

        #[allow(non_camel_case_types, dead_code)]
        mod __tabula_path_names {
            $( pub struct $pn; )+
        }

        $crate::transition_matrix!(@hops c=$c
            hdr=[
                machine $m;
                context $x;
                state   $s;
                action  $a;
                effects $e { $($ev $({ $($eff : $efft),* })?),* }
                initial $i;
                states  { $($sv $({ $($sf : $sft),* })?),* }
                actions { $($av $({ $($af : $aft),* })?),* }
            ]
            acts=[$($av)*]
            rows=[$($row => [ $($cell)* ];)*]
            acc=[]
            lasts=[]
            backs=[]
            paths=[$( ($pn start [$($pe),*] b=[$($pb)?]) )+]
        );
    };

    (@hops c=$c:tt hdr=$hdr:tt acts=$acts:tt rows=$rows:tt acc=[$($acc:tt)*] lasts=$lasts:tt
        backs=$backs:tt
        paths=[ ($pn:ident $step:ident [$st:ident, $ac:ident, $nx:ident $(, $more:ident)*] b=[])
            $($ps:tt)* ]
    ) => {
        __tabula_known_state!($pn $st);
        __tabula_known_action!($pn $ac);
        $crate::transition_matrix!(@hops c=$c hdr=$hdr acts=$acts rows=$rows
            acc=[$($acc)* ($pn $st $ac $nx)] lasts=$lasts backs=$backs
            paths=[ ($pn mid [$nx $(, $more)*] b=[]) $($ps)* ]);
    };
    (@hops c=$c:tt hdr=$hdr:tt acts=$acts:tt rows=$rows:tt acc=[$($acc:tt)*] lasts=$lasts:tt
        backs=[$($backs:tt)*]
        paths=[ ($pn:ident $step:ident [$st:ident, $ac:ident, $nx:ident $(, $more:ident)*]
            b=[$pb:ident]) $($ps:tt)* ]
    ) => {
        __tabula_known_state!($pn $st);
        __tabula_known_action!($pn $ac);
        __tabula_known_action!($pn $pb);
        $crate::transition_matrix!(@hops c=$c hdr=$hdr acts=$acts rows=$rows
            acc=[$($acc)* ($pn $st $ac $nx)] lasts=$lasts
            backs=[$($backs)* ($nx $pb $st)]
            paths=[ ($pn mid [$nx $(, $more)*] b=[$pb]) $($ps)* ]);
    };
    (@hops c=$c:tt hdr=$hdr:tt acts=$acts:tt rows=$rows:tt acc=$acc:tt lasts=[$($lasts:tt)*]
        backs=$backs:tt paths=[ ($pn:ident mid [$last:ident] b=$b:tt) $($ps:tt)* ]
    ) => {
        __tabula_known_state!($pn $last);
        $crate::transition_matrix!(@hops c=$c hdr=$hdr acts=$acts rows=$rows acc=$acc
            lasts=[$($lasts)* ($pn $last)] backs=$backs paths=[$($ps)*]);
    };
    (@hops c=$c:tt hdr=$hdr:tt acts=$acts:tt rows=$rows:tt acc=$acc:tt lasts=$lasts:tt
        backs=$backs:tt paths=[ ($pn:ident $step:ident [$($bad:ident),*] b=$b:tt) $($ps:tt)* ]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::path-broken: path `",
            ::core::stringify!($pn),
            "` does not alternate state and action from a state to a state; a path's ",
            "element count is odd and at least three"
        ));
        $crate::transition_matrix!(@hops c=$c hdr=$hdr acts=$acts rows=$rows acc=$acc
            lasts=$lasts backs=$backs paths=[$($ps)*]);
    };
    (@hops c=$c:tt hdr=$hdr:tt acts=$acts:tt rows=$rows:tt acc=[$($acc:tt)*] lasts=[$($lasts:tt)*]
        backs=[$($backs:tt)*] paths=[]
    ) => {
        $crate::__tabula_define_hops! { ($) hops=[$($acc)*] backs=[$($backs)*] lasts=[$($lasts)*] }
        $crate::__tabula_narrow! { c=$c hdr=$hdr hops=[$($acc)*] }
        $crate::transition_matrix!(@derive c=$c hdr=$hdr acts=$acts done=[] todo=$rows);
    };

    (@derive c=$c:tt hdr=[$($h:tt)*] acts=$acts:tt done=[$($done:tt)*] todo=[]) => {
        $crate::transition_matrix!(@main c=$c $($h)* $($done)*);
    };
    (@derive c=$c:tt hdr=$hdr:tt acts=$acts:tt done=$done:tt
        todo=[$row:ident => [ $($cells:tt)* ]; $($todo:tt)*]
    ) => {
        $crate::transition_matrix!(@cells c=$c hdr=$hdr acts=$acts done=$done
            todo=[$($todo)*] row=$row left=$acts out=[] in=[$($cells)*]);
    };

    (@cells c=$c:tt hdr=$hdr:tt acts=$acts:tt done=$done:tt todo=$todo:tt
        row=$row:ident left=[$act:ident $($more:ident)*] out=$out:tt
        in=[$k:ident $(! $g:tt)? $(, $($in:tt)*)?]
    ) => {
        __tabula_hop!(
            [@celled c=$c hdr=$hdr acts=$acts done=$done todo=$todo
                row=$row left=[$($more)*] out=$out in=[$($($in)*)?]]
            ; $row $act $k $(! $g)?
        );
    };
    (@celled c=$c:tt hdr=$hdr:tt acts=$acts:tt done=$done:tt todo=$todo:tt
        row=$row:ident left=$left:tt out=[$($out:tt)*] in=$in:tt cell=[$($cell:tt)*]
    ) => {
        $crate::transition_matrix!(@cells c=$c hdr=$hdr acts=$acts done=$done todo=$todo
            row=$row left=$left out=[$($out)* ($($cell)*)] in=$in);
    };
    (@cells c=$c:tt hdr=$hdr:tt acts=$acts:tt done=[$($done:tt)*] todo=$todo:tt
        row=$row:ident left=$left:tt out=[$( ($($o:tt)*) )*] in=[]
    ) => {
        $crate::transition_matrix!(@derive c=$c hdr=$hdr acts=$acts
            done=[$($done)* $row => [ $($($o)*),* ];] todo=$todo);
    };
    (@cells c=$c:tt hdr=$hdr:tt acts=$acts:tt done=[$($done:tt)*] todo=$todo:tt
        row=$row:ident left=$left:tt out=[$( ($($o:tt)*) )*] in=[$($in:tt)+]
    ) => {
        $crate::transition_matrix!(@derive c=$c hdr=$hdr acts=$acts
            done=[$($done)* $row => [ $($($o)*),* , $($in)+ ];] todo=$todo);
    };

    (@main c=$c:tt
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
        $( $crate::__tabula_struct!($sv $({ $($sf : $sft),* })?); )*
        $( $crate::__tabula_struct!($av $({ $($af : $aft),* })?); )*
        $( $crate::__tabula_struct!($ev $({ $($eff : $efft),* })?); )*

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

        $crate::__tabula_effects!($c; m=$m x=$x a=$a e=$e evs=[$($ev)*]);

        $crate::transition_matrix!(@check_rows
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*]
            actions=[$($av)*]
            rows_all=[$($row => [$($cell)*];)*]
            acc=[]
            rows=[$($row => [$($cell)*];)*]
            check_states=[$($sv)*]
            check_rows=[$($row)*]
        );
    };

    (@check_rows
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[] check_rows=[]
    ) => {
        $crate::transition_matrix!(@bounds
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*]
            rows_all=[$($ra)*] acc=[$($acc)*] rows=[$($rw)*]
        );
    };

    (@check_rows
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[$cs:ident $($csr:ident)*] check_rows=[$cr:ident $($crr:ident)*]
    ) => {
        $crate::transition_matrix!(@check_rows
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*]
            rows_all=[$($ra)*] acc=[$($acc)*] rows=[$($rw)*]
            check_states=[$($csr)*] check_rows=[$($crr)*]
        );
    };

    (@check_rows
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[$cs:ident $($csr:ident)*] check_rows=[]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::missing-row: state `", ::core::stringify!($cs),
            "` has no row. Every state needs exactly one row, in declaration order. States: ",
            $(::core::stringify!($sv), " ",)*
        ));
    };

    (@check_rows
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*] acc=[$($acc:tt)*] rows=[$($rw:tt)*]
        check_states=[] check_rows=[$cr:ident $($crr:ident)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::extra-row: row `", ::core::stringify!($cr),
            "` does not correspond to a declared state. States: ",
            $(::core::stringify!($sv), " ",)*
        ));
    };

    (@bounds
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
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

        $crate::__tabula_colored_fn! { $c;
        pub fn step<C>(
            __tabula_cells: &mut C,
            __tabula_ctx: &mut $x,
            __tabula_state: $s,
            __tabula_action: $a,
        ) -> $crate::Step<$s, $e>
        where
            C: $($acc)* ::core::marker::Sized,
        {
            $crate::__tabula_arms!(@rows
                s=$s a=$a c=$c m=$m et=$e
                bind=[__tabula_state __tabula_action __tabula_cells __tabula_ctx __tabula_s]
                actions=[$($av)*]
                rows=[$($rs => [$($rc)*];)*]
                acc=[]
            )
        }
        }

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
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*]
        actions=[$($av:ident)*]
        rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*]
        rows=[$rs:ident => [$($rc:tt)*]; $($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
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

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident cur_actions=[] cur_cells=[]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bounds
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$missing:ident $($mrest:ident)*] cur_cells=[]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::row-arity: row `", ::core::stringify!($st),
            "` has too few cells; missing a cell for action `",
            ::core::stringify!($missing),
            "`. Expected columns: ",
            $(::core::stringify!($av), " ",)*
        ));
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[] cur_cells=[$extra:tt $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::row-arity: row `", ::core::stringify!($st),
            "` has too many cells; unexpected `", ::core::stringify!($extra),
            "`. Expected columns: ",
            $(::core::stringify!($av), " ",)*
        ));
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$($ca:ident)*] cur_cells=[, $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($ca)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=Plain m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[HANDLE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=Plain m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)* $crate::Handle<$m, $st, $ca> +] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=Async m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[HANDLE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=Async m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)* $crate::AsyncHandle<$m, $st, $ca> +] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*]
        cur_cells=[DELEGATE ! ($ch:ident) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
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

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$c1:ident $c2:ident $c3:ident $c4:ident $($carest:ident)*]
        cur_cells=[IGNORE, IGNORE, IGNORE, IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$c1:ident $c2:ident $($carest:ident)*]
        cur_cells=[IGNORE, IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[IGNORE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[UNREACHABLE $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[GO ! ($($g:tt)*) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[EMIT ! ($(,)?) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::empty-emit: cell (", ::core::stringify!($st), ", ",
            ::core::stringify!($ca),
            ") uses EMIT with no effects. Use IGNORE if the action is not \
             applicable in this state, or HANDLE if it is handled deliberately."
        ));
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[EMIT ! ($($g:tt)*) $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        $crate::transition_matrix!(@bound_row
            c=$c m=$m s=$s a=$a e=$e x=$x i=$i
            states=[$($sv)*] actions=[$($av)*] rows_all=[$($ra)*]
            acc=[$($acc)*] st=$st
            cur_actions=[$($carest)*] cur_cells=[$($crest)*]
            rows=[$($rest)*]
        );
    };

    (@bound_row
        c=$c:tt m=$m:ident s=$s:ident a=$a:ident e=$e:ident x=$x:ident i=$i:ident
        states=[$($sv:ident)*] actions=[$($av:ident)*] rows_all=[$($ra:tt)*]
        acc=[$($acc:tt)*] st=$st:ident
        cur_actions=[$ca:ident $($carest:ident)*] cur_cells=[$bad:tt $($crest:tt)*]
        rows=[$($rest:tt)*]
    ) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::unknown-cell: `", ::core::stringify!($bad),
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

/// Defines `__tabula_hop!`, the lookup a path compiles to.
///
/// Rules whose tokens are the path's own identifiers, plus a fallback. For a
/// hop `(p S A N)`, the cell at `(S, A)`:
///
/// - `HANDLE` comes back as `GO!(N)` -- the derivation;
/// - `DELEGATE!(..)` or `GO!(N ..)` comes back as it was;
/// - anything else is `tabular-center::path-broken`: the cell cannot reach `N`.
///
/// For a path's last state `(p L)`, a cell that can still leave `L` -- a
/// HANDLE, a DELEGATE, a GO anywhere but `L` -- is
/// `tabular-center::path-unterminated`. Every other cell comes back as it was.
///
/// Every answer is delivered by calling back into `transition_matrix!` with
/// the continuation it was given, because a macro cannot return a value to
/// the middle of another macro's munch -- errors included, so the rest of
/// the machine still expands and the reported error is the one that matters.
///
/// `$d` is a literal `$`, handed in as `($)` by the caller: the definition
/// below needs metavariables of its own, and a macro cannot otherwise put a
/// `$` in its output.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_define_hops {
    (($d:tt)
        hops=[ $( ($p:ident $st:ident $ac:ident $nx:ident) )* ]
        backs=[ $( ($bf:ident $bact:ident $bt:ident) )* ]
        lasts=[ $( ($lp:ident $l:ident) )* ]
    ) => {
        macro_rules! __tabula_hop {
            $(
                ([$d($d k:tt)*] ; $st $ac HANDLE) => {
                    $crate::transition_matrix!($d($d k)* cell=[GO!($nx)]);
                };
                ([$d($d k:tt)*] ; $st $ac DELEGATE $d($d g:tt)*) => {
                    $crate::transition_matrix!($d($d k)* cell=[DELEGATE $d($d g)*]);
                };
                ([$d($d k:tt)*] ; $st $ac GO ! ($nx $d($d r:tt)*)) => {
                    $crate::transition_matrix!($d($d k)* cell=[GO ! ($nx $d($d r)*)]);
                };
                ([$d($d k:tt)*] ; $st $ac $d($d cell:tt)*) => {
                    ::core::compile_error!(::core::concat!(
                        "tabular-center::path-broken: path `", ::core::stringify!($p),
                        "` goes `", ::core::stringify!($st),
                        "` -`", ::core::stringify!($ac),
                        "`-> `", ::core::stringify!($nx),
                        "`, and cell (", ::core::stringify!($st),
                        ", ", ::core::stringify!($ac),
                        ") cannot reach `", ::core::stringify!($nx), "`"
                    ));
                    $crate::transition_matrix!($d($d k)* cell=[$d($d cell)*]);
                };
            )*
            $(
                ([$d($d k:tt)*] ; $bf $bact HANDLE) => {
                    $crate::transition_matrix!($d($d k)* cell=[GO!($bt)]);
                };
                ([$d($d k:tt)*] ; $bf $bact $d($d cell:tt)*) => {
                    $crate::transition_matrix!($d($d k)* cell=[$d($d cell)*]);
                };
            )*
            $(
                ([$d($d k:tt)*] ; $l $d _ac:ident GO ! ($l $d($d r:tt)*)) => {
                    $crate::transition_matrix!($d($d k)* cell=[GO ! ($l $d($d r)*)]);
                };
                ([$d($d k:tt)*] ; $l $d _ac:ident HANDLE) => {
                    $crate::__tabula_unterminated!($lp $l);
                    $crate::transition_matrix!($d($d k)* cell=[HANDLE]);
                };
                ([$d($d k:tt)*] ; $l $d _ac:ident DELEGATE $d($d g:tt)*) => {
                    $crate::__tabula_unterminated!($lp $l);
                    $crate::transition_matrix!($d($d k)* cell=[DELEGATE $d($d g)*]);
                };
                ([$d($d k:tt)*] ; $l $d _ac:ident GO $d($d g:tt)*) => {
                    $crate::__tabula_unterminated!($lp $l);
                    $crate::transition_matrix!($d($d k)* cell=[GO $d($d g)*]);
                };
            )*
            ([$d($d k:tt)*] ; $d _st:ident $d _ac:ident $d($d cell:tt)*) => {
                $crate::transition_matrix!($d($d k)* cell=[$d($d cell)*]);
            };
        }
    };
}

/// `tabular-center::path-unterminated`, for the last state `$l` of path `$p`.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_unterminated {
    ($p:ident $l:ident) => {
        ::core::compile_error!(::core::concat!(
            "tabular-center::path-unterminated: path `",
            ::core::stringify!($p),
            "` ends at `",
            ::core::stringify!($l),
            "`, which can still be left; a path ends where the machine is done"
        ));
    };
}

/// Defines the lookups `path-unknown-state` asks: one for declared states,
/// one for declared actions, each a rule per name plus a fallback that
/// reports the name it did not find -- with the declared list, as Kotlin and
/// Swift give it.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_define_known {
    (($d:tt) states=[$($sv:ident)*] actions=[$($av:ident)*]) => {
        macro_rules! __tabula_known_state {
            $( ($d _p:ident $sv) => {}; )*
            ($d p:ident $d other:ident) => {
                ::core::compile_error!(::core::concat!(
                    "tabular-center::path-unknown-state: path `", ::core::stringify!($d p),
                    "` names state `", ::core::stringify!($d other),
                    "`, which is not declared. States: ", ::core::stringify!($($sv)*)
                ));
            };
        }
        macro_rules! __tabula_known_action {
            $( ($d _p:ident $av) => {}; )*
            ($d p:ident $d other:ident) => {
                ::core::compile_error!(::core::concat!(
                    "tabular-center::path-unknown-state: path `", ::core::stringify!($d p),
                    "` names action `", ::core::stringify!($d other),
                    "`, which is not declared. Actions: ", ::core::stringify!($($av)*)
                ));
            };
        }
    };
}

/// An item-position `fn`, in the machine's color.
///
/// `Plain` passes the function through; `Async` inserts `async` before `fn`,
/// after any attributes (doc comments arrive here as `#[doc = ..]`) and the
/// visibility.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_colored_fn {
    (Plain; $($f:tt)*) => {
        $($f)*
    };
    (Async; $(#[$attr:meta])* $v:vis fn $($f:tt)*) => {
        $(#[$attr])* $v async fn $($f)*
    };
}

/// A HANDLE cell's call into developer code, in the machine's color:
/// `Handle::handle(..)`, or `AsyncHandle::handle(..).await`.
///
/// Every identifier arrives as an argument rather than being written here, so
/// the dispatcher's bindings keep their syntax context -- see the hygiene note
/// in `step`.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_handle_call {
    (Plain; $cty:ident $m:ident $st:ident $ca:ident; $bc:ident $bx:ident $bsv:ident $act:ident) => {
        <$cty as $crate::Handle<$m, $st, $ca>>::handle($bc, $bx, $bsv, $act)
    };
    (Async; $cty:ident $m:ident $st:ident $ca:ident; $bc:ident $bx:ident $bsv:ident $act:ident) => {
        <$cty as $crate::AsyncHandle<$m, $st, $ca>>::handle($bc, $bx, $bsv, $act).await
    };
}

/// A machine's narrowed surface: `spec/happy-paths.md`, "Settled before
/// implementation", in the shape `macro_rules!` can produce (see `hop.rs`).
///
/// One `Hop` impl per forward hop, keyed by the hop's existing types -- no new
/// names, which `macro_rules!` cannot make -- and one `narrow`, in the
/// machine's color, that steps `from` with the action that arrived and splits
/// the result: the happy state, or the whole `State` the matrix reached.
/// Effects come back either way, never run.
///
/// A hop shared by two paths generates its impl twice, and rustc reports the
/// conflict (E0119) -- `macro_rules!` cannot deduplicate the hop list the way
/// the Kotlin and Swift emitters do.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_narrow {
    (c=$c:tt hdr=[
        machine $m:ident; context $x:ident; state $s:ident; action $a:ident;
        effects $e:ident $effs:tt $($rest:tt)*
    ] hops=[$( ($pn:ident $st:ident $ac:ident $nx:ident) )*]) => {
        $(
            impl $crate::Hop<$ac> for $st {
                type State = $s;
                type To = $nx;

                fn into_state(self) -> $s {
                    $s::$st(self)
                }

                fn happy(next: $s) -> ::core::result::Result<$nx, $s> {
                    match next {
                        $s::$nx(to) => ::core::result::Result::Ok(to),
                        other => ::core::result::Result::Err(other),
                    }
                }
            }
        )*

        $crate::__tabula_colored_fn! { $c;
        #[allow(dead_code)]
        pub fn narrow<TabulaFrom, TabulaAction, TabulaCells>(
            cells: &mut TabulaCells,
            ctx: &mut $x,
            from: TabulaFrom,
            action: $a,
        ) -> ::core::result::Result<
            (<TabulaFrom as $crate::Hop<TabulaAction>>::To, $crate::Effects<$e>),
            ($s, $crate::Effects<$e>),
        >
        where
            TabulaFrom: $crate::Hop<TabulaAction, State = $s>,
            TabulaCells: Cells,
        {
            let current = <TabulaFrom as $crate::Hop<TabulaAction>>::into_state(from);
            let stepped = $crate::__tabula_delegate_step!($c; step(cells, ctx, current, action));
            let next = match stepped.outcome {
                $crate::Outcome::Go(next) => next,
                $crate::Outcome::Stay | $crate::Outcome::Ignored => current,
            };
            match <TabulaFrom as $crate::Hop<TabulaAction>>::happy(next) {
                ::core::result::Result::Ok(to) => ::core::result::Result::Ok((to, stepped.effects)),
                ::core::result::Result::Err(other) => {
                    ::core::result::Result::Err((other, stepped.effects))
                }
            }
        }
        }
    };
}

/// A DELEGATE cell's call into the child, in the PARENT's color.
///
/// Only the parent's color is known here -- the child's is not visible at
/// this expansion -- and it is enough: see `IntoFuture for Step`.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_delegate_step {
    (Plain; $($call:tt)*) => {
        $($call)*
    };
    (Async; $($call:tt)*) => {
        $($call)*.await
    };
}

/// A machine's effect surface in its color: the `Handlers` bound and the
/// `perform` pump.
///
/// One `Perform` (or `AsyncPerform`) bound per effect variant. **Add a
/// variant and every handler stops compiling** -- the same required-member
/// mechanism the transition side uses, applied to the other half of the
/// machine. It needs no muncher: effect variants are a flat list, with no
/// row/column zip to flatten.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_effects {
    (Plain; m=$m:ident x=$x:ident a=$a:ident e=$e:ident evs=[$($ev:ident)*]) => {
        /// This machine's entire effect surface, as one bound.
        pub trait Handlers:
            $( $crate::Perform<$m, $ev> + )* ::core::marker::Sized
        {
        }

        impl<T> Handlers for T where
            T: $( $crate::Perform<$m, $ev> + )* ::core::marker::Sized
        {
        }

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
    };
    (Async; m=$m:ident x=$x:ident a=$a:ident e=$e:ident evs=[$($ev:ident)*]) => {
        /// This machine's entire effect surface, as one bound: one
        /// `AsyncPerform` per effect variant.
        pub trait Handlers:
            $( $crate::AsyncPerform<$m, $ev> + )* ::core::marker::Sized
        {
        }

        impl<T> Handlers for T where
            T: $( $crate::AsyncPerform<$m, $ev> + )* ::core::marker::Sized
        {
        }

        #[allow(unused_variables, unreachable_code)]
        pub async fn perform<H: Handlers>(
            __tabula_handlers: &mut H,
            __tabula_ctx: &mut $x,
            __tabula_effect: $e,
        ) -> ::core::option::Option<$a> {
            match __tabula_effect {
                $(
                    $e::$ev(__tabula_ev) => <H as $crate::AsyncPerform<$m, $ev>>::perform(
                        __tabula_handlers, __tabula_ctx, __tabula_ev,
                    ).await,
                )*
            }
        }
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
    (@rows s=$s:ident a=$a:ident c=$c:tt m=$m:ident et=$et:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($av:ident)*] rows=[] acc=[$($acc:tt)*]
    ) => {
        match $bs { $($acc)* }
    };

    (@rows s=$s:ident a=$a:ident c=$c:tt m=$m:ident et=$et:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($av:ident)*]
        rows=[$rs:ident => [$($rc:tt)*]; $($rest:tt)*]
        acc=[$($acc:tt)*]
    ) => {
        $crate::__tabula_arms!(@rows s=$s a=$a c=$c m=$m et=$et
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($av)*]
            rows=[$($rest)*]
            acc=[$($acc)*
                $s::$rs($bsv) => $crate::__tabula_row!(@go
                    c=$c m=$m s=$s a=$a et=$et st=$rs
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
    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[] cells=[] arms=[$($arm:tt)*]
    ) => {
        match $ba { $($arm)* }
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$($ca:ident)*] cells=[, $($crest:tt)*] arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($ca)*] cells=[$($crest)*] arms=[$($arm)*])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$c1:ident $c2:ident $c3:ident $c4:ident $($carest:ident)*]
        cells=[IGNORE, IGNORE, IGNORE, IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)*
                $a::$c1(_) => $crate::Step::ignored(),
                $a::$c2(_) => $crate::Step::ignored(),
                $a::$c3(_) => $crate::Step::ignored(),
                $a::$c4(_) => $crate::Step::ignored(),
            ])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$c1:ident $c2:ident $($carest:ident)*]
        cells=[IGNORE, IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)*
                $a::$c1(_) => $crate::Step::ignored(),
                $a::$c2(_) => $crate::Step::ignored(),
            ])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[IGNORE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => $crate::Step::ignored(),])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[HANDLE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(__tabula_a) => {
                $crate::__tabula_handle_call!($c; C $m $st $ca; $bc $bx $bsv __tabula_a)
            },])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*] cells=[UNREACHABLE $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(_) => ::core::unreachable!(::core::concat!(
                "tabular-center: ", ::core::stringify!($st), " x ", ::core::stringify!($ca),
                " was declared UNREACHABLE but occurred"
            )),])
    };

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[GO ! ($t:expr $(, $ef:expr)* $(,)?) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
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

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[DELEGATE ! ($ch:ident) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
            bind=[$bs $ba $bc $bx $bsv]
            actions=[$($carest)*] cells=[$($crest)*]
            arms=[$($arm)* $a::$ca(__tabula_a) => {
                let __child_action = <C as $crate::Delegate<$m, $st, $ca, $ch::Marker>>::to_child(
                    $bc, $bx, &$bsv, __tabula_a,
                );
                match __child_action {
                    ::core::option::Option::None => $crate::Step::ignored(),
                    ::core::option::Option::Some(__ca) => {
                        let __cs =
                            <C as $crate::Lens<$m, $st, $ch::Marker>>::child_state($bc, &$bsv);
                        let __cx =
                            <C as $crate::Lens<$m, $st, $ch::Marker>>::child_ctx($bc, $bx);
                        let __cstep =
                            $crate::__tabula_delegate_step!($c; $ch::step($bc, __cx, __cs, __ca));
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

    (@go c=$c:tt m=$m:ident s=$s:ident a=$a:ident et=$et:ident st=$st:ident
        bind=[$bs:ident $ba:ident $bc:ident $bx:ident $bsv:ident]
        actions=[$ca:ident $($carest:ident)*]
        cells=[EMIT ! ($($ef:expr),* $(,)?) $($crest:tt)*]
        arms=[$($arm:tt)*]
    ) => {
        $crate::__tabula_row!(@go c=$c m=$m s=$s a=$a et=$et st=$st
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
            effects: &[$($crate::table::first_ident(::core::stringify!($ef))),*],
        },])
    };
}

/// Emits the `PAYLOADS` const, one state at a time.
#[doc(hidden)]
#[macro_export]
macro_rules! __tabula_payloads {
    (@go acc=[$($acc:tt)*] rest=[]) => {
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
