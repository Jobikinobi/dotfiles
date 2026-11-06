# Agent sandboxes on kiac

Isolated sandboxes for running untrusted (for example AI-agent) code on a local
[kiac](https://github.com/saiyam1814/kiac) cluster, using the Kubernetes
[agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) `Sandbox` API.

Two isolation runtimes are supported:

| Runtime | Isolation | Works on |
|---|---|---|
| **gVisor** (`runtimeClassName: gvisor`) | Each pod gets its own user-space kernel | Any Apple silicon Mac |
| **Kata** (`runtimeClassName: kata`) | Each pod is a separate VM | M3 or newer, via `kiac-create-kata.sh` |

Kata needs a VM inside the node VM (nested virtualization). M1 and M2 chips
can't do that, so the MacBook (M1) uses gVisor.

## Versions

| Component | Version |
|---|---|
| agent-sandbox | v1.0.9 (`agents.x-k8s.io/v1beta1`) |
| gVisor | release-20261026.0 |
| Kata Containers (kata-deploy chart) | 4.3.1 |

## Quick start

gVisor, on any kiac cluster:

```sh
kiac create cluster              # or use an existing cluster
cd ~/dotfiles/kube               # this folder (not deployed by chezmoi)
./bootstrap.sh gvisor
kubectl apply -f vm-sandbox.yaml
kubectl -n kiac-dev exec -it gpu-untrusted-sandbox -- bash
```

Kata needs a cluster made by `kiac-create-kata.sh` (a plain `kiac create cluster`
has no `/dev/kvm`); see [Kata on the Mac Studio](#kata-on-the-mac-studio-tested-m4-max-macos-2701-kiac-090).

Check which runtime a sandbox is using: inside gVisor, `uname -r` ends in
`-gvisor`. Inside Kata, `uname -r` shows the Kata guest kernel, not the node's.

## Files

| File | What it does |
|---|---|
| `bootstrap.sh` | Namespace + agent-sandbox controller + chosen runtime |
| `install-gvisor.sh` | Copies runsc onto worker nodes, registers it with containerd |
| `gvisor-runtime.yaml` | `gvisor` RuntimeClass (only nodes labeled `sandbox.gvisor.dev/ready`) |
| `vm-sandbox.yaml` | Example sandbox on gVisor |
| `install-kata.sh` | Checks nodes for `/dev/kvm`, labels them, installs kata-deploy with Helm |
| `kata-values.yaml` | Helm values: arm64 QEMU shim only, creates the `kata` RuntimeClass |
| `vm-sandbox-kata.yaml` | Example sandbox on Kata |
| `kiac-create-kata.sh` | Creates a nested-virt kiac cluster and installs Kata on it |
| `shim/krunkit` | Adds `--nested` to krunkit when put on PATH for kiac |

The gVisor node changes live only inside the running node VMs. If you delete
and recreate the cluster, run `bootstrap.sh` again.

## Kata on the Mac Studio (tested: M4 Max, macOS 27.0.1, kiac 0.9.0)

```sh
cd ~/dotfiles/kube
./kiac-create-kata.sh                  # creates cluster "kata", installs agent-sandbox + Kata
kubectl apply -f vm-sandbox-kata.yaml
kubectl -n kiac-dev exec untrusted-sandbox-kata -- uname -r   # 6.18.x = Kata guest kernel
```

After a reboot, resume with the shim on PATH, or the nodes boot without nested virt
(tested: `/dev/kvm`, mDNS and the sandbox all come back):
`PATH="$PWD/shim:$PATH" kiac resume cluster --name kata`

gVisor (`bootstrap.sh gvisor`) doesn't work on this cluster: `install-gvisor.sh`
uses `container exec`, which only reaches Apple container (non-GPU) kiac nodes.

Why the extra pieces are needed:

- **krunkit, not Apple container.** Apple's `container --virtualization` starts the
  guest at EL2, but its default kernel has no KVM, and kiac never passes the flag.
  kiac's GPU backend (`--gpu-workers`) runs nodes as Fedora VMs under krunkit, and
  Fedora's kernel has KVM.
- **`shim/krunkit`** adds `--nested` to every krunkit call kiac makes (kiac has no
  option for it). Nodes then have `/dev/kvm`.
- **mDNS.** kiac waits for nodes at `<node>.local`, but they came up with mDNS off and
  creation timed out. `kiac-create-kata.sh` turns it on in each node as it boots.
- **Kata drop-in (`kata-values.yaml`).** Under nested KVM: there's no PMU, so QEMU
  rejects Kata's `-cpu host,pmu=off`; MSI interrupts don't reach the guest, so it
  boots with `pci=nomsi`; and the agent takes longer to start, so the connect
  timeout is 60s.
- **Kata runs on the control plane.** The cluster has 0 plain workers (the GPU
  worker is tainted), so the control plane is untainted and hosts the Kata VMs.

Two macOS gotchas on the host:

- **Local Network privacy.** If `kubectl` says `no route to host` while `ping` works,
  the app running your shell lacks Local Network access (System Settings, Privacy &
  Security, Local Network). Apple's own `ssh`/`curl` aren't affected.
- **helm + Keychain.** `helm` OCI pulls can hang on `docker-credential-osxkeychain`.
  `install-kata.sh` installs the chart from the GitHub release tarball instead.

On an M1/M2 none of this works (no nested virt); use gVisor.

## GPUs

The nodes have no NVIDIA GPU, so the GPU passthrough steps in most Kata guides
don't apply. kiac's `--gpu-workers` exposes the Apple GPU through krunkit; how
that combines with gVisor or Kata hasn't been tested.
