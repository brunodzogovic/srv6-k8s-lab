#!/bin/bash

set -e

# Resolve directory this script lives in (e.g. ./cluster2)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="cluster2"
KIND_CONFIG="${SCRIPT_DIR}/kind-config/kind-cluster2.yaml"
CILIUM_DIR="${SCRIPT_DIR}/cilium"
CILIUM_INSTALL_SCRIPT="${CILIUM_DIR}/install_cilium_c2.sh"
POD_SUBNET="2001:db8:2::/64"
SERVICE_SUBNET="2001:db8:2:fee::/112"

# Get latest Cilium version dynamically
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/refs/heads/main/stable.txt)
echo "📦 Using Cilium version: $CILIUM_VERSION"

# Check if cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists."
  read -rp "❓ Do you want to delete and recreate it? (y/N): " confirm_delete
  if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
    echo "🧨 Deleting existing cluster '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "✅ Old cluster '$CLUSTER_NAME' deleted."
  else
    echo "🚫 Aborting cluster recreation. Exiting."
    exit 0
  fi
fi

# Generate KinD config in cluster2/kind-config/
echo "📄 Generating KinD config at $KIND_CONFIG ..."
mkdir -p "$(dirname "$KIND_CONFIG")"
cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "${POD_SUBNET}"
  serviceSubnet: "${SERVICE_SUBNET}"
  ipFamily: ipv6
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

# Create cluster
echo "🚀 Creating KinD cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
echo "✅ KinD cluster '$CLUSTER_NAME' created."

# Generate Cilium install script in cluster2/cilium/
echo "⚙️  Generating Cilium install script at $CILIUM_INSTALL_SCRIPT ..."
mkdir -p "$CILIUM_DIR"
cat > "$CILIUM_INSTALL_SCRIPT" <<EOF
#!/bin/bash

# Install Cilium with Cluster-Pool IPAM
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \\
  --namespace kube-system --create-namespace \\
  --set installCRDs=true \\
  --set ipam.mode=cluster-pool \\
  --set cluster.name=cluster2 \\
  --set cluster.id=2 \\
  --set bgpControlPlane.enabled=true \\
  --set ipv6.enabled=true
EOF
chmod +x "$CILIUM_INSTALL_SCRIPT"

# Run it
echo "🚀 Installing Cilium using $CILIUM_INSTALL_SCRIPT ..."
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for DaemonSet
echo "⏳ Waiting for Cilium pods to become ready..."
kubectl -n kube-system rollout status daemonset/cilium

# Generate BGP Peer Config
BGP_PEER_FILE="${CILIUM_DIR}/cilium-bgp-peerconfig.yaml"
echo "📄 Creating Cilium BGP Peer Config..."
cat > $BGP_PEER_FILE <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  authSecretRef: bgp-auth-secret
  ebgpMultihop: 4
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
EOF

# Generate Cilium BGP cluster config
BGP_CONFIG_FILE="${CILIUM_DIR}/cilium-bgp-clusterconfig.yaml"
echo "📡 Applying Cilium BGP Cluster Config..."
cat > "$BGP_CONFIG_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cilium-bgp
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
    - name: "cluster2-instance"
      localASN: 65002
      peers:
        - name: "cluster1-peer"
          peerASN: 65001
          peerAddress: 192.168.2.3
          peerConfigRef:
            name: cilium-peer
EOF

kubectl apply -f "$BGP_PEER_FILE"
echo "✅ BGP Peer Config applied."

kubectl apply -f "$BGP_CONFIG_FILE"
echo "✅ BGP Cluster Config applied."

echo "🎉 Cluster2 with KinD + Cilium $CILIUM_VERSION + BGP is fully ready."
