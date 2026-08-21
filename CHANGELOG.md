# Changelog

All notable changes to this repository are documented here.

This file is maintained automatically by
[release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/). Do not edit it by
hand — write good commit messages instead (`feat:`, `fix:`, `docs:`, …) and the
next release PR will regenerate the entries below.

## [1.2.0](https://github.com/Jobikinobi/dotfiles/compare/v1.1.0...v1.2.0) (2026-07-29)


### Features

* add zoxide ([#60](https://github.com/Jobikinobi/dotfiles/issues/60)); remove mac-studio projects alias ([#61](https://github.com/Jobikinobi/dotfiles/issues/61)) ([#108](https://github.com/Jobikinobi/dotfiles/issues/108)) ([f666528](https://github.com/Jobikinobi/dotfiles/commit/f666528a03117e02a2ee0105327aea1b6b2cd188))
* **bin:** add pdf-link-batch helper for PDF symlink batches ([#110](https://github.com/Jobikinobi/dotfiles/issues/110)) ([fff3772](https://github.com/Jobikinobi/dotfiles/commit/fff37720de943ac9da93d786e7337f502b86a58f)), closes [#109](https://github.com/Jobikinobi/dotfiles/issues/109)
* **bootstrap:** sudo-less agent-space deploy ([#99](https://github.com/Jobikinobi/dotfiles/issues/99)) ([#103](https://github.com/Jobikinobi/dotfiles/issues/103)) ([5b2d5da](https://github.com/Jobikinobi/dotfiles/commit/5b2d5da77dd6b8128d8c865f7f9322be1c8e3eb6))
* **nix:** implement agent home-manager profile — HOL-507 ([#77](https://github.com/Jobikinobi/dotfiles/issues/77)) ([7a59fa4](https://github.com/Jobikinobi/dotfiles/commit/7a59fa49e6a24cefa29cb3dd4c4b76ff61204760))
* **nix:** implement joe profile — home-manager + nix-darwin macOS settings [HOL-508] ([9ca0b94](https://github.com/Jobikinobi/dotfiles/commit/9ca0b94f9280e361b0c4d00ee88f39ce0fc4285d))
* **nix:** joe profile — home-manager + nix-darwin macOS settings [HOL-508] ([a10443b](https://github.com/Jobikinobi/dotfiles/commit/a10443ba3b7442b995a281fe07ce6b768d73ad5c))
* **nix:** scaffold flake with pinned inputs and profile stubs — HOL-506 ([01699ee](https://github.com/Jobikinobi/dotfiles/commit/01699ee28117308010dbb6efe309c5e70d339c75))
* **nix:** scaffold flake with pinned inputs and profile stubs [HOL-506] ([9ebbfc4](https://github.com/Jobikinobi/dotfiles/commit/9ebbfc489f79305839d1383cff9a625538582924))
* **nix:** wire nix_profile selection into chezmoi bootstrap (HOL-509) ([6a7cd30](https://github.com/Jobikinobi/dotfiles/commit/6a7cd301643f48669610700fd01c9131e23e7fed))
* **nix:** wire nix_profile selection into chezmoi bootstrap + provision-lxd ([ddcee07](https://github.com/Jobikinobi/dotfiles/commit/ddcee077ca23d6eaa9e7171586902671b850e115))
* **proxmox:** personal-codespaces runbook + dev-control SSH stub ([#27](https://github.com/Jobikinobi/dotfiles/issues/27)) ([0eea1c4](https://github.com/Jobikinobi/dotfiles/commit/0eea1c4e6a7c400028c31bf7f3356ff0e4fa5617))
* **ssh:** born-standardized NetBird overlay identities ([#58](https://github.com/Jobikinobi/dotfiles/issues/58)) ([#116](https://github.com/Jobikinobi/dotfiles/issues/116)) ([ee1e747](https://github.com/Jobikinobi/dotfiles/commit/ee1e747d427b1d47a641a0e094f5f28365775041))
* **workspace:** standardize home-dir layout — HOL-505 ([23781bd](https://github.com/Jobikinobi/dotfiles/commit/23781bd44ef24f3d4dd8f396537ee27ae21f24f2))
* **workspace:** standardize home-dir layout — HOL-505 ([09a02c4](https://github.com/Jobikinobi/dotfiles/commit/09a02c4d92db141099f9fbef9b906fa72614d45f))


### Bug Fixes

* **bashrc:** per-OS guarded Homebrew PATH injection ([#100](https://github.com/Jobikinobi/dotfiles/issues/100), [#56](https://github.com/Jobikinobi/dotfiles/issues/56)) ([#107](https://github.com/Jobikinobi/dotfiles/issues/107)) ([87c9036](https://github.com/Jobikinobi/dotfiles/commit/87c9036f8c19e258ebe9496eaa916986174558f6))
* **ci:** remove Supabase CLI, fix nix-darwin primaryUser and git.settings, repair oversight profile build ([#84](https://github.com/Jobikinobi/dotfiles/issues/84)) ([d2346b7](https://github.com/Jobikinobi/dotfiles/commit/d2346b76b2307f3d767b2dbc4e4ba24910106380))
* **ci:** skip optional toolchains in profile verification ([#95](https://github.com/Jobikinobi/dotfiles/issues/95)) ([00404db](https://github.com/Jobikinobi/dotfiles/commit/00404db0a701d8e70d1bf6d5a6db48bd43bec53c))
* **ci:** stop bootstrapping Supabase CLI in Linux profile builds ([f647944](https://github.com/Jobikinobi/dotfiles/commit/f64794487eb8dab708fdbf030e0c9443d81d5da0))
* **Dockerfile.test:** exclude encrypted files from standalone apply ([#38](https://github.com/Jobikinobi/dotfiles/issues/38)) ([ca02221](https://github.com/Jobikinobi/dotfiles/commit/ca02221f609b4e80b8a238dd0af90f0fce9f24d0))
* **fnm:** quiet loglevel and suppress init stderr on shell startup ([#113](https://github.com/Jobikinobi/dotfiles/issues/113)) ([02e0dc8](https://github.com/Jobikinobi/dotfiles/commit/02e0dc8a89537b3ff05a31b45b7529b2a1e9bad5))
* **fnm:** ship home-level default node version, resolve recursively ([#64](https://github.com/Jobikinobi/dotfiles/issues/64)) ([#106](https://github.com/Jobikinobi/dotfiles/issues/106)) ([d31ac0d](https://github.com/Jobikinobi/dotfiles/commit/d31ac0d269569feb00ca65fb2e8d72befcdffe52))
* **hol-638:** create user 'agent' in cloud-init when --nix-profile agent ([52cf517](https://github.com/Jobikinobi/dotfiles/commit/52cf51734a6918b7b51f3481f3dc9b4d03d19f16))
* multi-distro Linux bootstrap with unified /etc/os-release detection ([#87](https://github.com/Jobikinobi/dotfiles/issues/87)) ([27f871b](https://github.com/Jobikinobi/dotfiles/commit/27f871b420e5afeffe8c545dfc558a5fb2571be2))
* **nix:** set system.primaryUser for nix-darwin system defaults ([a4ad31d](https://github.com/Jobikinobi/dotfiles/commit/a4ad31db77a067ed59b1ccdafe64f9552e9759dd))
* **nix:** set system.primaryUser to fix nix flake check CI ([1c20df0](https://github.com/Jobikinobi/dotfiles/commit/1c20df087c01f59c32812550ca30fd2de6af5858))
* remove leftover merge marker in nix flake ([2ba038f](https://github.com/Jobikinobi/dotfiles/commit/2ba038f7f684b66e34c4d970246b81dee2adf401))
* set darwin user home path for nix home-manager evaluation ([5ed47e4](https://github.com/Jobikinobi/dotfiles/commit/5ed47e4ff0c205e9721fc7dc390c57e6993b40f0))
* **test-profile:** exempt non-brew-owned binaries from formula check (THE-79) ([99875f5](https://github.com/Jobikinobi/dotfiles/commit/99875f50a93cedd5b3ec908617c6e88a87666fd0))
* **test-profile:** hermetic bash -c in matrix gate (THE-79) ([87c8a4a](https://github.com/Jobikinobi/dotfiles/commit/87c8a4a9bd72baa628e088517073a78580160f79))
* **test-profile:** normalize brew which-formula tap prefix (THE-79) ([06d1cf9](https://github.com/Jobikinobi/dotfiles/commit/06d1cf97f6d1aca81ad0d41207b9893d96c4f7c2))
* **test-profile:** require declared binaries to be owned by profile Brewfile (THE-79) ([9045d93](https://github.com/Jobikinobi/dotfiles/commit/9045d93f8964a0c9bb03eadacd135a2fbcfb4a44))
* **test-profile:** use non-login bash to assert IMAGE state (THE-79) ([22755b1](https://github.com/Jobikinobi/dotfiles/commit/22755b1e54abc615891d352d0be0c146e5be13e5))
* **zprofile:** per-OS Homebrew path, guarded ([#62](https://github.com/Jobikinobi/dotfiles/issues/62)) ([#105](https://github.com/Jobikinobi/dotfiles/issues/105)) ([e5c1b73](https://github.com/Jobikinobi/dotfiles/commit/e5c1b734cf0ddfd81f46af18bd612ef50c3b6dea))


### Documentation

* add rough roadmap generated from gh issue backlog (HOL-233) ([3b86c8f](https://github.com/Jobikinobi/dotfiles/commit/3b86c8f51cb0a5e07f9fbcdb7d7acd6004d519d6))
* **adr:** ADR-002 standardize on Netbird; remove Tailscale/Cloudflare/headscale ([#102](https://github.com/Jobikinobi/dotfiles/issues/102)) ([ce36faf](https://github.com/Jobikinobi/dotfiles/commit/ce36fafcf71d9d3be2fecaccaf8fd366faa3bef1))
* **adr:** establish docs/adr/ and record ADR-001 — Doppler standard, reject dotenvx ([#72](https://github.com/Jobikinobi/dotfiles/issues/72)) ([f38e04a](https://github.com/Jobikinobi/dotfiles/commit/f38e04a34242f7b106d887015e5fc24ed7800b77))
* **headscale:** add migration playbook + per-OS recipes (HOL-8) ([66105ee](https://github.com/Jobikinobi/dotfiles/commit/66105ee7848198e17d8ef68f9e38bf74730d239b))
* **headscale:** flip Caddy from target-state to live in architecture.md ([6d5a08f](https://github.com/Jobikinobi/dotfiles/commit/6d5a08f81d718753bc1bd45c8d096b122db7d48d))
* **headscale:** HOL-11 paper + HOL-8 playbook + HOL-12 Caddy flip ([d579af2](https://github.com/Jobikinobi/dotfiles/commit/d579af21cb9f00f0b1732d7b3f8b2c25033d2a7c))
* **headscale:** refresh status after 2026-06-05 batch rollout (HOL-8) ([#48](https://github.com/Jobikinobi/dotfiles/issues/48)) ([045c61f](https://github.com/Jobikinobi/dotfiles/commit/045c61f26ebd4aa0fe4da84d1d0b605e5a972407))
* **homelab:** add NFS corpus mount + Samba Time Machine runbooks ([#112](https://github.com/Jobikinobi/dotfiles/issues/112)) ([a6eb086](https://github.com/Jobikinobi/dotfiles/commit/a6eb086d25dd3ca7c6508800b93a9109c0854934))
* **research:** add Headscale paper evaluation (HOL-11) ([56814aa](https://github.com/Jobikinobi/dotfiles/commit/56814aaaaa83280f51a71d2593d59cbee2d1a693))
* **roadmap:** add [#64](https://github.com/Jobikinobi/dotfiles/issues/64) bugfix/fnm setup to Workstream 1 ([53ef547](https://github.com/Jobikinobi/dotfiles/commit/53ef547caffca523363522eacebf4ca1e006ecd5))


### CI / Automation

* drop macOS runners, run heavy jobs off the PR hot path ([#96](https://github.com/Jobikinobi/dotfiles/issues/96)) ([#97](https://github.com/Jobikinobi/dotfiles/issues/97)) ([a3fefd8](https://github.com/Jobikinobi/dotfiles/commit/a3fefd8192b5360260ff2a236e2af4ecefe55005))
* **nix:** add Linux build job, eval caching, and local smoke-test path (HOL-510) ([#92](https://github.com/Jobikinobi/dotfiles/issues/92)) ([907c8cf](https://github.com/Jobikinobi/dotfiles/commit/907c8cf9fd17995f9e81373a5d38b50f4fc2e287))
* **profiles:** test-profile.sh matrix across {core,legal,godocs,oversight} (THE-72) ([#36](https://github.com/Jobikinobi/dotfiles/issues/36)) ([00d7f8d](https://github.com/Jobikinobi/dotfiles/commit/00d7f8d26739c6ff2fdb6695bcf56d90ad942d25))
* **release:** adopt release-please for automated versioning ([#115](https://github.com/Jobikinobi/dotfiles/issues/115)) ([d333479](https://github.com/Jobikinobi/dotfiles/commit/d33347994b50000bc41566e82c844d3deff1ffd5))
* rootless agent-space verification leg ([#99](https://github.com/Jobikinobi/dotfiles/issues/99)) ([#104](https://github.com/Jobikinobi/dotfiles/issues/104)) ([ee46590](https://github.com/Jobikinobi/dotfiles/commit/ee46590b2fe1f8cbf8ff41d88e2e9e84a218b8f7))

## [1.1.0] and earlier

Releases before automated changelogs were adopted. See the git tags
[`v1.0.0`](https://github.com/Jobikinobi/dotfiles/releases/tag/v1.0.0) and
[`v1.1.0`](https://github.com/Jobikinobi/dotfiles/releases/tag/v1.1.0) and the
commit history for details.
