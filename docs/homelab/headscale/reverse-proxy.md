# Reverse proxy — multiple HTTP services per Headscale node

This is the operational pattern for the original reason the network is migrating to Headscale: **run multiple HTTP services on a single host behind one external endpoint**, using internal hostnames the tailnet already resolves. Public Tailscale's `serve` / `funnel` effectively caps a node at one HTTPS site without contortions; behind self-hosted Headscale, the answer is "run your own reverse proxy on the node, the way you would for any other Linux host."

The reference reverse proxy across the hole-network is **Caddy**. The headscale control plane on `.77` will also be on Caddy once the swap issue ("Swap nginx for Caddy on .77 …") lands — same package, same config style, one pattern to learn.

## Two stages

| Stage | Transport | Why |
|-------|-----------|-----|
| **Stage 1 (today)** | HTTP over the tailnet | WireGuard encrypts node-to-node already. Inside the mesh, internal HTTP is fine and avoids the per-node cert-issuance dance. Anything outside the tailnet cannot reach these services. |
| **Stage 2 (follow-up)** | HTTPS with `tailscale cert`-issued LE certs | Real, trusted TLS per node — useful when an external browser (via subnet router or future router-forwarded path) needs to hit a service. Requires the per-node cert automation, which is a separate issue, intentionally deferred. |

This document covers stage 1 in full and stage 2 as a forward-looking appendix.

## Stage 1: HTTP over the tailnet — single node, multiple services

### Goal

On a Headscale-joined node — let's say `linux-test-01` (`100.64.0.1`) — run three internal HTTP services:

- `metabase` on `127.0.0.1:3000`
- `grafana` on `127.0.0.1:3001`
- `weaviate` on `127.0.0.1:8080`

Other tailnet members should be able to hit:

- `http://linux-test-01/metabase/...`
- `http://linux-test-01/grafana/...`
- `http://linux-test-01/weaviate/...`

(Path-based routing, single host. Subdomain-based routing is also possible and is shown below as an alternative.)

### Install Caddy

```bash
# Debian/Ubuntu
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy
```

### `/etc/caddy/Caddyfile` — path-based routing

```
# Path-based: one host, services under /service-name/
:80 {
    # Anything under /metabase/ → metabase service.
    handle_path /metabase/* {
        reverse_proxy 127.0.0.1:3000
    }

    handle_path /grafana/* {
        reverse_proxy 127.0.0.1:3001
    }

    handle_path /weaviate/* {
        reverse_proxy 127.0.0.1:8080
    }

    handle {
        respond "linux-test-01 — services: /metabase, /grafana, /weaviate" 200
    }
}
```

Apply and verify:

```bash
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy

# From another tailnet member:
curl http://linux-test-01/
curl http://linux-test-01/metabase/
```

### `/etc/caddy/Caddyfile` — subdomain routing (alternative)

Subdomain routing reads more naturally for human URLs and avoids the `/path/` prefix appearing in app links. Requires that the MagicDNS base domain works for the subdomain — `service-a.linux-test-01.tail.lab.hole-truth.org` will NOT resolve through MagicDNS by default, but you can add `extra_records` entries in `/etc/headscale/config.yaml` for each subdomain, OR use a wildcard configuration trick.

The simpler (and recommended) form: use **distinct hostnames per service** rather than subdomains of one hostname. Put each service on its own Caddy node with its own MagicDNS hostname:

```
# On a node named "metabase" (100.64.0.5):
:80 {
    reverse_proxy 127.0.0.1:3000
}
```

Then other tailnet members hit `http://metabase/` directly. This collapses the reverse-proxy + service into a 1:1 relationship per node and avoids the multi-service routing config entirely.

**The multi-service-per-node pattern is the right tool when you have one beefy node and many small services. The one-service-per-node pattern is the right tool when each service is heavy enough to deserve isolation.** Pick deliberately; don't default to one or the other.

### `caddy fmt` and `caddy validate`

Caddy's `caddy fmt` rewrites the Caddyfile to canonical form (kills inconsistent indentation, reorders directives). `caddy validate` checks the syntax without applying it. Run both before every `systemctl reload caddy`:

```bash
sudo caddy fmt --overwrite /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

A reload (not restart) is non-disruptive — Caddy hot-swaps the running config without dropping connections. Reserve `systemctl restart caddy` for daemon updates.

### Binding to tailnet IP only

By default `:80` in a Caddyfile binds to ALL interfaces, including the LAN IP. If you only want the service reachable over the tailnet (LAN cannot reach it), bind to the tailnet IP explicitly:

```
# Discover with: tailscale ip -4
100.64.0.1:80 {
    ...
}
```

This makes the reverse-proxy mesh-only. The LAN can still SSH to the node by LAN IP, but cannot reach the services. Useful for services you don't want a curious LAN device stumbling onto.

### Logs

Caddy logs to systemd by default. Tail with:

```bash
sudo journalctl -u caddy -f
```

Per-site access logs require an explicit `log` directive — see the [Caddyfile reference](https://caddyserver.com/docs/caddyfile/directives/log). For most internal services you don't need them.

## Stage 2: HTTPS via `tailscale cert` (follow-on, separate issue)

**Not implemented yet.** This is what the per-node TLS cert automation issue ("Per-node `tailscale cert` automation for multi-HTTP nodes") covers. Sketch of what it will look like:

### Headscale-side prerequisite

`tailscale cert <fqdn>` proxies an ACME request through the headscale control plane to Let's Encrypt. For this to work, two conditions must hold:

- **The MagicDNS base domain (`tail.lab.hole-truth.org`) is publicly resolvable** so Let's Encrypt can complete the DNS-01 challenge. Today the zone is internal-only; this requires publishing it in Cloudflare (DNS-only, no proxy).
- **Headscale config has the relevant `tls_letsencrypt_*` (or equivalent v0.28+) keys** set so the headscale server acts as the ACME proxy for its clients.

Both conditions are part of the per-node-cert issue's scope.

### Per-node `Caddyfile` with `tailscale cert`-issued cert

Once issued via `tailscale cert <hostname>.tail.lab.hole-truth.org`, the cert files land in `/var/lib/tailscale/` (Linux) or `/Library/Tailscale/` (Mac). Caddy can point at them statically:

```
linux-test-01.tail.lab.hole-truth.org {
    tls /var/lib/tailscale/certs/linux-test-01.tail.lab.hole-truth.org.crt \
        /var/lib/tailscale/certs/linux-test-01.tail.lab.hole-truth.org.key

    handle_path /metabase/* {
        reverse_proxy 127.0.0.1:3000
    }
}
```

Renewal is via re-running `tailscale cert <fqdn>` (Caddy's auto-renewal does not work with non-public ACME). The follow-up issue provides a script + systemd-timer for automatic re-issuance.

## Things this document deliberately doesn't cover

- **External (off-tailnet) exposure.** Anything reachable from the public internet goes through a router-side port forward + Cloudflare DNS + (optionally) the existing public-edge nginx/Caddy on the WAN-facing host. The Headscale-internal reverse proxy is not the right layer for public exposure.
- **WebSocket / HTTP/2 / gRPC pass-through.** Caddy handles all three by default. If a service has weird requirements, see the [Caddy reverse-proxy reference](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).
- **Load balancing across multiple backends.** Possible (`reverse_proxy backend-a:3000 backend-b:3000`), but the hole-network doesn't have a current need; tracked as out-of-scope.
- **Authentication.** If a service needs auth in front of it, add it inside the `handle` block via Caddy's [`forward_auth`](https://caddyserver.com/docs/caddyfile/directives/forward_auth) or the upstream's own auth layer.

## Related

- [`architecture.md`](architecture.md) — the broader headscale architecture this fits into
- [`cutover-playbook.md`](cutover-playbook.md) — playbook §6 references this document
- The "Swap nginx for Caddy on .77" issue — control-plane consistency prerequisite
- The "Per-node `tailscale cert` automation" issue — stage 2 prerequisite
