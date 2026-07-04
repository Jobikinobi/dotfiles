# ADR-002: Standardize on Netbird for mesh networking; remove Tailscale, Cloudflare, and headscale

## Status

Accepted

## Date

2026-07-02

## Context

`dotfiles` has cycled through several WireGuard/mesh approaches while searching for the
right standard:

- **Tailscale** — the incumbent. Baked into the Docker images (`Dockerfile.test`,
  `Dockerfile.alpine`, `Dockerfile.rhel` all `COPY` the `tailscaled`/`tailscale` binaries),
  the container `entrypoint.sh` (`tailscaled` + `tailscale up --ssh`), dedicated bootstrap
  scripts (`run_once_before_install-tailscale.sh.tmpl`,
  `run_once_after_install-tailscale-ssh.sh.tmpl`), `tailscale.json`, and a MagicDNS tailnet
  (`lemming-likert.ts.net`, referenced in `CLAUDE.md`).
- **headscale** — a self-hosted Tailscale control plane, evaluated and partially rolled out.
  It left a large docs footprint under `docs/homelab/headscale/` (cutover playbook, per-OS
  recipes, reverse-proxy, rollback) plus `docs/research/headscale-evaluation.md`. It never
  reached cert-automation parity with hosted Tailscale (issue #49).
- **Cloudflare** — a tunnel for external ingress was explored
  (`docs/research/cloudflare-mesh-evaluation.md`, issue #50).

This produced a contradictory backlog: issue #89 (remove Tailscale + Cloudflare, commit to
Netbird), issue #78 (run Tailscale + Netbird together), and issues #33/#49/#51 (extend the
Tailscale/headscale direction). They cannot all hold.

The deciding factor is developer ergonomics: **Netbird** delivers the target workflow —
`ssh username@netbirdhostname` (e.g. `ssh udev`, `ssh macstudio`) to any authenticated
machine, with first-class SSH support — while remaining a standards-based WireGuard mesh.
The long provider search has concluded on Netbird.

## Decision

**Standardize on Netbird for all mesh networking across `dotfiles` and the HOLE Foundation
ecosystem. Remove Tailscale, headscale, and Cloudflare (tunnel/mesh) entirely.**

Netbird becomes the single mesh transport and the SSH access layer. Any Tailscale, headscale,
or Cloudflare code, config, or documentation is contamination to be removed.

## Alternatives Considered

### Tailscale + Netbird together (issue #78)
- **Pros**: Tailscale is the de-facto standard; keeps a familiar fallback.
- **Cons**: Two overlapping WireGuard daemons, ambiguous ownership of routing/DNS/ACLs,
  double the bootstrap and update surface on every machine and image.
- **Rejected**: Redundant transports are a maintenance and debugging liability with no
  offsetting benefit once Netbird covers the SSH-access goal.

### Tailscale + self-hosted headscale (issues #33, #49, #51)
- **Pros**: Removes the Tailscale SaaS dependency; full control of the control plane.
- **Cons**: No cert-automation parity with hosted Tailscale (#49); ongoing burden of running,
  securing, and upgrading the control plane and its reverse proxy; the 2026-06-05 rollout
  surfaced non-trivial per-OS gotchas.
- **Rejected**: Operational cost of self-hosting the control plane is not justified once
  Netbird provides an equivalent managed mesh.

### Cloudflare tunnel for external routing (issue #50)
- **Pros**: Simple public ingress to self-hosted services.
- **Cons**: A separate tool solving a different problem than the mesh; adds a third networking
  vendor to reason about.
- **Rejected**: Out of scope for the mesh standard. External ingress, if still needed, will be
  decided separately and is not part of the default dotfiles stack.

## Consequences

### Immediate
- Issues superseded by this decision are closed: **#78** (Tailscale+Netbird), **#33**
  (Tailscale universal access), **#49** (headscale certs), **#50** (Cloudflare tunnel),
  **#51** (headscale per-OS docs). **#89** remains the implementation tracker.

### Cleanup surface (removal targets)
Roughly 45 files reference the retired stack. Grouped:

**Container / bootstrap (functional — must be replaced with Netbird, not just deleted):**
- `Dockerfile.test`, `Dockerfile.alpine`, `Dockerfile.rhel` — `COPY` of `tailscaled`/`tailscale`
- `entrypoint.sh` — starts `tailscaled` and `tailscale up --ssh`
- `run_once_before_install-tailscale.sh.tmpl`, `run_once_after_install-tailscale-ssh.sh.tmpl`
- `run_once_after_install-toolchains.sh.tmpl`, `scripts/provision-lxd.sh`,
  `scripts/cloud-init/proxmox-tst.yaml.tmpl`
- `dot_Brewfile`, `dot_Brewfile.save`, `dot_zshrc.tmpl` (tailscale alias — see #14),
  `dot_p10k.zsh`, `tailscale.json`, `private_dot_ssh/config.tmpl`

**Documentation (delete or rewrite for Netbird):**
- `docs/homelab/headscale/**` (entire tree), `docs/homelab/README.md`
- `docs/research/headscale-evaluation.md`, `docs/research/cloudflare-mesh-evaluation.md`
- `docs/architecture.md`, `docs/roadmap.md`, `docs/INDEX.md`, `README.md`, `CLAUDE.md`
  (tailnet reference), profile docs that mention it

### Follow-up (tracked under #89)
- Add Netbird to the bootstrap. Because the agent fleet spans musl (Alpine) and glibc
  (Ubuntu/Debian/Arch/RHEL) containers, the install must go through the **chezmoi** layer
  (the universal provisioner) with the Nix path as a glibc enhancement — mirroring the
  layering in the multi-distro bootstrap (#87).
- Define the Netbird ACL / SSH-access standard (setup keys, hostname scheme, peer policy),
  shared across machines the way the SSH standard (#58) proposes.
- Update `docs/architecture.md` and `CLAUDE.md` to describe Netbird as the mesh, and remove
  the `lemming-likert.ts.net` tailnet reference.

## ADR Directory Note

Second ADR in `dotfiles`, following ADR-001. Sequential `NNN-kebab-case.md` under `docs/adr/`.
