# Cutover recipe — macOS (App Store Tailscale build)

The harder macOS path. The App Store build does not accept `--login-server` or `--authkey` flags — its login flow is OAuth via the menu-bar UI, and pointing it at Headscale requires setting a system-wide preference (`ControlURL`) before login. This works, but it's scriptable only with a click-the-menu-bar step in the middle, which makes it a poor fit for the cutover playbook's "scripted, observed, rollback-able" pattern.

**Recommendation: migrate to the open-source brew build for any Mac that needs to be on Headscale.** See [`macos-oss.md`](macos-oss.md) for the open-source recipe; switching builds takes about ten minutes and removes most of the friction in this document.

This document exists for the cases where the user has a hard requirement to stay on the App Store build (FileVault entanglement, MDM policy, etc.).

## Status of this document

**Skeleton.** The procedure below is based on Tailscale's published documentation and prior community reports, not on a tested cutover. Validate and refine when the first App Store cutover is exercised on the lume VM (or any disposable Mac).

## The fundamental difference

| Concern | Open-source brew build | App Store build |
|---------|------------------------|-----------------|
| Where the binary lives | `/opt/homebrew/bin/tailscale` (or `/usr/local/bin/...`) | `/Applications/Tailscale.app/Contents/MacOS/Tailscale` |
| Daemon | `tailscaled` via `brew services` | Sandboxed system extension `io.tailscale.ipn.macsys` |
| How you point it at Headscale | `--login-server=https://...` flag to `tailscale up` | `defaults write /Library/Preferences/io.tailscale.ipn.macos ControlURL <url>` before login |
| Authentication | `--authkey=<preauth-key>` | Click menu-bar icon → "Log in" → OAuth flow in browser |
| Scriptable? | Fully | Partially (the URL set is scriptable; the login click is not) |
| Coexists with the other build? | **No** — they fight over `utun`. Choose one. |

## Cutover steps

### Step 1: Prerequisites

Same as `macos-oss.md` Step 0 — held-open LAN SSH session, console plan, etc.

In addition: **the user must be physically (or remotely) at the Mac to click "Log in" through the menu bar** at step 4. Pure SSH cutover is not possible with the App Store build.

### Step 2: Add the `/etc/hosts` entry

```bash
if ! grep -q "hs.lab.hole-truth.org" /etc/hosts; then
  echo "192.168.68.77 hs.lab.hole-truth.org" | sudo tee -a /etc/hosts
fi
dscacheutil -q host -a name hs.lab.hole-truth.org
```

### Step 3: Log out of the current tailnet

In the menu bar: click the Tailscale icon → **Disconnect** → **Log out**.

This is the start of the cutover window.

### Step 4: Set the Headscale `ControlURL` preference

```bash
sudo defaults write /Library/Preferences/io.tailscale.ipn.macos ControlURL "https://hs.lab.hole-truth.org"

# Verify.
defaults read /Library/Preferences/io.tailscale.ipn.macos ControlURL
# Expected: https://hs.lab.hole-truth.org
```

This tells the App Store build that the next login attempt should go to Headscale, not Tailscale Inc.

### Step 5: Log in via the menu bar

Click the Tailscale icon in the menu bar → **Log in**. This opens a browser tab pointing at `https://hs.lab.hole-truth.org/register/<key>` (or similar). The browser tab will show a Headscale registration prompt — typically a CLI command of the form:

```
headscale --user lab nodes register --key <node-key>
```

Run that command on `.77` (or have an agent / second person run it for you):

```bash
# On .77, as a user in the headscale group:
headscale --user lab nodes register --key <node-key>
```

The browser tab will refresh and show "Success". The menu-bar Tailscale icon will turn green.

If you have already generated a single-use preauth key for this machine, an alternative is:

- Open `https://hs.lab.hole-truth.org/?preauth=<key>` directly from the browser instead of waiting for the menu-bar login.

### Step 6: Verification block

```bash
# /Applications/Tailscale.app/Contents/MacOS/Tailscale is the CLI inside the App.
# Some users symlink it to /usr/local/bin/tailscale for convenience.
tailscale status
tailscale ip -4
tailscale status --json | jq -r '.Self.DNSName'
dscacheutil -q host -a name linux-test-01
tailscale ping linux-test-01
```

If the verification fails, [`rollback`](../rollback.md) — the App Store-specific path is documented there.

## Known App Store gotchas

To validate when this path is actually exercised:

- **`defaults write` may need a Tailscale restart to take effect** (right-click menu bar icon → Quit, then re-open).
- **`ControlURL` is read once at login**, not continuously. Changing it after login has no effect.
- **The App Store build may not honor `--accept-routes`-style preferences** the same way the brew build does. Verify with `tailscale debug prefs`.
- **`tailscale cert` from the App Store build** has historically been less reliable than from the brew build — another reason to prefer the brew build for any node that needs per-node TLS.

## Related

- [`macos-oss.md`](macos-oss.md) — the recommended macOS variant
- [`../cutover-playbook.md`](../cutover-playbook.md) — full procedure
- [`../rollback.md`](../rollback.md) — rollback (macOS App Store section)
