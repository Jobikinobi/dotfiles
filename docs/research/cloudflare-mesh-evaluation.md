# Cloudflare Mesh as a Tailscale Replacement — Evaluation

> Status: **paper evaluation**, pre-testbed.
> Branch: `experiment/cloudflare-mesh`.
> Author notes as of 2026-04-22.

## Why consider this

- Cloudflare is already our domain registrar, CDN, and Project Galileo sponsor — consolidating mesh networking into Cloudflare reduces the number of external providers.
- We originally had to uninstall Cloudflare WARP when deploying Tailscale because the two are explicitly incompatible (both want the TUN interface, both hijack DNS). Running Cloudflare's mesh restores WARP for the full Zero Trust/Gateway stack.
- Cloudflare rebranded "WARP Connector" to **Cloudflare Mesh** on 2026-04-14 with a new dashboard at Networking → Mesh and a raised node limit (10 → 50 per account). The product now explicitly markets peer-to-peer connectivity as a first-class feature.

## Current Tailscale footprint (what we actually use)

Derived from this repo (`run_once_before_install-toolchains.sh.tmpl`, `entrypoint.sh`, `private_dot_ssh/config.tmpl`, `docs/architecture.md`).

| Use | Where | Notes |
|---|---|---|
| Linux headless auto-join | `TS_AUTHKEY` via Doppler in toolchain script | `sudo tailscale up --authkey=... --ssh` |
| Docker container auto-join | `entrypoint.sh` → `TS_AUTHKEY` env var | tailnet hostname via `TS_HOSTNAME` |
| MagicDNS hostnames | `ssh mac-mini`, `curl http://hole-dev:8000` | Tailnet `lemming-likert.ts.net` |
| Tailscale SSH | `--ssh` flag on join | Keyless SSH between tailnet members |
| Cross-provider mesh | macOS laptops + Mac Mini + DO droplets + Docker containers | 6ish nodes in production |
| Prometheus/Grafana access | hole-dev over tailnet | Monitoring traffic stays on the mesh |

## Cloudflare Mesh — feature parity table

Citations are Cloudflare developer docs (`developers.cloudflare.com`) retrieved 2026-04-22.

| Capability | Tailscale | Cloudflare Mesh | Parity |
|---|---|---|---|
| Peer-to-peer overlay with private IP per node | Yes (`100.x.y.z` CGNAT range) | Yes — "Mesh IP" assigned per device/node | ✅ |
| Linux headless install | `tailscale up --authkey=...` | `warp-cli` + `/var/lib/cloudflare-warp/mdm.xml` with service token (`auth_client_id` / `auth_client_secret`) | ✅ (more verbose, but supported) |
| Service token / auth key model | Auth keys (reusable / ephemeral / pre-approved) | Zero Trust service tokens + device enrollment policy allowing "Service Auth" | ✅ |
| Docker / containerized node | Works via `TS_AUTHKEY` env + tailscaled in entrypoint | `warp-cli` runs in a Linux container if TUN is available (`--cap-add=NET_ADMIN --device /dev/net/tun`), but **OrbStack/LXD/full VM is the supported path** | ⚠️ degraded for Docker |
| Node limit | Unlimited on free tier (20 users) | **50 nodes per account** | ✅ (we have ~6) |
| Subnet router (advertise `192.168.68.0/24`) | `--advertise-routes` | CIDR routes on a Mesh node | ✅ |
| Exit node (route all internet through peer) | `--exit-node` | Mesh nodes support egress-as-gateway | ✅ |
| Client-to-client (no infrastructure) | Yes | Yes — explicitly advertised as of 2026-04-14 | ✅ |
| High availability for subnet routes | Subnet router failover | Active-passive replica nodes for routes | ✅ |
| MagicDNS-style hostname resolution (`ssh mac-mini`) | Yes, automatic, free | **Uncertain** — Cloudflare has Internal DNS + Resolver Policies, but requires configuring a DNS zone and CNAMEs or internal records per node. Not as automatic as MagicDNS. | ⚠️ gap |
| SSH without managing keys | Tailscale SSH (`--ssh`) — short-lived certs, no per-host known_hosts | **Three options**: (a) Access for Infrastructure with short-lived certs — closest analog, (b) browser-rendered terminal via Cloudflare Tunnel, (c) plain SSH over Mesh IP with your existing keys | ⚠️ more setup |
| ACLs / policies between nodes | Tailscale ACLs (JSON file) | Gateway network policies (per-identity, per-device-posture) | ✅ (arguably richer) |
| Device posture checks | Limited | Full Zero Trust posture checks | 🎁 bonus |
| Free for personal/small use | Free for up to 100 devices / 3 users | Zero Trust free plan: 50 users — **we're on Project Galileo so paid features are unlocked** | ✅ |
| Post-quantum encryption | Roadmap | **Already GA** per April 2026 announcement | 🎁 bonus |

Legend: ✅ parity • ⚠️ gap or degraded • 🎁 Cloudflare-only advantage

## Known gaps and open questions

### Hard blockers to resolve before commitment

1. **MagicDNS equivalent.** Currently we rely on `ssh mac-mini`, `curl http://hole-dev:8000`, `ssh foia-scraper` — all resolved by tailnet DNS with zero config. Cloudflare Mesh gives you a private IP per node, but stable hostnames require configuring Internal DNS. Open question: is there an auto-generated per-node DNS name (like `<node>.mesh.cloudflare.com` within a tenant), or does each host need a manual DNS record? **This is the #1 feature to verify in the testbed.**

2. **Tailscale SSH replacement quality.** Tailscale SSH is remarkably frictionless (`ssh user@mac-mini` just works, keys managed by the tailnet). The Cloudflare alternatives are all more setup. Access for Infrastructure with short-lived certs is the right long-term answer, but the migration cost is real — especially for `entrypoint.sh` which currently does `tailscale up --ssh` in one line.

3. **Docker container enrollment.** Our `dotfiles-test` container joins the tailnet via `TS_AUTHKEY` + `tailscaled` in the entrypoint. The Cloudflare One Client (`warp-cli`) is not designed for Docker — it wants a real Linux host. For container nodes we may need to either (a) switch them to Orb/LXD VMs, or (b) route them through a subnet router on the host. **Workable, but a meaningful architecture change.**

### Soft considerations

4. **arm64 vs amd64.** `warp-cli` has Linux arm64 builds, but we should confirm our specific DO droplets (amd64) work the same as Orb VMs (arm64 on Apple Silicon).
5. **Doppler over SSH (dotfiles#5).** Unrelated to the mesh migration, but the current Doppler-keyring-over-SSH issue means the mesh-join step may still hit the same failure when bootstrapping a node over SSH. No worse than today.
6. **Removal of `lemming-likert.ts.net` references.** The current tailnet hostname is baked into `CLAUDE.md`, `docs/architecture.md`, README, and p10k. A migration would touch these.

## Recommended experiment — Orb-based testbed

**Hypothesis:** Cloudflare Mesh can replace our Tailscale setup without regressing any capability we actively use, with the likely exception of MagicDNS.

### Topology (3–4 Orb Ubuntu 24.04 VMs)

```
mesh-node-a  ← mesh node with CIDR route 10.10.1.0/24 (simulates hole-dev)
mesh-node-b  ← mesh node, plain participant (simulates mac-mini)
mesh-bastion ← mesh node with exit-node egress (simulates exit-node case)
mesh-client  ← optional: macOS host running Cloudflare One Client (simulates laptop)
```

### Phases

1. **Phase 0 — Paper readiness (this doc).** Done.
2. **Phase 1 — Baseline chezmoi-on-Orb.** Spin up one fresh Orb Ubuntu, run the existing (Tailscale) toolchain script end-to-end against it. Verify current dotfiles work on arm64 Orb. Reference only — no Cloudflare changes.
3. **Phase 2 — Cloudflare tenant prep.** In the Cloudflare Zero Trust dashboard: create a service token, add device-enrollment "Service Auth" policy for that token, enable device-to-device connectivity settings, note down `organization` team name. Store `auth_client_id` / `auth_client_secret` in Doppler under a new key (`CF_WARP_CLIENT_ID` / `CF_WARP_CLIENT_SECRET`).
4. **Phase 3 — Branch toolchain script.** On this branch (`experiment/cloudflare-mesh`), modify `run_once_before_install-toolchains.sh.tmpl` so on Linux it installs `cloudflare-warp` via the APT repo, writes `/var/lib/cloudflare-warp/mdm.xml` from Doppler, and starts the daemon. Leave Tailscale-install code intact behind a `CF_MESH_ENABLED` feature flag so both can coexist during the test.
5. **Phase 4 — Bring up mesh.** Bootstrap `mesh-node-a` and `mesh-node-b` with the branch. Verify:
   - `warp-cli registration show` returns a Mesh IP.
   - `ping <mesh-node-b-mesh-ip>` works from `mesh-node-a`.
   - SSH over Mesh IP works (even if unauthenticated-for-now).
6. **Phase 5 — Feature-by-feature validation.** Run through each row of the parity table. Specifically measure:
   - Whether there's an automatic per-node hostname or we need our own DNS zone.
   - Whether the Cloudflare One Client on macOS coexists with `mesh-client` Orb VM traffic cleanly.
   - Whether the browser terminal + short-lived cert flow is tolerable for our SSH use cases.
7. **Phase 6 — Go/no-go writeup.** Update this doc with findings. If go, draft a migration plan for the production mesh.

### Abort criteria (when to bail)

- Phase 5 reveals no workable MagicDNS-equivalent and we'd have to hand-manage DNS records for every node. (Possible outcome: live with it, since our node count is low — but surface the cost explicitly.)
- Phase 5 reveals Cloudflare One Client and Tailscale can't coexist even on a single test host, making the transition period risky across the 6-node production topology.
- Phase 3 hits a blocker on the headless bootstrap (e.g., `warp-cli` requires interactive auth even with service tokens) — would materially regress our "one-shot chezmoi init" story.

## What this experiment does NOT commit to

- Rolling out mesh in production. The paper evaluation plus Orb testbed is enough to make a go/no-go decision; the actual rollout is a separate PR with its own review.
- Deleting the Tailscale install path. Keep it behind a feature flag for at least one release cycle after a go decision, so rollback is one env var change.
- Changing the `hole-devenv` repo. That's a downstream concern — if Weaviate/Transparency Engine networking assumptions change, those adjustments live there, not here.

## Next concrete action

Create the Orb VMs and proceed to Phase 1. (Or: read this doc, push back on the plan, and adjust before we commit testbed time.)
