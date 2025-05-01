#!/bin/bash
source "$(dirname "$0")/../cluster.env"

helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version "$CILIUM_VERSION" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=${CLUSTER_NAME} \
  --set cluster.id=${CLUSTER_ID} \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true \
  --set ipv4.enabled=true \
  --set routingMode=native \
  --set ipv6NativeRoutingCIDR=${POD_SUBNET_V6} \
  --set ipv4NativeRoutingCIDR=${POD_SUBNET_V4} \
  --set enableIPv4Masquerade=true \
  --set enableIPMasqAgent=false \
  --set autoDirectNodeRoutes=true
