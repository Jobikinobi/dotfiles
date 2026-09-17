# Open PR Merge Queue — Clear the Backlog

**Goal:** Get the 8 open PRs on `Jobikinobi/dotfiles` either merged to `main` or
explicitly closed/superseded, in an order that keeps `main` green and avoids
re-work from stacked CI.

**Scope decision (confirmed with user):** full merge-queue DAG with per-PR
actions, including 138's off-topic branch, plus the branch-protection gate.

---

## 1. Current state (verified 2026-09-17)

All CI is green everywhere. Nothing is failing. The blockers are structural, not
broken code.

| PR | Branch | Title | CI | Merge state | Real issue |
|----|--------|-------|----|-------------|------------|
| 131 | `release-please--branches--main` | chore(main): release 1.2.1 | ✅ CLEAN | MERGEABLE | release-please PR; merges cleanly |
| 129 | `copilot/fix-macos-unblock-deploy-before-phase-nix-install` | fix(macos): unblock deploy | ✅ CLEAN | MERGEABLE | needs maintainer approval |
| 138 | `update/remove-deprecated-ssh-hosts` | ssh-hosts-update | ✅ (CodeRabbit skipped) | MERGEABLE / **BLOCKED** | **branch content is GPU passthrough, not SSH**; blocked gate |
| 132 | `fix/ssh-lan-renumber-10-0-0` | fix(ssh,nix): 10.0.0.0/24 renumber … | ✅ all pass | MERGEABLE / **BEHIND** | **stale base** — needs update; pushes 2074 files incl. ~2000 `assets/*.js` |
| 134 | `feat/age-encrypted-secrets` | feat(secrets): age-encrypt credentials | ✅ all pass | **BEHIND** | stale base; closes #29; touches `.chezmoiignore` **and** 132 also touches it |
| 126 | `feat/tailscale-policy` | feat(tailscale): tailscale.json as source of truth | ✅ all pass | **BEHIND** | stale base; 1 file |
| 127 | `chore/gitignore-hardening` | chore(gitignore): ignore agent worktrees … | ✅ all pass | **BEHIND** | stale base; 1 file |
| 119 | `feat/incus-test-harness-114` | feat(scripts): ephemeral-Incus deployment test rig | ✅ all pass | **BEHIND** | stale base; cracks #114 |

Two PRs are *not* in the queue but must not be forgotten: PR **139** (CodeRabbit
docstring autofix) was **already merged into 138's branch** — that is how GPU
content got onto an SSH-named branch. `docs/profiles/README.md` and
`docs/homelab/` are relevant because 132 and 138 both add homelab docs.

### Why `main` matters

`main` is at `b484513`. Commits since 2026-08-25 landed on `main` outside these
PRs (e.g. `9c81aaa` #120, which 129 and 131 both reference). Every "BEHIND" PR is
behind *that* commit, not behind each other.

### Confirmed unknowns

- **Branch protection is unreadable by the current token** —
  `gh api repos/Jobikinobi/dotfiles/branches/main/protection` → `403 Resource not
  accessible by integration`. Rulesets list is **empty** (`gh api …/rulesets` →
  `[]`). So the mechanism producing `BLOCKED` on 138 is classic branch
  protection, not a ruleset, and the setting is invisible to this token.
- The repo sets `CodeRabbit` as a status check that reports **"Review skipped:
  manual review required for this OSS repository"** on 138 (its auto-review
  bailed; see 138's comment `skip review by coderabbit.ai`). A required check
  that never reports a *success* will pin a PR at BLOCKED forever.

---

## 2. Merge order (the DAG)

Only one hard ordering constraint exists: **132 and 134 both edit
`.chezmoiignore`** — 132 removes two hand-enumerated lines; 134 replaces the
whole hand-enumerated block with a self-maintaining glob. 134's version wins, but
it must merge *after* 132, or 132's rebase reintroduces the stale list and
silently re-breaks the fresh-machine bootstrap 134 is built to fix.

Recommended order:

```
Wave 0  (no dependency, unblock the queue)
  127  gitignore-hardening        — 1 file, protects secrets immediately
  126  tailscale-policy           — 1 file, no overlap
  129  macos-deploy-unblock       — 5 files, no overlap

Wave 1  (large/structural, do alone)
  132  ssh-lan-renumber           — must land BEFORE 134 (.chezmoiignore)
       → then split assets/* out (see §4)

Wave 2  (the substantive feature)
  134  age-encrypted-secrets      — closes #29; rebase on post-132 main

Wave 3  (independent, after the tree is calm)
  119  incus-test-harness-114     — script only, cracks #114
  138  gpu-passthrough (renamed)  — after retitle/re-description (see §3)

Release
  131  release-please 1.2.1       — LAST. Let release-please regenerate
                                    (see §5) rather than merging a stale one.
```

Rationale for 131 last: release-please rebases itself when `main` moves, and
merging it early would publish a changelog missing every fix above.

---

## 3. PR 138 — the special case

**Problem, stated plainly:** branch `update/remove-deprecated-ssh-hosts` was
opened to remove deprecated SSH hosts, but its head commit `1f34b52` merged
`origin/main` and pulled in CodeRabbit's docstring PR **#139** (merged into the
branch) plus a Copilot conflict resolution. The branch now changes 5 files that
are entirely NVIDIA GPU passthrough:

- `scripts/gpu-passthrough-lxc-host.sh` (new, 151 lines)
- `scripts/gpu-provision-lxc.sh` (new, 291 lines)
- `docs/homelab/gpu-passthrough-lxc.md` (new, 155 lines)
- `docs/INDEX.md`, `docs/homelab/README.md`

The branch name and title (`ssh-hosts-update`) describe none of it. The SSH-host
removal the branch was named for **already landed on `main`** via #132's
predecessor work / #116 — worth confirming with
`git log origin/main -- private_dot_ssh/config.tmpl` during execution.

**Also off-topic on this branch, and unsafe:** the branch contains `.github/` and
`assets/`-adjacent artifacts and a `tailscale.json`-adjacent `.github/github-app.yml`.
Re-diff before merging.

**Required actions on 138 before merge (in order):**

1. Verify the SSH-host work it was named for is already on `main`
   (`git log origin/main -- private_dot_ssh/config.tmpl`). If not, that work is
   *missing* and must not be lost in the rename.
2. Retitle to something like
   `feat(gpu): NVIDIA passthrough for Proxmox LXC containers` and rewrite the
   body (currently empty — CodeRabbit flagged this).
3. Address the CodeRabbit/Copilot findings that were *not* auto-fixed. Still-open
   items from the review threads on `scripts/gpu-provision-lxc.sh`:
   - **CWE-494 (unverified root-executed installer)** — `curl` then `chmod`+run
     of the NVIDIA runfile. Add a digest allowlist or fail closed. This is the
     critical finding and should block merge.
   - `gpg --dearmor -o` refuses to overwrite on re-run → breaks claimed
     idempotency after a partial failure. Use an atomic temp output.
   - Rootful Docker branch checks `systemctl is-active docker` only — an installed
     but *stopped* service takes the "no Docker" path and never gets configured.
     Detect installation separately from active state.
   - Unconditional `systemctl restart docker` / `systemctl --user restart docker`
     on every run → interrupts workloads even when config is unchanged.
   - `grep -q` + `pipefail` can SIGPIPE `systemctl` and silently skip enabling
     `nvidia-cdi-refresh.path`. Consume the full stream.
   - `for f in /home/*/…` rootless-user detection returns the first match silently
     on multi-user containers; require `--docker-user` when ambiguous.
   - Add `ca-certificates`/`curl`/`gnupg` bootstrap (script uses them before
     installing anything that provides them).
4. Re-run `shellcheck` on both scripts (`bash -n` was already reported clean).
5. Manually clear the `BLOCKED` gate (§6) — or get a maintainer review — then
   rebase and merge.

**If the GPU work is not actually wanted:** close 138 and reopen a clean,
correctly-named branch with only the GPU commits. Do not merge a branch whose
name contradicts its content — it destroys the changelog.

---

## 4. PR 132 — separate the junk before merging

`git diff origin/main origin/fix/ssh-lan-renumber-10-0-0 --stat` reports
**2074 files changed, 11618 insertions**, of which ~2000 are
`assets/*-v0-165-0-*.js` / `.css` / `.woff2` — a dumped web-asset tree (looks
like an Authentik or Proxmox UI build).

These are unrelated to "10.0.0.0/24 renumber, pve-admin correction, and a Linux
Nix path". They inflate the PR, make review impossible, and would land ~2000
files of minified vendor JS on a dotfiles repo.

**Actions before merging 132:**

1. Confirm the asset files are junk and not deliberately vendored
   (`git log --oneline -1 origin/main -- assets/` → likely absent).
2. Determine how they got in (`git log origin/fix/ssh-lan-renumber-10-0-0
   --oneline -5`) and whether `assets.tar` (also present, PR 132 file list) is
   the source.
3. Either (a) land 132 with the assets split into a separate, clearly-scoped PR,
   or (b) add an `assets/` ignore and drop them. Recommend (b): they are
   generated UI artifacts, not dotfiles.
4. Only then merge — because 134 rebases on top of it.

The real content of 132 is worth keeping: the two Nix bugs (unconditional
`--init none` on Linux; missing `joe-linux` / aarch64 flake outputs), the
`pve-admin` alias correction, and the `portainer` / `cf-sandbox-*` SSH blocks.
The PR body documents all of it well and the verification is credible.

---

## 5. PR 131 — do not merge the stale release PR

131 was generated 2026-08-25 for v1.2.1 and only contains the #120 fix
(`.release-please-manifest.json`, `CHANGELOG.md`, `version.txt`).

**Action:** after Waves 0–3 land, push any commit to `main` (or close/reopen 131,
or run the release workflow via `workflow_dispatch`) so release-please
regenerates the PR. Then review that the changelog includes everything merged.

Do not merge the current 131 early: the version number it sets is correct but the
changelog it publishes would omit every fix in this queue.

---

## 6. Clearing the `BLOCKED` gate

Confirmed: rulesets are empty and the token cannot read
`/branches/main/protection`. The gate is a classic branch-protection rule.

**Attempt with `gh` (per user's chosen approach):**

```bash
# See what the token CAN see
gh api repos/Jobikinobi/dotfiles/branches/main/protection   # currently 403

# Requires a token with admin:repo scope. If 403, stop and use the manual path.
gh api repos/Jobikinobi/dotfiles/branches/main/protection \
  --method PUT --input - <<'JSON'
{ "required_status_checks": { "strict": false, "contexts": ["linux"] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0 },
  "restrictions": null }
JSON
```

**Inspect before changing anything.** The two settings that most plausibly
produce `BLOCKED` on an otherwise-green PR are:

- `required_approving_review_count > 0` — 138 has only bot `COMMENTED` reviews
  and no `APPROVED` review, and the repo is a solo-maintainer project.
- a **required status check that never reports success** (e.g. `CodeRabbit`,
  which on 138 said "Review skipped: manual review required"). Note `ci.yml:14`
  claims `linux` is the only required check — verify that against the live
  protection config, because the contradiction is itself the bug.

**Manual fallback (document this for the user):** Settings → Branches → `main` →
either set "Require approvals" to 0, or add the acting identity as a bypass
actor. The agent should report the exact settings diff it found rather than
silently rewriting protection.

**Do not** disable protection wholesale as a shortcut. If the required check is
the phantom, remove that one check; do not delete the `linux` requirement
(`ci.yml` lines 268–301 depend on it).

---

## 7. Per-PR task list

### Wave 0

- [ ] **127** — rebase on `main` (`git rebase origin/main`), verify still only
      `.gitignore` changes, force-push, wait for `linux`, merge.
- [ ] **126** — rebase on `main`, verify `tailscale.json` still byte-matches the
      live tailnet ACL (`curl -u "$TS_API_KEY:" …/tailnet/-/acl` — per the PR
      body's own instructions in the file header), merge.
- [ ] **129** — small and clean (5 files). Verify the `bin/chezmoi` removal is
      consistent with `main` (129's diff vs main shows only the 5 real files —
      `.chezmoiignore`, `.gitignore`, `dot_bash_profile`,
      `dot_config/fish/config.fish`, `private_dot_ssh/config.tmpl`). Clear the
      approval gate, merge.

### Wave 1

- [ ] **132** — split/drop `assets/*` and `assets.tar` per §4. Rebase. Re-verify
      the Nix claims in the PR body still hold (`--init none` only when no init
      system; all flake outputs evaluate). Merge. **This unblocks 134.**
- [ ] Re-verify `docs/homelab/README.md` and `private_dot_ssh/config.tmpl`
      post-merge — 132 and 138 both touch homelab docs.

### Wave 2

- [ ] **134** — rebase on post-132 `main`. **Manual re-verification required**
      (cannot run in a sandbox without the age key and Doppler):
      1. `chezmoi apply --exclude=scripts` on a fresh `ubuntu:24.04` with **no**
         key → must succeed, encrypted targets absent, `dotfiles-unlock` present.
      2. Supply the key → all ~20 encrypted files deploy at mode `0600`;
         `id_lab` parses as a private key; AWS credentials parse; `[r2]` present.
      3. Confirm the new `glob`-based `.chezmoiignore` block derives every
         `encrypted_*` target path (the whole point of the PR — the old
         hand-enumerated list was stale).
      4. Confirm the `env DEBIAN_FRONTEND=…` fix in
         `run_once_before_00-linux-bootstrap.sh.tmpl` is present (the exit-127
         parse-time bug).
      Then merge. **Do not merge 134 before 132.**
- [ ] **Never commit `AGE_IDENTITY`.** It lives in Doppler (`dotfiles`/`prd`).
      Grep the diff before merging: `git diff origin/main origin/feat/age-encrypted-secrets
      | grep -i AGE-SECRET-KEY` must be empty.

### Wave 3

- [ ] **119** — rebase, then re-run the rig against the image variants it claims
      to have tested (`images:debian/12/cloud` provisions; plain
      `images:ubuntu/24.04` and `images:debian/12` do not) if an `incus2` remote
      is reachable. Merging is safe even if not re-run — it is one
      `chezmoi`-ignored script — but update #114 with the finding either way.
- [ ] **138** — execute §3 in full. Merge only after the CWE-494 finding is
      fixed or explicitly accepted in writing by the maintainer.

### Release

- [ ] **131** — regenerate per §5, merge last, confirm the changelog includes
      every fix from this queue, confirm the tag publishes.

---

## 8. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| 134 merges before 132 | Reintroduces stale hand-enumerated `.chezmoiignore`; fresh-machine bootstrap hard-fails (`age` exits 1, chezmoi does not skip) | Enforce the ordering in §2; re-check the ignore block after each rebase |
| 132 lands ~2000 `assets/*` files | Unreviewable diff; junk on `main`; slows every future clone | Split or ignore before merge (§4) |
| 138 merges as-is | Changelog says "ssh-hosts-update" but ships GPU scripts; unverified root-run installer (CWE-494) | Retitle, fix CWE-494, re-diff (§3) |
| Force-push during rebase loses review history | Lost approvals/context on 138, 134 | Rebase with `--force-with-lease`; re-request review after |
| Age identity leaks during 134 rebase | Credential compromise in a **public** repo | Grep the diff for `AGE-SECRET-KEY` before every push (§7) |
| Branch protection edited carelessly | Removes the `linux` gate that `ci.yml:268` depends on | Change only the specific blocking setting; report the diff; keep `linux` required |
| `strict: true` protection | Every merge makes all other PRs BEHIND again → serialized queue | Accept serialization, or set `strict: false` while clearing the backlog |

---

## 9. Validation

After each merge, on the updated `main`:

```bash
gh run list --branch main --limit 3          # all legs green
git log --oneline -5                          # expected commit landed
```

Required check remains `linux` (`ci.yml:268–301`). Merge is only acceptable when
`gh pr checks <n>` shows every leg `pass` (or `skipping`).

Post-queue (after 134):

- Fresh `ubuntu:24.04`, no key → `chezmoi init --apply Jobikinobi` succeeds and
  encrypted targets are absent.
- `dotfiles-unlock` with Doppler → secrets deploy at `0600`.
- Linux bootstrap: no exit-127 on the apt-prereqs path, both as root and with
  `sudo`.

Report any validation that could not be run (the age/Doppler round-trip and the
Incus rig both need live infrastructure this sandbox does not have).

---

## 10. Open questions

1. **Is the GPU passthrough work in 138 actually wanted?** Recommended answer:
   yes, it is well-written and documented — but it must be retitled and the
   CWE-494 finding fixed. If not wanted, close 138 and drop the branch.
2. **Were the SSH-host removals 138 was named for ever merged?** Recommended:
   verify with `git log origin/main -- private_dot_ssh/config.tmpl` before
   closing the branch; if absent, reopen that work under its own PR.
3. **What exactly is in branch protection?** Recommended: run the `gh api`
   read as an admin; the agent's token returns 403. The `ci.yml:14` claim that
   `linux` is the only required check conflicts with 138's BLOCKED state and
   should be resolved in favour of the live config.
4. **Is `strict` required-status-checks on?** Recommended: if yes, turn it off
   while clearing this backlog, then decide whether to re-enable — otherwise
   every merge re-blocks its siblings and the queue never drains.
