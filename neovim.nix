# Neovim from any git ref: the `neovim` flake input pins the source. A source
# identical to a nixpkgs release is that package, so it comes from the binary
# cache; anything else is built here from nixpkgs' recipe, with the tree-sitter
# grammars and libghostty-vt that the source itself pins in cmake.deps/deps.txt.
{
  src,
  # nixpkgs builds besides this one's own whose source may match.
  releases,
}:
final: prev:
let
  inherit (prev) lib;

  fromSource =
    (prev.neovim-unwrapped.override { treesitter-parsers = grammars; }).overrideAttrs
      (old: {
        inherit src;
        version = cmakeVersion;
        buildInputs = old.buildInputs ++ lib.optional (deps ? GHOSTTY_URL) libghostty-vt;
        # The tree-sitter functional tests take longer than the build.
        doCheck = false;
        # nixpkgs' wrapper rewrites nvim.desktop, which master renamed.
        postInstall = (old.postInstall or "") + ''
          cd $out/share/applications
          [ -e nvim.desktop ] || ln -s org.neovim.nvim.desktop nvim.desktop
        '';
      });

  deps = parseDeps (builtins.readFile "${src}/cmake.deps/deps.txt");

  # The grammars bundled into the runtime, one per TREESITTER_<LANG>_URL.
  grammars = lib.mapAttrs' (
    key: url:
    let
      lang = builtins.head (builtins.match "TREESITTER_([A-Z]+)_URL" key);
    in
    lib.nameValuePair (lib.toLower lang) {
      src = prev.fetchurl {
        inherit url;
        sha256 = deps."TREESITTER_${lang}_SHA256";
      };
    }
  ) (lib.filterAttrs (key: _: builtins.match "TREESITTER_[A-Z]+_URL" key != null) deps);

  # Ghostty's own flake builds libghostty-vt at any commit, with its zig pin.
  libghostty-vt =
    let
      rev = builtins.head (builtins.match ".*/archive/([0-9a-f]+)\\.tar\\.gz" deps.GHOSTTY_URL);
      ghostty = builtins.getFlake "github:ghostty-org/ghostty/${rev}";
    in
    ghostty.packages.${prev.stdenv.hostPlatform.system}.libghostty-vt;

  # What `nvim --version` reports, which nixpkgs' version check compares against.
  cmakeVersion =
    let
      cmake = builtins.readFile "${src}/CMakeLists.txt";
      field =
        name: builtins.head (builtins.match ".*set\\(NVIM_VERSION_${name} \"?([^\")]*)\"?\\).*" cmake);
    in
    "${field "MAJOR"}.${field "MINOR"}.${field "PATCH"}${field "PRERELEASE"}";

  # deps.txt is one `KEY value` pair per line.
  parseDeps =
    text:
    lib.listToAttrs (
      map (
        line:
        let
          kv = builtins.match "([A-Z0-9_]+) (.*)" line;
        in
        lib.nameValuePair (builtins.elemAt kv 0) (builtins.elemAt kv 1)
      ) (builtins.filter (line: builtins.match "[A-Z0-9_]+ .*" line != null) (lib.splitString "\n" text))
    );
in
{
  neovim-unwrapped = lib.findFirst (release: release.src.outputHash == src.narHash) fromSource (
    [ prev.neovim-unwrapped ] ++ releases
  );
}
