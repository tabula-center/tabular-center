// Compose's annotation, stubbed. The processor recognises `@Composable` by its
// qualified name, and without the Compose compiler plugin it is only an
// annotation -- so this fixture tests the processor, not Compose, and needs no
// Compose artifacts in the locked set. Only this fixture's build sees it: each
// fixture compiles alone (`-PtabulaFixture`).
package androidx.compose.runtime

@Target(AnnotationTarget.FUNCTION)
annotation class Composable
