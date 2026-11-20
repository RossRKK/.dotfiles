# The ACP adapter CodeCompanion drives Claude Code through, at a release newer
# than nixpkgs' 0.36.1, running the `claude` given so its sessions load the same
# --plugin-dir mods and login as the TUI.
{
  claude-agent-acp,
  fetchFromGitHub,
  fetchNpmDeps,
  claude,
}:

(claude-agent-acp.override { claude-code = claude; }).overrideAttrs (
  finalAttrs: _: {
    version = "0.109.0";
    src = fetchFromGitHub {
      owner = "agentclientprotocol";
      repo = "claude-agent-acp";
      tag = "v${finalAttrs.version}";
      hash = "sha256-I2m+q06rB5hxi2J1Ai5mdcbZYD3p0LQ4/KAruk0jjQs=";
    };
    npmDeps = fetchNpmDeps {
      inherit (finalAttrs) src;
      name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
      hash = "sha256-qSKBpAYu2/2B5uBnkS+yqdqyUDfHsbIyTgk824GPcH4=";
    };
  }
)
