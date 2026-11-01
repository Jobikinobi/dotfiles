# Agent sandboxes on kiac

Isolated sandboxes for running untrusted (for example AI-agent) code on a local
[kiac](https://github.com/) cluster, using the Kubernetes
[agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox) `Sandbox` API.

Two isolation runtimes are supported:

| Runtime | Isolation | Works on |
|---|---|---|
| **gVisor** (`runtimeClassName: gvisor`) | Each pod gets its own user-space kernel | Any Apple silicon Mac |
| **Kata** (`runtimeClassName: kata`) | Each pod is a separate VM | Nodes with `/dev/kvm`: M3 or newer, macOS 15+, nested virtualization on |

Kata needs a VM inside the node VM (nested virtualization). M1 and M2 chips
can't do that, so the MacBook (M1) uses gVisor.

## Versions

| Component | Version |
|---|---|
| agent-sandbox | v1.0.9 (`agents.x-k8s.io/v1beta1`) |
| gVisor | release-20261026.0 |
| Kata Containers (kata-deploy chart) | 4.3.1 |

## Quick start

```sh
kiac create cluster              # or use an existing cluster
cd ~/dotfiles/kube               # this folder (not deployed by chezmoi)
./bootstrap.sh gvisor            # or: ./bootstrap.sh kata
kubectl apply -f vm-sandbox.yaml # or: vm-sandbox-kata.yaml
kubectl -n kiac-dev exec -it gpu-untrusted-sandbox -- bash
```

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

The gVisor node changes live only inside the running node VMs. If you delete
and recreate the cluster, run `bootstrap.sh` again.

## Kata on the Mac Studio

1. **Check the chip.** Run `sysctl -n machdep.cpu.brand_string`. It needs to be
   M3 or newer (M3 Ultra, M4 Max, etc.) with macOS 15 or later.
2. **Create the cluster and run `./bootstrap.sh kata`.** The script checks
   every worker for `/dev/kvm` and stops without installing anything if none
   has it.
3. **If no node has `/dev/kvm`:** kiac v0.9.0 has no option to turn on nested
   virtualization for its node VMs (Apple's `container` tool supports it with
   `--virtualization`, but kiac doesn't pass that through). Options:
   - Check whether a newer kiac adds it: `kiac create cluster --help | grep -i virt`.
   - Run the cluster in [Lima](https://lima-vm.io) VMs instead, which support
     `limactl create --nested-virt` (Lima 2.x, `vz` VM type), and install
     Kubernetes (for example k3s) inside them. Set `k8sDistribution: k3s` in
     `kata-values.yaml` if you use k3s. *Not tested yet.*

## GPUs

The nodes have no NVIDIA GPU, so the GPU passthrough steps in most Kata guides
don't apply. kiac's `--gpu-workers` exposes the Apple GPU through krunkit; how
that combines with gVisor or Kata hasn't been tested.
