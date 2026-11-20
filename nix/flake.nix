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

    # Linux — standalone home-manager for agent containers (agent profile, P3)
    homeConfigurations."agent-linux" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        ./profiles/common.nix
        ./profiles/agent.nix
        {
          home.username = "agent";
          home.homeDirectory = "/home/agent";
          home.stateVersion = "25.05";
        }
      ];
    };

  };
}
