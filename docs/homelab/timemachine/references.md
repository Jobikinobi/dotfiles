# References — Samba Time Machine

The three sources that actually mattered, and what each contributed. All three
independently confirm the key fixes in the runbook.

## Primary

- **mbentley/docker-timemachine** — <https://github.com/mbentley/docker-timemachine>
  Proven, widely-used working config. Source of `fruit:nfs_aces = no`,
  `fruit:zero_file_id = yes`, `fruit:advertise_fullsync = true`, and the pattern
  of a **dedicated owning user** (not `nobody`).

- **FreeBSD Foundation Journal — "Samba-based Time Machine backups"**
  <https://freebsdfoundation.org/our-work/journal/browser-based-edition/storage-and-filesystems/samba-based-time-machine-backups/>
  Authoritative `vfs_fruit` write-up. Its share uses `valid users = %U` +
  `path = .../%U` with **no `force user`** — the connecting user owns their own
  backup. Confirmed that our `force user = nobody` was the outlier causing the
  `Permission denied` on disk-image creation. Also has `fruit:nfs_aces = no` and
  `fruit:advertise_fullsync = true` in `[global]`.

## Supporting

- **Samba `vfs_fruit` man page** — `man vfs_fruit` (or
  <https://www.samba.org/samba/docs/current/man-html/vfs_fruit.8.html>)
  Canonical meaning of every `fruit:*` option, including `nfs_aces` (default
  `yes` lets the client set POSIX perms via NFS ACEs — the thing that fought
  `force user = nobody`).

- **Generic Ubuntu/Samba TM guide** (the "practical low-cost" walkthrough)
  Good for the baseline share/user/size-limit steps, but note: it enables
  Spotlight (we disabled it — caused `mds_init_ctx ... Permission denied` noise)
  and it does NOT include the `nfs_aces`/`advertise_fullsync`/no-`force user`
  fixes, so following it alone reproduces the failure.

## The one-line lesson

> Every reputable config lets the **real authenticated user own the backup
> files**. `force user = nobody` + `fruit:nfs_aces = yes` (the default) is what
> breaks sparsebundle creation with "The backup disk image could not be created."
