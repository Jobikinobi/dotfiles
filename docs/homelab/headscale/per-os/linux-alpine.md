# Cutover recipe — Alpine Linux

This recipe was exercised on the `lab-controller` (PVE VM 107, Alpine 3.23.4) on 2026-06-05. The host is now node 7 (`100.64.0.7`) on Headscale. **The notes here reflect what actually happened, not the upstream-conventions guess.**

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

## Known Alpine gotchas (observed on the 2026-06-05 `lab-controller` join)

Real issues that happened, in the order they bit:

- **DHCP lease drift.** The doc and the parent issue called this host `.74` (its public-tailnet name was `alp.lemming-likert.net`, a `.74` lease). After being powered off for a while and coming back up, it took a new DHCP lease at `192.168.68.51`. Always re-probe `arp` or `headscale nodes list` for the actual current IP before treating a doc-recorded address as truth.
- **`apk` repositories misconfigured.** `/etc/apk/repositories` listed `https://alpinelinux.org` twice with no `/v3.23/main` or `/v3.23/community` path component. `apk add` resolved nothing until the file was rewritten. **Fix once on the affected host**:
  ```
  https://dl-cdn.alpinelinux.org/alpine/v3.23/main
  https://dl-cdn.alpinelinux.org/alpine/v3.23/community
  ```
  followed by `apk update`. The community repo line is required because `tailscale` ships there.
- **No `sudo`. `doas` wants a first-use password.** Out-of-the-box Alpine has no `sudo`. `doas` is configured as `permit persist :wheel` — group `wheel` can use `doas`, but the first invocation in a session prompts for the user's password. If the agent has SSH-key access to `jth@host` but no password, the agent cannot escalate. **Fix once on a fresh Alpine VM, via root console (Proxmox web UI):**
  ```sh
  echo "permit nopass :wheel" > /etc/doas.d/wheel.conf
  ```
  This was the blocker that paused HOL-6 between 2026-06-04 (when the VM was booted) and 2026-06-05 (when the operator fixed it via root console). Build it into the Alpine VM template if you provision more.
- **Hostname carryover from the previous tailnet.** The VM came up as `alp.lemming-likert.net`, its public-TS name. Headscale registration used `--hostname=lab-controller`, which the recipe step 4 does — but `hostnamectl` (or `/etc/hostname` on Alpine, since there's no systemd) was not changed, so SSH banners and `uname -n` still show the old name. Decide whether you want the OS hostname to match the headscale name; if yes, edit `/etc/hostname` + `reboot`.

Items to verify on the next Alpine cutover (these did not bite on `lab-controller` but are still worth probing):

- **`/dev/net/tun` permissions** on minimal Alpine installs. `ls -la /dev/net/tun` after install.
- **`busybox` getent variant** — `lab-controller` had `getent` available, but minimal installs may not. Use `nslookup` as fallback.
- **DNS resolution under musl libc**. `--accept-dns=true` worked on `lab-controller` without the manual `resolv.conf` workaround.
- **OpenRC service ordering**. `tailscaled` started cleanly on boot; `rc_need="net"` was not required.

## Related

- [`../cutover-playbook.md`](../cutover-playbook.md) — full procedure
- [`../rollback.md`](../rollback.md) — rollback path
- [`linux-debian.md`](linux-debian.md) — the well-trodden Debian/Ubuntu variant
