# Headscale on the hole-network

This directory documents the migration of the hole-network off public Tailscale (`lemming-likert.ts.net`) onto self-hosted Headscale (`hs.lab.hole-truth.org`). Headscale gives us a mesh where **we** own MagicDNS, control-plane TLS, and ingress — the underlying reason being that public Tailscale effectively caps a node at one HTTPS service via its `serve` / `funnel` model, and the long-term plan is multi-HTTP per node behind our own reverse proxy.

Everything in `docs/**` is repo-internal (filtered out of `chezmoi apply` by `.chezmoiignore`). The cutover scripts that actually touch machine state will land separately in `bin/` and `scripts/headscale/` in a follow-up PR — see "What is NOT here" below.

## What lives here

| File | Audience | Purpose |
|------|----------|---------|
| [`architecture.md`](architecture.md) | engineer onboarding to the mesh | Ports, names, DNS plan, control-plane shape. Target end-state — what the network looks like after the migration is done. |
| [`cutover-playbook.md`](cutover-playbook.md) | the operator running a cutover | The how-to. One machine at a time, with a held-open LAN SSH session, with rollback every step of the way. **The main deliverable of this doc set.** |
| [`rollback.md`](rollback.md) | the operator during a cutover that's gone wrong | The five-minute path back to public Tailscale. Practiced on a disposable VM before any production machine is touched. |
| [`reverse-proxy.md`](reverse-proxy.md) | engineer adding services to a Headscale-managed node | Caddy reference config for running multiple HTTP services on one node behind the tailnet. Stage-1 is HTTP-only over the mesh — per-node TLS is a follow-on. |
| [`per-os/linux-debian.md`](per-os/linux-debian.md) | operator cutting over a Debian/Ubuntu host | Concrete per-OS join recipe. The path the trial nodes (`linux-test-01`, `linux-test-02`) actually took. |
| [`per-os/linux-alpine.md`](per-os/linux-alpine.md) | operator cutting over an Alpine host | Skeleton — to be filled in when the Alpine lab-controller (`.74`) join happens. |
| [`per-os/macos-oss.md`](per-os/macos-oss.md) | operator cutting over a Mac running the open-source Tailscale brew build | Recipe + measured-on-lume baseline (macOS 26.5 arm64). |
| [`per-os/macos-appstore.md`](per-os/macos-appstore.md) | operator cutting over a Mac running the App Store Tailscale | The `defaults write io.tailscale.ipn.macos ControlURL …` quirk. Skeleton — fills in after the lume cutover experiment exercises it. |

## Current state (as of 2026-06-06)

The migration has moved far past the original two-VM trial. **Eight nodes are now registered on Headscale under user `lab`**, including the production Mac Studio. Only Mac Mini and (transiently) the lume `my-vm` remain off Headscale.

| Component | Where | Status |
|-----------|-------|--------|
| Headscale control plane | VM 112 on PVE, IP `192.168.68.77`, accessed as `https://hs.lab.hole-truth.org` | Healthy. **Caddy on `:443`** terminates the LE cert (HOL-12 done 2026-06-05). Cert renewal stays on certbot DNS-01 with a deploy hook that reloads Caddy. nginx left installed but disabled — rollback insurance. |
| Joined nodes | See [`architecture.md`](architecture.md) host inventory | 8 nodes total: `coding`, `linux-test-02` (offline), `headscale-test`, `udev`, `debdesk`, `lab-controller` (Alpine), `mba` (offline), `josephs-mac-studio`. |
| Production Mac Studio | LAN `192.168.68.168`, tailnet `100.64.0.10` | **Cut over to Headscale 2026-06-05.** Ahead of the original "Mac Studio last" plan; this happened because the batch rollout was authorized end-to-end. Watch item: client/daemon Tailscale version skew (CLI 1.98.5 vs daemon 1.98.3) from a partial `brew upgrade` — fix is `sudo brew services restart tailscale`. |
| Alpine `lab-controller` | VM 107 on PVE | **Joined.** IP drifted from original `.74` to `192.168.68.51` (DHCP), hostname changed from `alp.lemming-likert.net` (public TS leftover) to `lab-controller`. Required apk repo repair + doas first-use password ceremony. HOL-6 is `done`. |
| MagicDNS base domain | `tail.lab.hole-truth.org` | Active inside the tailnet. Not publicly resolvable yet (blocks per-node `tailscale cert`). |
| Internal DNS for `hs.lab.hole-truth.org` | `/etc/hosts` line on each joined node | **Provisional.** Long-term plan: publish in the `ddns` LXC (`.55`, currently running), then split-horizon. |
| Lume macOS VM `my-vm` | `192.168.64.2` (macOS 26.5 arm64) | HOL-7 cutover experiment is **`blocked`** on SSH-auth setup. Practically obsolete now that the Mac Studio direct-cutover succeeded; remains a useful disposable target for the App Store cutover path if/when one is exercised. |
| Mac Mini | LAN `192.168.68.68` | **Not migrated.** Only remaining Mac on the public tailnet. Tracked for a future cutover. |
| Tailscale SSH | Enabled on Mac Studio | **ACL-blocked.** Mac Studio's `tailscale status` warns "Tailscale SSH enabled, but access controls don't allow anyone to access this device." Resolving requires writing a Headscale ACL policy. Open item. |

## Prerequisites — both satisfied as of 2026-06-05

| What | Status | Notes |
|------|--------|-------|
| Caddy on `.77` as the standard reverse proxy (HOL-12) | ✅ done 2026-06-05 | `systemctl is-active caddy` returns `active`; nginx `systemctl is-enabled` returns `disabled`. |
| Per-node `tailscale cert` automation (HOL-13) | ⏸ still backlog | Not a stage-1 need (stage 1 ships HTTP over tailnet). Has its own prereqs in HOL-13's description. |

The earlier "do not onboard a virgin node until Caddy is on `.77`" precondition was **loosened in practice** during the 2026-06-05 batch rollout — five nodes were onboarded against nginx by explicit owner override, then HOL-12 swapped the box to Caddy after. Tailscale clients do not pin TLS to a specific server cert, so existing-node sessions were unaffected by the swap. The cutover playbook reflects the loosened precondition.

## Cutover order — revised after 2026-06-05

The original "Mac Studio last" plan was abandoned during the 2026-06-05 batch. Remaining order:

1. ✅ Disposable trial nodes (`coding`, `debdesk`, etc.) — done.
2. ✅ Alpine `lab-controller` (HOL-6) — done.
3. ✅ MacBook Air (`mba`) — done (currently offline; observed online via headscale earlier).
4. ✅ Mac Studio (`josephs-mac-studio`) — done. Production daily-driver, the workstation flagged "cannot afford to lose"; cutover succeeded.
5. ⏸ Mac Mini — only remaining production Mac. Not yet migrated. When done, the public tailnet can be retired for the lab.
6. ⏸ Lume `my-vm` — optional, blocked on SSH-auth setup (HOL-7).

A cutover still requires:
- A second SSH session over the **LAN IP** (not tailnet) held open through the operation.
- The rollback path ready (see [`rollback.md`](rollback.md)).
- For a production machine, console-of-last-resort availability within ~10 minutes.

## What is NOT here

- **No scripts.** The actual `cutover.sh` / `rollback.sh` / `preflight.sh` land in `scripts/headscale/` in a follow-up PR. Until then, the cutover-playbook documents what to run by hand.
- **No automatic execution.** Nothing in this directory is wired into `chezmoi apply`. Network identity changes are deliberate human acts, not batch operations.
- **No control-plane server bootstrap.** How `.77` is provisioned (the Ubuntu VM, the `/etc/headscale/config.yaml`, the certbot setup) lives in [hole-devenv](https://github.com/Jobikinobi/hole-devenv) — the infrastructure layer. This directory is purely the client-side / network-identity perspective.
- **No internal DNS automation.** The plan to publish `hs.lab.hole-truth.org` via the `ddns` LXC at `.55`, and later split-horizon, is tracked separately.

## Why dotfiles is the right home for this

Every machine in the hole-network already has this repo deployed. That means:

- The playbook and the (future) cutover scripts are present on a machine **before** any cutover begins, just by virtue of `chezmoi apply` having run at any point in the machine's history.
- The operator doesn't have to fetch this doc on a held-open SSH session; it's already at `~/dotfiles/docs/homelab/headscale/cutover-playbook.md` on the machine they're SSHed into.
- A future fresh machine inherits the same toolkit just by being initialized from dotfiles — no separate provisioning step to remember.

This is the same logic that puts `dot_Brewfile.legal` in the repo rather than in a separate package: the cross-machine artifact rides with the cross-machine config delivery system.

## Related

- `docs/homelab/README.md` — the broader homelab project this is part of
- `docs/homelab/recovery.md` — age-identity recovery (separate concern, but shares the "cannot afford to lose this" risk profile)
- [hole-devenv](https://github.com/Jobikinobi/hole-devenv) — the infrastructure layer where the `.77` VM bootstrap actually lives
