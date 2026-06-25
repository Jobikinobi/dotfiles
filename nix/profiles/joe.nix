# Joe's personal profile — nix-darwin + home-manager (P4, HOL-508)
#
# Layer ownership (from HOL-499 ADR):
#   - THIS FILE owns: tool versions (Nix-managed), macOS system settings
#   - chezmoi owns: shell configs (.zshrc), secret injection
#   - Doppler owns: all secrets
#
# home.file workspace dirs mirror docs/conventions/workspace-directory-layout.md.
# The run_once_after_create-workspace-dirs.sh.tmpl creates the same dirs via
# chezmoi; both are idempotent. Long-term (P5+) the script will be removed in
# favour of this declarative source of truth.

{ pkgs, ... }: {

  users.users.jth.home = "/Users/jth";

  # ── home-manager user settings ───────────────────────────────────────────
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.jth = { pkgs, ... }: {
    home.username = "jth";
    home.homeDirectory = "/Users/jth";
    home.stateVersion = "25.05";

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
      "projects/gh/.keep".text  = "";
      "projects/local/.keep".text = "";
      "docs/notes/.keep".text     = "";
      "docs/references/.keep".text = "";
      "apps/.keep".text           = "";
      "bin/.keep".text            = "";
      "scratch/.keep".text        = "";
    };
  };

  # ── nix-darwin system settings ────────────────────────────────────────────
  system.defaults = {

    dock = {
      autohide                = true;
      show-recents            = false;
      minimize-to-application = true;
      tilesize                = 48;
    };

    finder = {
      AppleShowAllFiles       = true;   # show hidden files
      ShowPathbar             = true;
      ShowStatusBar           = true;
      FXPreferredViewStyle    = "Nlsv"; # list view default
      _FXShowPosixPathInTitle = true;
      FXEnableExtensionChangeWarning = false;
    };

    NSGlobalDomain = {
      # Key repeat — essential for vim/helix; disables press-and-hold accent picker
      ApplePressAndHoldEnabled = false;
      KeyRepeat                = 2;
      InitialKeyRepeat         = 15;

      # Scroll / gesture
      "com.apple.swipescrolldirection" = false; # disable natural scrolling
    };

    trackpad = {
      Clicking = true; # tap to click
    };
  };
}
