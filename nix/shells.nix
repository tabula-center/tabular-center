# Development shells.
ctx:

with ctx;
{
  default = mkShell "all" (rustInputs ++ kotlinInputs ++ swiftPkgs);
  rust = mkShell "rust" rustInputs;
  kotlin = mkShell "kotlin" kotlinInputs;
  swift = mkShell "swift" swiftPkgs;
}
