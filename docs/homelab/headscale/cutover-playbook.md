# Headscale cutover playbook

This is the operator-facing procedure for moving one machine off public Tailscale onto self-hosted Headscale. Run it once per machine. Do not batch — every cutover is its own session with its own go-ahead, its own held-open SSH, and its own rollback rehearsal.

If this is your first time, read [`architecture.md`](architecture.md) and [`rollback.md`](rollback.md) first. Read them cold. The cost is twenty minutes; the cost of skipping them and discovering the rollback procedure mid-cutover on a headless production machine is much higher.

## Status of this playbook (read first)

This playbook is **documentation-complete** as of 2026-06-04, but **not yet safe to run on virgin nodes**. Two prerequisites are open:

1. **`.77` must be running Caddy, not nginx**, as the headscale control-plane TLS terminator. This is the swap that standardizes the reverse-proxy pattern across the network. See the "Swap nginx for Caddy on .77 …" issue in the project tracker. The trial nodes already on the mesh are unaffected; they continue to work through and after this swap. But virgin nodes joined while `.77` is still on nginx would inherit an inconsistent pattern that would have to be migrated later.
2. **The cutover scripts (`bin/hs-preflight`, `bin/hs-cutover`, `bin/hs-rollback`) referenced below do not exist yet** — they ship in a follow-up PR. Until they do, the "scripted" steps below are run by hand from this document.

Both prerequisites can land before the first production cutover. Neither blocks document review.

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

Execute machines one at a time, in this order. Each cutover requires its own go-ahead from the owner (the user, for now) before it begins. Do not batch.

1. **Lume macOS VM** (`Josephs-Virtual-Machine.local` at `192.168.64.2`).
   This is the **experiment**, not a production cutover. The point is to capture every quirk of the macOS join path — both the fresh-install path (clean Headscale join) and the cutover path (install public Tailscale, join, then switch to Headscale). Every observation from this run becomes a note in `per-os/macos-oss.md` (or `per-os/macos-appstore.md`, depending on which build is exercised). No production machine is touched until this experiment is complete.

2. **Alpine lab-controller** (`.74`, VM 107).
   Currently offline. Power on, then run the Alpine recipe. Isolated host, very low blast radius. Empty of services.

3. **Any newly-spun trial Linux VM** (e.g., `linux-test-03`).
   Cheap to redeploy if something goes wrong. Useful for one more pass of the cutover playbook before touching production.

4. **`mac-mini`** (secondary workstation, `192.168.68.68`).
   First production cutover. Has a screen, has a wired Ethernet path, runs no daily-critical workloads. If the macOS path turns out to need adjustment, find that here, not on the Mac Studio.

5. **`macbook-air`** (`192.168.68.70`, when not roaming).
   Mobile, but uses LAN-attached at home. Cutover happens at home.

6. **`my-vm` / `udev`** (`.66`, primary development VM on PVE).
   Linux. Has services. Cutover happens during low-activity hours with the LAN SSH escape path open.

7. **`mac-mini` again** if the secondary workstation slot has been re-used; otherwise skip.

8. **Mac Studio LAST**. This is the workstation the operator cannot afford to lose. By the time we reach it, every other macOS host on the network is on Headscale and has been observed for at least 24 hours. The actual cutover follows the per-OS Mac recipe with extra paranoia: two held-open LAN SSH sessions (not one), the rollback script pre-positioned in a third terminal, and a window of attention reserved for at least 30 minutes after the cutover to confirm soak.

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

## Section 10: Post-cutover cleanup

These are not blocking on the cutover succeeding — they are housekeeping done over the days after.

- **Purge `tailscaled` cruft from the headscale host `.77`**. The control plane should not run a Tailscale client. `sudo apt purge tailscale && sudo rm -rf /var/lib/tailscale`. This was identified as a leftover from the original trial bring-up.
- **Remove the `/etc/hosts` line** for `hs.lab.hole-truth.org` once internal DNS via `ddns` LXC is live. Verify with `getent hosts hs.lab.hole-truth.org` returning the same answer without the line present.
- **Retire the public-Tailscale auth key** in Doppler once no machine on the network needs it for rollback anymore. Until then, keep it valid — it is the rollback path.
- **Delete stale nodes** from the public Tailscale admin console for machines that have been cut over and confirmed soaked.
- **Update [`architecture.md`](architecture.md)** — the host inventory table to reflect the new tailnet IPs for cut-over machines.
- **Update `private_dot_ssh/config.tmpl`** in this repo if any SSH aliases point at public-tailnet hostnames that have changed. The LAN-IP fallback `Host` entries stay; tailnet aliases get the new addresses.

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
