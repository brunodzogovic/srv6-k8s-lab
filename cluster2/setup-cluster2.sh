#!/bin/bash
set -e

CLUSTER_NAME="cluster2"
CILIUM_INSTALL_SCRIPT="cluster2/cilium/install_cilium_c2.sh"
BGP_CONFIG_FILE="cluster2/cilium/cilium-bgp-clusterconfig.yaml"
PEER_CONFIG_FILE="cluster2/cilium/cilium-bgp-peerconfig.yaml"
LB_POOL_FILE="cluster2/cilium/lb-pool.yaml"
LB_ADVERTISE_FILE="cluster2/cilium/lb-advertisement.yaml"
LB_SERVICE_FILE="cluster2/cilium/lb-service.yaml"

# Load env vars
if [[ -f "cluster2/cluster.env" ]]; then
  source cluster2/cluster.env
else
  echo "❌ Missing cluster2/cluster.env. Aborting."
  exit 1
fi

echo "🚀 Installing K3s with no default CNI ..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb --disable-cloud-controller" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sleep 5

echo "📦 Installing Cilium via Helm..."
CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/refs/heads/main/stable.txt)

# Prepare Cilium Helm install script
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
  --set operator.replicas=1 \
  --set ipv4.enabled=true \
  --set ipv6.enabled=false \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{${POD_SUBNET_V4}}" \
  --set bgpControlPlane.enabled=true \
  --set ipv4.enabled=true \
  --set ipv6.enabled=false \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR=${POD_SUBNET_V4} \
  --set ipv6NativeRoutingCIDR=${POD_SUBNET_V6} \
  --set autoDirectNodeRoutes=true \
  --set loadBalancer.mode=ipip \
  --set bpf.masquerade=false
EOF

chmod +x "$CILIUM_INSTALL_SCRIPT"
bash "$CILIUM_INSTALL_SCRIPT"
echo "✅ Cilium installed."

# Wait for Cilium pods
kubectl -n kube-system rollout status daemonset/cilium --timeout=300s

# Generate BGP cluster config
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
    - name: peer-v4
      peerASN: ${LOCAL_ASN}
      peerAddress: ${LOCAL_IPV4}
      peerConfigRef:
        name: cilium-peer
    - name: peer-v6
      peerASN: ${LOCAL_ASN}
      peerAddress: ${LOCAL_FRR_IPV6}
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
  authSecretRef: bgp-auth-secret
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
    - afi: ipv6
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
EOF

# LoadBalancer pool definition
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
EOF

# Example LB service
#cat > "$LB_SERVICE_FILE" <<EOF
#apiVersion: v1
#kind: Service
#metadata:
#  name: test-lb-service
#  labels:
#    pool: ${CLUSTER_NAME}-pool
#    app: test-app
#    advertise: bgp
#spec:
#  selector:
#    app: test-app
#  ipFamilyPolicy: PreferDualStack
#  ipFamilies:
#    - IPv4
#    - IPv6
#  type: LoadBalancer
#  ports:
#    - name: http
#      port: 80
#      targetPort: 80
#EOF

# Apply everything
kubectl apply -f "$PEER_CONFIG_FILE"
kubectl apply -f "$BGP_CONFIG_FILE"
kubectl apply -f "$LB_POOL_FILE"
kubectl apply -f "$LB_ADVERTISE_FILE"
kubectl apply -f "$LB_SERVICE_FILE"

echo "🎉 Cluster2 is up with K3s + Cilium ($CILIUM_VERSION) + DualStack BGP + LB IPAM."

