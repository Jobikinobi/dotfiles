# Headscale architecture — target end-state

This document describes what the hole-network looks like once the migration to Headscale is complete. It is **not** an installation guide — for the operator-facing cutover procedure see [`cutover-playbook.md`](cutover-playbook.md). For per-OS join recipes see [`per-os/`](per-os/).

Some of what is described here (per-node `tailscale cert`, public DNS publication of the base domain) is the **target state**, not the live state. Each section flags the delta from today. Caddy as the control-plane reverse proxy IS live as of 2026-06-05 (HOL-12).

## Component map

```
                                ┌─────────────────────────────────┐
                                │  Mac clients / Linux clients    │
                                │  (Tailscale client + login-     │
                                │   server pointed at headscale)  │
                                └────────────────┬────────────────┘
                                                 │ HTTPS (control)
                                                 │ + WireGuard UDP (data)
                                                 │
                                                 ▼
                                 https://hs.lab.hole-truth.org
                                                 │
                              (internal DNS or /etc/hosts → 192.168.68.77)
                                                 │
                                                 ▼
                                ┌─────────────────────────────────┐
                                │  Headscale VM (PVE VMID 112)    │
                                │  192.168.68.77                  │
                                │                                 │
                                │  Caddy on :443                  │
                                │  (LE cert via certbot DNS-01,   │
                                │   reloaded on renewal via       │
                                │   /etc/letsencrypt/renewal-     │
                                │   hooks/deploy/01-reload-       │
                                │   caddy.sh)                     │
                                │     │                           │
                                │     ▼                           │
                                │  headscale on 127.0.0.1:8080    │
                                │  (control plane v0.28.0)        │
                                └─────────────────────────────────┘
```

The Headscale VM is **only** a control plane. It does not run the Tailscale client itself — that is policy and there is no good reason to violate it. (Running `tailscaled` on the box that's also running headscale produces confusing interactions around MagicDNS, routes, and relay behavior.)

## Host inventory

| Role | Hardware | LAN IP | Tailnet IP | Notes |
|------|----------|--------|------------|-------|
| Headscale control plane | VM 112 on PVE | `192.168.68.77` | — (not a client) | Ubuntu. Caddy + headscale (nginx still installed but disabled — rollback insurance). Snapshots: `before-headscale-lab`, `headscale-working`, `pre-caddy-swap`. |
| Trial node `linux-test-01` | QEMU VM 108 on PVE | `192.168.68.70` | `100.64.0.1` | Joined as user `lab`. Has `/etc/hosts` entry for `hs.lab.hole-truth.org`. |
| Trial node `linux-test-02` | LXC 102 on PVE | (DHCP) | `100.64.0.2` | LXC required `lxc.cgroup2.devices.allow: c 10:200 rwm` + `lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file` + `features: nesting=1`. |
| PVE host | bare metal | `192.168.68.86` | — | Hypervisor for all the above. Console of last resort during cutover. |
| Alpine lab-controller (planned) | VM 107 on PVE | `192.168.68.74` | TBD | Currently offline. Will join via the Alpine recipe — separate issue. |
| Mac Studio | Apple Silicon | `192.168.68.168` | `100.94.84.6` (public TS, today) | Daily-driver workstation. Last machine to migrate. |
| Mac Mini | Apple Silicon | `192.168.68.68` | `100.119.161.120` (public TS, today) | |
| MacBook Air | Apple Silicon | `192.168.68.70` (collides with `linux-test-01` LAN — but different MAC and only one is ever up at a time on the same DHCP lease) | `100.115.1.29` (public TS, today) | |
| Lume macOS VM | guest of Mac Studio | `192.168.64.2` (lume vmnet) | — (no Tailscale yet) | Disposable. Where the macOS cutover experiment runs. |

The IP collision between `linux-test-01` (DHCP `.70`) and the MacBook Air (DHCP `.70` in the homelab README snapshot) is a tracker item — fine in practice today because they are never online at the same time on the same lease, but worth reserving distinct addresses on the router before the cutover gets to laptops.

## Naming

| Name | Resolves to | Owned by |
|------|-------------|----------|
| `hs.lab.hole-truth.org` | `192.168.68.77` | Internal DNS (target) / `/etc/hosts` line per joined node (today) |
| `<hostname>.tail.lab.hole-truth.org` | tailnet IP for `<hostname>` | Headscale MagicDNS |
| `<short-hostname>` | tailnet IP for `<hostname>` | Headscale MagicDNS (search-domain expansion) |
| `<hostname>.lan.lab.hole-truth.org` | LAN IP (future routed services) | Headscale `extra_records` (small) / split DNS (large) |

The DNS plan has three phases:

1. **Today** — Every joined node carries a `/etc/hosts` line: `192.168.68.77 hs.lab.hole-truth.org`. Trial nodes use this. The cutover playbook installs this line as part of the join.
2. **Medium term** — Publish `hs.lab.hole-truth.org` → `192.168.68.77` in the LAN's internal DNS (the `ddns` LXC at `.55` is the planned home). Joined nodes drop the `/etc/hosts` line and rely on resolver chain.
3. **Long term (optional)** — Split horizon: `hs.lab.hole-truth.org` resolves to `.77` internally and to the WAN IP externally (with router-side TCP 443 forward to `.77:443`). Required only if we want to onboard nodes from outside the LAN.

## Control-plane TLS

Caddy on `.77:443` terminates a Let's Encrypt cert for `hs.lab.hole-truth.org` issued via certbot's DNS-01 challenge through Cloudflare. Caddy proxies to `127.0.0.1:8080` (headscale); the upgrade-header dance nginx needed is automatic in Caddy's `reverse_proxy` directive.

Cert renewal stays under certbot's control (the "conservative" handoff from HOL-12). When certbot writes a renewed cert, `/etc/letsencrypt/renewal-hooks/deploy/01-reload-caddy.sh` runs `systemctl reload caddy`, which causes Caddy to re-read the cert files in place — no downtime.

nginx remains installed on the box but its unit is disabled. Rollback is `systemctl stop caddy; systemctl start nginx` (the nginx config still lives at `/etc/nginx/sites-enabled/headscale` pointing at the same backend).

Headscale itself never terminates TLS in this setup. Every client registration goes through Caddy.

**Caddyfile (live):**

```caddy
{
	admin localhost:2019
	auto_https off
}

:443 {
	tls /etc/letsencrypt/live/hs.lab.hole-truth.org/fullchain.pem /etc/letsencrypt/live/hs.lab.hole-truth.org/privkey.pem
	reverse_proxy 127.0.0.1:8080 {
		header_up X-Real-IP {remote_host}
	}
}
```

`admin localhost:2019` is required (not "off") because `caddy reload` uses the admin API. The admin endpoint is bound to loopback only.
`auto_https off` is required because we provide the cert manually — without it Caddy would try to issue its own.

## Headscale config (key invariants)

```yaml
server_url: https://hs.lab.hole-truth.org
listen_addr: 127.0.0.1:8080
metrics_listen_addr: 127.0.0.1:9090

tls_cert_path: ""        # TLS is handled by the front reverse proxy, NOT headscale
tls_key_path: ""

dns:
  magic_dns: true
  base_domain: tail.lab.hole-truth.org
  override_local_dns: true
  nameservers:
    global:
      - 1.1.1.1
      - 1.0.0.1
      - 2606:4700:4700::1111
      - 2606:4700:4700::1001
    split: {}
  search_domains: []
  extra_records: []
```

Notes:

- `tls_*` are empty by design — headscale is HTTP-only on loopback, the reverse proxy handles TLS.
- `magic_dns: true` + `base_domain` set is what makes `<hostname>.tail.lab.hole-truth.org` work without per-host `/etc/hosts` entries on joined nodes.
- `override_local_dns: true` makes the tailnet DNS the resolver for joined clients while connected. If a node has a local DNS service that must keep authority, set this to `false` and rely on search-domain expansion instead.
- `split` is empty for now. When the `lan.lab.hole-truth.org` zone is delegated to a real internal resolver, populate this so `.lan.` lookups go to the right place.
- `extra_records` is empty. For small routed-LAN tests (e.g., a single internal-only service that isn't on the tailnet), an `extra_records` entry is the lightest possible name registration. For more than a handful of records, switch to split DNS.

## Cert renewal

`certbot` runs as a snap on `.77` with the `certbot-dns-cloudflare` plugin. Renewal uses DNS-01 against the `hole-truth.org` zone in Cloudflare. The Cloudflare API token is scoped to `Zone:DNS:Edit` + `Zone:Zone:Read` on `hole-truth.org` only. Renewal cadence is the snap `snap.certbot.renew.timer` (~daily, late morning UTC).

On successful renewal, `/etc/letsencrypt/renewal-hooks/deploy/01-reload-caddy.sh` calls `systemctl reload caddy`. The cert files at `/etc/letsencrypt/live/hs.lab.hole-truth.org/{fullchain,privkey}.pem` are symlinks into `archive/`, so Caddy re-reading them picks up the new keypair without any file replacement on Caddy's side.

`certbot renew --dry-run` succeeds.

**Open security item**: the original Cloudflare API token was exposed in terminal output during initial setup. Treat it as compromised. The HOL-12 cert handoff chose the conservative path (keep certbot), so the token rotation was NOT done as part of that swap — it remains an outstanding item, tracked separately from the proxy change.

## Auth keys

User `lab` is the operating identity for the trial. Preauth keys are short-lived where possible (24h for single-shot, reusable for iterating). The CLAUDE recipe is:

```bash
# On .77 (headscale group member, no sudo needed for headscale CLI)
headscale preauthkeys create --user lab --reusable --expiration 24h
```

For long-lived nodes (post-trial), each node gets its own one-time preauth key, used once, then discarded.

**Do not bake reusable long-lived auth keys into a template that will be reused across machines.** A leaked template + a reusable key = arbitrary node enrollment.

## Lockout prevention (architectural)

- The Headscale control-plane VM is administered exclusively over LAN SSH (`192.168.68.77`) and the Proxmox console — never via the tailnet. Losing the tailnet must not lose the control plane.
- Every joined node retains LAN SSH reachability — public Tailscale and Headscale are both "extra" access paths, never the only one.
- Proxmox snapshots are the cheap rollback. `before-headscale-lab`, `headscale-working`, and `pre-caddy-swap` exist on VM 112 covering the high-risk operations.
- The `headscale users delete <user>` command will deregister every node owned by that user. Do not delete `lab` once production nodes are joined under it.

## Things this architecture does **not** do (today)

- **External enrollment.** No router-side port forward is set up; no Cloudflare-proxied public exposure. Onboarding from outside the LAN requires either the medium-term DNS phase + a port forward, or VPN-in-then-join.
- **Per-node TLS for services.** Stage 1 ships internal HTTP over the tailnet for multi-HTTP-per-node use cases. Per-node `tailscale cert` issuance is a follow-on (separate issue).
- **Subnet routing.** No `--advertise-routes` on any joined node yet. Once a node is added as a subnet router (the planned `route-prox-01` role), routes are explicitly approved via `headscale nodes approve-routes`.
- **ACLs.** Headscale runs with the default open-mesh policy. Tightening ACLs is a post-migration concern.
- **Tailscale Funnel equivalent.** Headscale does not have a "public Funnel" feature. Public exposure of an internal service goes through the standard reverse-proxy + DNS path, not the mesh.

## Related

- [`cutover-playbook.md`](cutover-playbook.md) — operator procedure
- [`rollback.md`](rollback.md) — get back to public Tailscale fast
- [`reverse-proxy.md`](reverse-proxy.md) — Caddy reference for multi-HTTP per node
