# Headscale cutover playbook

This is the operator-facing procedure for moving one machine off public Tailscale onto self-hosted Headscale. Run it once per machine. Do not batch — every cutover is its own session with its own go-ahead, its own held-open SSH, and its own rollback rehearsal.

If this is your first time, read [`architecture.md`](architecture.md) and [`rollback.md`](rollback.md) first. Read them cold. The cost is twenty minutes; the cost of skipping them and discovering the rollback procedure mid-cutover on a headless production machine is much higher.

## Status of this playbook (as of 2026-06-06)

This playbook is **documentation-complete** and **executable**. As of the 2026-06-05 batch rollout, eight nodes are on Headscale including the production Mac Studio; the playbook reflects observed behavior, not just plan.

Two things to be aware of:

1. **The "no virgin onboarding until Caddy is on `.77`" precondition was loosened** during the 2026-06-05 rollout. Five nodes were onboarded against nginx by explicit owner override, then HOL-12 swapped `.77` to Caddy after. Tailscale clients do not TLS-pin, so existing-node sessions survived the swap without re-keying. This means the playbook can run before the reverse-proxy story is consistent across the network — at the cost of having two patterns coexist for a short window. The order chosen on 2026-06-05 was acceptable; future rollouts can choose either order.
2. **The cutover scripts (`bin/hs-preflight`, `bin/hs-cutover`, `bin/hs-rollback`) referenced below do not exist yet** — they ship in a follow-up PR. The 2026-06-05 batch was done by hand from this document. The procedure is right; the wrappers are convenience.

## Section 1: Preconditions

Before initiating a cutover on any machine, ALL of the following must be true. This is a checklist, not a recommendation.

- [ ] **The target machine has a working LAN IP and you can SSH to it over that LAN IP** (not over the tailnet, not over a hostname that resolves through Tailscale DNS). Verify with `ssh user@192.168.68.x` from a workstation on the same LAN. If this fails, the cutover does not start — fix LAN reachability first.
- [ ] **A second, independent SSH session over the LAN IP is open and held** in a separate terminal window. This is the escape hatch. If the primary session is interrupted, the secondary lets you run rollback without a console trip.
- [ ] **The console of last resort is accessible** for this machine class:
  - PVE VM: Proxmox web UI logged in, VM console window open in a third tab.
  - PVE LXC: a shell on the PVE host so `pct enter <vmid>` is one command away.
  - Bare-metal Mac: physical keyboard + monitor available within ~10 minutes (you can probably skip this for the lume VM and `mac-mini` since they have monitors attached; mandatory for any Mac without a screen).
  - Bare-metal Linux: physical keyboard + monitor, or IPMI/iDRAC, or "I trust this LAN segment with a fallback Ethernet path".
- [ ] **The previous machine in the cutover order is healthy on Headscale** and has been observed for at least 24 hours. No machine cuts over until the one before it has soaked.
- [ ] **You have run the rollback drill on a disposable VM in the last 7 days.** Cold-reading the rollback document for the first time during a real cutover is the failure mode this rule prevents.
- [ ] **`.77` is healthy.** `curl -s https://hs.lab.hole-truth.org/health` returns `{"status":"pass"}` from any joined node.
- [ ] **A fresh, single-use preauth key has been generated** for the target user (`lab` today). Reusable keys are fine for the disposable trial; single-use is required for any production machine.

If any of the boxes are unchecked, **stop**. Address the gap. Re-enter the playbook from the top when it's resolved.

## Section 2: One control plane per node — the hard constraint

A Tailscale client can register with exactly **one** control plane at a time. It cannot be on public Tailscale and Headscale simultaneously. There is no dual-homed mode and no transparent failover between control planes.

The practical consequences:

- **The cutover window has a real, observable gap.** Between `tailscale logout` (public) and the verification step on the new Headscale tailnet, this node is not on any tailnet. Target: less than 60 seconds. Maximum tolerable: 5 minutes (above which, abort and roll back).
- **Any service that depends on the tailnet to be reachable will be unreachable during the gap.** This includes anything bound only to a tailnet IP, or anyone trying to SSH in via a tailnet hostname. The LAN-IP SSH session that you held open in section 1 is unaffected; it is the contract this playbook is built on.
- **Other machines on public Tailscale lose this node from their peer list at logout.** Their next attempted connection to the cut-over node via tailnet will fail until that node rejoins (this time, on Headscale — different peer list).

This is the irreducible cost. There is no playbook step that makes it go away. The playbook is designed around making the gap small, observed, and recoverable.

## Section 3: The LAN SSH fallback contract

For each machine, before any cutover step is run, the following must all be true:

| Check | How to verify | What "passing" looks like |
|-------|---------------|---------------------------|
| LAN IP is reachable from your workstation | `ping -c 3 192.168.68.<n>` | 0% packet loss |
| SSH on LAN IP works with key | `ssh -i <key> user@192.168.68.<n> 'whoami'` | returns the expected username |
| The connection is over LAN, not tailnet | `ssh user@192.168.68.<n> 'who -m'` | shows your workstation's LAN address as the source, not a `100.x.x.x` |
| Sudo works without prompting (or with a known password) | `ssh user@192.168.68.<n> 'sudo -n whoami'` | returns `root`, OR you have the password and can interact |

If any of these fail, the playbook does not proceed for this machine. The single most common cutover failure mode is "I thought I had a LAN SSH path but it turned out my session was via a tailnet alias" — verify with `who -m`.

The second SSH session held in a separate terminal window for the duration of the cutover MUST satisfy the same four checks, independently.

## Section 4: Internal DNS for `hs.lab.hole-truth.org`

The target machine must be able to resolve `hs.lab.hole-truth.org` to `192.168.68.77` before the cutover step. There are three options, in order of preference:

### Short term — `/etc/hosts` entry

This is what the trial nodes use today. The cutover script installs the line; if running by hand:

```bash
# On the target machine, in the LAN SSH session:
if ! grep -q "hs.lab.hole-truth.org" /etc/hosts; then
  echo "192.168.68.77 hs.lab.hole-truth.org" | sudo tee -a /etc/hosts
fi
# Verify:
getent hosts hs.lab.hole-truth.org
# Expected: 192.168.68.77   hs.lab.hole-truth.org
```

This survives reboot. It is brittle if `.77` ever moves to a different LAN IP — the cutover playbook deliberately does not own that scenario.

### Medium term — internal DNS via `ddns` LXC

When the `ddns` LXC at `.55` is configured to authoritatively serve `lab.hole-truth.org`, the `/etc/hosts` entry can be dropped. Joined nodes will resolve `hs.lab.hole-truth.org` through their normal DNS resolver chain (Headscale's MagicDNS hands them the LAN DNS server in `nameservers.global` — see [`architecture.md`](architecture.md)).

This is the right end state for the LAN. Until it's live, the `/etc/hosts` line is the supported path.

### Long term — split horizon

Publish `hs.lab.hole-truth.org` in Cloudflare DNS pointing at the WAN IP, with a router-side TCP 443 forward to `192.168.68.77:443`. This enables off-LAN enrollment. Out of scope for the migration playbook; tracked separately.

## Section 5: Per-OS join recipe

The actual `tailscale up …` command and the surrounding state-clean is OS-specific. Follow the right per-OS document:

- **[`per-os/linux-debian.md`](per-os/linux-debian.md)** — Debian, Ubuntu, anything systemd + apt
- **[`per-os/linux-alpine.md`](per-os/linux-alpine.md)** — Alpine, anything OpenRC + apk
- **[`per-os/macos-oss.md`](per-os/macos-oss.md)** — macOS running the open-source brew Tailscale build (recommended)
- **[`per-os/macos-appstore.md`](per-os/macos-appstore.md)** — macOS running the App Store Tailscale (works, but harder)

Every per-OS recipe ends with the same **verification block**, which is the contract for "did the join succeed":

```bash
# 1. Tailscale client reports healthy.
tailscale status
# Expected: shows "100.64.x.x  <hostname>  lab  <os> -" for self

# 2. Tailnet IP assigned.
tailscale ip -4
# Expected: a "100.64.x.x" address

# 3. MagicDNS round-trip for self.
tailscale status --json | jq -r '.Self.DNSName'
# Expected: <hostname>.tail.lab.hole-truth.org.

# 4. Peer reachability — pick any other joined node and ping it.
getent hosts linux-test-01
# Expected: "100.64.0.1   linux-test-01.tail.lab.hole-truth.org"

tailscale ping linux-test-01
# Expected: a pong via direct or DERP — both fine
```

If any of these four fail, abort and proceed to [`rollback.md`](rollback.md). Do not skip ahead to "fix it forward" — the time spent troubleshooting forward almost always exceeds the time spent rolling back and trying again with a clear head.

## Section 6: Reverse-proxy pattern (the real motivator)

This section is about what you do *after* the cutover, when you actually want to run multiple HTTP services on a single Headscale-managed node. See [`reverse-proxy.md`](reverse-proxy.md) for the full Caddy reference; the short version:

- Each service binds to a `127.0.0.1:<port>` on the node.
- Caddy on the node binds to the node's tailnet IP on `:80` (stage 1) or `:443` (stage 2 / `tailscale cert`).
- Caddy routes by `Host` header to the localhost port.
- Other tailnet members hit `http://<hostname>/<path>` or `http://service-a.<hostname>/` (with a wildcard CNAME if you want subdomain-per-service) and Caddy demuxes.

Stage 1 is HTTP-only over the tailnet because the WireGuard transport is already encrypted node-to-node. Stage 2 adds real LE-issued TLS certs via `tailscale cert` — a separate follow-up issue, not required for closing this migration.

## Section 7: Per-machine cutover order

**This section is mostly historical now.** The bulk of the network is on Headscale; what remains is Mac Mini and (optionally) the lume `my-vm`. The original "Mac Studio last" order was abandoned during the 2026-06-05 batch rollout — the owner chose to onboard the production Mac Studio directly during the batch and it succeeded. The original order is preserved below as reference for future cutovers.

### What is done

1. ✅ Disposable Linux trial nodes (`coding`, `debdesk`, `headscale-test`, `linux-test-02`) — done in the original trial + 2026-06-05 batch.
2. ✅ Alpine `lab-controller` (HOL-6) — done 2026-06-05.
3. ✅ `udev` (PVE VM 101, the dev / agent-runtime control node) — done 2026-06-05.
4. ✅ MacBook Air (`mba`) — done 2026-06-05.
5. ✅ Mac Studio (`josephs-mac-studio`) — done 2026-06-05 in the same batch (precondition loosened — see "Status of this playbook" above).

### What remains

- ⏸ **Mac Mini** (`192.168.68.68`). Only remaining Mac on public Tailscale. Should follow the per-OS macOS-OSS recipe. Has a screen attached — full console access available, so this cutover is low-risk despite being a "production" workstation.
- ⏸ **Lume `my-vm`** (`192.168.64.2`). Originally the macOS cutover experiment; less load-bearing now that Mac Studio is on Headscale. Useful as the **App Store cutover rehearsal target** if/when a real machine on the App Store build needs cutting over. Currently blocked on SSH-auth setup — see HOL-7.

### Original ordering doctrine (reference)

The principle was: **least load-bearing first**, with the workstation that cannot afford to lose **last**. That principle remains good guidance for future, similar migrations. It was waived for Mac Studio here because (a) the operator was actively running the batch and ready to roll back, (b) the rollback path was well-rehearsed by then, and (c) the cumulative risk of leaving the migration half-done across many machines for an extended period was judged higher than the per-machine cutover risk on Mac Studio specifically.

A cutover-of-one still warrants the original paranoia: held-open LAN SSH session in a second terminal, console-of-last-resort available within ten minutes, rollback rehearsed on a disposable target in the last seven days. None of that changes for the Mac Mini step.

## Section 8: Rollback drill — practice before production

Before cutting over any production machine, run the cutover + rollback drill end to end on a disposable target (lume VM, fresh trial Linux VM, or one of the existing trial nodes). The drill is:

1. Cut over the disposable machine to Headscale per the playbook.
2. Verify it works (section 5 verification block).
3. Wait 10 minutes.
4. Pretend it's gone wrong. Follow [`rollback.md`](rollback.md) end to end. Time it.
5. Verify the machine is back on the public tailnet.
6. Time recorded must be < 5 minutes from "decide to roll back" to "verified back on public tailnet." If longer, find the slow step and fix it before the playbook touches anything real.
7. (Optional) Cut it over to Headscale again. The point of the drill is that switching control planes is now a routine, low-stress operation for you.

Drill at least once per quarter even after the migration is complete, so operator muscle memory does not atrophy.

## Section 9: Cutover-day checklist (printable, ~20 lines)

Print this. Cross items off in pen. Do not skip.

```
[ ] LAN SSH session to target (primary)         (terminal 1)
[ ] LAN SSH session to target (escape hatch)    (terminal 2)
[ ] Console-of-last-resort window open           (terminal 3 or PVE/UI)
[ ] Rollback document open                      (browser or another window)
[ ] Previous machine in order: healthy ≥ 24h    (verify in headscale nodes list)
[ ] `.77` health check passes                    (curl /health → "pass")
[ ] Single-use preauth key generated             (on .77 as headscale group)
[ ] Auth key copied (not echoed in shared window)
[ ] /etc/hosts entry for hs.lab.hole-truth.org present on target
[ ] who -m on primary session: source IP is LAN, not tailnet
[ ] Run per-OS recipe up through `tailscale up …`
[ ] Verification block: tailscale status         (shows 100.64.x.x)
[ ] Verification block: tailscale ip -4          (returns address)
[ ] Verification block: tailscale ping <peer>    (pong)
[ ] Verification block: getent hosts <peer>      (resolves)
[ ] All four ✅                  → cutover successful, soak 30 min
[ ] Any ✗                        → ROLLBACK (rollback.md)
[ ] Mark machine in homelab inventory (architecture.md or homelab README)
[ ] Notify (if anyone else uses this machine)
```

## Section 9b: Known gotchas observed during the 2026-06-05 batch

Concrete problems that bit during the multi-node rollout. Pre-flight against these on the next cutover.

- **Cloned-template VMs share `tailscaled.state`.** VMs 108, 110, 111 were cloned from a common Ubuntu template that had `tailscaled` pre-installed and had been run once on the template. Result: every new `tailscale up` overwrote the previous node in headscale's node-slot 1 because all three VMs presented identical machine keys. **Fix per VM, before `tailscale up`**:
  ```bash
  sudo systemctl stop tailscaled
  sudo rm /var/lib/tailscale/tailscaled.state
  sudo systemctl start tailscaled
  ```
  Then `tailscale up --login-server=... --authkey=...`. This is now part of the Linux per-OS recipe's "clear prior state" step but is easy to forget when the node has never been "on" any tailnet from your point of view.
- **Headscale CLI socket ownership.** On 2026-06-05 the `/var/run/headscale/headscale.sock` was created with `root:root` 0770 after some operation, and the daemon ran as user `headscale`. The CLI silently fell back to gRPC at `127.0.0.1:50443`, which the daemon wasn't listening on, and every `headscale nodes list` timed out. **Diagnosis**: `ls -la /var/run/headscale/headscale.sock` shows the wrong owner. **Fix**: `sudo systemctl restart headscale` recreates the socket with the correct ownership (`headscale:headscale`). Re-occurs after some upgrade flows; restart-of-headscale is the universal fix.
- **DHCP drift between the doc and reality.** The Alpine VM the docs called `.74` came up at `192.168.68.51` after a long power-off. Always probe live (`headscale nodes list`, `arp`) before trusting a doc-recorded IP.
- **First-use password ceremony on doas-only Alpine.** Out-of-the-box Alpine has no `sudo`, and `doas` defaults to `permit persist :wheel` which prompts for a password on first use per session. If `jth` is a wheel member but the agent doesn't have the password, the agent cannot acquire root. **Fix once, manually, on a fresh Alpine VM**: as root via console, `echo "permit nopass :wheel" > /etc/doas.d/wheel.conf`. Then agents in `wheel` can run `doas` without prompting.
- **Apk repositories misconfigured on the Alpine VM.** `/etc/apk/repositories` listed `https://alpinelinux.org` twice with no `/v3.23/main` path, so `apk add` resolved nothing. **Fix**: rewrite the file to point at the right mirror + version:
  ```
  https://dl-cdn.alpinelinux.org/alpine/v3.23/main
  https://dl-cdn.alpinelinux.org/alpine/v3.23/community
  ```
  Then `apk update; apk add tailscale`.
- **macOS Tailscale client/daemon version skew after `brew upgrade`.** Observed on Mac Studio post-cutover: CLI is `1.98.5`, daemon is `1.98.3`. `tailscale status` warns about it but continues to work. **Fix**: `sudo brew services restart tailscale`. The skew can produce confusing behavior on `tailscale set` operations until restarted; do this any time `tailscale status` shows the warning.
- **`tailscale SSH` enabled but ACL-blocked on Mac Studio.** `tailscale status` health check warns: *Tailscale SSH enabled, but access controls don't allow anyone to access this device.* Headscale's default open-mesh policy does not grant `tailscale ssh` permission — that requires an explicit ACL entry. Without it, `tailscale ssh josephs-mac-studio` from another tailnet member is silently rejected. **Fix**: write a Headscale ACL policy (out of scope for the cutover playbook, but worth knowing it's needed).

## Section 10: Post-cutover cleanup

These are not blocking on the cutover succeeding — they are housekeeping done over the days after. Current state as of 2026-06-06 in parens.

- ⏸ **Purge `tailscaled` cruft from the headscale host `.77`.** (**Still open**.) The control plane should not run a Tailscale client. `sudo apt purge tailscale && sudo rm -rf /var/lib/tailscale`. Deferred repeatedly because it needs an interactive `sudo` password on `.77` that the agents don't have. As of 2026-06-06 the unit is still `enabled` and `tailscale0` is `UP` on the box. Inert (no traffic) but should be removed for hygiene.
- ⏸ **Remove the `/etc/hosts` line** for `hs.lab.hole-truth.org` once internal DNS via `ddns` LXC (`.55`) is live. (Still open. `ddns` LXC is running but not authoritatively serving `lab.hole-truth.org` yet.)
- ⏸ **Retire the public-Tailscale auth key** in Doppler once no machine on the network needs it for rollback anymore. Mac Mini still depends on public Tailscale; **keep the key valid until Mac Mini is migrated**.
- ⏸ **Delete stale nodes** from the public Tailscale admin console for the machines cut over on 2026-06-05 (Mac Studio, MBA, lab nodes). Confirm at least 30 days of soak first, in case rollback is needed.
- ⏸ **Define a Headscale ACL policy** to grant `tailscale ssh` access. Currently every node with `--ssh` enabled is silently rejecting connections (see §9b gotchas). Tracked separately.
- ✅ **Expire reusable preauth keys** after rollout. Key id 6 from the 2026-06-05 batch has been expired.
- ✅ **Migrated `architecture.md`** host inventory table to reflect the new tailnet IPs (done 2026-06-06).
- ⏸ **Update `private_dot_ssh/config.tmpl`** in this repo if any SSH aliases point at public-tailnet hostnames that have changed. The LAN-IP fallback `Host` entries stay; tailnet aliases get the new addresses. (Not yet done.)

## What this playbook deliberately does not cover

- **Whole-network backup before cutover.** The risk model is per-machine, not per-network. Each cutover is independently rollback-able; there is no batch operation that warrants a whole-network snapshot. Per-machine Proxmox snapshots (for VMs) and Time Machine (for Macs) are the operator's choice — sufficient, not required.
- **Automatic execution.** Nothing in this playbook is wired into `chezmoi apply`. The reasons are documented in [`README.md`](README.md): network identity changes are deliberate human acts.
- **The macOS App Store TLS-cert quirks.** The `defaults write … ControlURL` path works for joining, but App Store builds have historically had inconsistent behavior around `tailscale cert`. Recommendation in [`per-os/macos-appstore.md`](per-os/macos-appstore.md) is to migrate to the open-source brew build for any Mac that needs per-node TLS.
- **Subnet routing and ACL design.** Both are post-migration concerns. The migration ships an open-mesh policy and no advertised routes. Tightening happens after every machine is on Headscale.

## Related

- [`README.md`](README.md) — directory overview, current state, hard prerequisites
- [`architecture.md`](architecture.md) — target end-state architecture
- [`rollback.md`](rollback.md) — five-minute path back to public Tailscale
- [`reverse-proxy.md`](reverse-proxy.md) — Caddy reference for multi-HTTP per node
- [`per-os/`](per-os/) — OS-specific join recipes
