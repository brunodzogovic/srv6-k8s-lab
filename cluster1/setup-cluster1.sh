#!/bin/bash
set -e

CLUSTER_NAME="cluster1"
CILIUM_INSTALL_SCRIPT="cluster1/cilium/install_cilium_c1.sh"
BGP_CONFIG_FILE="cluster1/cilium/cilium-bgp-clusterconfig.yaml"
PEER_CONFIG_FILE="cluster1/cilium/cilium-bgp-peerconfig.yaml"
LB_POOL_FILE="cluster1/cilium/lb-pool.yaml"
LB_ADVERTISE_FILE="cluster1/cilium/lb-advertisement.yaml"
LB_SERVICE_FILE="cluster1/cilium/lb-service.yaml"

# Load env vars
if [[ -f "cluster1/cluster.env" ]]; then
  source cluster1/cluster.env
elif [[ -f "cluster.env" ]]; then
  source cluster.env
else
  echo "❌ Missing cluster1/cluster.env. Aborting."
  exit 1
fi

echo "🚀 Installing K3s with no default CNI ..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
--node-ip=$LOCAL_IPV4 \
--advertise-address=$LOCAL_IPV4 \
--cluster-cidr=$CLUSTER_CIDR_V4 \
--service-cidr=$SERVICE_SUBNET_V4 \
--flannel-backend=none \
--disable-network-policy \
--disable=traefik \
--disable=servicelb \
--disable-cloud-controller" sh -

# Export kubeconfig to default location for kubectl/helm/cilium
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
echo "✅ Kubeconfig set at ~/.kube/config"

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
  --set k8sServiceHost=${LOCAL_IPV4} \
  --set k8sServicePort=6443 \
  --set operator.replicas=1 \
  --set cleanCiliumState=true \
  --set cleanCiliumBpfState=true \
  --set ipam.operator.clusterPoolIPv6PodCIDRList="{${POD_SUBNET_V6}}" \
  --set bgpControlPlane.enabled=true \
  --set ipv4.enabled=true \
  --set ipam.operator.clusterPoolIPv4PodCIDRList="{${POD_SUBNET_V4}}" \
  --set service.cidr=${SERVICE_SUBNET_V4} \
  --set ipv4NativeRoutingCIDR=${POD_SUBNET_V4} \
  --set ipv4.enabled=false \
  --set enableIPv4Masquerade=false \
  --set ipv6.enabled=true \
  --set routingMode=native \
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
      peerAddress: ${LOCAL_FRR_IPV4}
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

# Apply everything
kubectl apply -f "$PEER_CONFIG_FILE"
kubectl apply -f "$BGP_CONFIG_FILE"
kubectl apply -f "$LB_POOL_FILE"
kubectl apply -f "$LB_ADVERTISE_FILE"

echo "🎉 Cluster2 is up with K3s + Cilium ($CILIUM_VERSION) + DualStack BGP + LB IPAM."
