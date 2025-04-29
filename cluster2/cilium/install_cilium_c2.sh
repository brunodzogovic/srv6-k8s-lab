#!/bin/bash

set -e

echo "📦 Installing Cilium into cluster2..."

# Add Helm repo if not added
helm repo add cilium https://helm.cilium.io/ || true
helm repo update

helm install cilium cilium/cilium --version 1.15.2 \
  --namespace kube-system --create-namespace \
  --set cluster.name=cluster2 \
  --set cluster.id=2 \
  --set ipv6.enabled=true \
  --set ipv4.enabled=false \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set kubeProxyReplacement=partial \
  --set nodePort.enabled=true \
  --set hostServices.enabled=false \
  --set bgpControlPlane.enabled=true \
  --set ipam.mode=kubernetes \
  --set k8sServiceHost="127.0.0.1" \
  --set k8sServicePort=6443

echo "✅ Cilium installed for cluster2 with BGP and IPv6"

