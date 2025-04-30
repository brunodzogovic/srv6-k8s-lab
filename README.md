# 🧠 SRv6-Enabled Kubernetes Lab with Cilium and BGP

This lab sets up a dual-cluster Kubernetes environment with SRv6 (Segment Routing over IPv6), BGP-based routing using FRR (Free Range Routing), and Cilium as the CNI. 

## 📦 Project Structure

```
./srv6-k8s-lab
├── build/                        # Docker image build tools for FRR
├── cluster1/                     # Cluster 1 configuration
│   ├── cilium/                   # Cilium install and configs
│   ├── kind-config/             # KinD config
│   ├── benchmarking/            # Network test manifests
│   ├── routers/                 # FRR daemon and config
│   └── setup-cluster1.sh        # Cluster1 setup script
├── cluster2/                     # Cluster 2 configuration
│   ├── cilium/                   # Cilium install and configs
│   ├── kind-config/             # KinD config
│   ├── benchmarking/            # Network test manifests
│   ├── routers/                 # FRR daemon and config
│   └── setup-cluster2.sh        # Cluster2 setup script
├── prepare-nodes.sh             # Installs dependencies and prepares the node
├── initialize-cluster.sh        # Interactive launcher for cluster1 or cluster2
├── cleanup-cluster1.sh          # Clean cluster1 environment
├── cleanup-cluster2.sh          # Clean cluster2 environment
└── README.md                    # This file
```

## ✅ Prerequisites
- Linux system with root access
- Bash shell

## ⚙️ Node Preparation
Run this once per VM to prepare the environment:

```bash
sudo ./prepare-nodes.sh
```
This will:
- Enable IPv6 + SRv6
- Install Docker + Docker Compose
- Install KinD
- Install Helm
- Install `kubectl`
- Install `cilium` CLI
- Patch FRR config (`frr1.conf` or `frr2.conf`) with the current hostname and peer IPs
- Launch FRR container using Docker Compose

## 🚀 Cluster Deployment
Use the top-level interactive launcher to initialize either cluster:

```bash
./initialize-cluster.sh
```

You’ll be asked to:
- Choose cluster (1 or 2)
- Optionally delete an existing cluster
- Choose Cilium mode (minimal or full eBPF + XDP)

Each setup script:
- Creates a new KinD cluster with IPv6-only networking
- Fetches latest Cilium version
- Installs Cilium with the chosen config
- Waits for Cilium to be ready
- Generates and applies:
  - `CiliumBGPClusterConfig`
  - `CiliumBGPPeerConfig`

## 🔧 Cilium Config Modes
You’ll be prompted to choose one:

### 1️⃣ Minimal
- Uses `ipam.mode=cluster-pool`
- BGP control plane enabled
- eBPF and kube-proxy are **not** replaced

### 2️⃣ Full (eBPF + XDP)
- Enables eBPF datapath
- Replaces kube-proxy
- Enables XDP acceleration (if supported)

## 🔍 Benchmarking Tools
Both clusters include:
- `iperf3` client/server
- `qperf` daemonset
- `scale_test.sh` to stress-test the cluster

Deploy benchmarking:
```bash
kubectl apply -f ./cluster1/benchmarking/
# or
kubectl apply -f ./cluster2/benchmarking/
```

## 🧼 Cleanup
Each cluster has a dedicated cleanup script:
```bash
./cleanup-cluster1.sh
./cleanup-cluster2.sh
```
> These preserve all generated config files (`kind-config/*.yaml`, `cilium/*.yaml`).

## 🛠 Troubleshooting
- If `kubectl rollout status` hangs, inspect pod logs:
```bash
kubectl -n kube-system logs -l k8s-app=cilium
```
- To test cluster state:
```bash
cilium status
cilium connectivity test
```

## 📘 Documentation References
- Cilium: https://docs.cilium.io
- SRv6 Linux Kernel: https://segment-routing.org/
- BGP + Cilium: https://docs.cilium.io/en/stable/network/bgp/

---

Enjoy programmable networking in Kubernetes with SRv6 and Cilium! 🎉

