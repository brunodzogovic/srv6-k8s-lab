#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="cluster2/kind-config/kind-cluster2.yaml"
CILIUM_INSTALL_SCRIPT="cluster2/cilium/install_cilium_c2.sh"
BGP_CONFIG_FILE="cluster2/cilium/cilium-bgp-clusterconfig.yaml"
PEER_CONFIG_FILE="cluster2/cilium/cilium-bgp-peerconfig.yaml"

# Load environment variables
if [[ -f "cluster2/cluster.env" ]]; then
  source cluster2/cluster.env
else
  echo "❌ Missing cluster2/cluster.env file. Aborting."
  exit 1
fi

# Fetch latest stable Cilium version
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/refs/heads/main/stable.txt)
echo "📦 Using Cilium version: $CILIUM_VERSION"
export CILIUM_VERSION

# Ask user if existing cluster should be deleted
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  read -p "⚠️  Cluster '$CLUSTER_NAME' already exists. Delete it and recreate? (y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ Aborting setup."
    exit 0
  fi
  echo "   Deleting existing cluster..."
  kind delete cluster --name "$CLUSTER_NAME"
fi

# Generate KinD config
echo "📄 Generating KinD config at $KIND_CONFIG..."
mkdir -p "$(dirname "$KIND_CONFIG")"
cat > "$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: "${POD_SUBNET_V4},${POD_SUBNET_V6}"
  serviceSubnet: "${SERVICE_SUBNET_V4},${SERVICE_SUBNET_V6}"
  ipFamily: dual
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

# Create the cluster
echo "🚀 Creating KinD cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
echo "✅ KinD cluster '$CLUSTER_NAME' created."

# Generate and run install script for Cilium
echo "⚙️  Creating Cilium install script at $CILIUM_INSTALL_SCRIPT ..."
mkdir -p "$(dirname "$CILIUM_INSTALL_SCRIPT")"
cat > "$CILIUM_INSTALL_SCRIPT" <<'EOF'
#!/bin/bash
source "$(dirname "$0")/../cluster.env"

helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium \
  --namespace kube-system --create-namespace \
  --version "$CILIUM_VERSION" \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set ipv6.enabled=true \
  --set ipv6NativeRoutingCIDR=$POD_SUBNET_V6 \
  --set clusterPoolIPv6PodCIDR=$POD_SUBNET_V6 \
  --set clusterPoolIPv6MaskSize=64 \
  --set ipv4.enabled=true \
  --set ipv4NativeRoutingCIDR=$POD_SUBNET_V4 \
  --set clusterPoolIPv4PodCIDR=$POD_SUBNET_V4 \
  --set clusterPoolIPv4MaskSize=16 \
  --set cluster.name=$CLUSTER_NAME \
  --set cluster.id=$CLUSTER_ID \
  --set bgpControlPlane.enabled=true
EOF
chmod +x "$CILIUM_INSTALL_SCRIPT"

# Install Cilium
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for pods
kubectl -n kube-system rollout status daemonset/cilium

# Generate BGP cluster config
cat > "$BGP_CONFIG_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cluster2-bgp-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
  - name: instance-${LOCAL_ASN}
    localASN: ${LOCAL_ASN}
    peers:
    - name: peer-${PEER_ASN}
      peerASN: ${PEER_ASN}
      peerAddress: ${PEER_IPV4}
      peerConfigRef:
        name: cilium-peer
EOF

# Generate peer config
cat > "$PEER_CONFIG_FILE" <<EOF
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
    - afi: ipv6
      safi: unicast
      advertisements:
        matchLabels:
          advertise: "bgp"
EOF

# Apply configs
kubectl apply -f "$PEER_CONFIG_FILE"
kubectl apply -f "$BGP_CONFIG_FILE"

echo "🎉 Cluster2 with Cilium $CILIUM_VERSION + BGP is fully ready."

