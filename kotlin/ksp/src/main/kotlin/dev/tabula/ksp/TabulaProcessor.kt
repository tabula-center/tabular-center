package dev.tabula.ksp

import codegen.ChildDesc
import codegen.RawCell
import codegen.RawMachine
import codegen.RawRow
import codegen.RawVariant
import codegen.TabulaError
import codegen.buildDesc
import codegen.emit
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

        return RawMachine(
            packageName = decl.packageName.asString(),
            machine = machineAnn.string("name").ifBlank { decl.simpleName.asString().removeSuffix("Spec") },
            // The sealed hierarchies are nested in the annotated interface, so
            // their outer names are the type names a developer already chose.
            stateType = outerOf(machineAnn, "states"),
            actionType = outerOf(machineAnn, "actions"),
            effectType = outerOf(machineAnn, "effects"),
            ctxType = ctxTypeOf(decl),
            initial = initial,
            states = states,
            actions = actions,
            effects = effects,
            rows = rows,
            prototypeModifiers = prototypeModifiers(decl),
            children = emptyList(), // DELEGATE support lands with child resolution
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

    @Suppress("UNCHECKED_CAST")
    private fun KSAnnotation.classes(name: String): List<KSClassDeclaration> =
        when (val v = argument(name)) {
            is List<*> -> v.filterIsInstance<KSType>().mapNotNull { it.declaration as? KSClassDeclaration }
            is KSType -> listOfNotNull(v.declaration as? KSClassDeclaration)
            else -> emptyList()
        }

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
    }
}

private fun KSClassDeclaration.getDeclaredFunctions() =
    com.google.devtools.ksp.getDeclaredFunctions(this)

/** Registered via `META-INF/services`. */
class TabulaProcessorProvider : SymbolProcessorProvider {
    override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor =
        TabulaProcessor(environment.codeGenerator, environment.logger)
}
