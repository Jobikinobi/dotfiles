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

## Current state (as of 2026-06-04)

| Component | Where | Status |
|-----------|-------|--------|
| Headscale control plane | VM 112 on PVE, IP `192.168.68.77`, accessed as `https://hs.lab.hole-truth.org` | Healthy. nginx terminates TLS via certbot DNS-01 LE cert. **Slated to swap to Caddy** — see "Hard prerequisite" below. |
| Trial node `linux-test-01` | QEMU VM 108 on PVE, IP `192.168.68.70`, tailnet `100.64.0.1` | Joined. MagicDNS works (`linux-test-01.tail.lab.hole-truth.org`). |
| Trial node `linux-test-02` | LXC 102 on PVE, tailnet `100.64.0.2` | Joined. Bidirectional ping with `-01` works. |
| MagicDNS base domain | `tail.lab.hole-truth.org` | Active inside the tailnet. Not publicly resolvable yet (deferred). |
| Internal DNS for `hs.lab.hole-truth.org` | `/etc/hosts` line on each joined node | **Provisional.** Long-term plan: publish in the `ddns` LXC (`.55`), then split-horizon. |
| Lume macOS VM | `Josephs-Virtual-Machine.local` at `192.168.64.2` (macOS 26.5 arm64) | Probed 2026-06-04 — outbound to `.77:443` works, TLS handshake validates, no Tailscale installed yet. The cutover experiment runs here before any real Mac. |
| Daily-driver Macs (Mac Studio, MacBook Air, Mac Mini) | Public Tailscale tailnet `lemming-likert.ts.net` | Untouched. Cutover order: Mac Studio LAST. |

## Hard prerequisite: Caddy on `.77`

The cutover playbook is written around Caddy as the standard reverse proxy across the Headscale network. `.77` currently runs nginx for control-plane TLS termination. Until that swap is completed (separate issue: "Swap nginx for Caddy on .77 as headscale control-plane TLS terminator"), the playbook is documentation-only — **do not onboard a virgin node yet**, or you commit the network to two different reverse-proxy patterns and have to migrate one of them later.

The trial nodes already on the mesh are unaffected by this prerequisite — they keep working through and after the nginx → Caddy swap.

## Cutover order

The playbook executes machines one at a time, with explicit go-ahead per machine. Suggested order (least load-bearing first):

1. Disposable lume macOS VM (the cutover experiment — proves the macOS path on Tahoe arm64)
2. Alpine lab-controller `.74` (when powered on)
3. New trial Linux VMs (cheap to redeploy)
4. `mac-mini` (secondary workstation)
5. `macbook-air` (mobile workstation)
6. `my-vm` / `udev` (`.66` — primary development VM)
7. **Mac Studio LAST** — the workstation we cannot afford to lose

A cutover requires:
- A second SSH session over the **LAN IP** (not tailnet) held open through the operation.
- The rollback script ready in a third terminal.
- The previous machine successfully cut over and observed for at least 24 hours.

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
