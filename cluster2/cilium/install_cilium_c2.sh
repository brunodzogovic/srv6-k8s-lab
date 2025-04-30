#!/bin/bash

# Install Cilium with Cluster-Pool IPAM
helm install cilium cilium/cilium --version "v1.17.3" \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set cluster.name=cluster2 \
  --set cluster.id=2 \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true
