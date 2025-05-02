#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="cluster2/kind-config/kind-cluster2.yaml"
CILIUM_INSTALL_SCRIPT="cluster2/cilium/install_cilium_c2.sh"
BGP_CONFIG_FILE="cluster2/cilium/cilium-bgp-clusterconfig.yaml"
PEER_CONFIG_FILE="cluster2/cilium/cilium-bgp-peerconfig.yaml"
LB_POOL_FILE="cluster2/cilium/lb-pool.yaml"
LB_ADVERTISE_FILE="cluster2/cilium/lb-advertisement.yaml"
LB_SERVICE_FILE="cluster2/cilium/lb-service.yaml"

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
cat > "$CILIUM_INSTALL_SCRIPT" <<EOF
#!/bin/bash
helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=${CLUSTER_NAME} \
  --set cluster.id=${CLUSTER_ID} \
  --set bgpControlPlane.enabled=true \
  --set ipv4.enabled=true \
  --set ipv6.enabled=true \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR=${POD_SUBNET_V4} \
  --set ipv6NativeRoutingCIDR=${POD_SUBNET_V6} \
  --set autoDirectNodeRoutes=true \
  --set loadBalancer.mode=ipip \
  --set bpf.masquerade=false
EOF
chmod +x "$CILIUM_INSTALL_SCRIPT"

# Install Cilium
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for pods
kubectl -n kube-system rollout status daemonset/cilium

# Generate BGP cluster config to point to local FRR instance
cat > "$BGP_CONFIG_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: ${CLUSTER_NAME}-bgp-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
  - name: instance-${LOCAL_ASN}
    localASN: ${LOCAL_ASN}
    peers:
    - name: peer-${LOCAL_ASN}
      peerASN: ${LOCAL_ASN}
      peerAddress: ${LOCAL_IPV4}
      peerConfigRef:
        name: cilium-peer
    - name: peer-ipv6
      peerASN: ${LOCAL_ASN}
      peerAddress: ${LOCAL_FRR_IPV6}
      peerConfigRef:
        name: cilium-peer
EOF

# Generate peer config (single merged definition)
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
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
    - afi: ipv6
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
EOF

# Generate LB IPAM pool definition
cat > "$LB_POOL_FILE" <<EOF
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: ${CLUSTER_NAME}-pool
spec:
  blocks:
  - cidr: "$LB_POOL_V4"
  - cidr: "$LB_POOL_V6"
EOF

# Generate BGP advertisement config
cat > "$LB_ADVERTISE_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: bgp-advertisements
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
EOF

# Generate example LB service with label
cat > "$LB_SERVICE_FILE" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: test-lb-service
  labels:
    app: test-app
    advertise: bgp
spec:
  selector:
    app: test-app
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
    - IPv4
    - IPv6
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF

# Apply configs
kubectl apply -f "$PEER_CONFIG_FILE"
kubectl apply -f "$BGP_CONFIG_FILE"
kubectl apply -f "$LB_POOL_FILE"
kubectl apply -f "$LB_ADVERTISE_FILE"
kubectl apply -f "$LB_SERVICE_FILE"

echo "🎉 Cluster2 with Cilium $CILIUM_VERSION + BGP + DualStack LB IPAM is fully ready."

