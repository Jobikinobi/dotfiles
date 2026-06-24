#!/usr/bin/env bash
# test-workspace-dirs.sh — Verification tests for the workspace directory
# provisioning script and related gitignore patterns introduced in
# feat/hol-505-workspace-layout.
#
# Tests:
#   1. run_once_after_create-workspace-dirs.sh.tmpl — creates canonical dirs
#   2. .gitignore — .worktrees pattern
#   3. dot_config/git/ignore — scratch/ and **/.claude/settings.local.json
#
# Usage:
#   scripts/test-workspace-dirs.sh
#
# Exit codes:
#   0   all tests passed
#   1   one or more tests failed
#
# Constraints:
#   - ShellCheck clean.
#   - Pure bash, runs identically on macOS and Linux.
#   - No external dependencies beyond coreutils and git.

set -euo pipefail

PROG="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_SCRIPT="$REPO_ROOT/run_once_after_create-workspace-dirs.sh.tmpl"
GITIGNORE="$REPO_ROOT/.gitignore"
GLOBAL_IGNORE="$REPO_ROOT/dot_config/git/ignore"

# ── helpers ──────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() { printf '  ✓ %s\n' "$*"; (( PASS++ )) || true; }
fail() { printf '  ✗ %s\n' "$*" >&2; (( FAIL++ )) || true; }

assert_dir() {
  local dir="$1" label="${2:-$1}"
  if [[ -d "$dir" ]]; then
    pass "$label exists"
  else
    fail "$label missing — expected directory at $dir"
  fi
}

assert_not_dir() {
  local dir="$1" label="${2:-$1}"
  if [[ ! -d "$dir" ]]; then
    pass "$label not present (correct)"
  else
    fail "$label should not exist at $dir"
  fi
}

assert_exit_zero() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$label exits 0"
  else
    fail "$label exited non-zero"
  fi
}

assert_output_contains() {
  local label="$1" pattern="$2"; shift 2
  local output
  output="$("$@" 2>&1)"
  if echo "$output" | grep -qF "$pattern"; then
    pass "$label output contains '$pattern'"
  else
    fail "$label output missing '$pattern' (got: $output)"
  fi
}

# Returns 0 if the given path matches the pattern in the given gitignore file,
# 1 otherwise. Uses git check-ignore with an isolated index.
gitignore_matches() {
  local ignore_file="$1" path="$2"
  # Run git check-ignore from a temp repo so the ignore file is the only one
  # in scope. We copy the ignore file into the temp repo's .gitignore.
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN
  git -C "$tmpdir" init -q
  cp "$ignore_file" "$tmpdir/.gitignore"
  # Create the path inside the temp repo so git check-ignore can evaluate it.
  # Always create as a directory: gitignore directory patterns (e.g. scratch/)
  # only match directories, so using mkdir -p gives consistent semantics for
  # both file-like and dir-like paths.
  local full_path="$tmpdir/$path"
  mkdir -p "$full_path"
  git -C "$tmpdir" check-ignore -q "$path" 2>/dev/null
}

assert_ignored() {
  local label="$1" ignore_file="$2" path="$3"
  if gitignore_matches "$ignore_file" "$path"; then
    pass "$label: '$path' is ignored"
  else
    fail "$label: '$path' should be ignored but is not"
  fi
}

assert_not_ignored() {
  local label="$1" ignore_file="$2" path="$3"
  if ! gitignore_matches "$ignore_file" "$path"; then
    pass "$label: '$path' is not ignored (correct)"
  else
    fail "$label: '$path' should NOT be ignored but is"
  fi
}

# ── test suite ────────────────────────────────────────────────────────────────

run_workspace_script_tests() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  printf '\nWorkspace dir script (%s)\n' "$WORKSPACE_SCRIPT"

  # T1: script file exists and is executable (or interpretable by sh)
  if [[ -f "$WORKSPACE_SCRIPT" ]]; then
    pass "T1: script file exists"
  else
    fail "T1: script file not found at $WORKSPACE_SCRIPT"
    return
  fi

  # T2: script exits 0 in a fresh HOME
  local fake_home="$tmpdir/home"
  mkdir -p "$fake_home"
  if HOME="$fake_home" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1; then
    pass "T2: script exits 0 in fresh HOME"
  else
    fail "T2: script exited non-zero in fresh HOME"
  fi

  # T3–T9: each of the 7 canonical directories is created
  local expected_dirs=(
    "projects/gh"
    "projects/local"
    "docs/notes"
    "docs/references"
    "apps"
    "bin"
    "scratch"
  )
  local i=3
  for d in "${expected_dirs[@]}"; do
    assert_dir "$fake_home/$d" "T$i: ~/\$d"
    (( i++ )) || true
  done

  # T10: success message is printed to stdout
  local output
  local fake_home2="$tmpdir/home2"
  mkdir -p "$fake_home2"
  output="$(HOME="$fake_home2" sh "$WORKSPACE_SCRIPT" 2>&1)"
  if echo "$output" | grep -q "workspace dirs ready"; then
    pass "T10: stdout contains 'workspace dirs ready'"
  else
    fail "T10: stdout missing 'workspace dirs ready' (got: $output)"
  fi

  # T11: idempotency — running twice in the same HOME exits 0 and produces the
  # same directory set (mkdir -p must not error on existing dirs)
  local fake_home3="$tmpdir/home3"
  mkdir -p "$fake_home3"
  HOME="$fake_home3" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1 || true
  if HOME="$fake_home3" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1; then
    pass "T11: idempotent — second run exits 0"
  else
    fail "T11: second run exited non-zero (not idempotent)"
  fi

  # T12: idempotency — directories still present after second run
  for d in "${expected_dirs[@]}"; do
    assert_dir "$fake_home3/$d" "T12: ~/\$d still present after second run"
    break  # spot-check one representative directory to keep output terse
  done

  # T13: partial pre-existing tree — if some dirs already exist, no error
  local fake_home4="$tmpdir/home4"
  mkdir -p "$fake_home4/projects/gh" "$fake_home4/bin"
  if HOME="$fake_home4" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1; then
    pass "T13: runs cleanly when some dirs pre-exist"
  else
    fail "T13: exited non-zero with partially pre-existing tree"
  fi

  # T14: all expected dirs present even when starting from partial tree
  for d in "${expected_dirs[@]}"; do
    assert_dir "$fake_home4/$d" "T14: ~/\$d created from partial tree"
  done

  # T15: nested dirs are created in a single pass (projects/gh requires parent
  # projects/ to be created implicitly by mkdir -p)
  local fake_home5="$tmpdir/home5"
  mkdir -p "$fake_home5"
  HOME="$fake_home5" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1
  assert_dir "$fake_home5/projects" "T15: parent projects/ created by mkdir -p"
  assert_dir "$fake_home5/docs"     "T15: parent docs/ created by mkdir -p"

  # T16: regression — scratch/ is created at the HOME level, not nested
  local fake_home6="$tmpdir/home6"
  mkdir -p "$fake_home6"
  HOME="$fake_home6" sh "$WORKSPACE_SCRIPT" >/dev/null 2>&1
  assert_dir "$fake_home6/scratch" "T16: scratch/ at \$HOME level"
  assert_not_dir "$fake_home6/projects/scratch" "T16: scratch/ not nested under projects/"
}

run_gitignore_worktrees_tests() {
  printf '\n.gitignore — .worktrees pattern\n'

  # T17: .worktrees directory is ignored by .gitignore
  assert_ignored "T17" "$GITIGNORE" ".worktrees"

  # T18: a file inside .worktrees is also matched (directory rule covers contents)
  assert_ignored "T18" "$GITIGNORE" ".worktrees/some-branch"

  # T19: a similarly-named but distinct path is NOT ignored
  # (e.g. a file called worktrees without the dot should not be caught)
  assert_not_ignored "T19" "$GITIGNORE" "worktrees"

  # T20: regression — Dockerfile.test (pre-existing pattern) still ignored
  assert_ignored "T20" "$GITIGNORE" "Dockerfile.test"
}

run_global_ignore_tests() {
  printf '\ndot_config/git/ignore — global gitignore patterns\n'

  # T21: scratch/ at repo root is ignored
  assert_ignored "T21" "$GLOBAL_IGNORE" "scratch"

  # T22: scratch/anything is ignored (directory rule)
  assert_ignored "T22" "$GLOBAL_IGNORE" "scratch/notes.txt"

  # T23: .claude/settings.local.json at root is ignored
  assert_ignored "T23" "$GLOBAL_IGNORE" ".claude/settings.local.json"

  # T24: nested .claude/settings.local.json is ignored (** glob)
  assert_ignored "T24" "$GLOBAL_IGNORE" "some/project/.claude/settings.local.json"

  # T25: .claude/settings.json (not settings.local.json) is NOT ignored
  assert_not_ignored "T25" "$GLOBAL_IGNORE" ".claude/settings.json"

  # T26: .claude/settings.local.json.bak is NOT ignored
  assert_not_ignored "T26" "$GLOBAL_IGNORE" ".claude/settings.local.json.bak"

  # T27: a file named settings.local.json NOT inside .claude/ is NOT ignored
  assert_not_ignored "T27" "$GLOBAL_IGNORE" ".other/settings.local.json"

  # T28: regression — scratch at a nested path should also be ignored
  assert_ignored "T28" "$GLOBAL_IGNORE" "scratch/subdir/file.txt"
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  printf 'test-workspace-dirs.sh — workspace layout tests\n'
  printf '%s\n' "$(printf '─%.0s' {1..50})"

  run_workspace_script_tests
  run_gitignore_worktrees_tests
  run_global_ignore_tests

  printf '\n%s\n' "$(printf '─%.0s' {1..50})"
  printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"

  if [[ "$FAIL" -gt 0 ]]; then
    printf '%s: FAIL\n' "$PROG" >&2
    exit 1
  fi
  printf '%s: PASS\n' "$PROG"
}

main "$@"
