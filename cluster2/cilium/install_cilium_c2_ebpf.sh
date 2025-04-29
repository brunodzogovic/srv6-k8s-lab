#!/bin/bash
set -e

# Install Cilium with full eBPF, XDP acceleration, kube-proxy replacement, no tunneling

helm repo add cilium https://helm.cilium.io/ || true
helm repo update

helm install cilium cilium/cilium --version 1.15.2 \
  --namespace kube-system --create-namespace \
  --set ipam.mode=cluster-pool \
  --set cluster.name=cluster2 \
  --set cluster.id=2 \
  --set bgpControlPlane.enabled=true \
  --set ipv6.enabled=true \
  --set ipv4.enabled=false \
  --set ipv6NativeRoutingCIDR="2001:db8:2::/64" \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set kubeProxyReplacement=strict \
  --set k8sServiceHost="127.0.0.1" \
  --set k8sServicePort=6443 \
  --set xdp.enabled=true \
  --set xdp.mode=native \
  --set bpf.masquerade=true \
  --set enableXTSocketFallback=false \
  --set enableXdpLoadBalancer=true

