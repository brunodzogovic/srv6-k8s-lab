#!/bin/bash
helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version "v1.17.3"   --namespace kube-system --create-namespace   --set installCRDs=true   --set ipam.mode=cluster-pool   --set kubeProxyReplacement=true   --set cluster.name=srv6-cluster   --set cluster.id=1   --set operator.replicas=1   --set cleanCiliumState=true   --set cleanCiliumBpfState=true   --set bgpControlPlane.enabled=true   --set ipv4.enabled=true   --set ipam.operator.clusterPoolIPv4PodCIDRList="{10.42.0.0/16}"   --set service.cidr=10.96.0.0/12   --set ipv4NativeRoutingCIDR=10.42.0.0/16   --set routingMode=native   --set autoDirectNodeRoutes=true
