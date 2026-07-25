# Homelab project

This directory tracks the work to turn Joe's home Proxmox host + Mac fleet into
a coherent dev environment that travels with the dotfiles repo. Documentation
in this folder is **repo-internal** (filtered out of chezmoi deploy by
`.chezmoiignore: docs/**`) — for **user-facing** runtime documentation that
deploys to every machine, see `dot_local/private_share/infra/`
(→ `~/.local/share/infra/` after `chezmoi apply`).

## Goal

> "Make this server my development/storage/hub where I can let my workstations
> log in to do development work without having that work distributed on the
> workstations. Once it is ready we will migrate our current systems to
> re-format our hard drives into native linux and migrate them to being hosted
> by this machine and accessible from any other."

Translation:
- Proxmox box at `192.168.68.16` is the hub.
- Mac workstations become thin clients that SSH into hosted Linux guests.
- Eventually the Macs themselves get reformatted to Linux and migrated to be
  hosted from PVE too.

## Architectural pins (decisions locked in)

1. **PVE host = root-only, by design.** No daily-driver users on the bare
   Debian. Day-to-day work happens in guest VMs/CTs. Admin tasks go through
   `pve-admin` LXC, never directly on the host.
2. **LAN IPs are the primary addressing layer.** Tailscale aliases are
   *fallbacks* for off-LAN access only. The system must keep working if
   Tailscale ever disappears (acquisition, policy change, etc.).
3. **Per-target SSH keys**, not one shared key. Stolen-laptop blast radius is
   one revocation per target. Cost is ~30 seconds of extra setup per target.
4. **Password fallback stays enabled** on SSH targets that humans use
   (PVE host, Mac Studio). Key auth is preferred; password is recovery. The
   admin LXC is key-only because it's reachable only via SSH.
5. **Ubuntu** is the preferred distro for workload VMs. Debian is fine for
   the PVE admin LXC (matches the host) but workload guests = Ubuntu.
6. **chezmoi + age** is the source of truth for cross-machine config and
   credentials. The age identity is the single critical secret.

## Current state (2026-05-20)

### Mac fleet

| Host             | LAN              | Public TS (`lemming-likert`) | Headscale (`lab`)   | Role                                |
|------------------|------------------|------------------------------|---------------------|-------------------------------------|
| MacBook Air      | 192.168.68.70    | 100.115.1.29 (legacy)        | 100.64.0.9 (node 9, currently offline) | Mobile / current dev workstation. Cut over to Headscale 2026-06-05. |
| Mac Studio       | 192.168.68.168   | 100.94.84.6 (legacy)         | 100.64.0.10 (node 10, online) | Primary desktop workstation. Cut over to Headscale 2026-06-05. **Production cutover succeeded ahead of the original "Mac Studio last" plan.** |
| Mac Mini         | 192.168.68.68    | 100.119.161.120              | — (not migrated)    | Secondary workstation. Only Mac still on public TS — pending Headscale cutover. |

All three Macs: FileVault on, Touch-ID-for-sudo enabled via `pam_tid.so`.

The Headscale rollout details, current node inventory, and the cutover playbook live under [`headscale/`](headscale/).

### Proxmox

- **Host** `pve` (Debian 12 / PVE 9.1.18) at `192.168.68.16`.
  CPU: i7-11700K (8c/16t). RAM: 62 GiB. Storage: `local` (96 GiB XFS),
  `local-lvm` (337 GiB free thin pool), `NFS-ISOs` (self-served NFS export
  with installer ISOs + image library).
  SSH: key + password fallback, fail2ban active. PVE firewall disabled. No
  off-host backup target yet.
- **CTID 100 `pve-admin`** — Debian 13 unprivileged LXC at `192.168.68.60`
  (DHCP — should be reserved at the router). User `jth`, key-only sshd,
  passwordless sudo. 2c/2GB/8GB. Created 2026-05-20.

### Pinned LAN addressing — `10.0.0.0/24` fleet (2026-07-23)

The Incus host and the corpus NFS server sit on the **`10.0.0.0/24`** LAN
(distinct from the PVE `192.168.68.0/24` net above). These addresses are now
**DHCP-reserved at the router** so they no longer drift on lease renewal —
which is what makes the LAN-primary rule (pin #2) safe to rely on for these
hosts. Reservations verified holding 2026-07-23.

| Host             | LAN (reserved)   | NetBird (`*.netbird.hole`) | Notes                                            |
|------------------|------------------|----------------------------|--------------------------------------------------|
| Incus host       | `10.0.0.33`      | `100.80.12.6`              | `incusd` binds `core.https_address :8443` (all ifaces) → reachable on **both** LAN and NetBird. |
| nfs (corpus)     | `10.0.0.36`      | `100.80.245.142`           | Proxmox CT 114; exports `/data/corpus`. See [`nfs-corpus-mount.md`](nfs-corpus-mount.md). |
| MacBook Air      | `10.0.0.4`       | `100.80.139.213`           | This workstation (`en0`). Was `.34` pre-reservation. |

**Incus remote = LAN-primary, NetBird fallback** (matches pin #2). The Mac's
default Incus remote points at the LAN IP; the overlay path is kept as a named
fallback:

| Remote          | URL                            | Path     |
|-----------------|--------------------------------|----------|
| `incus` *(default)* | `https://10.0.0.33:8443`   | LAN — `route get 10.0.0.33` → `en0`, ~130 ms `incus list` |
| `incus2`        | `https://incus.netbird.hole:8443` | NetBird overlay — for off-LAN |

Switch paths with `incus remote switch incus` / `incus remote switch incus2`.
No reverse DNS (PTR) zone exists in Pi-hole for `10.0.0.0/24` yet — forward
`.hole` names resolve, but `host 10.0.0.33` returns NXDOMAIN (cosmetic).

### SSH key catalog (managed by chezmoi)

| Key file (deployed)              | Reaches                          | In dotfiles? |
|----------------------------------|----------------------------------|--------------|
| `~/.ssh/id_ed25519_pve`          | `root@192.168.68.16`             | encrypted    |
| `~/.ssh/id_ed25519_pve_admin`    | `jth@192.168.68.60`              | encrypted    |
| `~/.ssh/id_ed25519_macstudio`    | `jth@192.168.68.168`             | encrypted    |
| `~/.ssh/id_ed25519`              | DigitalOcean droplets            | (pre-existing)|
| `~/.ssh/joe-laptop`              | `windev` (Windows gaming PC)     | (pre-existing)|
| `~/.ssh/mac-mini`                | `mac-mini`                       | (pre-existing)|

The `.gitignore` line `private_dot_ssh/id_*` filters both private and public
keys from git. Encrypted private keys (`encrypted_private_id_*.age`) commit
fine — different prefix. Public keys are reconstructable on demand:
`ssh-keygen -y -f <privkey>`.

### Documentation map

| Location                                          | Audience          | Deployed? |
|---------------------------------------------------|-------------------|-----------|
| `docs/homelab/` (this file)                       | future-me at repo | no        |
| `docs/homelab/timemachine/` (Samba TM runbook)    | future-me at repo | no        |
| `~/.local/share/infra/` (from `dot_local/...`)    | future-me on Mac  | yes (enc) |
| `~/Documents/__RECOVERY__/` (transient)           | bootstrap         | manual    |

## Setup log

### 2026-07-06

1. **Stood up network Time Machine** on `jdebian` (Samba 4.22, dedicated ext4
   disk at `/mnt/timemachine`, unencrypted over SMB). Full runbook:
   [`timemachine/README.md`](timemachine/README.md).
2. **Root cause of prior failures found:** `force user = nobody` prevented macOS
   from owning the sparsebundle → "backup disk image could not be created."
   Fixed by letting `jth` own the backups + `fruit:nfs_aces = no` +
   `fruit:advertise_fullsync = true`. Verified against `mbentley` and FreeBSD
   Foundation configs.
3. **Disk hygiene:** mounted backup disk by **UUID** with `nofail` (device
   letters had swapped `sda`↔`sdb` on a reboot); grew it 300G→500G online
   (`growpart` + `resize2fs`); capped `time machine max size` below disk size.
4. **Confirmed working:** `<ComputerName>.sparsebundle` created and growing.

### 2026-05-20

1. **Audit** of MBA remote-work configuration: SSH keys, ssh-agent, FileVault,
   sleep, multiplexers (none), VPNs, dotfile tooling. Recorded in Claude
   memory.
2. **Keychain-over-SSH diagnosis**: confirmed it's an architectural limit of
   macOS, not a config bug. Three viable approaches catalogued: 1Password as
   keychain alternative; `launchctl asuser` bridge; interactive
   `security unlock-keychain` wrapper. Open item.
3. **Generated three new ed25519 keys** on MBA: `id_ed25519_pve`,
   `id_ed25519_pve_admin`, `id_ed25519_macstudio`. Passphraseless
   (relying on FileVault for at-rest protection); loaded into Apple Keychain
   via `ssh-add --apple-use-keychain`.
4. **Enrolled the pubkeys** on PVE and Mac Studio via `ssh-copy-id`
   (interactive — required current-password auth one last time).
5. **Created the `pve-admin` LXC** (CTID 100, Debian 13, unprivileged) with
   `jth`, sudo, key-only sshd, passwordless sudo. Verified
   `ssh pve-admin && sudo -n whoami` returns `root`.
6. **Updated `~/.ssh/config`** with `pve`, `pve-admin`, `macstudio` blocks
   plus Tailscale fallbacks. Backup of original at
   `~/.ssh/config.bak.20260520_125422`.
7. **Researched the PVE CLI surface** via Context7 + live inspection. Saved
   a 17-tool reference into Claude memory.
8. **Added snippets content type** to PVE's `local` storage (prereq for
   cloud-init user-data injection).
9. **chezmoi integration**: updated `private_dot_ssh/config.tmpl`, added
   encrypted private keys, added `~/.local/share/infra/{README,proxmox}.md`
   docs (encrypted). Verified end-to-end decryption.
10. **Staged age identity recovery** at `~/Documents/__RECOVERY__/`
    (text + QR + instructions). Performed swap-and-restore drill: backup
    identity decrypts identical bytes. Drill PASSED.
11. **Rebased** local commit onto origin's `rclone` + `rnr` Brewfile additions
    (no conflicts).

## Open items (priority order)

### Should do next

- **Back up the age identity to ≥2 durable channels.** See
  `docs/homelab/recovery.md`. Until done, single point of failure.
- **Ubuntu cloud-init workload template** (VMID 9000) for fast clone-based VM
  provisioning. Pending two decisions: storage target (`local` vs `NFS-ISOs`)
  and Ubuntu version (24.04 LTS vs 26.04 LTS).
- **Reserve `192.168.68.60`** for the `pve-admin` LXC's MAC at the router.

### Quality-of-life on the Mac

- Install `tmux` / `mosh` / `pam_reattach` / `atuin` (persistent sessions +
  Touch-ID-under-multiplexer + cross-machine shell history).
- Bump `pmset sleep` from 1 min so the MBA stays reachable when idle.

### Bigger projects (eventually)

- **Off-host backup** target (PBS or remote NFS). The current 2-hour vzdump
  writes to the same physical disk it's protecting.
- **Tailscale on PVE**: `tailscale up` to join the tailnet so `pve-ts` works.
- **Migrate legacy `jth` Linux user on the PVE host** — dormant, intended to
  be removed once nothing depends on it.
- **Reformat workstations to Linux** and migrate them to PVE-hosted VMs
  (long-term north star, per the original goal statement).

## Headscale migration (in progress)

Separate effort tracked in [`headscale/`](headscale/): moving the entire
hole-network off public Tailscale (`lemming-likert.ts.net`) onto self-hosted
Headscale at `hs.lab.hole-truth.org`. Headscale gives us ownership of MagicDNS,
control-plane TLS, and the per-node reverse proxy, which unblocks
multi-HTTP-per-node service deployment.

- [`headscale/README.md`](headscale/README.md) — entry point + current state
- [`headscale/architecture.md`](headscale/architecture.md) — target end-state
- [`headscale/cutover-playbook.md`](headscale/cutover-playbook.md) — operator procedure
- [`headscale/rollback.md`](headscale/rollback.md) — get back to public Tailscale fast
- [`headscale/reverse-proxy.md`](headscale/reverse-proxy.md) — Caddy reference
- [`headscale/per-os/`](headscale/per-os/) — per-OS join recipes

## Conventions

- VMID `9000-9999` = templates by convention (community pattern, not enforced).
- CTID `100+` for guests.
- Resource pools: `pve` (host stuff, never delete), `userpool` (user stuff).
- Hostnames in SSH config use the short LAN name primary, Tailscale alias
  suffixed `-ts`.
