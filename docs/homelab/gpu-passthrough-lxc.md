# NVIDIA GPU passthrough into a Proxmox LXC container

How to give an unprivileged Proxmox LXC container access to the host's NVIDIA
GPU, so Docker containers running inside it can use `--gpus all` or CDI's
`--device nvidia.com/gpu=all`.

This is **not** VM-style PCI passthrough. An LXC container shares the host
kernel, so the NVIDIA kernel module only ever loads once, on the host. What
each container needs is (a) the device nodes and (b) a matching userspace
driver — no VFIO, no IOMMU groups, no exclusive ownership of the card. Multiple
containers (and the host itself) can use the same GPU concurrently.

## Prior art on this host

- **CT 149** (`ubuntu-nvidia`) and **CT 1001** (`docker-gpu-template`) were
  already configured this way before this doc existed — that's where the
  device-passthrough config below and `gpu-provision.sh` (the ancestor of
  `scripts/gpu-provision-lxc.sh`) came from. 1001 is a template that clones
  self-provision from on first boot; see `template-prepare.sh` /
  `install-template.sh` under `/opt/template-build` in that container.
- **CT 113** (`Portainer`) was wired up on 2026-08-24 using the two scripts
  documented here, as the first time this was done deliberately/repeatably
  rather than by hand.

## The two-step pattern

### Step 1 — host side: attach the device nodes

Run **on the Proxmox host**, as root:

```bash
scripts/gpu-passthrough-lxc-host.sh <ctid> --dry-run   # see what it would do
scripts/gpu-passthrough-lxc-host.sh <ctid>              # apply
```

This runs (idempotently — safe to re-run):

```bash
pct set <ctid> \
  -dev0 /dev/nvidia0,gid=44 \
  -dev1 /dev/nvidiactl,gid=44 \
  -dev2 /dev/nvidia-uvm,gid=44 \
  -dev3 /dev/nvidia-uvm-tools,gid=44 \
  -dev4 /dev/nvidia-caps/nvidia-cap1,gid=44 \
  -dev5 /dev/nvidia-caps/nvidia-cap2,gid=44
```

`gid=44` is the `video` group on Debian/Ubuntu — the device nodes on the host
are `root:video 0660`, so anything inside the container running as root (or a
member of its own `video` group) can open them once passed through.

**This does not take effect on a running container.** The devices attach at
container start, so the container needs a reboot (`pct reboot <ctid>`, or
pass `--reboot` to the script) before `/dev/nvidia*` shows up inside it.

**Before rebooting a container with a live workload**, check what's running
inside it and whether it'll come back on its own:

```bash
pct exec <ctid> -- docker ps --format '{{.Names}}\t{{.Status}}'
pct exec <ctid> -- docker inspect --format '{{.Name}} restart={{.HostConfig.RestartPolicy.Name}}' $(pct exec <ctid> -- docker ps -q)
```

Docker persists each container's restart policy itself, independent of
however it was originally created (`docker run`, compose, Portainer stack).
`unless-stopped` / `always` containers come back automatically once `dockerd`
starts, on any reboot — you do **not** need to re-run `docker compose up` or
have the original compose file present on that host. `docker.service` being
`enabled` (check `systemctl is-enabled docker`) is the other half of that:
the daemon itself needs to start at boot too. `no` / `on-failure` containers
may not restart automatically — worth checking for those and starting them
manually after, or fixing their restart policy separately.

### Step 2 — container side: install the matching driver + toolkit

Run **inside the container**, as root, once the devices are visible
(`ls /dev/nvidia0` should succeed):

```bash
scripts/gpu-provision-lxc.sh --dry-run   # see what it would do
scripts/gpu-provision-lxc.sh              # apply
```

This is the generalized, idempotent version of what `docker-gpu-template`'s
`gpu-provision.sh` already did for rootless Docker, extended to also handle
rootful (system) Docker by auto-detection. It:

1. Reads the **host's** driver version from `/proc/driver/nvidia/version` —
   readable from inside the container even though NVIDIA's kernel module is
   invisible to `lsmod` in the container's own view otherwise, because
   NVIDIA's proc entries aren't namespaced.
2. Downloads and installs the *exact matching* version of NVIDIA's official
   `.run` installer with `--no-kernel-module` — userspace libraries only
   (`libcuda`, `libnvidia-ml`, `nvidia-smi`, …). The host already owns the
   loaded kernel module; a version mismatch between host module and
   container userspace is the most common way this breaks.
3. Installs `nvidia-container-toolkit` from NVIDIA's official apt repo.
4. Sets `nvidia-container-cli.no-cgroups=true` — **mandatory** for an
   unprivileged LXC container. It cannot manage device cgroups itself (the
   host already restricted them via the `dev0..dev5` passthrough in step 1);
   without this setting, `nvidia-container-cli` fails trying to write cgroup
   rules it has no permission to write.
5. Generates a CDI spec (`/etc/cdi/nvidia.yaml`) and enables
   `nvidia-cdi-refresh.path` so it regenerates automatically on driver
   upgrade or reboot — this script should rarely need to run twice.
6. Wires the `nvidia` runtime into whichever Docker daemon it finds:
   - **Rootful** (`systemctl is-active docker`): edits
     `/etc/docker/daemon.json` in place via `nvidia-ctk runtime configure`
     (merges — doesn't clobber existing keys, e.g. a custom `hosts` array)
     and restarts `docker.service`.
   - **Rootless**: auto-detects by scanning for an installed
     `~/.config/systemd/user/docker.service` unit, adds that user to the
     `video` group, edits their `~/.config/docker/daemon.json`, restarts
     their `systemctl --user` docker. Pass `--docker-user <name>` to force
     this if the rootless daemon exists but hasn't been started yet (so
     auto-detect can't see it).
   - **Neither found**: leaves driver + toolkit + CDI spec ready and exits
     cleanly — useful if Docker gets installed later.

Verify with:

```bash
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi
# or, CDI form:
docker run --rm --device nvidia.com/gpu=all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi
```

## Gotchas encountered

- **`docker inspect`/`docker ps` dialing a stray remote host.** Seen once on
  CT 113 (`no route to host` against an unrelated `10.0.0.61:2375`) with no
  reproducible cause found — a `docker context` or leftover `DOCKER_HOST` in
  some shell init file, transient. Force the local socket explicitly if this
  happens: `export DOCKER_HOST=unix:///var/run/docker.sock` before the
  `docker` command.
- **Driver version must match exactly**, not just "close enough" — `nvidia-smi`
  will run but fail cryptically on a minor mismatch. The script fails loudly
  if the post-install `nvidia-smi` doesn't come up clean.
- **`/tmp` vs `/var/tmp`**: the `.run` installer self-extracts roughly 1 GB.
  On a small container `/tmp` is often tmpfs (RAM-backed) and this can trip
  the OOM killer. Both scripts here use `/var/tmp`.
- **GPU sharing is fine.** The host and every passthrough container see the
  same physical GPU and can run processes on it concurrently (default
  compute mode). No MIG/MPS setup needed unless you specifically want
  isolation between tenants.

## Files

- `scripts/gpu-passthrough-lxc-host.sh` — host-side device passthrough (`pct set`).
- `scripts/gpu-provision-lxc.sh` — in-container driver + toolkit + Docker wiring.

Neither script is chezmoi-templated or applied to `$HOME` — they're
infrastructure tooling for the Proxmox host and its containers, invoked
directly (over SSH to the host, then `pct exec` into the container, or copied
in and run locally), not part of a machine's personal dotfile state.
