#!/bin/bash

set -e

CLUSTER_NAME="cluster1"
ENV_FILE="./cluster1/cluster.env"
KIND_CONFIG="cluster1/kind-config/kind-cluster1.yaml"
CILIUM_INSTALL_SCRIPT="./cluster1/cilium/install_cilium_c1.sh"

# Load env variables
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ Environment file $ENV_FILE not found. Aborting."
  exit 1
fi
source "$ENV_FILE"

# Prompt to delete existing cluster
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists."
  read -p "Do you want to delete and recreate it? (y/n): " delete_choice
  if [[ "$delete_choice" == "y" ]]; then
    echo "🧨 Deleting existing cluster..."
    kind delete cluster --name "$CLUSTER_NAME"
    echo "✅ Deleted existing cluster."
  else
    echo "❌ Aborting setup."
    exit 1
  fi
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

# Create KinD cluster
echo "🚀 Creating KinD cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
echo "✅ KinD cluster '$CLUSTER_NAME' created."

# Fetch latest Cilium version
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/refs/heads/main/stable.txt)
echo "📦 Using Cilium version: $CILIUM_VERSION"

# Create install script dynamically
echo "⚙️  Creating Cilium install script at $CILIUM_INSTALL_SCRIPT ..."
mkdir -p ./cluster1/cilium
cat > "$CILIUM_INSTALL_SCRIPT" <<EOF
#!/bin/bash

helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=$CLUSTER_NAME \
  --set cluster.id=$CLUSTER_ID \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true
EOF
chmod +x "$CILIUM_INSTALL_SCRIPT"

# Install Cilium
echo "🚀 Installing Cilium using $CILIUM_INSTALL_SCRIPT ..."
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for pods
echo "⏳ Waiting for Cilium pods to be ready..."
kubectl -n kube-system rollout status daemonset/cilium

# Apply BGP peer config
echo "⚙️  Generating Cilium BGP Peer Config..."
mkdir -p ./cluster1/cilium
cat > ./cluster1/cilium/cilium-bgp-peerconfig.yaml <<EOF
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
kubectl apply -f ./cluster1/cilium/cilium-bgp-peerconfig.yaml

# Apply BGP cluster config
echo "📡 Applying Cilium BGP Cluster Config..."
cat > ./cluster1/cilium/cilium-bgp-clusterconfig.yaml <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: cluster1-bgp-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
  - name: "instance-${LOCAL_ASN}"
    localASN: ${LOCAL_ASN}
    peers:
    - name: "peer-${LOCAL_ASN}-${PEER_NAME}"
      peerASN: ${PEER_ASN}
      peerAddress: ${PEER_IPV4}
      peerConfigRef:
        name: "cilium-peer"
EOF
kubectl apply -f ./cluster1/cilium/cilium-bgp-clusterconfig.yaml

echo "🎉 Cluster1 with KinD + Cilium $CILIUM_VERSION + BGP is fully ready."

