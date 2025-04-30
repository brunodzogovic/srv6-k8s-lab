#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="kind-config/kind-cluster2.yaml"
POD_SUBNET="2001:db8:2::/64"
SERVICE_SUBNET="2001:db8:2:fee::/112"
CILIUM_INSTALL_SCRIPT="./cilium/install_cilium_c2.sh"

# Fetch latest stable Cilium version
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/refs/heads/main/stable.txt)
echo "📦 Using Cilium version: $CILIUM_VERSION"

# Auto-delete if cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists. Deleting it..."
  kind delete cluster --name "$CLUSTER_NAME"
  echo "✅ Old cluster '$CLUSTER_NAME' deleted."
fi

# Create KinD config
echo "📄 Generating KinD config..."
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

# Generate Cilium install script dynamically based on latest version
echo "⚙️  Generating Cilium install script at $CILIUM_INSTALL_SCRIPT ..."
mkdir -p ./cilium
cat > "$CILIUM_INSTALL_SCRIPT" <<EOF
#!/bin/bash

# Install Cilium with Cluster-Pool IPAM
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=cluster2 \
  --set cluster.id=2 \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true
EOF
chmod +x "$CILIUM_INSTALL_SCRIPT"

# Install Cilium
echo "🚀 Installing Cilium using $CILIUM_INSTALL_SCRIPT ..."
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for Cilium daemonset to be ready
echo "⏳ Waiting for Cilium pods to become ready..."
kubectl -n kube-system rollout status daemonset/cilium

# Wait for CiliumBGPClusterConfig CRD to become available
#echo "⏳ Waiting for CiliumBGPClusterConfig CRD to become available..."
#until kubectl get crd ciliumbgpclusterconfigs.cilium.io >/dev/null 2>&1; do
#  echo "⌛ Waiting for Cilium CRDs to be created..."
#  sleep 2
#done

# Apply Cilium BGP Cluster Config
echo "📡 Applying Cilium BGP Cluster Config..."
cat > ./cilium/cilium-bgp-clusterconfig.yaml <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cluster2-bgp-config
spec:
  serviceSelector:
    matchExpressions:
    - key: some-key`
      operator: NotIn
      values: ["never-match"]
  virtualRouters:
  - localASN: 65002
    neighbors:
    - peerAddress: "192.168.2.3/32"
      peerASN: 65001
    exportPodCIDR: true
EOF
kubectl apply -f ./cilium/cilium-bgp-clusterconfig.yaml

echo "✅ BGP Cluster Config applied."
echo "🎉 Cluster2 with KinD + Cilium $CILIUM_VERSION + BGP is fully ready."`

