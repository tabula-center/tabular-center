package dev.tabula.ksp

import codegen.ChildDesc
import codegen.RawCell
import codegen.RawMachine
import codegen.RawPath
import codegen.RawRow
import codegen.RawVariant
import codegen.TabulaError
import codegen.buildDesc
import codegen.emit
import com.google.devtools.ksp.getDeclaredFunctions
import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.Dependencies
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.processing.SymbolProcessorEnvironment
import com.google.devtools.ksp.processing.SymbolProcessorProvider
import com.google.devtools.ksp.symbol.KSAnnotation
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.KSType
import com.google.devtools.ksp.symbol.Modifier
import java.io.OutputStreamWriter

/**
 * **The one file that has never been run.**
 *
 * KSP is a Maven artifact and the environment this was developed in cannot
 * reach Maven, so this adapter is unverified while everything it feeds into is
 * covered. That is deliberate rather than resigned: the work went into making
 * this file as small and as dumb as possible.
 *
 * Its entire job is `KSP API -> RawMachine`. Reading annotation arguments into
 * strings is mechanical and reviewable by eye. Every decision, every
 * diagnostic, and all of the source emission live in `codegen/`, which runs
 * and is tested with `kotlinc` alone:
 *
 * - `buildDesc` validates and reports every declaration diagnostic — 14 cases,
 *   all tested.
 * - `emit` produces the source — golden-diffed, then *compiled*, then checked
 *   against a complete and an incomplete implementation.
 *
 * So a bug here is an extraction bug (a wrong argument name, a missing null
 * check), not a logic bug, and it surfaces as an obviously wrong `RawMachine`
 * rather than as subtly wrong generated code.
 */
class TabulaProcessor(
    private val codeGenerator: CodeGenerator,
    private val logger: KSPLogger,
) : SymbolProcessor {

    override fun process(resolver: Resolver): List<com.google.devtools.ksp.symbol.KSAnnotated> {
        val machines = resolver
            .getSymbolsWithAnnotation(MACHINE_ANNOTATION)
            .filterIsInstance<KSClassDeclaration>()
            .toList()

        for (decl in machines) {
            try {
                val raw = readMachine(decl)
                val desc = buildDesc(raw)
                write(decl, desc.packageName, raw.machine, emit(desc))
            } catch (e: TabulaError) {
                // Diagnostics are authored in `codegen`, not here, so their
                // text stays identical whether they are triggered through KSP
                // or through the tests. Only the source position is added.
                logger.error(e.message, decl)
            } catch (e: Exception) {
                logger.error("tabula: ${e.message}", decl)
            }
        }
        // Nothing is deferred: everything needed is resolvable in one round.
        return emptyList()
    }

    // -- extraction ---------------------------------------------------------

    private fun readMachine(decl: KSClassDeclaration): RawMachine {
        val machineAnn = decl.annotation(MACHINE_SIMPLE)
            ?: error("no @Machine on ${decl.simpleName.asString()}")

        val states = machineAnn.classes("states").map { it.variant() }
        val actions = machineAnn.classes("actions").map { it.variant() }
        val effects = machineAnn.classes("effects").map { it.variant() }
        val initial = machineAnn.classes("initial").firstOrNull()?.simpleName?.asString()
            ?: states.first().name

        val rows = decl.annotations
            .filter { it.shortName.asString() == ROW_SIMPLE }
            .map { row ->
                val state = row.classes("state").first().simpleName.asString()
                RawRow(state, row.annotations("cells").map(::readCell))
            }
            .toList()

        // Happy paths. Same shape as the rows above, which is the point: both
        // are repeatable annotations on the declaration, and reading them the
        // same way keeps one pattern rather than two.
        //
        // No validation here. `buildDesc` owns all four `path-*` diagnostics,
        // so a route naming a state that does not exist is rejected there with
        // the normative message rather than twice with two.
        val paths = decl.annotations
            .filter { it.shortName.asString() == PATH_SIMPLE }
            .map { path ->
                RawPath(
                    path.string("name"),
                    path.classes("states").map { it.simpleName.asString() },
                )
            }
            .toList()

        return RawMachine(
            packageName = decl.packageName.asString(),
            machine = machineAnn.string("name").ifBlank { decl.simpleName.asString().removeSuffix("Spec") },
            // The sealed hierarchies are nested in the annotated interface, so
            // their outer names are the type names a developer already chose.
            stateType = outerOf(machineAnn, "states"),
            actionType = outerOf(machineAnn, "actions"),
            // `F` when there are no effects, not `Unit`.
            //
            // The type names are read from the first variant's outer class,
            // which is right for states and actions -- a machine cannot have
            // none -- and has no answer for an empty `effects` list.
            // `outerOf` returned `Unit`, so the generated surface was
            // `Step<S, Unit>` while the developer had written
            // `sealed interface F` and implemented against `Step<S, F>`:
            //
            //   Return type of 'failedStart' is not a subtype of the return
            //   type of the overridden member ... Step<S, Unit>
            //
            // Every machine before `Spine` declared at least one effect, so
            // this path had never run. `F` matches the convention SURFACE.md
            // states and `ChildDesc` already defaults to, and it makes the
            // `sealed interface F` a developer writes mean something.
            effectType = outerOf(machineAnn, "effects").takeIf { it != "Unit" } ?: "F",
            ctxType = ctxTypeOf(decl),
            initial = initial,
            states = states,
            actions = actions,
            effects = effects,
            rows = rows,
            prototypeModifiers = prototypeModifiers(decl),
            children = emptyList(), // DELEGATE support lands with child resolution
            paths = paths,
        )
    }

    private fun readCell(a: KSAnnotation): RawCell = RawCell(
        kind = a.enumName("kind"),
        target = a.classes("to").firstOrNull()?.simpleName?.asString()?.takeIf { it != "Unit" } ?: "",
        targetArgs = a.string("args"),
        effects = a.classes("emit").map { it.simpleName.asString() },
        child = a.classes("child").firstOrNull()?.simpleName?.asString()?.takeIf { it != "Unit" } ?: "",
    )

    /**
     * The prototype's modifiers, copied verbatim onto every generated member.
     *
     * ARCHITECTURE §5: the library never enumerates colors, it copies them. A
     * `suspend` prototype yields suspending cells; a context receiver or an
     * annotation this code has never heard of is carried along the same way.
     */
    private fun prototypeModifiers(decl: KSClassDeclaration): List<String> {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "handle" }
            ?: return emptyList()
        return buildList {
            if (Modifier.SUSPEND in proto.modifiers) add("suspend")
            proto.annotations.forEach { add("@" + it.shortName.asString()) }
        }
    }

    private fun ctxTypeOf(decl: KSClassDeclaration): String {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "handle" }
        return proto?.parameters?.firstOrNull()?.type?.resolve()?.declaration?.simpleName?.asString()
            ?: "Unit"
    }

    private fun write(decl: KSClassDeclaration, pkg: String, machine: String, source: String) {
        val file = codeGenerator.createNewFile(
            Dependencies(aggregating = false, decl.containingFile!!),
            pkg,
            "${machine}Generated",
        )
        OutputStreamWriter(file, Charsets.UTF_8).use { it.write(source) }
    }

    // -- tiny KSP helpers ---------------------------------------------------

    private fun KSClassDeclaration.annotation(simple: String): KSAnnotation? =
        annotations.firstOrNull { it.shortName.asString() == simple }

    private fun KSAnnotation.argument(name: String): Any? =
        arguments.firstOrNull { it.name?.asString() == name }?.value

    private fun KSAnnotation.string(name: String): String = argument(name) as? String ?: ""

    private fun KSAnnotation.enumName(name: String): String =
        when (val v = argument(name)) {
            is KSType -> v.declaration.simpleName.asString()
            else -> v?.toString()?.substringAfterLast('.') ?: ""
        }

    /**
     * `KClass` arguments, which KSP hands back as [KSType].
     *
     * An unrecognised shape **throws** rather than returning an empty list.
     * That is the whole change: `filterIsInstance` silently dropped anything
     * it did not recognise, so a KSP version handing back
     * `KSClassDeclaration` directly would have produced a machine with no
     * states and no error -- the one failure mode on this file's list that can
     * look like success. It is unverified code against an API that has moved
     * between versions; it should fail loudly or not at all.
     */
    private fun KSAnnotation.classes(name: String): List<KSClassDeclaration> =
        when (val v = argument(name)) {
            null -> emptyList()
            is List<*> -> v.map { it.asClassDeclaration(name) }
            else -> listOf(v.asClassDeclaration(name))
        }

    private fun Any?.asClassDeclaration(name: String): KSClassDeclaration = when (this) {
        is KSType -> declaration as? KSClassDeclaration
        is KSClassDeclaration -> this
        else -> null
    } ?: error(
        // Not a TabulaError: diagnostics are authored in `codegen` and this is
        // an extraction failure in the adapter, not a claim about the user's
        // machine. `process` catches it and prefixes `tabula:` like any other.
        "argument `$name` came back as ${this?.let { it::class.simpleName } ?: "null"}, " +
            "which this processor does not know how to read as a class. " +
            "See the argument-shape note in kotlin/ksp/README.md.",
    )

    @Suppress("UNCHECKED_CAST")
    private fun KSAnnotation.annotations(name: String): List<KSAnnotation> =
        (argument(name) as? List<*>)?.filterIsInstance<KSAnnotation>() ?: emptyList()

    /**
     * `S.Running` carries a payload iff it is a data class rather than an
     * object.
     *
     * The field list feeds `tabula::payload-hoist` only, so an unresolvable
     * type degrades that one lint rather than the machine.
     */
    private fun KSClassDeclaration.variant(): RawVariant {
        val hasPayload = classKind == com.google.devtools.ksp.symbol.ClassKind.CLASS
        val fields = if (!hasPayload) emptyList() else
            primaryConstructor?.parameters.orEmpty().mapNotNull { p ->
                val n = p.name?.asString() ?: return@mapNotNull null
                n to (p.type.resolve().declaration.simpleName.asString())
            }
        return RawVariant(simpleName.asString(), hasPayload, fields)
    }

    /** The sealed hierarchy's own name, e.g. `S` for `S.Idle`. */
    private fun outerOf(ann: KSAnnotation, name: String): String =
        ann.classes(name).firstOrNull()?.parentDeclaration?.simpleName?.asString() ?: "Unit"

    private companion object {
        const val MACHINE_ANNOTATION = "dev.tabula.Machine"
        const val MACHINE_SIMPLE = "Machine"
        const val ROW_SIMPLE = "Row"
        const val PATH_SIMPLE = "Path"
    }
}

/** Registered via `META-INF/services`. */
class TabulaProcessorProvider : SymbolProcessorProvider {
    override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor =
        TabulaProcessor(environment.codeGenerator, environment.logger)
}
