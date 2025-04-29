#!/bin/bash

set -e

echo "📦 Installing Cilium into cluster2..."

# Add the Cilium Helm repo if not already
helm repo add cilium https://helm.cilium.io/ || true
helm repo update

# Install Cilium
helm install cilium cilium/cilium --version 1.15.2 \
  --namespace kube-system --create-namespace \
  --set ipam.mode=kubernetes \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true \
  --set ipv4.enabled=false \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set ipv6NativeRoutingCIDR="2001:db8:2::/64" \
  --set k8sServiceHost="kubernetes.default.svc" \
  --set k8sServicePort=443

echo "✅ Cilium installed successfully."

