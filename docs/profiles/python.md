# `python` profile

Generic chezmoi profile for **Python application and data-science projects**. Adds a quality-tooling layer on top of the core stack (`uv`, `pyenv`, `direnv`, `doppler`) without pinning specific Python versions or project dependencies — those are per-repo concerns.

Activate by adding `"python"` to the `projects` list in `~/.config/chezmoi/chezmoi.toml`, then re-run `chezmoi apply`. With `projects = []` the profile is a no-op.

## What this profile installs

Brews from [`dot_Brewfile.python`](../../dot_Brewfile.python):

| Package | Binary | Purpose |
|---|---|---|
| `ruff` | `ruff` | All-in-one Python linter + formatter — replaces flake8/black/isort. Configured via `pyproject.toml` or `ruff.toml`. |
| `pre-commit` | `pre-commit` | Git hook framework. Run `pre-commit install` once per repo to wire linting into the commit cycle. |
| `httpie` | `http`, `https` | Human-friendly HTTP client for interactive API development and debugging. |

Already provided by [`dot_Brewfile.core`](../../dot_Brewfile.core) and therefore not duplicated here: `uv`, `pyenv`, `direnv`, `doppler`, `git`, `gh`, `jq`, `fd`, `ripgrep`, `helix`, `fnm`.

## Installed binaries

[`scripts/test-profile.sh`](../../scripts/test-profile.sh) asserts each entry below is on `PATH` inside an applied container. Binary names, not formula names. Comment lines and blank lines are ignored.

```text
ruff
pre-commit
http
```

## Quick start

```bash
# New project
uv init my-project && cd my-project
uv add <dep>          # add a dependency (updates pyproject.toml + uv.lock)
pre-commit install    # wire ruff/mypy/etc. into git commit hooks

# Pin a Python version per repo
pyenv install 3.12.4
pyenv local 3.12.4    # writes .python-version (respected by uv)

# Existing project
git clone git@github.com:... && cd ...
uv sync               # installs all deps from uv.lock
pre-commit install    # set up hooks
```

## What you must do manually

This profile intentionally stops short of any step that requires credentials or project-specific context:

1. **Log in to Doppler** (if your project uses Doppler for secrets):
   ```bash
   doppler login
   doppler setup --project <your-project> --config dev
   ```

2. **Set a Python version** in each repo:
   ```bash
   pyenv install 3.12.4   # or whichever version the project requires
   pyenv local 3.12.4
   ```

3. **Sync the project's dependencies**:
   ```bash
   uv sync    # or: pip install -e ".[dev]" for legacy projects
   ```

## Notes

- **No pinned Python version:** `pyenv` lets you install multiple versions and activate them per-directory. The profile does not set a global version.
- **`ruff` replaces black + flake8 + isort:** if an existing repo already uses those, you may want to keep them in the project's own dev-dependencies rather than relying on the profile brew.
- **`httpie` vs `curl`:** `httpie` shines for interactive exploration; use `curl` in scripts for portability.
