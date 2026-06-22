# Cutover recipe — Alpine Linux

The lab-controller at `.74` (VM 107) is the first Alpine target. As of 2026-06-04, that host is offline — this recipe is a sketch based on Alpine + Tailscale upstream conventions, **not yet exercised on a real host**. Update with measured values when the `.74` join happens.

Read [`../cutover-playbook.md`](../cutover-playbook.md) first.

## Differences from the Debian recipe

| Concern | Debian | Alpine |
|---------|--------|--------|
| Init system | systemd | OpenRC |
| Package manager | apt | apk |
| Tailscale install path | `curl …/install.sh` | `apk add tailscale` |
| Daemon service name | `tailscaled` (`systemctl`) | `tailscaled` (`rc-service` / `rc-update`) |
| Service enable | `systemctl enable tailscaled` | `rc-update add tailscaled default` |
| Log inspection | `journalctl -u tailscaled` | `tail -f /var/log/messages` (or `logread` on busybox) |

Everything else — `/etc/hosts` requirement, preauth key, `tailscale up --login-server=…`, verification block — is identical.

## Step 1: Install

```bash
# Update repo state if necessary
sudo apk update

# Install Tailscale from the community repo
sudo apk add tailscale
```

If the community repo is not enabled, edit `/etc/apk/repositories` to uncomment the `community` line for your Alpine version, then re-run `apk update`.

## Step 2: Enable and start the daemon

```bash
sudo rc-update add tailscaled default
sudo rc-service tailscaled start

# Wait for socket.
for _ in 1 2 3 4 5; do
  tailscale status &>/dev/null && break
  sleep 1
done

tailscale status
# Expected: "Logged out." (fresh install) or "..." if re-joining
```

## Step 3: Clear any prior state (cutover case)

```bash
sudo tailscale logout || true
sudo tailscale down || true
sudo rc-service tailscaled stop
sudo rm -rf /var/lib/tailscale
sudo rc-service tailscaled start
```

## Step 4: Verify reachability + join

```bash
# Reachability check (assumes /etc/hosts entry is already present per the playbook).
getent hosts hs.lab.hole-truth.org
curl -sf https://hs.lab.hole-truth.org/health

# Join. Same flags as the Debian recipe.
sudo tailscale up \
  --login-server=https://hs.lab.hole-truth.org \
  --authkey=<YOUR_PREAUTH_KEY> \
  --hostname=<hostname> \
  --accept-dns=true \
  --accept-routes=true \
  --reset
```

## Step 5: Verification block

Same as the Debian recipe. See [`../cutover-playbook.md`](../cutover-playbook.md) §5.

## Known Alpine gotchas (to verify on first real cutover)

These are upstream-reported issues — confirm or refute when `.74` is actually cut over.

- **`/dev/net/tun` permissions** may need a one-time `mknod` on minimal Alpine installs that omit the device. Check with `ls -la /dev/net/tun` — if missing, `sudo mkdir -p /dev/net && sudo mknod /dev/net/tun c 10 200 && sudo chmod 0666 /dev/net/tun`.
- **`busybox`-based environments** sometimes lack `getent`. Use `nslookup hs.lab.hole-truth.org` or `cat /etc/hosts | grep hs.lab`.
- **DNS resolution**: Alpine uses `musl libc`, which has historically had weaker DNS-resolver behavior than glibc. If `--accept-dns=true` does not produce working MagicDNS, fall back to running `tailscale set --accept-dns=false` and adding a manual `/etc/resolv.conf` entry for the MagicDNS IP from `tailscale status --json`.
- **OpenRC service ordering**: if `tailscaled` starts before `net` is up, it may fail. Verify with `rc-status` post-boot. Add `rc_need="net"` to `/etc/conf.d/tailscaled` if so.

## Status of this document

**Skeleton, not yet validated.** Update each "to verify" item with concrete observed behavior the first time `.74` (or any other Alpine host) is cut over. Particular fields to fill in:

- Actual `apk` repo line if the community repo had to be enabled.
- Exact `rc-service` output on startup.
- `tailscale version` reported on Alpine.
- Anything `tailscale status --json | jq -r '.Self.DNSName'` returns (sanity-check the FQDN format).
- Whether `--accept-dns=true` worked out of the box or needed the musl workaround.

## Related

- [`../cutover-playbook.md`](../cutover-playbook.md) — full procedure
- [`../rollback.md`](../rollback.md) — rollback path
- [`linux-debian.md`](linux-debian.md) — the well-trodden Debian/Ubuntu variant
