# Mounting the `corpus` NFS drive

How to mount the shared **`/data/corpus`** NFS export (legal corpus + working
data) on a Mac workstation. Repo-internal runbook — filtered out of chezmoi
deploy by `.chezmoiignore: docs/**`.

## What / where

| Fact | Value |
|---|---|
| Export | `/data/corpus (rw,sync,insecure,no_subtree_check,no_root_squash)` |
| Allowed nets | `10.0.0.0/24` (LAN), `100.80.0.0/16` (NetBird) |
| Server | Proxmox LXC **container 114 "nfs"** on `pve` |
| LAN address | `10.0.0.36` / `nfs.local` |
| NetBird address | `100.80.245.142` |
| Mounts at | `/Volumes/corpus` |

The container advertises the export over **Bonjour/mDNS** (`avahi-daemon`,
`_nfs._tcp` port 2049), so it shows up in **Finder → Network as "corpus on
nfs"** — clicking it mounts with no sudo. The CLI equivalents below do the same
thing without leaving the terminal.

## Mount (on the home LAN — the normal case)

```sh
osascript -e 'mount volume "nfs://nfs.local/data/corpus"'
```

Bonjour discovery is link-local, so `nfs.local` only resolves on the home LAN
(`10.0.0.0/24`). This is the everyday path.

Verify:

```sh
mount | grep corpus
#   nfs.local:/data/corpus on /Volumes/corpus (nfs, nodev, nosuid, mounted by <you>)
df -h /Volumes/corpus
```

## Mount (off-LAN, via NetBird)

`nfs.local` won't resolve off the home network — address the NetBird IP directly:

```sh
osascript -e 'mount volume "nfs://100.80.245.142/data/corpus"'
```

## Fallback: classic `mount_nfs`

The export sets `insecure` specifically so the Finder/NetFS mount works without a
reserved source port. If you instead mount with the default-`secure` path (e.g.
`mount_nfs` without NetFS), pass `resvport`:

```sh
mkdir -p /Volumes/corpus
mount_nfs -o rw,resvport 10.0.0.36:/data/corpus /Volumes/corpus
```

## Unmount

```sh
umount /Volumes/corpus
# or, if the server dropped and it's wedged:
diskutil unmount force /Volumes/corpus
```

## Troubleshooting

- **"corpus on nfs" not in Finder → Network / `nfs.local` won't resolve** — you're
  off-LAN (Bonjour is link-local). Use the NetBird IP form above.
- **Mount hangs / "Operation timed out"** — the `nfs` container (CT 114) or `pve`
  is down, or you're on neither the LAN nor NetBird. Confirm reachability:
  `ping nfs.local` (LAN) or `ping 100.80.245.142` (NetBird).
- **`Permission denied` / `RPC: Authentication error`** — you tried a `secure`
  mount without `resvport`. Use the Bonjour/NetFS path, or add `resvport` as
  shown in the fallback.
- **Do NOT use autofs.** macOS Tahoe (26) blocks autofs direct maps into
  `/Volumes` (`automount: .../Volumes/corpus: mountpoint unavailable`). The old
  `/etc/auto_nfs` + `/-  auto_nfs` lines were removed on purpose.

## Optional: shell shortcut

Not wired by default. To make mounting one word, add to your shell rc:

```sh
alias corpus='osascript -e '\''mount volume "nfs://nfs.local/data/corpus"'\'' && open /Volumes/corpus'
```

## See also

- Server-side export config and Bonjour/avahi setup live with the `nfs`
  container (CT 114) on `pve`.
- Homelab topology and addressing: [`README.md`](README.md).
