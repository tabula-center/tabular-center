# Development shells.
ctx:

with ctx;
let
  # Only the shells that carry Swift get it: LD_LIBRARY_PATH is a blunt
  # instrument and there is no reason for the Rust or Kotlin shells to have the
  # Swift runtime ahead of anything.
  swiftEnv = { LD_LIBRARY_PATH = swiftLibraryPath; };
in
{
  default = mkShell "all" (rustInputs ++ kotlinInputs ++ swiftPkgs) swiftEnv;
  rust = mkShell "rust" rustInputs { };
  kotlin = mkShell "kotlin" kotlinInputs { };
  swift = mkShell "swift" swiftPkgs swiftEnv;
}
