#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="kind-config/kind-cluster2.yaml"
POD_SUBNET="2001:db8:2::/64"
SERVICE_SUBNET="2001:db8:2:fee::/112"
FRR_PEER_IP="192.168.2.3"
LOCAL_ASN="65002"
PEER_ASN="65001"

# Auto-delete if cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists. Deleting it..."
  kind delete cluster --name $CLUSTER_NAME
  echo "✅ Old cluster '$CLUSTER_NAME' deleted."
fi

echo "📦 Creating KinD cluster: $CLUSTER_NAME..."

cat > $KIND_CONFIG <<EOF
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

kind create cluster --name $CLUSTER_NAME --config $KIND_CONFIG
echo "✅ KinD cluster '$CLUSTER_NAME' created."

echo "🚀 Installing Cilium from: ./cilium/install_cilium_c2.sh ..."
bash ./cilium/install_cilium_c2.sh
echo "✅ Cilium installed via script."

# Wait for all pods to be ready
echo "⏳ Waiting for Cilium pods to become ready..."
kubectl -n kube-system rollout status daemonset/cilium

# Apply BGP Peering Policy
echo "📡 Applying BGP peering policy..."

cat > bgp-peering-policy.yaml <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: cluster2-peering
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  virtualRouters:
  - localASN: ${LOCAL_ASN}
    exportPodCIDR: true
    neighbors:
    - peerAddress: "${FRR_PEER_IP}/32"
      peerASN: ${PEER_ASN}
EOF

kubectl apply -f bgp-peering-policy.yaml
echo "✅ BGP Peering Policy applied."

echo "🎉 Cluster2 with KinD + Cilium + BGP is fully ready."

