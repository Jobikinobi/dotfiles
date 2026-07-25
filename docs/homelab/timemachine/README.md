# Time Machine → Samba on `jdebian` — Runbook

How to stand up (or rebuild) the network Time Machine backup target on the
`jdebian` VM, and — more importantly — every trap that cost us hours the first
time. If future-you is staring at "The backup disk image could not be created,"
**jump to [Troubleshooting](#troubleshooting)**.

- **Server:** `jdebian` — Debian 13, Samba 4.22, a dedicated ext4 disk mounted
  at `/mnt/timemachine`.
- **Reach:** LAN `10.0.0.26` (fast, use when co-located) or NetBird
  `jdebian.netbird.hole` / `100.80.247.107` (off-LAN).
- **Client:** macOS, backing up unencrypted over SMB.
- **Companion files:** [`smb.conf`](smb.conf) (verbatim working config),
  [`references.md`](references.md).

---

## TL;DR — the four things that actually made it work

1. **Mount the backup disk by UUID in `/etc/fstab` with `nofail`.** Linux device
   letters (`sda`/`sdb`) swap across reboots; a name-based mount silently grabs
   the wrong disk or vanishes. Ours flipped `sda1`→`sdb1` on a reboot mid-project.
2. **Let the real user own the backups — NO `force user = nobody`.** This was the
   killer. `nobody` can't take ownership of the sparsebundle → `Permission denied`
   → "backup disk image could not be created."
3. **`fruit:nfs_aces = no`** (+ `fruit:advertise_fullsync = true`,
   `fruit:zero_file_id = yes`) in `[global]`. Stops macOS from trying ownership
   changes the server will reject.
4. **The destination lives on the Mac, not the server.** A perfect `smb.conf`
   backs up nothing until `tmutil setdestination` is run on the Mac.

---

## Server setup (from scratch)

### 1. Install Samba
```bash
sudo apt update
sudo apt install -y samba
smbd --version   # need >= 4.8
```

### 2. Prepare the backup disk — **by UUID**
```bash
# format a dedicated disk (DESTROYS the disk — be sure of the device)
sudo mkfs.ext4 /dev/sdX1

# find its stable UUID
lsblk -f            # note the UUID of the backup partition

sudo mkdir -p /mnt/timemachine

# persistent mount by UUID, nofail so a missing disk never blocks boot
echo "UUID=<PASTE-UUID> /mnt/timemachine ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/timemachine
findmnt /mnt/timemachine     # confirm it's the RIGHT disk
```

### 3. Ownership — the real user owns it (not `nobody`)
```bash
# jth is the Samba/backup user; the share connects AS this user
sudo chown jth:jth /mnt/timemachine
sudo chmod 0770 /mnt/timemachine
```

### 4. Samba user
```bash
sudo smbpasswd -a jth     # sets the SMB password (separate from the Linux one)
sudo smbpasswd -e jth     # ensure enabled
sudo pdbedit -L -v jth | grep 'Account Flags'   # want [U ...], NOT [D ...]
# jth must be in the sambashare group (valid users = @sambashare):
id jth | grep -o sambashare || sudo usermod -aG sambashare jth
```

### 5. `smb.conf`
Install the companion [`smb.conf`](smb.conf) to `/etc/samba/smb.conf`
(back up any existing one first). Then:
```bash
sudo testparm -s            # must say "Loaded services file OK"
sudo systemctl restart smbd nmbd
sudo systemctl enable smbd nmbd
```

### 6. Avahi advertisement (LAN discovery only — see note)
`/etc/avahi/services/samba.service`:
```xml
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
    <name replace-wildcards="yes">%h</name>
    <service><type>_smb._tcp</type><port>445</port></service>
    <service>
        <type>_adisk._tcp</type><port>9</port>
        <txt-record>sys=waMa=0,adVF=0x100</txt-record>
        <txt-record>dk0=adVN=timemachine,adVF=0x82</txt-record>
    </service>
</service-group>
```
```bash
sudo systemctl restart avahi-daemon
```
> **Note:** mDNS/Bonjour is link-local multicast and **does not cross the NetBird
> overlay**. Over NetBird the share will NOT auto-appear in Finder — you connect
> manually (below). Avahi only helps same-LAN discovery.

### 7. Server-side sanity checks
```bash
# can the connecting user write?
sudo -u jth bash -c 'touch /mnt/timemachine/.wtest && echo OK && rm /mnt/timemachine/.wtest'

# capability test — this is EXACTLY what Time Machine does.
# Run on a Mac with the share mounted; it must succeed and create band files:
hdiutil create -size 10g -type SPARSEBUNDLE -fs HFS+J -volname t \
  /Volumes/timemachine/t.sparsebundle && rm -rf /Volumes/timemachine/t.sparsebundle
```

---

## Mac setup (this is where backups are actually enabled)

```bash
# 1. mount + save creds to Keychain (LAN IP is faster for the first full backup)
#    Finder → Cmd-K → smb://jth@jdebian.netbird.hole/timemachine   (or smb://10.0.0.26/timemachine)

# 2. register the destination (unencrypted — see key-custody note)
sudo tmutil setdestination -a "smb://jth@jdebian.netbird.hole/timemachine"
tmutil destinationinfo        # should now list it

# 3. start + watch
sudo tmutil startbackup
tmutil status
```
Confirm it's real, server-side:
```bash
ssh jth@jdebian.netbird.hole \
  'sudo find /mnt/timemachine -maxdepth 2 -iname "*.sparsebundle"; df -h /mnt/timemachine'
# you want a "<ComputerName>.sparsebundle" that GROWS.
```

---

## Growing the disk later (done once already, 300G → 500G)

Disk was expanded in the hypervisor; inside the guest, online-grow it:
```bash
sudo apt install -y cloud-guest-utils     # for growpart, if missing
sudo growpart /dev/sdX 1                   # grow partition into new free space
sudo resize2fs /dev/sdX1                    # online-grow ext4 (safe while mounted)
df -h /mnt/timemachine
# then optionally raise `fruit:time machine max size` in smb.conf (keep < disk)
```

---

## Encryption / key custody ⚠️

We run this **unencrypted** *on purpose*. History: an earlier encrypted network
backup became unrecoverable because the sparsebundle password lived **only in the
Mac's login Keychain**, which was destroyed when the Mac was wiped — "backed up
fine, couldn't decrypt, data lost."

- If you ever re-enable **encrypted** Time Machine: **record the password in a
  password manager BEFORE the first backup**, and verify you can decrypt it from
  a *different* Mac (no shared Keychain) before trusting it.
- Unencrypted trade-off: anyone who can read `/mnt/timemachine` (or the disk) can
  read everything on the Mac. If you want at-rest protection without the
  key-loss risk, use **LUKS on the server** with a passphrase you control.

**Always verify a restore (read data back) before relying on a backup.**

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| **"The backup disk image could not be created"** / `hdiutil ... Permission denied` | `force user = nobody` — `nobody` can't own the sparsebundle | Remove `force user`/`force group`; `chown jth:jth /mnt/timemachine`; set `fruit:nfs_aces = no` in `[global]` |
| `Failed to mount destination` (backupd Code 32) | destination registered but not truly mounted / cred issue | Re-mount in Finder (save to Keychain), then `sudo tmutil setdestination -a smb://…` |
| Backup never starts; `tmutil status` Running=0 | **no destination configured on the Mac** | `sudo tmutil setdestination -a smb://user@host/timemachine` |
| Share not visible in Finder / TM disk list | mDNS doesn't cross NetBird overlay | Connect manually: Finder → ⌘K → `smb://user@host/timemachine` |
| Backup disk gone after a reboot | fstab used device name, or not in fstab | Mount by **UUID** with `nofail` (see step 2) |
| `mds_init_ctx ... vfs_ChDir ... Permission denied` in samba logs | `spotlight = yes` (mds can't enter the share dir) | `spotlight = no` — TM doesn't need it |
| Backup fills disk / corrupts | `fruit:time machine max size` > physical disk | Cap it **below** the disk size |
| Auth fails from Mac | Samba pw not set/enabled (separate from Linux pw) | `sudo smbpasswd -a jth && sudo smbpasswd -e jth` |

### Useful diagnostics
```bash
# server: live samba log + errors
sudo tail -f /var/log/samba/log.*        # watch during a backup
sudo grep -riE 'error|denied|no space' /var/log/samba/

# mac: what backupd thinks
tmutil status ; tmutil destinationinfo ; tmutil latestbackup
```

---

## Why it kept failing (post-mortem)

The disk/mount/space fixes were necessary but never the blocker. The real
failure was **ownership**: our share used `force user = nobody`, and with
`fruit:nfs_aces = yes` (the Samba default) macOS tried to set ownership on the
new sparsebundle. `nobody` isn't allowed to do that, so Samba returned
`Permission denied` and macOS reported "The backup disk image could not be
created." Both the `mbentley` and FreeBSD Foundation reference configs avoid
`nobody` entirely and let the connecting user own its backups — matching that,
plus `fruit:nfs_aces = no`, is what fixed it. See [`references.md`](references.md).
