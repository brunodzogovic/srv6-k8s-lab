
# SRv6 Kubernetes Multi-Cluster Lab with K3s, Cilium, and FRR

This lab demonstrates a dual-stack, BGP-advertised, SRv6-capable Kubernetes setup using:

- **K3s** as the Kubernetes distribution
- **Cilium** as the CNI and BGP control plane
- **FRR (Free Range Routing)** for BGP and SRv6
- **Docker** for containerizing FRR and managing networking
- **Helm** for managing Cilium deployment

## 🧭 Project Structure

```
.
├── cluster1/
│   ├── cluster.env                # Cluster1 environment variables
│   ├── routers/frr1.conf          # FRR config for Cluster1
│   └── docker-compose.yml         # Launches FRR router in Docker
│   └── setup-cluster1.sh          # Script that starts the cluster
├── cluster2/
│   ├── cluster.env
│   ├── routers/frr2.conf
│   └── docker-compose.yml
│   └── setup-cluster2.sh
├── build/
│   ├── Dockerfile
│   ├── build.sh                   # A script to build custom Docker image for FRR routers
│   ├── entrypoint.sh      
├── prepare-node.sh                # Installs dependencies, configures system, and starts FRR
├── cleanup-cluster.sh             # Removes K3s & Cilium from any cluster
├── initialize-cluster.sh          # Interactive launcher script
|-- README.md
|-- test.yaml                          # Test deployment to test the BGP SRv6 endpoints
```

## 🚀 Getting Started

### 1. Prepare a Node

This sets up sysctl, installs Docker, Helm, Cilium CLI, and launches FRR:

```bash
./prepare-node.sh
```

Follow the prompt to choose cluster 1 or 2. This will:
- Modify the relevant FRR config using values from `cluster.env`
- Replace BGP `listen range` with the correct `LB_POOL_V4`
- Launch FRR with Docker Compose

### 2. Deploy a Cluster (K3s + Cilium)

```bash
./initialize-cluster.sh
```

You’ll be asked to choose Cluster 1 or 2. This will:
- Install the latest stable K3s version
- Install Cilium with BGP + LoadBalancer IPAM
- Apply cluster-specific Cilium BGP and LB configs

### 3. Clean Up

To remove K3s and Cilium:

```bash
./cleanup.sh
```

The script automatically detects the active cluster and removes its stack.

## 📡 BGP + SRv6 Configuration Highlights

- Each FRR container is configured with:
  - `bgp listen range` dynamically set to `LB_POOL_V4` from env
  - Peering with the opposite cluster’s FRR via IPv4
  - `network` directive to advertise SRv6 `/64` prefixes
  - `segment-routing srv6` static SID and locator blocks

- Cilium advertises LoadBalancer IPs over BGP using:
  - `CiliumBGPClusterConfig`
  - `CiliumBGPAdvertisement`
  - `CiliumLoadBalancerIPPool`

## 📋 Requirements

- Ubuntu 20.04+ (tested)
- Internet access (for installing Docker, Helm, K3s, etc.)
- At least 2 nodes (VMs or physical) to represent cluster1 and cluster2

## 📎 Useful Commands

- Check BGP peering:
  ```bash
  docker exec -it frr1 vtysh -c "show bgp summary"
  ```

- Check advertised routes in Cilium:
  ```bash
  cilium bgp routes advertised ipv6
  ```

- Deploy a test app:
  ```bash
  kubectl apply -f nginx.yaml
  ```

- View service IPs:
  ```bash
  kubectl get svc -o wide
  ```

## 📦 Future Improvements

- Add support for cluster mesh via clustermesh-apiserver
- Integrate Hubble for observability
- Automate dual-stack test validation

## ✅ Maintainers

This lab was designed to demonstrate advanced Cilium BGP features with SRv6, useful for 5G Core, Edge, and Service Mesh deployments.

Happy experimenting!

