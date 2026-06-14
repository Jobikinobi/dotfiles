# Installing Cloudflare One (WARP) on a Linux vnet node

Runbook for enrolling a Linux host into a Cloudflare mesh / Zero Trust vnet via
the WARP client (`warp-cli`). Written after the Cloudflare-published install
command broke apt on the Trixie box (2026-06-13) — see **The trap** below.

> **Read this first — WARP vs Tailscale conflict.** Cloudflare One/WARP and
> Tailscale both claim the system TUN interface and both hijack DNS. They cannot
> run on the same host at the same time. Only install WARP on a node you are
> deliberately moving onto the Cloudflare mesh, and uninstall/disable Tailscale
> there first. Context: [`docs/research/cloudflare-mesh-evaluation.md`](../research/cloudflare-mesh-evaluation.md).

## The trap

Cloudflare's website (and some copy-paste guides) hand you a repo line with the
**suite/codename left blank**:

```
# WRONG — what broke apt on the Trixie box
deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/  main
                                                                                                         ^^ codename missing (double space)
```

apt parses `main` as the **suite** and then finds no **component**, so every
`apt update` on the machine dies with:

```
Error: Malformed entry 1 in list file /etc/apt/sources.list.d/cloudflare-client.list (Component)
Error: The list of sources could not be read.
```

It's a hard parse error, so it blocks *all* apt operations, not just the
Cloudflare repo. The keyring is fine — only the source line is malformed. The
fix is to put the real codename (e.g. `trixie`) between the URL and `main`.

## Correct install

The WARP apt repo uses the **distro codename** as the suite (unlike `cloudflared`,
which uses the literal `any`). `$(. /etc/os-release; echo "$VERSION_CODENAME")`
resolves it automatically, so the same block works on any supported release.

```bash
# 1. GPG key (dearmored binary keyring, signed-by convention)
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
  | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

# 2. Repo — note the codename between the URL and `main`
. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${VERSION_CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

# 3. Install
sudo apt-get update && sudo apt-get install -y cloudflare-warp
```

### Verified supported codenames (checked 2026-06-13)

`https://pkg.cloudflareclient.com/dists/<codename>/InRelease` returns HTTP 200 for:

| Distro            | `VERSION_CODENAME` |
|-------------------|--------------------|
| Debian 13         | `trixie`           |
| Debian 12         | `bookworm`         |
| Debian 11         | `bullseye`         |
| Ubuntu 24.04      | `noble`            |
| Ubuntu 22.04      | `jammy`            |
| Ubuntu 20.04      | `focal`            |

If `apt-get update` 404s on a brand-new release, Cloudflare hasn't published that
suite yet — pin to the previous LTS codename rather than leaving it blank.

The repo signing key fingerprint (verify with `gpg --show-keys <keyring>`):

```
C068 A2B5 7717 7519 3CBE  1F2F 6E2D D217 4FA1 C3BA
Cloudflare Package Repository <support@cloudflare.com>
```

## Headless / mesh enrollment

For a server node (no browser), enroll with a Zero Trust **service token** rather
than the interactive `warp-cli registration new` browser flow:

```bash
sudo warp-cli registration new <team-name>        # or via mdm.xml, below
warp-cli connect
warp-cli registration show                         # confirm a mesh IP is assigned
```

The fully unattended path writes `/var/lib/cloudflare-warp/mdm.xml` with
`auth_client_id` / `auth_client_secret` from a Service Auth policy. Store those
in Doppler (proposed keys `CF_WARP_CLIENT_ID` / `CF_WARP_CLIENT_SECRET`) — see
the mesh evaluation's Phase 2/3 for the dashboard prerequisites.

## Recovering a node that's already broken

If a malformed source line is already blocking apt, remove the offending file
and re-run update:

```bash
sudo rm -f /etc/apt/sources.list.d/cloudflare-client.list
sudo apt update
```

Then re-add it correctly with the **Correct install** block above.

## Related

- `cloudflared` (tunnel daemon, different repo — `…/cloudflared any main`) is
  installed automatically by
  [`run_once_after_install-cloudflared.sh.tmpl`](../../run_once_after_install-cloudflared.sh.tmpl).
  That repo uses `any`, not a codename, so it is not subject to this trap.
- [Cloudflare Mesh evaluation](../research/cloudflare-mesh-evaluation.md) — why we
  might move nodes onto WARP, and the open questions (MagicDNS equivalent, Docker
  enrollment, SSH replacement).
