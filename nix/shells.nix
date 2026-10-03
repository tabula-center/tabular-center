# The combined development shell, `nix develop`: every toolchain at once.
# The per-language shells are the language flakes' own, re-exported by name.
ctx:

with ctx;
{
  default = mkShell "all" allInputs (
    allEnv // lib.optionalAttrs toolchains.swift.available {
      LD_LIBRARY_PATH = toolchains.swift.libraryPath;
    }
  );
}
