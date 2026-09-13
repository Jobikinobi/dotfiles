{
  description = "HOLE Foundation dotfiles — Nix configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, ... }:
  let
    # Builds a darwinSystem running the `joe` profile for a given account name.
    # Keeps the host entries below to one line each and keeps the account name
    # out of ./profiles/joe.nix.
    mkJoeDarwin = primaryUser: nix-darwin.lib.darwinSystem {
      specialArgs = { inherit primaryUser; };
      modules = [
        home-manager.darwinModules.home-manager
        ./profiles/common.nix
        ./profiles/joe.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 6;
        }
      ];
    };
  in {

    # macOS — Joe's personal machines (joe profile, P4 — HOL-508).
    #
    # run_once_after_nix-profile.sh.tmpl activates `#{{ .chezmoi.hostname }}`, so
    # every machine that should get this profile needs an entry keyed on its
    # exact LocalHostName (`scutil --get LocalHostName`). A missing key fails with
    # "flake output attribute not found" (dotfiles#117 — MacBook-Air had no entry).
    #
    # `primaryUser` flows into ./profiles/joe.nix via specialArgs so the profile
    # never hardcodes an account name.
    darwinConfigurations."joes-macbook" = mkJoeDarwin "jth";
    darwinConfigurations."MacBook-Air"  = mkJoeDarwin "josephherrmann";

    # macOS — headless agent node (agent profile, P3 / Q3 scope TBD)
    darwinConfigurations."agent-mac" = nix-darwin.lib.darwinSystem {
      modules = [
        ./profiles/common.nix
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system.stateVersion = 6;
        }
      ];
    };

    # ── Linux — standalone home-manager ──────────────────────────────────────
    #
    # run_once_after_nix-profile.sh.tmpl activates `#<profile>-linux` on x86_64
    # and `#<profile>-linux-aarch64` elsewhere, so every profile that may be
    # selected on Linux needs BOTH keys. A missing one fails the same way the
    # missing darwin key did in dotfiles#117: "flake output attribute not found".
    #
    # `joe-linux` exists because chezmoi.toml offers `joe` on every platform but
    # the flake only ever defined agent-linux — picking `joe` on a Linux box was
    # an unconditional hard failure. joe.nix itself cannot serve here (it is
    # nix-darwin-only), hence the portable ./profiles/joe-home.nix split.
    homeConfigurations = let
      mkLinux = system: modules: home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit modules;
      };

      # provision-lxd.sh --nix-profile agent creates user "agent" to match this.
      agentModules = [
        ./profiles/common.nix
        ./profiles/agent.nix
        {
          home.username = "agent";
          home.homeDirectory = "/home/agent";
          home.stateVersion = "25.05";
        }
      ];

      # "jth" matches the account Dockerfile.alpine / Dockerfile.rhel create.
      joeModules = [
        ./profiles/common.nix
        ./profiles/joe-home.nix
        {
          home.username = "jth";
          home.homeDirectory = "/home/jth";
          home.stateVersion = "25.05";
        }
      ];
    in {
      "agent-linux"         = mkLinux "x86_64-linux"  agentModules;
      "agent-linux-aarch64" = mkLinux "aarch64-linux" agentModules;
      "joe-linux"           = mkLinux "x86_64-linux"  joeModules;
      "joe-linux-aarch64"   = mkLinux "aarch64-linux" joeModules;
    };

  };
}
