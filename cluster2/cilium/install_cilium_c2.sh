#!/bin/bash
helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version "v1.17.3"   --namespace kube-system --create-namespace   --set installCRDs=true   --set ipam.mode=cluster-pool   --set cluster.name=cluster2   --set cluster.id=2   --set operator.replicas=1   --set ipv4.enabled=true   --set ipv6.enabled=false   --set cleanState.enabled=true   --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.42.0.0/16}"   --set bgpControlPlane.enabled=true   --set ipv4.enabled=true   --set ipv6.enabled=false   --set routingMode=native   --set ipv4NativeRoutingCIDR=10.42.0.0/16   --set ipv6NativeRoutingCIDR=2001:db8:2::/64   --set autoDirectNodeRoutes=true   --set loadBalancer.mode=ipip   --set bpf.masquerade=false
