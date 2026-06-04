# Rollback — back to public Tailscale

This is the document you read **during** a cutover that has gone wrong. Read it once cold, before you run a cutover, so you know what's here. The whole point is to keep the worst case bounded: a Headscale join that fails leaves the node back on public Tailscale within five minutes.

## When to roll back

You should be on this page if any of the following happens during a cutover:

1. **The Headscale join command hangs or errors out** and the verification steps in the per-OS recipe do not produce a `100.64.x.x` tailnet IP within ~2 minutes.
2. **You join Headscale successfully, but the node can no longer reach a peer it could reach before** (LAN peers via LAN-IP still work; tailnet peers do not).
3. **The held-open LAN SSH session is lost** — even if the cutover technically succeeded. Better to roll back, restore a known-good state, then redo the cutover with the safety net in place.
4. **You feel uncertain.** The cost of rolling back and trying again is a few minutes. The cost of pushing through and locking yourself out of a headless machine is much higher.

## What rollback actually does

Rollback logs the node out of Headscale, removes the cached client state, and rejoins the **public** Tailscale tailnet (`lemming-likert.ts.net`) using the auth key stored in Doppler. After rollback, the node is exactly where it was before you started the cutover — same tailnet, same `100.x.x.x` address (assigned fresh, may differ), same peer list.

It does NOT undo any other change you may have made on the node — Caddy config, `/etc/hosts` lines, firewall rules. Those have to be reverted by hand if they were touched.

## Prerequisites you should already have

All of these are part of the cutover preflight ([`cutover-playbook.md`](cutover-playbook.md) §3). If any are missing, the rollback can still happen but will require an extra manual step.

- **A held-open SSH session over the LAN IP** of the node. Rollback runs in this session. If you lost it, console (Proxmox web UI for VMs; physical keyboard for bare metal) is the next path.
- **The public Tailscale auth key** retrievable from Doppler scope `dotfiles/lxd-bootstrap`, secret name `TAILSCALE_AUTHKEY`. Doppler can be flaky over SSH — see "If Doppler can't reach the keyring" below.
- **The original public-Tailscale node identity** is gone from the public tailnet (the cutover deliberately logged it out, which expires the node key after a grace period). Rollback creates a *new* node identity on the public tailnet. The previous node entry will need to be deleted in the Tailscale admin console after the dust settles — not blocking.

## Linux rollback (Debian/Ubuntu/Alpine)

Run all of this in the held-open LAN SSH session. Each command is idempotent.

```bash
# 1. Confirm you are on the machine you think you are.
hostname
ip -4 -br addr | head -5

# 2. Log out of Headscale (no error if we're not on it).
sudo tailscale logout || true

# 3. Stop tailscaled and clear state.
sudo systemctl stop tailscaled
sudo rm -rf /var/lib/tailscale
sudo systemctl start tailscaled
sudo systemctl enable tailscaled

# 4. Get the public Tailscale auth key from Doppler.
#    On Linux this usually works fine. On macOS over SSH, see the macOS section.
TS_AUTHKEY="$(doppler secrets get TAILSCALE_AUTHKEY --plain -p dotfiles -c lxd-bootstrap 2>/dev/null)"
if [[ -z "$TS_AUTHKEY" ]]; then
  echo "FATAL: could not retrieve auth key from Doppler. See 'If Doppler can't reach the keyring' below."
  exit 1
fi

# 5. Join the public tailnet.
sudo tailscale up \
  --authkey="$TS_AUTHKEY" \
  --hostname="$(hostname -s)" \
  --reset

# 6. Verify.
tailscale status
tailscale ip -4
ping -c 3 100.94.84.6   # Mac Studio public-tailnet IP, change to any known peer
```

Expected: `tailscale ip -4` returns a `100.x.x.x` address in the `lemming-likert.ts.net` range, and you can ping a known peer.

## macOS rollback (open-source brew build)

Same shape as Linux but with macOS-specific paths.

```bash
# 1. Log out of Headscale.
sudo tailscale logout || true

# 2. Stop the daemon and clear state.
sudo brew services stop tailscale
sudo rm -rf /Library/Tailscale          # client state
sudo rm -rf /var/db/tailscale           # daemon state (path varies by brew version)
sudo brew services start tailscale

# Give the daemon a moment to come up.
for _ in 1 2 3 4 5; do
  tailscale status &>/dev/null && break
  sleep 1
done

# 3. Get the public Tailscale auth key.
TS_AUTHKEY="$(doppler secrets get TAILSCALE_AUTHKEY --plain -p dotfiles -c lxd-bootstrap 2>/dev/null)"

# 4. Join the public tailnet.
sudo tailscale up \
  --authkey="$TS_AUTHKEY" \
  --hostname="$(scutil --get LocalHostName)" \
  --reset

# 5. Verify.
tailscale status
tailscale ip -4
```

## macOS rollback (App Store build)

The App Store build does not accept `--authkey` and `--login-server` flags the way the open-source build does. Rolling back is a two-part operation:

1. **Remove the Headscale ControlURL override.**

   ```bash
   sudo defaults delete /Library/Preferences/io.tailscale.ipn.macos ControlURL 2>/dev/null || true
   # Or set explicitly to public:
   sudo defaults write /Library/Preferences/io.tailscale.ipn.macos ControlURL "https://controlplane.tailscale.com"
   ```

2. **Log out and re-authenticate** through the Tailscale menu-bar UI:
   - Click the Tailscale menu-bar icon → **Disconnect**.
   - Click **Log out**.
   - Click **Log in** — this opens the public Tailscale OAuth flow in a browser. Complete it.
   - The node will appear in the public tailnet admin console under your account.

The App Store rollback path is harder to script because it depends on the menu-bar UI. This is one reason the recommendation for production Macs is the open-source brew build.

## If Doppler can't reach the keyring

The most common Doppler-over-SSH failure mode on macOS is `dbus-launch: command not found` or `Could not connect to keyring`. The fallback is to retrieve the key from Doppler on a workstation that has GUI keyring access, then paste it into the rollback session:

```bash
# On a workstation (NOT on the locked-out node):
doppler secrets get TAILSCALE_AUTHKEY --plain -p dotfiles -c lxd-bootstrap

# Copy the output, then on the node (in the held-open SSH session):
TS_AUTHKEY="tskey-auth-..."
sudo tailscale up --authkey="$TS_AUTHKEY" --hostname="$(hostname -s)" --reset
```

For Linux nodes specifically, Doppler over SSH usually works because there's no keyring required for service-account tokens stored in `~/.config/doppler/`. If a Linux node fails to retrieve, run `doppler login` interactively in the SSH session first.

## If the node is genuinely locked out

If the held-open SSH session was lost AND the node is not reachable on its LAN IP either AND it's not on the tailnet, you are in console-recovery territory.

- **PVE VM**: open the Proxmox web UI → VM → Console. You have keyboard + screen. Boot single-user mode if you need to bypass network-level lockout, then run the rollback commands from there. If filesystem is intact this is straightforward.
- **PVE LXC**: `pct enter <vmid>` from a host shell (over the LAN-IP of `prox`). You're in as root with no SSH involved.
- **Bare-metal Mac**: physical keyboard + screen. Boot into recovery mode if needed (`Cmd-R` at boot).
- **Bare-metal Linux without console access**: this is the scenario the cutover playbook explicitly avoids by demanding console availability before starting on any headless machine. If you got here, the lesson is "do not skip the console-availability check next time."

The single most valuable property of this setup is that **every machine in the hole-network is reachable by its LAN IP without any tailnet involvement**. As long as you can `ssh user@192.168.68.x` from a wired LAN connection, the rollback is alive.

## Practicing rollback

Before any production machine is touched, run the cutover + rollback drill on the lume macOS VM end to end. Time the rollback — if it takes more than five minutes from "decide to roll back" to "node is healthy on public tailnet", figure out what the slow step was and fix it before the playbook touches anything real.

The disposable trial nodes (`linux-test-01`, `linux-test-02`) are also fine practice — they are already on Headscale, so the experiment is "log them out, rejoin public Tailscale, then log them back into Headscale". Each pass costs maybe 10 minutes and builds operator muscle memory.

## Related

- [`cutover-playbook.md`](cutover-playbook.md) — full procedure, where this file is referenced from
- [`per-os/macos-oss.md`](per-os/macos-oss.md), [`per-os/macos-appstore.md`](per-os/macos-appstore.md) — per-OS specifics
