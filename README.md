# 🚀 SRv6 Kubernetes Lab: FRR, Cilium & KinD Integration

Welcome to the **SRv6-K8s-Lab**, an end-to-end environment for experimenting with cutting-edge IPv6 Segment Routing (SRv6), Border Gateway Protocol (BGP), and Cilium-powered Kubernetes networking — all built atop lightweight [KinD](https://kind.sigs.k8s.io/) clusters.

---

## 🌐 Overview

This lab brings together:

- ✅ **FRRouting (FRR)** – for advanced BGP and SRv6 routing.
- ✅ **Cilium** – for container networking, with modes for:
  - Minimal CNI (no eBPF)
  - Full eBPF/XDP acceleration with kube-proxy replacement
- ✅ **Kubernetes (KinD)** – container-based local clusters.
- ✅ Benchmarking tools (`iperf3`, `qperf`) for performance testing.
- ✅ **IPv6** + **SRv6** + **BGP Peering** – end-to-end.

---

## 📁 Project Structure

```
srv6-k8s-lab/
├── cluster1/
│   ├── cilium/
│   ├── kind-config/
│   ├── routers/
│   └── benchmarking/
├── cluster2/
│   ├── cilium/
│   ├── kind-config/
│   ├── routers/
│   └── benchmarking/
├── build/                      # Dockerfile & FRR image build
├── prepare-nodes.sh           # Node preparation script
├── README.md
```

---

## ⚙️ Requirements

- Docker
- A Linux-based environment (Debian/Ubuntu recommended)
- Basic networking knowledge

⚠️ You **do not** need to pre-install `kubectl`, `kind`, `helm`, or `cilium`. These will be installed automatically.

---

## 🛠️ Step 1: Prepare the Node

Run this on each VM:

```bash
sudo bash prepare-nodes.sh
```

- Enables SRv6 kernel support via `sysctl`
- Installs:
  - KinD
  - Helm
  - kubectl
  - Cilium CLI
- Prompts:
  - Choose cluster ID (1 or 2)
  - Edit hostname and IPs in FRR config interactively

---

## 🚀 Step 2: Launch the Cluster

```bash
cd cluster2
bash setup-cluster2.sh
```

You will be prompted to choose between:

1. Minimal Cilium (kube-proxy, no eBPF)
2. Full eBPF + XDP + kube-proxy replacement

The script:

- Creates a KinD cluster with IPv6
- Installs Cilium via Helm
- Waits for CRDs to be ready
- Applies BGP configuration

Repeat for `cluster1` as needed.

---

## 🧪 Step 3: Benchmark & Validate

From inside the cluster directory:

```bash
kubectl apply -f benchmarking/iperf3-server.yaml
kubectl apply -f benchmarking/iperf3-client-pod.yaml
```

Other useful commands:

```bash
vtysh -c "show bgp ipv6 unicast summary"    # FRR BGP status
cilium status                               # Cilium agent status
cilium connectivity test                    # End-to-end connectivity check
```

---

## 🧹 Cleanup

To delete the KinD cluster:

```bash
cd cluster2
bash cleanup.sh
```

Cluster config files will be retained between runs for consistency.

---

## 🚧 Roadmap

- 🔄 ClusterMesh federation
- ⚖️ BGP Multipath + ECMP
- 📊 Performance benchmarking:
  - kube-proxy vs eBPF/XDP
- 🧠 Advanced SRv6 policies
- ☁️ Ingress + L4/L7 routing w/ SRv6 paths

---

## 🙌 Acknowledgments

Built with ❤️ by SRv6 & Kubernetes networking enthusiasts.

Feel free to fork, improve, or open issues. PRs are welcome!
