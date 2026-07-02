# Cutover recipe — Linux (Debian / Ubuntu)

The well-trodden path. This is what `linux-test-01` (Ubuntu, QEMU VM 108) and `linux-test-02` (Ubuntu LXC 102) actually did. systemd + apt.

Read [`../cutover-playbook.md`](../cutover-playbook.md) first. This document covers only the OS-specific commands inside Section 5 (Per-OS join recipe). The preconditions, LAN-SSH-fallback contract, DNS prerequisite, and verification block all live there.

## Prerequisites (assumed satisfied per the playbook)

- Held-open LAN SSH session.
- Console-of-last-resort available (Proxmox web UI VM console for VMs, `pct enter` host shell for LXCs).
- `/etc/hosts` line present: `192.168.68.77 hs.lab.hole-truth.org`.
- Single-use preauth key generated on `.77` and ready to paste.
- For **LXC** targets only: the host-side LXC config has been edited and the container has been restarted with these three lines in `/etc/pve/lxc/<vmid>.conf`:
  ```
  features: nesting=1
  lxc.cgroup2.devices.allow: c 10:200 rwm
  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
  ```
  Without these, `tailscaled` falls back to slow userspace networking or fails to bring up `tailscale0` at all in unprivileged LXC. For QEMU VMs, none of this applies — Tailscale Just Works.

## Step 1: Install the official Linux Tailscale package

Skip this step if `dpkg -l tailscale` already shows it installed. Use the official package, not a snap or sideloaded build:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

The script auto-detects the distro and configures the appropriate apt repository under `/etc/apt/sources.list.d/`. Verify:

```bash
which -a tailscale
# Expected: /usr/bin/tailscale (and possibly nothing else)

/usr/bin/tailscale version
systemctl is-active tailscaled
# Expected: a 1.9x.x version; tailscaled = active
```

If `which -a tailscale` shows multiple binaries (Homebrew, snap, nix, etc.), the client/daemon version mismatch will bite you. Remove or path-shadow the non-official builds before continuing.

## Step 2: Clear any prior Tailscale state

If this is a fresh install, skip — `/var/lib/tailscale/` will be empty.

If this node was on public Tailscale before (the typical cutover case), clear the cached state so the new control plane sees a clean enrollment:

```bash
sudo /usr/bin/tailscale logout || true
sudo /usr/bin/tailscale down || true
sudo systemctl stop tailscaled
sudo rm -rf /var/lib/tailscale
sudo systemctl start tailscaled

# Wait for the daemon to come up.
for _ in 1 2 3 4 5; do
  /usr/bin/tailscale status &>/dev/null && break
  sleep 1
done

# Verify daemon is up but unlogged.
/usr/bin/tailscale status
# Expected: "Logged out." or similar
```

This is the start of the "cutover window" — the node is off the previous tailnet at this point. The window closes after step 4 verifies. Target: under 60 seconds total.

## Step 3: Confirm reachability to the control plane

This catches DNS / TLS / firewall issues before they cause a confusing `tailscale up` hang:

```bash
getent hosts hs.lab.hole-truth.org
# Expected: 192.168.68.77   hs.lab.hole-truth.org

curl -sf https://hs.lab.hole-truth.org/health
# Expected: {"status":"pass"}
```

If `getent` fails, the `/etc/hosts` line is missing. If `curl` fails with a TLS error, the cert is invalid or the reverse proxy isn't running. Either way, stop and fix before continuing.

## Step 4: Join Headscale

```bash
# Replace <YOUR_PREAUTH_KEY> with the single-use key generated on .77.
# Replace <hostname> with what this node should be called in MagicDNS — usually
# the short hostname, e.g., "mac-mini" or "my-vm".

sudo /usr/bin/tailscale up \
  --login-server=https://hs.lab.hole-truth.org \
  --authkey=<YOUR_PREAUTH_KEY> \
  --hostname=<hostname> \
  --accept-dns=true \
  --accept-routes=true \
  --reset
```

Notes on the flags:

- `--login-server` is the critical one. Plain `sudo tailscale up` defaults to Tailscale Inc. and will silently take you back to the public tailnet — exactly the cutover-undo failure mode.
- `--reset` ensures any leftover preference state from the previous tailnet is dropped, not merged.
- `--accept-dns=true` enables MagicDNS resolution for `*.tail.lab.hole-truth.org`. Required for the verification block to pass.
- `--accept-routes=true` is forward-looking — when the planned subnet router (`route-prox-01`) is added, this node will be ready to use routed LAN subnets without re-running `tailscale set`.
- `--hostname` becomes the MagicDNS short name. Pick it carefully — changing it later requires removing and re-adding the node in headscale.

## Step 5: Verification block (the contract)

This is the same block as Section 5 of the playbook. Run all four:

```bash
# 1. Status.
tailscale status
# Expected: "100.64.x.x  <hostname>  lab  linux -" for self

# 2. Tailnet IP assigned.
tailscale ip -4
# Expected: a 100.64.x.x address

# 3. Self DNSName.
tailscale status --json | jq -r '.Self.DNSName'
# Expected: <hostname>.tail.lab.hole-truth.org.

# 4. Peer reachability.
getent hosts linux-test-01
tailscale ping linux-test-01
# Expected: address returned, pong via direct or DERP
```

If any of the four fail, **stop and [`rollback`](../rollback.md)**. Do not troubleshoot forward.

## Step 6: Soak

Watch this terminal for 10 minutes. The two failure modes to look for:

- `tailscale status` flips to `Logged out` or shows a re-auth prompt — means the control plane rejected the session after initial accept. Logs:
  ```bash
  sudo journalctl -u tailscaled -n 50 --no-pager
  ```
- Peer ping fails after initially working — usually a DERP issue or a transient routing problem. Try again in 30 seconds; if it persists past 5 minutes, roll back.

If both pass, the cutover is complete. Mark the machine off in the playbook checklist and update the host inventory in [`../architecture.md`](../architecture.md).

## Known gotchas for Linux cutovers

- **LXC nodes drop `tailscale0` on host reboot** unless the `lxc.cgroup2.devices.allow` line was persisted properly. After a host reboot, verify with `ip link show tailscale0` on every LXC.
- **DERP-only connectivity** is normal between two LXC peers on the same Proxmox host because of how the bridge eats the direct-connect handshake. `tailscale ping` will report "via DERP" — that's fine, the throughput is acceptable, and direct connect resumes when one peer is on a different host.
- **Ubuntu 24.04 with `systemd-resolved`** can ignore `--accept-dns=true` because resolved already owns `/etc/resolv.conf`. Check `resolvectl status` to see whether `tailscale0` is listed; if not, `sudo tailscale set --accept-dns=true` won't help and you need `resolvectl dns tailscale0 100.100.100.100` (or the actual MagicDNS service IP from `tailscale status --json`).

## Related

- [`../cutover-playbook.md`](../cutover-playbook.md) — full procedure
- [`../rollback.md`](../rollback.md) — when this recipe fails
- [`linux-alpine.md`](linux-alpine.md) — OpenRC-based Alpine variant
