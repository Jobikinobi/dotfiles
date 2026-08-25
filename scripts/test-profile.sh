#!/usr/bin/env bash
# test-profile.sh — Docker-backed verification gate for chezmoi profiles.
#
# Given a profile key (legal, godocs, oversight, core), builds the existing
# Dockerfile.test with CHEZMOI_PROJECT=<key> baked in, applies chezmoi inside
# the container, then asserts the binaries declared in docs/profiles/<key>.md
# are actually on PATH inside the resulting image.
#
# Usage:
#   scripts/test-profile.sh --project <key> [--branch <branch>]
#                                            [--repository <owner/repo>]
#                                            [--no-cache] [--keep-images]
#
# Exit codes:
#   0   success — image built and every declared binary is on PATH (or, for
#       a docs-only profile, the brew-list diff against core is empty).
#   1   verification failure — at least one declared binary is missing, OR a
#       docs-only profile installed extras beyond the core baseline.
#   2   usage / argument error.
#
# Conventions parsed:
#   docs/profiles/<key>.md must contain a `## Installed binaries` heading
#   followed by a fenced ```text``` block whose contents are one binary name
#   per line. Comment lines (#…) and blank lines are ignored. An empty block
#   marks a "docs-only" profile and triggers the brew-list diff path.
#
# See docs/profiles/README.md#verification for the full convention.
#
# Constraints:
#   - ShellCheck clean.
#   - Pure bash, runs identically on macOS and Linux (CI host).
#   - No Tailscale / Doppler / external network beyond Docker Hub / GHCR.
#   - Build cache is reused across profile keys by default; --no-cache opts
#     out per invocation.

set -euo pipefail

PROG="$(basename "$0")"
IMAGE_PREFIX="dotfiles-test"

err() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { err "$*"; exit 2; }

usage() {
  cat >&2 <<EOF
Usage: $PROG --project <key> [--branch <branch>] [--repository <owner/repo>]
                    [--no-cache] [--keep-images]

Required:
  --project <key>   Profile key to validate. Must be one of:
                      - "core" (baseline build only)
                      - or a populated profile (\$repo_root/dot_Brewfile.<key>
                        + docs/profiles/<key>.md must both exist)

Optional:
  --branch <ref>    Chezmoi branch to clone inside the image (default: main).
                    Pushed to Docker as --build-arg CHEZMOI_BRANCH=<ref>.
                    Useful for iterating on a feature branch before merge.
  --repository <owner/repo>
                    GitHub repository containing --branch (default:
                    Jobikinobi/dotfiles). Pushed to Docker as
                    --build-arg CHEZMOI_REPOSITORY=<owner/repo>.
  --no-cache        Pass --no-cache to docker build. By default the build
                    cache is reused so reruns across profiles are fast.
  --keep-images     Skip the rmi of intermediate images at the end. Handy
                    for poking around with \`docker run -it\`.
  -h, --help        Show this help and exit.

Examples:
  $PROG --project legal
  $PROG --project godocs --branch feat/godocs-cleanup
  $PROG --project oversight       # asserts docs-only invariant
  $PROG --project core            # baseline build, no per-profile asserts
EOF
}

# ── argument parsing ────────────────────────────────────────────────────────
project=""
branch="main"
repository="Jobikinobi/dotfiles"
no_cache=0
keep_images=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "--project requires a value"
      project="$2"; shift 2 ;;
    --project=*)
      project="${1#--project=}"; shift ;;
    --branch)
      [[ $# -ge 2 ]] || die "--branch requires a value"
      branch="$2"; shift 2 ;;
    --branch=*)
      branch="${1#--branch=}"; shift ;;
    --repository)
      [[ $# -ge 2 ]] || die "--repository requires a value"
      repository="$2"; shift 2 ;;
    --repository=*)
      repository="${1#--repository=}"; shift ;;
    --no-cache)
      no_cache=1; shift ;;
    --keep-images)
      keep_images=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      err "unknown argument: $1"
      usage
      exit 2
      ;;
  esac
done

[[ -n "$project" ]] || { err "--project is required"; usage; exit 2; }

# Profile key shape: lowercase, kebab-case, ≤12 chars, starts with a letter.
# Matches the convention used in docs/profiles/README.md and provision-lxd.sh.
if ! [[ "$project" =~ ^[a-z][a-z0-9-]{0,11}$ ]]; then
  die "invalid --project '$project': must be lowercase kebab-case, ≤12 chars, start with a letter"
fi

# Branch is fed into Docker as a build-arg and into shell error messages.
# Reject anything that isn't a plausible git ref (letters, digits, -, _, /, .).
if ! [[ "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  die "invalid --branch '$branch': only A-Za-z0-9._/- are allowed"
fi

if ! [[ "$repository" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  die "invalid --repository '$repository': expected GitHub owner/repository"
fi

# ── resolve repo root + validate profile artifacts ──────────────────────────
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
dockerfile="$repo_root/Dockerfile.test"

[[ -f "$dockerfile" ]] || die "missing $dockerfile (expected at repo root)"

if [[ "$project" == "core" ]]; then
  doc=""   # core has no per-profile doc; baseline build only
else
  brewfile="$repo_root/dot_Brewfile.$project"
  doc="$repo_root/docs/profiles/$project.md"
  if [[ ! -f "$brewfile" ]]; then
    err "unknown profile '$project': expected $brewfile (not found)."
    err "Existing profiles:"
    for f in "$repo_root"/dot_Brewfile.*; do
      [[ -f "$f" ]] || continue
      key="${f##*/dot_Brewfile.}"
      case "$key" in
        core|save) ;;  # not a project profile
        *) printf '  - %s\n' "$key" >&2 ;;
      esac
    done
    exit 2
  fi
  if [[ ! -f "$doc" ]]; then
    die "profile '$project' is missing its doc at $doc; the verification convention requires it"
  fi
fi

command -v docker >/dev/null 2>&1 || die "docker is not on PATH"
docker info >/dev/null 2>&1 \
  || die "docker daemon is not reachable (does 'docker info' succeed?)"

# ── parse the "Installed binaries" block from the profile doc ──────────────
# Convention (see docs/profiles/README.md#verification):
#   ## Installed binaries
#   <prose>
#   ```text
#   binary1
#   binary2
#   # comment, ignored
#   ```
# We grab the first ```text fence following the heading and strip comments
# + blank lines. awk is more robust than grep -A for fenced blocks because
# it tracks state across line boundaries.
parse_binaries() {
  local doc_path="$1"
  awk '
    /^## Installed binaries[[:space:]]*$/ { in_section = 1; next }
    in_section && /^## / { exit }                # next H2 ends the section
    in_section && /^```text[[:space:]]*$/ { in_fence = 1; next }
    in_section && in_fence && /^```/ { exit }
    in_section && in_fence {
      line = $0
      sub(/#.*/, "", line)                       # strip trailing/whole-line comments
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) > 0) print line
    }
  ' "$doc_path"
}

declared_binaries=()
if [[ -n "$doc" ]]; then
  # mapfile is portable across bash 4+ (macOS ships 3; we assume the script
  # runs on bash from Homebrew or Ubuntu CI where ≥4 is the norm). Fall back
  # to a read loop for safety on older shells.
  if (( BASH_VERSINFO[0] >= 4 )); then
    mapfile -t declared_binaries < <(parse_binaries "$doc")
  else
    while IFS= read -r line; do
      declared_binaries+=("$line")
    done < <(parse_binaries "$doc")
  fi
fi

# Empty list (zero binaries declared) means the profile is docs-only — we
# verify it by diffing brew formulae against a fresh core build. Only the
# `core` build itself is treated as "no asserts, just build".
docs_only_invariant=0
if [[ "$project" != "core" && ${#declared_binaries[@]} -eq 0 ]]; then
  docs_only_invariant=1
fi

# ── helpers ─────────────────────────────────────────────────────────────────
# Image tag for a given project key. "" → core baseline.
image_tag() {
  local key="${1:-core}"
  printf '%s:%s' "$IMAGE_PREFIX" "$key"
}

# Build Dockerfile.test for a given project key (empty → core baseline).
# Layers stay cached across keys for everything before the ARG declarations.
build_image() {
  local key="$1"
  local tag
  tag="$(image_tag "$key")"
  local -a args=()
  args+=(build)
  (( no_cache )) && args+=(--no-cache)
  args+=(-f "$dockerfile")
  args+=(--build-arg "CHEZMOI_BRANCH=$branch")
  args+=(--build-arg "CHEZMOI_REPOSITORY=$repository")
  if [[ -n "$key" && "$key" != "core" ]]; then
    args+=(--build-arg "CHEZMOI_PROJECT=$key")
  else
    # Explicitly passing the empty value keeps the build-arg in the build
    # graph so cache keys stay stable between "no project" and "project=foo".
    args+=(--build-arg "CHEZMOI_PROJECT=")
  fi
  args+=(-t "$tag")
  args+=("$repo_root")
  printf '%s: building %s (repository=%s branch=%s)\n' "$PROG" "$tag" "$repository" "$branch" >&2
  docker "${args[@]}" >&2
  printf '%s\n' "$tag"
}

# Run a one-shot command in the built image. The default ENTRYPOINT is
# entrypoint.sh which starts tailscaled/sshd; we bypass it explicitly.
#
# IMPORTANT: we deliberately use `bash -c` (NOT `bash -lc`). A login shell
# sources /etc/profile and ~/.bash_profile, both of which can mutate the
# binary-resolution environment in ways that mask the IMAGE'S real state:
#   - dot_bash_profile unconditionally prepends /Users/jth/micromamba/bin
#     (a stale macOS path) and sources $HOME/.cargo/env (PATH-augmenting).
#   - dot_bashrc prepends /opt/homebrew/opt/postgresql@15/bin (macOS path).
#   - Future operator-installed rc snippets could alias or shadow binary
#     names (see THE-79 for the original false-negative report — a login
#     shell made `command -v tesseract` succeed even when brew bundle had
#     not installed it, breaking the matrix gate's credibility).
# A non-login shell inherits PATH from the Dockerfile's ENV, which is the
# ground truth we want the matrix to assert against. Callers that need
# brew on PATH must eval shellenv themselves (see brew_formulae_in_image).
run_in_image() {
  local tag="$1"; shift
  docker run --rm --entrypoint /bin/bash "$tag" -c "$*"
}

# brew list --formula inside the image, sorted. Wraps the shellenv eval so
# brew is on PATH regardless of which user the container defaults to. The
# $(...) expansion is intentionally evaluated *inside* the container, hence
# the single-quoted body (and the SC2016 disable).
brew_formulae_in_image() {
  local tag="$1"
  # shellcheck disable=SC2016
  run_in_image "$tag" '
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    brew list --formula 2>/dev/null | LC_ALL=C sort -u
  '
}

# Hermetic binary-presence check used by the populated-profile assertion.
# Wraps `command -v` in a non-login bash and adds the brew prefix to PATH
# without sourcing any user rc files. Returns 0 if the binary resolves,
# non-zero otherwise. Suppresses stdout/stderr — callers only inspect $?.
binary_on_path_in_image() {
  local tag="$1" bin="$2"
  # shellcheck disable=SC2016
  run_in_image "$tag" '
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    command -v '"$(printf '%q' "$bin")"' >/dev/null 2>&1
  '
}

# Resolve the brew formula that owns a given binary in the image. Uses
# `brew which-formula --explain` for accuracy. Prints the formula name on
# stdout (empty string if no formula matches), and always returns 0. This
# is the load-bearing check for THE-79: the matrix gate must verify that
# the binary's source formula is the one declared in dot_Brewfile.<profile>,
# not just that the binary happens to be on PATH (it can arrive via
# transitive dependencies of unrelated formulas or npm/post-install hooks
# — see THE-79 evidence comment for the regression that motivated this).
formula_for_binary_in_image() {
  local tag="$1" bin="$2"
  # shellcheck disable=SC2016
  run_in_image "$tag" '
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    bin='"$(printf '%q' "$bin")"'
    # First try `brew which-formula` (fast, tap-aware). Fall back to walking
    # the symlink under $HOMEBREW_PREFIX/bin to its Cellar parent dir name,
    # which is the canonical (formula, version) tuple.
    out="$(brew which-formula "$bin" 2>/dev/null | head -1)"
    if [ -n "$out" ]; then
      # `brew which-formula` returns the tap-qualified name (user/tap/foo) for
      # tap formulae; strip the prefix so the comparison matches the basenames
      # produced by formulas_in_brewfile() and the Cellar-walk fallback below.
      printf "%s\n" "${out##*/}"
    else
      target="$(readlink -f "/home/linuxbrew/.linuxbrew/bin/$bin" 2>/dev/null)"
      if [ -n "$target" ]; then
        # /home/linuxbrew/.linuxbrew/Cellar/<formula>/<version>/bin/<bin>
        printf "%s\n" "$target" | awk -F/ "{ for(i=1;i<=NF;i++) if(\$i==\"Cellar\") { print \$(i+1); exit } }"
      fi
    fi
  ' 2>/dev/null | tr -d '[:space:]'
}

# Parse `brew "X"` formula declarations from a Brewfile. Skips commented
# lines, `tap` / `cask` / `vscode` lines, and inline comments. Returns one
# formula name per line on stdout.
formulas_in_brewfile() {
  local brewfile_path="$1"
  [[ -f "$brewfile_path" ]] || return 0
  # Match: optional whitespace, then `brew "..."`. Capture the quoted name.
  # Ignore lines whose first non-whitespace character is `#`.
  awk '
    /^[[:space:]]*#/ { next }                       # full-line comment
    {
      sub(/[[:space:]]*#.*/, "")                    # strip inline comment
      if (match($0, /^[[:space:]]*brew[[:space:]]+"[^"]+"/)) {
        line = substr($0, RSTART, RLENGTH)
        if (match(line, /"[^"]+"/)) {
          name = substr(line, RSTART+1, RLENGTH-2)
          # strip optional tap prefix (e.g., "supabase/tap/supabase")
          n = split(name, parts, "/")
          print parts[n]
        }
      }
    }
  ' "$brewfile_path"
}

# Diagnostic dump used when a binary-presence assertion FAILS or appears
# anomalous. Prints (a) the PATH the test saw, (b) all hits along PATH
# (`which -a`), (c) what `type -a` thinks the name refers to (alias,
# function, builtin, file), (d) whether a matching file exists under the
# Homebrew prefix, and (e) any brew formula matching the name. Together
# these answer "if the gate fired wrong, where did the false signal come
# from?" without a second CI round-trip.
diagnose_binary_in_image() {
  local tag="$1" bin="$2"
  printf '%s: diagnostic for "%s" in %s:\n' "$PROG" "$bin" "$tag" >&2
  # shellcheck disable=SC2016
  run_in_image "$tag" '
    if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
    bin='"$(printf '%q' "$bin")"'
    printf "    PATH=%s\n" "$PATH"
    printf "    which -a:\n"; which -a "$bin" 2>&1 | sed "s/^/      /" || true
    printf "    type -a:\n";  type -a  "$bin" 2>&1 | sed "s/^/      /" || true
    printf "    ls -la \$HOMEBREW_PREFIX/bin/%s:\n" "$bin"
    ls -la "/home/linuxbrew/.linuxbrew/bin/$bin" 2>&1 | sed "s/^/      /" || true
    printf "    brew list --formula | grep -i %s:\n" "$bin"
    brew list --formula 2>/dev/null | grep -i "$bin" | sed "s/^/      /" || printf "      (no match)\n"
  ' >&2 || true
}

# Cleanup intermediate images unless --keep-images was set.
cleanup_images() {
  (( keep_images )) && return 0
  local key
  for key in "$@"; do
    local tag
    tag="$(image_tag "$key")"
    docker image rm "$tag" >/dev/null 2>&1 || true
  done
}

# ── run ─────────────────────────────────────────────────────────────────────
built_keys=()

if [[ "$project" == "core" ]]; then
  # Baseline build only — exercises the no-project path through Dockerfile.test.
  build_image "core" >/dev/null
  built_keys+=("core")
  printf '%s: ✓ core baseline image built (no per-profile asserts).\n' "$PROG"
  cleanup_images "${built_keys[@]}"
  exit 0
fi

# Populated profile or docs-only profile: build the profile image first.
build_image "$project" >/dev/null
built_keys+=("$project")
profile_tag="$(image_tag "$project")"

failed=0

if (( docs_only_invariant )); then
  # Docs-only invariant: build core too, diff brew formulae. Any extra
  # formula in the profile image is a test failure — the doc declared none.
  build_image "core" >/dev/null
  built_keys+=("core")
  core_tag="$(image_tag "core")"

  printf '%s: comparing brew formulae (%s vs core) for docs-only invariant\n' \
    "$PROG" "$project" >&2

  core_list="$(brew_formulae_in_image "$core_tag")"
  profile_list="$(brew_formulae_in_image "$profile_tag")"

  extras="$(comm -23 \
    <(printf '%s\n' "$profile_list") \
    <(printf '%s\n' "$core_list") )"

  if [[ -n "$extras" ]]; then
    err "✗ profile '$project' is declared docs-only but installed extras vs core:"
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '    - %s\n' "$line" >&2
    done <<< "$extras"
    err "Either add these binaries to docs/profiles/$project.md's"
    err "'Installed binaries' block, or drop them from dot_Brewfile.$project."
    failed=1
  else
    printf '%s: ✓ profile %s installs nothing beyond core baseline.\n' \
      "$PROG" "$project"
  fi
else
  # Populated profile: for each declared binary assert BOTH
  #   (1) the binary is on PATH (integration smoke test), and
  #   (2) the formula that owns the binary is explicitly declared in
  #       dot_Brewfile.<profile>.
  #
  # (2) is the load-bearing check. THE-79 demonstrated that (1) alone is a
  # false-positive risk: binaries can arrive in the image via transitive
  # dependencies of unrelated formulas or npm post-install hooks, so a
  # profile that removes `brew "tesseract"` from its Brewfile still passed
  # the old gate because tesseract was being installed as a side effect of
  # other tooling. The matrix gate is only credible if it verifies the
  # profile's Brewfile is the path of record for each promised binary.
  #
  # `brew which-formula` is the authoritative answer for "which formula
  # owns this binary"; formulas_in_brewfile() is the simple `brew "X"`
  # parser for the profile Brewfile.
  printf '%s: asserting %d binar%s on PATH AND declared in dot_Brewfile.%s inside %s:\n' \
    "$PROG" "${#declared_binaries[@]}" \
    "$( [[ ${#declared_binaries[@]} -eq 1 ]] && printf y || printf ies )" \
    "$project" "$profile_tag"

  declared_formulas_file="$(mktemp)"
  trap 'rm -f "$declared_formulas_file"' EXIT
  formulas_in_brewfile "$brewfile" | LC_ALL=C sort -u > "$declared_formulas_file"

  missing=()
  unowned=()
  for bin in "${declared_binaries[@]}"; do
    on_path=0
    declared=0
    if binary_on_path_in_image "$profile_tag" "$bin"; then
      on_path=1
    fi

    # Three-way ownership resolution:
    #   - formula non-empty AND in Brewfile  → brew-owned + declared (✓)
    #   - formula non-empty AND NOT in Brewfile → brew-owned but undeclared (THE-79 leak)
    #   - formula empty → binary is not brew-owned (apt-installed by run_once,
    #     system binary, npm global, etc). On-PATH is the only contract we can
    #     enforce; skip the brew-attribution check. The classic example is
    #     `soffice` in the godocs profile — LibreOffice has no Linuxbrew formula
    #     and is intentionally apt-installed by the run_once script, with the
    #     docs noting it explicitly. THE-79's failure mode (binary leaked via
    #     a transitive brew dep) can only occur when the binary IS brew-owned,
    #     so this exemption does not weaken the attribution check.
    formula="$(formula_for_binary_in_image "$profile_tag" "$bin")"
    if [[ -z "$formula" ]]; then
      declared=1
    elif grep -qxF "$formula" "$declared_formulas_file"; then
      declared=1
    fi

    if (( on_path && declared )); then
      if [[ -n "$formula" ]]; then
        printf '  ✓ %s (formula=%s)\n' "$bin" "$formula"
      else
        printf '  ✓ %s (non-brew, on PATH)\n' "$bin"
      fi
    elif (( ! on_path )); then
      printf '  ✗ %s (not on PATH)\n' "$bin" >&2
      diagnose_binary_in_image "$profile_tag" "$bin"
      missing+=("$bin")
    else
      # On PATH AND brew-owned, but the owning formula is not in
      # dot_Brewfile.<profile>. This is the THE-79 failure mode: the binary
      # is present via a transitive brew dependency or another profile's
      # install, not because this profile's Brewfile asked for it.
      printf '  ✗ %s (on PATH, but owning formula "%s" is NOT declared in dot_Brewfile.%s)\n' \
        "$bin" "$formula" "$project" >&2
      diagnose_binary_in_image "$profile_tag" "$bin"
      unowned+=("$bin")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    err "✗ profile '$project' is missing ${#missing[@]} declared binar$( [[ ${#missing[@]} -eq 1 ]] && printf y || printf ies ) on PATH:"
    for m in "${missing[@]}"; do printf '    - %s\n' "$m" >&2; done
    err "Either fix dot_Brewfile.$project / run_once_after_install-project-$project.sh.tmpl"
    err "to put these on PATH, or remove them from docs/profiles/$project.md's"
    err "'Installed binaries' block if they are not actually promised."
    failed=1
  fi

  if (( ${#unowned[@]} > 0 )); then
    err "✗ profile '$project' has ${#unowned[@]} declared binar$( [[ ${#unowned[@]} -eq 1 ]] && printf y || printf ies ) whose owning brew formula is NOT in dot_Brewfile.$project:"
    for u in "${unowned[@]}"; do printf '    - %s\n' "$u" >&2; done
    err "The binar$( [[ ${#unowned[@]} -eq 1 ]] && printf y || printf ies ) appear$( [[ ${#unowned[@]} -eq 1 ]] && printf s || printf '' ) on PATH only because"
    err "of a transitive dependency or side-channel install (npm postinstall,"
    err "another profile, etc.). Add an explicit \`brew \"<formula>\"\` line to"
    err "dot_Brewfile.$project so this profile actually owns the install."
    failed=1
  fi
fi

cleanup_images "${built_keys[@]}"

if (( failed )); then
  exit 1
fi

printf '%s: ✓ profile %s verified.\n' "$PROG" "$project"
exit 0
