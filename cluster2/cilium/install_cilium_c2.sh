#!/bin/bash
# Install Cilium on cluster2
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.13.3 \
  --namespace kube-system --create-namespace \
  --set cluster.name=cluster1 --set cluster.id=2 :contentReference[oaicite:15]{index=15}
  --set ipv6.enabled=true \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set kubeProxyReplacement=partial \
  --set nodePort.enabled=true --set hostServices.enabled=false
