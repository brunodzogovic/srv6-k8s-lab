#!/bin/bash
set -e


# Get current directory (inside cluster1/ or cluster2/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR_NAME="$(basename "$SCRIPT_DIR")"

# Absolute paths to resources
CILIUM_INSTALL_SCRIPT="$SCRIPT_DIR/cilium/install_cilium_${CLUSTER_DIR_NAME}.sh"
BGP_CONFIG_FILE="$SCRIPT_DIR/cilium/cilium-bgp-clusterconfig.yaml"
PEER_CONFIG_FILE="$SCRIPT_DIR/cilium/cilium-bgp-peerconfig.yaml"
LB_POOL_FILE="$SCRIPT_DIR/cilium/lb-pool.yaml"
LB_ADVERTISE_FILE="$SCRIPT_DIR/cilium/lb-advertisement.yaml"

echo "📂 SCRIPT_DIR: $SCRIPT_DIR"
echo "📁 CLUSTER_DIR_NAME: $CLUSTER_DIR_NAME"
echo "📄 BGP config path: $BGP_CONFIG_FILE"

# Load env vars
ENV_FILE="$SCRIPT_DIR/cluster.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo "❌ Missing cluster.env in $SCRIPT_DIR. Aborting."
  exit 1
fi

echo "🚧 Creating Docker network with IPv6 enabled ..."
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
  docker network create \
    --driver=bridge \
    --subnet=$IPV4_NETWORK \
    --gateway=$IPV4_GATEWAY \
    --ipv6 \
    --subnet=$IPV6_NETWORK \
    --gateway=$IPV6_GATEWAY \
    $NETWORK_NAME
else
  echo "ℹ️ Docker network '$NETWORK_NAME' already exists. Skipping creation."
fi

echo "🚀 Creating k3d cluster '$CLUSTER_NAME' ..."
k3d cluster create "$CLUSTER_NAME" \
  --network "$NETWORK_NAME" \
  --api-port "$K3D_API_PORT" \
  --servers 1 \
  --agents 1 \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=servicelb@server:0" \
  --k3s-arg "--disable-network-policy@server:0" \
  --k3s-arg "--flannel-backend=none@server:0" \
  --k3s-arg "--cluster-cidr=$CLUSTER_CIDR_V4@server:0" \
  --k3s-arg "--service-cidr=$SERVICE_SUBNET_V4@server:0"

echo "✅ k3d cluster created."

# Set kubeconfig for kubectl/helm
export KUBECONFIG=$(k3d kubeconfig write "$CLUSTER_NAME")
echo "✅ Kubeconfig set."

# Prepare Cilium Helm install
mkdir -p "$(dirname "$CILIUM_INSTALL_SCRIPT")"
cat > "$CILIUM_INSTALL_SCRIPT" <<EOF
#!/bin/bash
helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set kubeProxyReplacement=true \
  --set cluster.name=${CLUSTER_NAME} \
  --set cluster.id=${CLUSTER_ID} \
  --set operator.replicas=1 \
  --set cleanCiliumState=true \
  --set cleanCiliumBpfState=true \
  --set bgpControlPlane.enabled=true \
  --set ipv4.enabled=true \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{${POD_SUBNET_V4}}" \
  --set service.cidr=${SERVICE_SUBNET_V4} \
  --set ipv4NativeRoutingCIDR=${POD_SUBNET_V4} \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true
EOF

# Wait briefly for API to be accessible (not full readiness)
echo "⏳ Waiting for Kubernetes API to come up..."
for i in {1..30}; do
  if kubectl get nodes &>/dev/null; then
    break
  fi
  sleep 2
done

# Install Cilium BEFORE waiting for node readiness
echo "📦 Installing Cilium..."
chmod +x "$CILIUM_INSTALL_SCRIPT"
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for Cilium pods
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

# Final node readiness check after Cilium
echo "🧪 Verifying all nodes are Ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=180s

mkdir -p "$(dirname "$BGP_CONFIG_FILE")"
cat > "$BGP_CONFIG_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: ${CLUSTER_NAME}-bgp-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/hostname: k3d-${CLUSTER_NAME}-server-0
  bgpInstances:
  - name: instance-${LOCAL_ASN}
    localASN: ${LOCAL_ASN}
    peers:
    - name: peer-v4
      peerASN: ${LOCAL_ASN}
      peerAddress: ${LOCAL_IPV4}
      peerConfigRef:
        name: cilium-peer
EOF

# Peer config
cat > "$PEER_CONFIG_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: cilium-peer
spec:
  timers:
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  ebgpMultihop: 1
  gracefulRestart:
    enabled: true
    restartTimeSeconds: 15
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
EOF

# LoadBalancer pool definition
cat > "$LB_POOL_FILE" <<EOF
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: ${CLUSTER_NAME}-pool
spec:
  allowFirstLastIPs: "No"
  blocks:
  - cidr: "$LB_POOL_V4"
EOF

# Advertisement config
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
      selector:             # <-- select Services to advertise
        matchExpressions:
          - { key: bgp, operator: In, values: [ ${CLUSTER_NAME}-pool ] }
EOF

echo "📄 Dump of $BGP_CONFIG_FILE:"
cat "$BGP_CONFIG_FILE"

echo "📌 CLUSTER_NAME = $CLUSTER_NAME"
echo "📌 LOCAL_ASN = $LOCAL_ASN"
echo "📌 LOCAL_IPV4 = $LOCAL_IPV4"

# 🛑 Wait until the Cilium CRDs are registered before applying custom resources
echo "⏳ Waiting for Cilium CRDs to become available..."
for crd in ciliumloadbalancerippools.cilium.io \
           ciliumbgpadvertisements.cilium.io \
           ciliumbgpclusterconfigs.cilium.io \
           ciliumbgppeerconfigs.cilium.io; do
  for i in {1..30}; do
    if kubectl wait --for=condition=Established --timeout=60s crd/"$crd"; then
      echo "✅ CRD $crd is ready"
      break
    fi
    echo "   Waiting for $crd..."
    sleep 2
  done
done

# Apply resources

echo "🔍 BGP config:"
cat "$BGP_CONFIG_FILE"
echo
for yaml in "$PEER_CONFIG_FILE" "$BGP_CONFIG_FILE" "$LB_POOL_FILE" "$LB_ADVERTISE_FILE"; do
  echo "📄 Validating $yaml..."
  if [[ ! -s "$yaml" ]]; then
    echo "❌ ERROR: YAML file is missing or empty: $yaml"
    exit 1
  fi
  cat "$yaml"
  echo
  echo "🧪 Dry-run apply check for $yaml..."
  kubectl apply --dry-run=client -f "$yaml" -o yaml || {
    echo "❌ Invalid YAML: $yaml"
    exit 1
  }
done
echo "📎 Applying Cilium BGP + LB resources..."
kubectl apply -f $PEER_CONFIG_FILE
kubectl apply -f $BGP_CONFIG_FILE
kubectl apply -f $LB_POOL_FILE
kubectl apply -f $LB_ADVERTISE_FILE

echo "🎉 k3d Cluster '$CLUSTER_NAME' with Cilium + BGP is ready."
