#!/bin/bash

# Install Cilium with Cluster-Pool IPAM
helm install cilium cilium/cilium --version 1.15.2 \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=cluster2 \
  --set cluster.id=2 \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true 
#  --set ipv4.enabled=false \
#  --set tunnel=disabled \
#  --set autoDirectNodeRoutes=true \
#  --set ipv6NativeRoutingCIDR="2001:db8:2::/64" \
#  --set kubeProxyReplacement=partial \
#  --set nodePort.enabled=true \
#  --set hostServices.enabled=false

