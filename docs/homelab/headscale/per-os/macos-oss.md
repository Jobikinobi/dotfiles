# Cutover recipe — macOS (open-source brew build)

The recommended macOS path. The open-source Tailscale build installed via Homebrew accepts the same `--login-server` and `--authkey` flags as the Linux client, which means `tailscale up` from a script Just Works. The App Store build requires the `defaults write … ControlURL …` workaround instead (see [`macos-appstore.md`](macos-appstore.md)); avoid it for any Mac that needs to be scripted.

Read [`../cutover-playbook.md`](../cutover-playbook.md) first.

## Measured baseline (lume macOS VM, 2026-06-04)

The reachability and TLS-handshake assumptions in the playbook were verified empirically on the disposable lume VM. Pinning what was observed so the recipe below is grounded in reality, not assumed behavior.

| Test | Result |
|------|--------|
| Guest macOS version | 26.5 (Tahoe), arm64 |
| Default route from VM | gateway `192.168.64.1` (lume vmnet), via `en0` |
| TCP `192.168.68.77:443` from inside VM | succeeds — lume's NAT'd vmnet allows outbound to LAN |
| TLS handshake against `https://hs.lab.hole-truth.org` (with `--resolve` workaround) | succeeds — `CN=hs.lab.hole-truth.org`, valid until Sep 2026 |
| `GET /health` response | `{"status":"pass"}` |
| `/etc/hosts` entry for `hs.lab.hole-truth.org` | not present by default — must be added before join |
| Tailscale pre-installed on the VM | no (`tailscale` CLI missing, no `/Applications/Tailscale.app`, no `ControlURL` pref) |

Implication: the lume VM is a clean-slate environment. It exercises the **fresh-install path** for the macOS Headscale join, but not the **cutover path**. For the cutover-rehearsal use case (HOL-7), the experiment needs to install public Tailscale on the VM first, then switch to Headscale, then switch back as a rollback drill.

## Production observed state (Mac Studio, 2026-06-05 cutover)

The Mac Studio (`josephs-mac-studio`) was cut over to Headscale on 2026-06-05 as part of the same batch that brought up the Linux nodes. This is the only production macOS cutover so far. Observed state, post-cutover:

| Check | Result |
|-------|--------|
| `tailscale ip -4` | `100.64.0.10` (Headscale tailnet) |
| `defaults read /Library/Preferences/io.tailscale.ipn.macos ControlURL` | absent — confirms this is the open-source brew build, not App Store |
| `/Applications/Tailscale.app` | absent — the App Store build had been removed before the join (the cohabitation conflict described in step 1 below) |
| `which tailscale` | `/opt/homebrew/bin/tailscale` |
| `nc -zv 192.168.68.77 443` from Mac Studio | succeeds |
| `getent hosts hs.lab.hole-truth.org` | `192.168.68.77` (via `/etc/hosts`) |
| `curl https://hs.lab.hole-truth.org/health` | `{"status":"pass"}` |
| `tailscale status` health-check warning | **"Tailscale SSH enabled, but access controls don't allow anyone to access this device. Update your tailnet's ACLs to allow access."** — see "Known gotchas" below. |
| Client/daemon version | **skewed**: CLI `1.98.5-t295179bf2`, daemon `1.98.3-t8f2c8d6a1` — see "Known gotchas". |

Headscale's `nodes list` confirms the node as online under user `lab`, OS `macOS`, `online: true`.

## Step 0: Prerequisites

Same as the playbook:
- Held-open LAN SSH session to the Mac (over LAN IP, not tailnet alias).
- For headless / remote Macs: console plan in place (physical screen, VNC, or for lume: `lume vnc` URL ready).
- For the Mac Studio specifically: a **second** held-open LAN SSH session in a different terminal window. This machine is "cannot afford to lose"; spend the extra paranoia.

## Step 1: Refuse to run alongside Tailscale.app (App Store build)

The open-source brew build's `tailscaled` and the App Store `Tailscale.app`'s sandboxed system extension cannot coexist on the same Mac — they fight over the `utun` interface and produce a confusing version flap. If `Tailscale.app` is present, you have to remove it before installing the brew build:

```bash
# Check.
ls -la /Applications/Tailscale.app 2>/dev/null && echo "App Store build present — must remove"
systemextensionsctl list 2>/dev/null | grep "io.tailscale.ipn.macsys.*activated" && echo "System extension still active — must remove"

# To remove (interactive, requires a reboot):
sudo rm -rf /Applications/Tailscale.app
# Then reboot the Mac to clear the activated system extension.
# After reboot, verify:
systemextensionsctl list 2>/dev/null | grep -c "io.tailscale.ipn.macsys.*activated"
# Expected: 0
```

If `Tailscale.app` is present and the user wants to stay on the App Store build, **do not use this recipe** — go to [`macos-appstore.md`](macos-appstore.md).

## Step 2: Install via Homebrew

```bash
# Install the formula (not the cask, which would install the App Store build).
brew install tailscale

# Start the daemon. On macOS, tailscaled must run as root to manage utun + DNS.
sudo brew services start tailscale

# Wait for the socket.
for _ in 1 2 3 4 5; do
  tailscale status &>/dev/null && break
  sleep 1
done

# Verify.
which -a tailscale
# Expected: /opt/homebrew/bin/tailscale (Apple Silicon) or /usr/local/bin/tailscale (Intel)

tailscale version
# Expected: 1.9x.x
```

If `Tailscale.app` later somehow gets reinstalled (App Store auto-update, user clicks the cask), the brew build's daemon will silently fail with a version mismatch. This is the most common Mac-specific failure mode and the reason the cutover playbook recommends the brew build globally.

## Step 3: Clear any prior Tailscale state (cutover case)

If this Mac was on public Tailscale before (the typical case), wipe state:

```bash
sudo tailscale logout || true
sudo tailscale down || true
sudo brew services stop tailscale
sudo rm -rf /Library/Tailscale       # client state
sudo rm -rf /var/db/tailscale        # daemon state — path varies, safe to rm both if present
sudo brew services start tailscale

# Wait again.
for _ in 1 2 3 4 5; do
  tailscale status &>/dev/null && break
  sleep 1
done
```

The cutover window opens here. Target: less than 60 seconds to the verified state in step 6.

## Step 4: Add the `/etc/hosts` entry

macOS reads `/etc/hosts` before any DNS lookup, so this works the same as Linux:

```bash
if ! grep -q "hs.lab.hole-truth.org" /etc/hosts; then
  echo "192.168.68.77 hs.lab.hole-truth.org" | sudo tee -a /etc/hosts
fi

# Verify.
dscacheutil -q host -a name hs.lab.hole-truth.org
# Expected: ip_address: 192.168.68.77
# (dscacheutil is the macOS equivalent of getent — there is no getent on macOS by default)
```

## Step 5: Confirm reachability

```bash
nc -zv -G 5 192.168.68.77 443
# Expected: Connection to 192.168.68.77 port 443 [tcp/https] succeeded!

curl -sf https://hs.lab.hole-truth.org/health
# Expected: {"status":"pass"}
```

If either fails, stop. The cutover window is open; either complete it quickly or roll back.

## Step 6: Join Headscale

```bash
sudo tailscale up \
  --login-server=https://hs.lab.hole-truth.org \
  --authkey=<YOUR_PREAUTH_KEY> \
  --hostname=<hostname> \
  --accept-dns=true \
  --accept-routes=true \
  --reset
```

For `<hostname>`, prefer the short LocalHostName:

```bash
scutil --get LocalHostName
# Use the output as --hostname value
```

This makes MagicDNS resolution consistent with the macOS Bonjour name the user is already used to (`<hostname>.local`).

## Step 7: Verification block

```bash
# 1. Status.
tailscale status

# 2. Tailnet IP assigned.
tailscale ip -4

# 3. Self DNSName.
tailscale status --json | jq -r '.Self.DNSName'

# 4. Peer reachability.
dscacheutil -q host -a name linux-test-01
tailscale ping linux-test-01
```

If any of the four fail, [`rollback`](../rollback.md).

## Step 8: Soak

For a production Mac, watch for 30 minutes after the cutover succeeds. The macOS-specific failure modes to look for:

- **`Tailscale.app` reinstalls itself** via App Store auto-update mid-soak. This will conflict with the brew daemon. Disable App Store auto-updates for Tailscale.app specifically, or uninstall the cask if present.
- **`brew services` daemon dies after a system update.** macOS updates have historically reset some launch services. After any macOS update, verify with `sudo brew services list | grep tailscale`.
- **DNS resolver scope.** macOS sometimes only applies the MagicDNS resolver for new connections. If a long-running app's connections are not resolving tailnet names, restart that app.

## Known macOS gotchas

- **`utun` interface number is non-deterministic.** `tailscale0` on Linux; `utunN` (where N is the next free number) on macOS. Don't hardcode the interface name in any script.
- **System Integrity Protection** may block `tailscaled` from setting DNS unless the daemon is run by root via `brew services` (not as a user-launched LaunchAgent).
- **The Mac Studio's daily-driver SSH key is in `~/.ssh/`** — if the cutover script ever needs to chmod or temporarily relocate `~/.ssh` (it shouldn't), be aware.
- **Client/daemon version skew after `brew upgrade tailscale`** (observed on Mac Studio post-2026-06-05 cutover). `brew upgrade tailscale` updates the `/opt/homebrew/bin/tailscale` CLI binary, but the daemon (running under `brew services`) keeps executing the older binary until restarted. Symptom: `tailscale status` prints `Warning: client version "1.98.5-…" != tailscaled server version "1.98.3-…"`. The mismatch is usually benign but produces confusing failures on `tailscale set` operations until resolved. **Fix**: `sudo brew services restart tailscale` (or `sudo brew services kill tailscale && sudo brew services start tailscale` if restart-in-place misbehaves). Build this into your post-`brew upgrade` muscle memory for any Mac on the tailnet.
- **`tailscale SSH` is enabled but ACL-blocked.** Observed on Mac Studio. Headscale's default open-mesh policy at the peer level does **not** include an SSH ACL — `tailscale ssh josephs-mac-studio` from another tailnet member is silently rejected. The health-check warning is the surface signal. Writing a Headscale ACL policy that grants SSH is a separate cleanup task (tracked in cutover-playbook §10) but worth knowing about because `tailscale ssh` from a Mac to another tailnet host **will not work** until that policy lands.

## Related

- [`../cutover-playbook.md`](../cutover-playbook.md) — full procedure
- [`../rollback.md`](../rollback.md) — rollback path (macOS section)
- [`macos-appstore.md`](macos-appstore.md) — App Store Tailscale build variant
