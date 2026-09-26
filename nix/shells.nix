# The combined development shell. The per-language shells are the language
# flakes' own, re-exported by name in ../flake.nix.
ctx:

with ctx;
{
  default = mkShell "all" allInputs (
    allEnv // lib.optionalAttrs toolchains.swift.available {
      LD_LIBRARY_PATH = toolchains.swift.libraryPath;
    }
  );
}
