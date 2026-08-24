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
    # Shared specialArgs for all joe-profile darwin configs.
    # username / homeDir are injected here so joe.nix stays machine-agnostic.
    joeArgs = {
      username = "jth";
      homeDir  = "/Users/jth";
    };
  in {

    # macOS — Joe's personal machine (joe profile, P4 — HOL-508)
    darwinConfigurations."joes-macbook" = nix-darwin.lib.darwinSystem {
      specialArgs = joeArgs;
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

    # macOS — Joe's MacBook Air (joe profile, same config as joes-macbook)
    darwinConfigurations."MacBook-Air" = nix-darwin.lib.darwinSystem {
      specialArgs = joeArgs;
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
