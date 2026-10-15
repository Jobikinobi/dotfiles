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

# `primaryUser` is supplied per-host via the flake's specialArgs, so this profile
# is portable across machines. It previously hardcoded "jth" / "/Users/jth", which
# broke activation on any host with a different account name (dotfiles#117).
{ pkgs, primaryUser, ... }: {

  # Required by nix-darwin ≥ 24-11 — system defaults (dock, finder, NSGlobalDomain)
  # now run as root and must know which user they target.
  # NOTE: this was defined twice in the same attrset, which is a Nix eval error
  # ("attribute already defined") and hard-failed the whole activation.
  system.primaryUser = primaryUser;

  users.users.${primaryUser}.home = "/Users/${primaryUser}";

  # ── home-manager user settings ───────────────────────────────────────────
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  # Packages and workspace dirs live in ./joe-home.nix so homeConfigurations
  # ."joe-linux" can import the identical set. Only the paths differ.
  home-manager.users.${primaryUser} = {
    imports = [ ./joe-home.nix ];
    home.username = primaryUser;
    home.homeDirectory = "/Users/${primaryUser}";
    home.stateVersion = "25.05";
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
