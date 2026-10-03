package center.tabula.ksp

import center.tabula.codegen.ChildDesc
import center.tabula.codegen.RawCell
import center.tabula.codegen.RawMachine
import center.tabula.codegen.RawPath
import center.tabula.codegen.RawRow
import center.tabula.codegen.RawVariant
import center.tabula.codegen.RenderDesc
import center.tabula.codegen.TabularCenterError
import center.tabula.codegen.buildDesc
import center.tabula.codegen.emit
import com.google.devtools.ksp.getDeclaredFunctions
import com.google.devtools.ksp.getVisibility
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
import com.google.devtools.ksp.symbol.Variance
import com.google.devtools.ksp.symbol.Visibility
import java.io.OutputStreamWriter

/**
 * **Written before it could be run; now run on every `nix flake check`.**
 *
 * KSP is a Maven artifact and the environment this was first developed in
 * could not reach Maven, so this adapter was written unverified while
 * everything it feeds into was covered. It now runs against the artifact set
 * pinned in `tabular-center-kotlin/nix/gradle-lock.json` (`kotlin-ksp`, `kotlin-ksp-compile-fail`,
 * `kotlin-ksp-incremental`). The arrangement is kept because it paid: the work
 * went into making this file as small and as dumb as possible.
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
class TabularCenterProcessor(
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
                warnComposableTransition(decl)
                val raw = readMachine(decl)
                val desc = buildDesc(raw)
                write(decl, desc.packageName, raw.machine, emit(desc))
            } catch (e: TabularCenterError) {
                logger.error(e.message, e.state?.let { rowNodes(decl)[it] } ?: decl)
            } catch (e: Exception) {
                logger.error("tabular-center: ${e.message}", decl)
            }
        }
        return emptyList()
    }

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

        val paths = decl.annotations
            .filter { it.shortName.asString() == PATH_SIMPLE }
            .map { path ->
                RawPath(
                    path.string("name"),
                    path.classes("states").map { it.simpleName.asString() },
                    back = path.classes("back").firstOrNull()
                        ?.simpleName?.asString()?.takeIf { it != "Unit" } ?: "",
                )
            }
            .toList()

        return RawMachine(
            packageName = decl.packageName.asString(),
            machine = machineNameOf(decl),
            stateType = outerOf(machineAnn, "states"),
            actionType = outerOf(machineAnn, "actions"),
            effectType = outerOf(machineAnn, "effects").takeIf { it != "Unit" } ?: "F",
            ctxType = ctxTypeOf(decl),
            initial = initial,
            states = states,
            actions = actions,
            effects = effects,
            rows = rows,
            prototypeModifiers = prototypeModifiers(decl),
            children = childrenOf(decl),
            paths = paths,
            prototypeReceiver = prototypeReceiver(decl),
            visibility = visibilityOf(decl),
            render = renderOf(decl),
        )
    }

    private fun readCell(a: KSAnnotation): RawCell = RawCell(
        kind = a.enumName("kind"),
        target = a.classes("to").firstOrNull()?.simpleName?.asString()?.takeIf { it != "Unit" } ?: "",
        targetArgs = a.string("args"),
        effects = a.classes("emit").map { it.simpleName.asString() } +
            a.annotations("emits").map { e ->
                val name = e.classes("effect").firstOrNull()?.simpleName?.asString() ?: ""
                val args = e.string("args")
                if (args.isBlank()) name else "$name($args)"
            },
        child = a.childDecl()?.let { aliasOf(it) } ?: "",
    )

    private fun rowNodes(decl: KSClassDeclaration): Map<String, KSAnnotation> =
        decl.annotations
            .filter { it.shortName.asString() == ROW_SIMPLE }
            .mapNotNull { row ->
                row.classes("state").firstOrNull()?.simpleName?.asString()?.let { it to row }
            }
            .toMap()

    private fun KSAnnotation.childDecl(): KSClassDeclaration? =
        classes("child").firstOrNull()?.takeIf { it.simpleName.asString() != "Unit" }

    private fun machineNameOf(decl: KSClassDeclaration): String =
        decl.annotation(MACHINE_SIMPLE)?.string("name")?.ifBlank { null }
            ?: decl.simpleName.asString().removeSuffix("Spec")

    private fun aliasOf(decl: KSClassDeclaration): String =
        machineNameOf(decl).replaceFirstChar { it.lowercase() }

    private fun childrenOf(decl: KSClassDeclaration): List<ChildDesc> = decl.annotations
        .filter { it.shortName.asString() == ROW_SIMPLE }
        .flatMap { it.annotations("cells").asSequence() }
        .mapNotNull { it.childDecl() }
        .distinctBy { it.qualifiedName?.asString() ?: it.simpleName.asString() }
        .map { child ->
            val ann = child.annotation(MACHINE_SIMPLE) ?: throw TabularCenterError(
                "tabular-center::unknown-child",
                "tabular-center::unknown-child: `${child.simpleName.asString()}` is named by a DELEGATE " +
                    "cell but is not a machine. A child must carry @Machine, and must be compiled " +
                    "together with its parent: @Machine is SOURCE-retention, so a child from " +
                    "another module has no annotation left to read.",
            )
            ChildDesc(
                alias = aliasOf(child),
                packageName = child.packageName.asString(),
                stateType = outerOf(ann, "states"),
                actionType = outerOf(ann, "actions"),
                effectType = outerOf(ann, "effects").takeIf { it != "Unit" } ?: "F",
                ctxType = ctxTypeOf(child),
            )
        }
        .toList()

    private fun prototypeModifiers(decl: KSClassDeclaration): List<String> {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "handle" }
            ?: return emptyList()
        return buildList {
            if (Modifier.SUSPEND in proto.modifiers) add("suspend")
            proto.annotations.forEach { a ->
                val fq = a.annotationType.resolve().declaration.qualifiedName?.asString()
                add("@" + (fq ?: a.shortName.asString()))
            }
        }
    }

    private fun warnComposableTransition(decl: KSClassDeclaration) {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "handle" }
            ?: return
        val composable = proto.annotations.any {
            it.annotationType.resolve().declaration.qualifiedName?.asString() == COMPOSABLE
        }
        if (!composable) return
        logger.warn(
            "tabular-center::composable-transition: `handle` is @Composable, so every transition " +
                "runs inside composition, which Compose may skip, restart, reorder or discard. " +
                "Keep `handle` plain and put UI in a rendering prototype, " +
                "`@Composable fun render(state: S)`.",
            proto,
        )
    }

    private fun renderOf(decl: KSClassDeclaration): RenderDesc? {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "render" }
            ?: return null
        if (proto.extensionReceiver != null) {
            error(
                "a rendering prototype with an extension receiver is not supported yet; " +
                    "declare `fun render(state: S): R` without one"
            )
        }
        if (proto.parameters.size != 1) {
            error(
                "the rendering prototype takes exactly one parameter, the state; " +
                    "`render` here takes ${proto.parameters.size}"
            )
        }
        val modifiers = buildList {
            if (Modifier.SUSPEND in proto.modifiers) add("suspend")
            proto.annotations.forEach { a ->
                val fq = a.annotationType.resolve().declaration.qualifiedName?.asString()
                add("@" + (fq ?: a.shortName.asString()))
            }
        }
        val returnType = proto.returnType?.resolve()?.render() ?: "Unit"
        return RenderDesc(modifiers = modifiers, returnType = returnType)
    }

    private fun prototypeReceiver(decl: KSClassDeclaration): String {
        val proto = decl.getDeclaredFunctions().firstOrNull { it.simpleName.asString() == "handle" }
            ?: return ""
        return proto.extensionReceiver?.resolve()?.render() ?: ""
    }

    private fun visibilityOf(decl: KSClassDeclaration): String = when (decl.getVisibility()) {
        Visibility.PUBLIC -> ""
        Visibility.INTERNAL -> "internal"
        else -> error(
            "@Machine on a ${decl.getVisibility().name.lowercase()} declaration: the " +
                "generated surface lives in another file, so it can only be public or " +
                "internal. Declare `${decl.simpleName.asString()}` internal.",
        )
    }

    private fun KSType.render(): String {
        val base = declaration.qualifiedName?.asString() ?: declaration.simpleName.asString()
        val args = if (arguments.isEmpty()) "" else arguments.joinToString(", ", "<", ">") { arg ->
            when (arg.variance) {
                Variance.STAR -> "*"
                Variance.CONTRAVARIANT -> "in " + (arg.type?.resolve()?.render() ?: "*")
                Variance.COVARIANT -> "out " + (arg.type?.resolve()?.render() ?: "*")
                else -> arg.type?.resolve()?.render() ?: "*"
            }
        }
        return base + args + if (isMarkedNullable) "?" else ""
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
        "argument `$name` came back as ${this?.let { it::class.simpleName } ?: "null"}, " +
            "which this processor does not know how to read as a class. " +
            "See the argument-shape note in tabular-center-kotlin/ksp/README.md.",
    )

    @Suppress("UNCHECKED_CAST")
    private fun KSAnnotation.annotations(name: String): List<KSAnnotation> =
        (argument(name) as? List<*>)?.filterIsInstance<KSAnnotation>() ?: emptyList()

    private fun KSClassDeclaration.variant(): RawVariant {
        val hasPayload = classKind == com.google.devtools.ksp.symbol.ClassKind.CLASS
        val fields = if (!hasPayload) emptyList() else
            primaryConstructor?.parameters.orEmpty().mapNotNull { p ->
                val n = p.name?.asString() ?: return@mapNotNull null
                n to (p.type.resolve().declaration.simpleName.asString())
            }
        return RawVariant(simpleName.asString(), hasPayload, fields)
    }

    private fun outerOf(ann: KSAnnotation, name: String): String =
        ann.classes(name).firstOrNull()?.parentDeclaration?.simpleName?.asString() ?: "Unit"

    private companion object {
        const val MACHINE_ANNOTATION = "center.tabula.Machine"
        const val MACHINE_SIMPLE = "Machine"
        const val ROW_SIMPLE = "Row"
        const val PATH_SIMPLE = "Path"
    }
}

/** Registered via `META-INF/services`. */
class TabularCenterProcessorProvider : SymbolProcessorProvider {
    override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor =
        TabularCenterProcessor(environment.codeGenerator, environment.logger)
}

private const val COMPOSABLE = "androidx.compose.runtime.Composable"
