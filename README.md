🚀 SRv6 BGP Lab with K3s + Cilium + FRR

This project sets up a dual-stack Kubernetes environment using K3s with Cilium CNI, BGP peering via FRR (Free Range Routing), and SRv6 support for advanced networking experimentation.

📦 Components

K3s: Lightweight Kubernetes distribution

Cilium: CNI plugin with BGP Control Plane v2

FRR: Used for BGP peering and SRv6 configuration

Docker: Hosts FRR containers and used to build isolated lab environments

🧱 Directory Structure

srv6-k8s-lab/
├── cluster1/
│   ├── cluster.env
│   ├── docker-compose.yml
│   ├── routers/
│   │   └── frr1.conf
├── cluster2/
│   ├── cluster.env
│   ├── docker-compose.yml
│   ├── routers/
│   │   └── frr2.conf
├── common/
│   ├── base-images/
│   └── helpers/
├── initialize-cluster.sh
├── prepare-node.sh
├── cleanup.sh
└── README.md

⚙️ Usage

1. ✅ Prepare the host

sudo ./prepare-node.sh

Sets sysctl flags for IPv6 forwarding and SRv6

Installs Docker, Helm, and Cilium CLI if missing

Starts the appropriate FRR container

Dynamically updates FRR config using values in cluster.env

2. 🚀 Initialize a cluster

./initialize-cluster.sh

Prompts you to choose cluster1 or cluster2

Uses values from cluster.env to:

Generate K3s config

Install Cilium with correct flags (e.g. dual-stack, BGP)

Apply IPAM pool, advertisement, and BGP CRDs

3. 🧼 Cleanup

./cleanup.sh

Automatically detects which cluster is running and removes:

Helm release of Cilium

K3s installation

🔍 Configuration Details

Each cluster's cluster.env file defines:

Local/peer BGP settings

IP pool for LB IPAM

Pod/Service subnets

SRv6 locator and static SIDs

Example snippet:

LOCAL_IPV6=2001:db8:2::1/64
PEER_IPV4=192.168.2.3
ADVERTISED_IPV6=2001:db8:2::/64
LB_POOL_V4=172.23.0.0/16
LB_POOL_V6=2001:db8:2:fee::/112

These are parsed automatically into:

FRR config (frr2.conf)

K3s + Cilium deployment flags

Cilium BGP advertisements + peer config

🛰️ FRR & SRv6

FRR is launched as a Docker container (host network mode)

BGP config includes dynamic peering (bgp listen range ... peer-group CILIUM)

Segment Routing is enabled via:

segment-routing
 srv6
  static-sids
   sid 2001:db8:2:1::1/128 locator cluster2_locator behavior uN
  ...

✅ Status Check

cilium status
cilium bgp peers
cilium bgp routes available ipv6
cilium bgp routes advertised ipv6

📌 Notes

Pod-to-pod routing requires correct clusterPoolIPv4PodCIDRList in Cilium config

Peering works with dynamic IPs assigned from the Docker bridge (172.19.0.0/16) and maps to LB IPAM pool

K3s is used exclusively (no longer using KinD)

📬 Feedback / Contribution

Open an issue or PR for improvements!

🔗 References

Cilium BGP Control Plane v2 Docs

FRR BGP Guide

K3s Official Site

 
