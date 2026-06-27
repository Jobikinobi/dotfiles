# Nix CI contract

How the Nix layer is validated in CI and locally.

## CI jobs (`.github/workflows/ci.yml`)

| Job | Runner | What it checks |
|---|---|---|
| `nix-flake-check` | `macos-latest` | Evaluates all flake outputs (`--no-build`). Catches syntax errors, missing attrs, eval errors. Validates both `darwinConfigurations` and `homeConfigurations`. |
| `nix-agent-linux-build` | `ubuntu-latest` | Builds `homeConfigurations.agent-linux.activationPackage` on a native x86_64-linux runner. Proves packages download and assemble correctly on Linux. |

### What is NOT run in CI

- **`darwin-rebuild switch`** — building the full `darwinConfigurations."joes-macbook"` derivation in CI is not done. macOS GitHub Actions runners are expensive (~10× Linux cost) and a full nix-darwin build takes 30+ minutes. The `--no-build` eval on macOS is sufficient to catch nix expression errors. Physical mac applies are the acceptance gate for darwin configs.

- **`joe-linux` build** — `homeConfigurations."joe-linux"` is added to the matrix when that configuration lands on `main`. It is currently defined on a feature branch.

### Caching strategy

Both nix jobs cache `~/.cache/nix` (the Nix evaluation cache) keyed on `nix/flake.lock`. This avoids re-evaluating the full nixpkgs attribute tree on every run. Binary packages are fetched from `cache.nixos.org` (the default Nix substituter) — no additional binary cache is configured.

To add a binary cache (e.g. Cachix), set `extra-substituters` in `nix/nix.conf` and add the public key to `extra-trusted-public-keys`. This requires no secrets if the cache is public.

## Local smoke tests (`scripts/test-profile.sh --nix-profile`)

Run the Linux activation build locally:

```bash
# Requires nix on PATH
scripts/test-profile.sh --nix-profile agent-linux
```

This is the local equivalent of the `nix-agent-linux-build` CI job. It builds `homeConfigurations.agent-linux.activationPackage` from `nix/flake.nix` without activating.

For verbose build output on failure:

```bash
nix build ./nix#homeConfigurations.agent-linux.activationPackage -L
```

## Adding a new Nix profile to CI

1. Add the `homeConfigurations."<key>"` output to `nix/flake.nix`.
2. Add `<key>` to the `matrix.profile` list in the `nix-agent-linux-build` job in `.github/workflows/ci.yml`.
3. Verify locally: `scripts/test-profile.sh --nix-profile <key>`.
4. Open a PR — both `nix-flake-check` and `nix-agent-linux-build` must pass.

For `darwinConfigurations`, the `nix-flake-check` job validates them automatically. No separate CI step is added unless full build validation is later deemed necessary.
