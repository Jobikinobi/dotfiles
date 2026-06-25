{ config, pkgs, lib, ... }:

# Headless profile for Paperclip/agent machines.
#
# Platform-agnostic: works under home-manager.lib.homeManagerConfiguration (Linux)
# and nix-darwin.darwinModules.home-manager (macOS) — but macOS agent-mac is gated
# on Q3 board resolution; for now only agent-linux uses this module.
#
# home.username / homeDirectory / stateVersion are set per-host in flake.nix.
# Secrets are NOT managed here — they stay in Doppler per ADR-001.
{
  home.packages = with pkgs; [
    # VCS and GitHub integration
    git
    gh

    # HTTP and data
    curl
    jq

    # Filesystem search (agents grep and navigate codebases)
    ripgrep
    fd

    # Agent runtimes
    nodejs_22  # Paperclip harness + TypeScript tooling
    python3    # agent scripts, ML pipeline helpers

    # Headless session management
    tmux

    # Commit signing
    gnupg
  ];

  programs.git = {
    enable = true;
    # name/email unset — operators set these per-deployment via git config or env.
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # Workspace directory layout from docs/conventions/workspace-directory-layout.md.
  # Uses home.activation (not home.file) because home.file creates files, not empty
  # directories — activation is the correct home-manager idiom for this.
  # Mirrors run_once_after_create-workspace-dirs.sh.tmpl for parity.
  home.activation.createWorkspaceDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p \
      "${config.home.homeDirectory}/projects/gh" \
      "${config.home.homeDirectory}/projects/local" \
      "${config.home.homeDirectory}/docs/notes" \
      "${config.home.homeDirectory}/docs/references" \
      "${config.home.homeDirectory}/apps" \
      "${config.home.homeDirectory}/bin" \
      "${config.home.homeDirectory}/scratch"
  '';
}
