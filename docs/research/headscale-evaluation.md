# Headscale as a Tailscale Replacement — Evaluation

> Status: **paper evaluation**, pre-testbed.
> Branch: `experiment/headscale`.
> Tracking: [HOL-11](https://github.com/Jobikinobi/dotfiles) ("Headscale Features").
> Author notes as of 2026-06-03.

## Why consider this

- We currently depend on cloud-hosted Tailscale (`lemming-likert.ts.net`) as the only coordination plane for the mesh described in `docs/architecture.md`. The Tailscale-managed tailnet is convenient but it's a hard external dependency: acquisition risk, free-tier policy change, or a regional outage takes the homelab off the air.
- The intent (per the triggering CEO comment on HOL-11) is to fully replace cloud Tailscale with a self-hosted [Headscale](https://headscale.net) coordination server — same clients, same mesh semantics, our own control plane. Either before cutover or alongside, Headscale needs to reach feature parity for the capabilities we actually use.
- We have a parallel paper evaluation for [Cloudflare Mesh](./cloudflare-mesh-evaluation.md). The two are **competing replacements**, not complementary — see "Relationship to the Cloudflare Mesh evaluation" below.

## Current Tailscale footprint (what we actually use)

Reused from `cloudflare-mesh-evaluation.md` so we don't drift between docs. Derived from `run_once_before_install-tailscale.sh.tmpl`, `run_once_after_install-tailscale-ssh.sh.tmpl`, `entrypoint.sh`, `private_dot_ssh/config.tmpl`, `docs/architecture.md`.

| Use | Where | Notes |
|---|---|---|
| Linux headless auto-join | `TS_AUTHKEY` via Doppler in toolchain script | `sudo tailscale up --authkey=... --ssh` |
| Docker container auto-join | `entrypoint.sh` → `TS_AUTHKEY` env var | tailnet hostname via `TS_HOSTNAME` |
| MagicDNS hostnames | `ssh mac-mini`, `curl http://hole-dev:8000` | Tailnet `lemming-likert.ts.net` |
| Tailscale SSH | `--ssh` flag on join | Keyless SSH between tailnet members |
| Cross-provider mesh | macOS laptops + Mac Mini + DO droplets + Docker containers | 6ish nodes in production |
| Prometheus/Grafana access | hole-dev over tailnet | Monitoring traffic stays on the mesh |
| Per-node HTTPS certs | Implicit — none in use today | Reserved capability; `tailscale cert` not currently invoked anywhere in the repo |

## Headscale — feature parity table

Citations are Headscale upstream docs (`headscale.net/stable`) and the `juanfont/headscale` issue tracker, retrieved 2026-06-03. Latest stable Headscale release at time of writing: **v0.28.0** (2025-02-04, per GitHub releases page).

| Capability | Tailscale | Headscale | Parity |
|---|---|---|---|
| Peer-to-peer overlay with per-node CGNAT IP | Yes (`100.x.y.z`) | Yes — Headscale assigns from a configurable IPv4/IPv6 prefix | ✅ |
| Same `tailscale` / `tailscaled` clients | n/a | Yes — clients point at Headscale via `--login-server=<url>` | ✅ |
| Linux headless install (single-flag join) | `tailscale up --authkey=...` | `tailscale up --login-server=<url> --authkey=<key>` | ✅ |
| Auth key model (reusable / ephemeral / pre-approved) | Yes | Yes (`headscale preauthkeys create`) | ✅ |
| Docker / containerized node | Works via `TS_AUTHKEY` env + tailscaled in entrypoint | Same client, additional `--login-server` arg — no daemon-side changes required | ✅ |
| MagicDNS-style hostname resolution (`ssh mac-mini`) | Yes, automatic, free | Supported per [Headscale DNS ref](https://headscale.net/stable/ref/dns/) | ✅ |
| Tailscale SSH (`--ssh`) | Yes — short-lived certs minted by control plane | Supported by the Tailscale client against any control server | ✅ |
| ACLs / policies between nodes | Tailscale ACLs (HuJSON) | Same HuJSON policy file format | ✅ |
| Subnet router (`--advertise-routes`) | Yes | Yes (server must approve via `headscale routes enable`) | ✅ (minor admin step) |
| Exit nodes | Yes | Yes | ✅ |
| DERP relays | Tailscale-operated global DERP, free | Self-host required for production; can opt in to Tailscale's public DERP map but that re-introduces the cloud dependency | ⚠️ self-host work |
| HTTPS for the Headscale **server endpoint** | n/a (Tailscale's problem) | Native: `tls_letsencrypt_hostname` (HTTP-01 or TLS-ALPN-01) or `tls_cert_path` / `tls_key_path` per [TLS ref](https://headscale.net/stable/ref/tls/) | ✅ |
| Per-**node** HTTPS certs via `tailscale cert <node.tailnet.domain>` | Yes — built-in, free, uses DNS-01 against `*.ts.net` | **Not implemented.** Tracked as [juanfont/headscale#2137](https://github.com/juanfont/headscale/issues/2137), labelled `tailscale-feature-gap`, milestoned **v0.34.0**, no PR. `tailscale serve` is blocked on the same gap ([#1530](https://github.com/juanfont/headscale/issues/1530)). | ❌ **hard gap** |
| Free for personal use | Yes (20 users / 100 devices) | Self-hosted, no per-node licensing | ✅ |
| Multi-region HA control plane | Tailscale runs HA for us | Single binary, SQLite/Postgres; HA is our problem | ⚠️ ops cost |

Legend: ✅ parity • ⚠️ gap or degraded • ❌ hard gap • 🎁 self-hosting advantage

## The cert-generation gap, in detail

The CEO singled out cert generation as the first capability check. Findings, primary-sourced 2026-06-03:

1. **Headscale's TLS support is for the Headscale server itself, not for nodes.** The `tls_letsencrypt_hostname` / `tls_cert_path` knobs documented at [headscale.net/stable/ref/tls/](https://headscale.net/stable/ref/tls/) provision a cert that secures the control-plane HTTPS endpoint nodes connect to. They do **not** mint certs for individual node FQDNs.

2. **`tailscale cert <node.tailnet>` is unsupported by Headscale today.** [Issue #2137](https://github.com/juanfont/headscale/issues/2137) is the upstream feature request, opened 2024-09-16, currently milestoned for **v0.34.0** with no linked PR. Current stable is v0.28.0. The closest near-term proxy was a request for `tailscale serve` ([#1530](https://github.com/juanfont/headscale/issues/1530)), which depends on the same plumbing and is also unimplemented.

3. **Why it's hard upstream.** Tailscale's implementation works because the Tailscale control plane owns `*.ts.net` DNS and runs an ACME DNS-01 solver. To replicate this Headscale must (a) own a real base domain we control, (b) run an ACME DNS-01 capable solver against that zone, and (c) wire the LocalAPI path that `tailscaled` uses to request and receive certs. Steps (a) and (b) are our infra; step (c) is the upstream blocker.

4. **Workarounds short of upstream parity.**
   - **Node-local ACME sidecar.** Each node runs Caddy / Traefik / Lego with its own Cloudflare API token, ACME DNS-01 against `<node>.mesh.<domain>`. Works for HTTPS services exposed on the mesh, but every node needs the credential and a DNS record. Not `tailscale cert`.
   - **Wildcard cert distributed via chezmoi + age.** One Let's-Encrypt-wildcard cert for `*.mesh.<domain>`, encrypted in the repo, decrypted onto each node. Operationally awkward — 90-day rotation, every renewal touches every node.
   - **Stay on cloud Tailscale for cert-issuing nodes only.** Hybrid: Headscale becomes the default control plane; any node that needs `tailscale cert` keeps a cloud-Tailscale install behind a feature flag until #2137 lands. Retains the dependency we're trying to remove.

**Bottom line on cert generation:** The first parity check fails today against upstream Headscale. We need a product decision (see Blocker #1 below) about whether that is acceptable as a known gap for cutover or whether cutover is gated on it.

## Known gaps and open questions

### Hard blockers requiring product / infra decisions

1. **Per-node cert generation parity is a hard "no" today.** As above. Decide whether (a) we cut over and accept "no `tailscale cert`" until upstream v0.34.0, (b) we stay on cloud Tailscale until #2137 lands, or (c) we ship one of the workarounds (sidecar / wildcard) and explicitly degrade off the Tailscale-issued model. This is a **CEO call**, not a CTO call — it changes user expectations.

2. **Base domain choice for the Headscale tailnet.** Tailscale gave us `lemming-likert.ts.net` for free. Headscale needs us to pick a real domain we own (e.g. `mesh.<somedomain>`) and commit to it — node FQDNs, ACL `src`/`dst` patterns, and any future per-node certs all bake the choice in. **Needs product input** on which existing domain (or new registration) to use; we already use Cloudflare as registrar per `docs/research/cloudflare-mesh-evaluation.md`.

3. **Cloudflare API token for ACME DNS-01.** Scoped to `Zone:DNS:Edit` on the chosen zone, stored in Doppler under a new key (proposed: `HEADSCALE_CLOUDFLARE_API_TOKEN`). **Needs infra input** — Joe to mint and store.

4. **Where Headscale itself runs.** Options: (a) Proxmox LXC on the homelab box (cheap, but the homelab is single-host and the control plane is then unreachable from outside the LAN unless we add a tunnel), (b) DigitalOcean droplet alongside `hole-dev` (always-on, public, ~$6/mo), (c) Cloudflare Tunnel fronting a private LXC. **Needs infra input** — this is an architectural choice with ongoing cost.

5. **DERP relay strategy.** For node-to-node connectivity when direct UDP fails. Self-hosting a `derper` is a separate single-binary deploy; using Tailscale's public DERP map re-introduces the cloud dependency. Defer until phase 4, but flag now.

6. **HA / recovery for the control plane.** Tailscale's outage SLO is theirs; Headscale's is ours. Single binary + SQLite is easy to back up but not HA. Acceptable for homelab use; document the RTO.

### Soft considerations

7. **Token / authkey scope.** `TAILSCALE_AUTHKEY_SERVER` in Doppler (per `run_once_before_install-tailscale.sh.tmpl`) becomes `HEADSCALE_AUTHKEY_SERVER`. Tag scheme (`tag:server`) carries over identically.

8. **Coexistence during migration.** A node can only point at one control server at a time. A clean cutover sequence per node is `tailscale logout` → re-`tailscale up --login-server=<headscale>`. Reversible: the node has both auth keys available.

9. **References that bake the tailnet name.** `docs/architecture.md`, `README.md`, `CLAUDE.md`, `dot_p10k.zsh` (search confirms no references to either `headscale` or the literal `lemming-likert` in the current tree as of this commit — the tailnet name appears only in the Cloudflare-mesh research doc). A migration would rewrite those references in one PR.

## Relationship to the Cloudflare Mesh evaluation

We have two open paper evaluations for replacing Tailscale: this one (Headscale) and [Cloudflare Mesh](./cloudflare-mesh-evaluation.md). They are **alternatives** — picking one means shelving the other. Working tradeoff one-liner:

- **Cloudflare Mesh** consolidates on a vendor we already use (registrar, CDN, Project Galileo) and gives us posture checks / post-quantum / WARP coexistence as bonus features, at the cost of a per-account node cap, MagicDNS-equivalent uncertainty, and a non-trivial Docker-container story.
- **Headscale** keeps the existing client + MagicDNS + ACL semantics we already understand, removes the cloud dependency entirely, and has a clear DERP / cert-generation gap that we control the timeline on.

**Recommendation, pending CEO review:** Do **not** run both testbeds in parallel. Pick a primary based on the cert-gen blocker (Blocker #1): if "no per-node certs until upstream v0.34" is acceptable, Headscale is the cheaper, faster path because it changes nothing about the clients; if not, the Cloudflare Mesh path is worth the deeper rebuild because it's not blocked on third-party feature work.

## Recommended experiment — Orb-based testbed (Headscale)

**Hypothesis:** Headscale can replace our cloud Tailscale control plane without regressing any capability we actively use, with the known exception of per-node `tailscale cert`.

### Topology (2 Orb Ubuntu 24.04 VMs + 1 macOS test client)

```
headscale-srv   ← Headscale v0.28.0 binary, Caddy in front for TLS, base domain mesh.<domain>
node-a          ← Ubuntu 24.04, tailscaled, --login-server=https://headscale-srv.<domain>
node-b          ← Ubuntu 24.04, tailscaled, --login-server=…  (verifies node↔node)
[macstudio]     ← optional: switch one real Mac to headscale auth key, with cloud-Tailscale rollback ready
```

### Phases

1. **Phase 0 — Paper readiness (this doc).** Done on this branch.
2. **Phase 1 — Decisions captured.** Blockers #1–#4 above resolved in writing (issue comment or follow-up sub-issues). Until those land, Phase 2 is wasted infra time.
3. **Phase 2 — Headscale-srv up with TLS for the server endpoint.** Stand up the chosen host with Headscale v0.28.0, point `tls_letsencrypt_hostname` at `headscale.<basedomain>`, verify HTTPS handshake succeeds. **Acceptance: `curl https://headscale.<basedomain>/health` returns 200 with a valid LE chain.** This is the first cert check — and the one that *should* pass.
4. **Phase 3 — Two Orb nodes join.** Create authkeys (`headscale preauthkeys create`), bring up `node-a` and `node-b` with `tailscale up --login-server=https://headscale.<basedomain> --authkey=…`. Verify `tailscale status`, `ping`, `tailscale ssh`.
5. **Phase 4 — Capability checklist.** Run through the parity table row by row on the testbed, recording each as ✅ / ⚠️ / ❌:
   - MagicDNS lookup (`ssh node-b` from node-a using MagicDNS hostname).
   - ACL test (HuJSON policy denying node-a → node-b on a port; verify drop).
   - Subnet router approval flow (`tailscale up --advertise-routes=…` + `headscale routes enable`).
   - Tailscale SSH between Orb nodes.
   - **Per-node cert check (expected to fail today).** Attempt `tailscale cert node-a.mesh.<basedomain>`; capture the exact error from the LocalAPI. This is the second, and critical, cert check.
6. **Phase 5 — One-Mac pilot.** Switch one production Mac to Headscale with cloud-Tailscale install retained behind the `TS_LOGIN_SERVER` env feature flag. Reversible by `tailscale logout && tailscale up` to the cloud tailnet.
7. **Phase 6 — Go/no-go writeup.** Append findings to this doc. If go, draft migration plan: order of node cutover, DERP rollout, tailnet-name reference rewrite PR.

### Abort criteria (when to bail)

- Phase 2 fails: Headscale endpoint cert won't issue (DNS-01 misconfiguration is the usual cause; if not fixable in an hour, infra problem worth raising before sinking more time).
- Phase 4 reveals additional unflagged parity gaps beyond `tailscale cert`. ACL semantics, MagicDNS edge cases, and subnet-route propagation are the likely surprises.
- Phase 5 one-Mac pilot shows mesh-wide regressions when even one node is on Headscale and others are still on cloud Tailscale (expected to be fine — they're different tailnets — but if the Mac multiplexes both interfaces oddly, that's the signal).

## What this evaluation does NOT commit to

- Standing up Headscale in production. Phase 2 happens on a testbed, on a subdomain we accept may be torn down.
- Removing the Tailscale install path from chezmoi. Keep it behind a feature flag for at least one release cycle after a go decision, mirroring the Cloudflare-mesh playbook.
- Resolving the cert-generation gap. The plan above explicitly leaves Blocker #1 to the CEO and documents the workarounds; it does not pick one.
- Touching `hole-devenv` or production secrets. Those changes belong in separate PRs once a primary path is chosen.

## Next concrete action

The next concrete action is **not** "spin up Orb VMs." It's a CEO/product decision on Blocker #1 (the cert-generation gap is acceptable as a known regression, or it isn't) and on Blocker #2 (base domain choice). Until those land, Phase 2 should not start.

If both are answered "yes, acceptable" / "use domain X," then phase order is: provision Cloudflare API token → stand up Headscale on the chosen host → run Phase 4 capability checklist → reconvene.
