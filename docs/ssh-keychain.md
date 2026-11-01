# SSH → login keychain on macOS (`ssh_aqua`)

An SSH login on macOS runs in its own "remote" security session (launchd
`Background`). securityd won't touch the login keychain from there, so `gh`,
Claude Code and anything else keychain-backed fails ("User interaction is not
allowed"), even though the keychain is unlocked at the console.

`~/.local/bin/aqua` fixes this by moving the shell into your logged-in GUI
(`Aqua`) session with `sudo launchctl asuser <uid>`, then dropping straight back
to you. Interactive SSH logins hop automatically via the hook at the top of
`~/.zshrc`. No `security unlock-keychain` needed.

## Enable on a Mac

Opt-in per machine. Answer yes to the `ssh_aqua` prompt on `chezmoi init`, or add
`ssh_aqua = true` under `[data]` in `~/.config/chezmoi/chezmoi.toml`, then apply.
That deploys:

| What | Where |
|---|---|
| `aqua` helper | `~/.local/bin/aqua` |
| SSH hook | top of `~/.zshrc` |
| Narrow sudo rule (visudo-checked, asks for your password once) | `/etc/sudoers.d/ssh-aqua` |

The rule only lets root re-enter your GUI session and drop back to you:
`jth ALL=(root) NOPASSWD: /bin/launchctl asuser 501 /usr/bin/sudo -n -E -u jth -- *`.
No blanket `NOPASSWD: ALL` needed.

## Use

- `ssh mac` → lands in Aqua; check with `launchctl managername`.
- `ssh mac aqua gh auth status` → one-off command in Aqua.
- `NO_AQUA=1 ssh mac` → skip the hop.

## Limits

- Someone must be logged in at the console (`gui/<uid>` must exist). After a
  FileVault reboot, use `sudo fdesetup authrestart` or log in first. Without it,
  `aqua` says so and you get a normal shell.
- Only interactive shells hop. `ssh host cmd`, VS Code Remote and agents' Bash
  tools stay in Background unless wrapped in `aqua`.
- Disable: set `ssh_aqua = false`, delete `/etc/sudoers.d/ssh-aqua` and
  `~/.local/bin/aqua`.
