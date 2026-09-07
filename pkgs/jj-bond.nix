# jj-bond: a Jujutsu TUI (binary `jb`), not yet in nixpkgs.
# https://github.com/TD-Sky/jj-bond -- built from the crates.io release so the
# Cargo.lock ships with the source. The build script asks for a git sha but
# tolerates its absence (0.1.5 "Optional VERGEN_GIT_SHA").
{ lib, rustPlatform, fetchCrate }:
rustPlatform.buildRustPackage rec {
  pname = "jj-bond";
  version = "0.1.6";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-vm66WRQadJyaeZDq5RIzUTrzVKOOgL1vHZtK6p+8DO8=";
  };

  cargoHash = "sha256-UjJCbfew6WBsaPYKmj8C8C6aO7mdaF3oNrymEWC+Wsg=";

  meta = {
    description = "TUI for Jujutsu VCS";
    homepage = "https://github.com/TD-Sky/jj-bond";
    license = lib.licenses.mit;
    mainProgram = "jb";
  };
}
