#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="kind-config/kind-cluster2.yaml"
BGP_CONFIG="./cilium/generated-cilium-bgp-clusterconfig.yaml"
POD_SUBNET="2001:db8:2::/64"
SERVICE_SUBNET="2001:db8:2:fee::/112"
FRR_PEER_IP="192.168.2.3"
LOCAL_ASN="65002"
PEER_ASN="65001"

echo "🌐 Preparing to deploy cluster: $CLUSTER_NAME"

# Auto-delete if cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists. Deleting it..."
  kind delete cluster --name "$CLUSTER_NAME"
  echo "✅ Old cluster '$CLUSTER_NAME' deleted."
fi

# Regenerate KinD config
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

# Create KinD cluster
echo "🚀 Creating KinD cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
echo "✅ KinD cluster '$CLUSTER_NAME' created."

# Choose Cilium installation mode
echo ""
echo "Choose Cilium installation mode:"
echo "1) Minimal (kube-proxy, no XDP)"
echo "2) Full (eBPF + XDP acceleration + kube-proxy replacement)"
read -rp "Select option (1 or 2): " CILIUM_MODE

if [[ "$CILIUM_MODE" == "1" ]]; then
  echo "🚀 Installing Cilium (minimal mode) using ./cilium/install_cilium_c2.sh..."
  bash ./cilium/install_cilium_c2.sh
elif [[ "$CILIUM_MODE" == "2" ]]; then
  echo "🚀 Installing Cilium (full eBPF mode) using ./cilium/install_cilium_c2_ebpf.sh..."
  bash ./cilium/install_cilium_c2_ebpf.sh
else
  echo "❌ Invalid selection. Exiting."
  exit 1
fi

echo "✅ Cilium installed."

# Wait for Cilium daemonset to be ready
echo "⏳ Waiting for Cilium pods to become ready..."
kubectl -n kube-system rollout status daemonset/cilium

# Wait until CiliumBGPClusterConfig CRD is ready
echo "⏳ Waiting for CiliumBGPClusterConfig CRD to become available..."
until kubectl get crd ciliumbgpclusterconfigs.cilium.io >/dev/null 2>&1; do
  echo "⌛ Waiting for Cilium CRDs to be created..."
  sleep 2
done

# Generate fresh BGP ClusterConfig
mkdir -p "$(dirname "$BGP_CONFIG")"
cat > "$BGP_CONFIG" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cluster2-bgp-config
spec:
  virtualRouters:
  - localASN: ${LOCAL_ASN}
    serviceSelector:
      matchExpressions:
      - key: some-key
        operator: DoesNotExist
    neighbors:
    - peerAddress: "${FRR_PEER_IP}/32"
      peerASN: ${PEER_ASN}
EOF

# Apply BGP ClusterConfig
echo "📡 Applying Cilium BGP ClusterConfig..."
kubectl apply -f "$BGP_CONFIG"
echo "✅ BGP ClusterConfig applied."

echo "🎉 Cluster2 with KinD + Cilium (mode: $CILIUM_MODE) + BGP is fully ready!"

