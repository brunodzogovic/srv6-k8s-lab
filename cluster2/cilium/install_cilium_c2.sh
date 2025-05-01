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
