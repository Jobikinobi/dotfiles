# Joe's home-manager content, split out of joe.nix so it is platform-portable.
#
# joe.nix is nix-darwin-specific — it sets system.primaryUser and
# system.defaults (dock/finder/NSGlobalDomain), none of which exist under
# standalone home-manager. That is why `nix_profile = "joe"` on Linux used to
# die with "flake output attribute not found": there simply was no joe-linux,
# and joe.nix could not have served as one.
#
# Everything below is portable, so both darwinConfigurations."<host>" and
# homeConfigurations."joe-linux" import this module.
#
# home.username / homeDirectory / stateVersion are NOT set here — the caller
# owns them, because they differ per platform (/Users/x vs /home/x).
{ pkgs, ... }: {

  # Personal tools managed by Nix for version pinning.
  # Only tools NOT already in dot_Brewfile.core or a project Brewfile.
  # Homebrew continues to own the core CLI stack and casks.
  home.packages = with pkgs; [
    nil          # Nix language server (LSP for .nix files)
    nixpkgs-fmt  # canonical Nix formatter (for nix/ in this repo)
    mkcert       # local HTTPS dev certificates
  ];

  # Workspace directory stubs (see docs/conventions/workspace-directory-layout.md).
  # home-manager creates parent dirs when symlinking these sentinel files.
  home.file = {
    "projects/gh/.keep".text     = "";
    "projects/local/.keep".text  = "";
    "docs/notes/.keep".text      = "";
    "docs/references/.keep".text = "";
    "apps/.keep".text            = "";
    "bin/.keep".text             = "";
    "scratch/.keep".text         = "";
  };
}
