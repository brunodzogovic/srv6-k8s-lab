#!/bin/bash
####### K3S INSTALL #######

export INSTALL_K3S_VERSION=v1.32.4+k3s1
export INSTALL_K3S_EXEC="\
  --node-ip=192.168.2.5,2001:db8:1::1 \
  --disable traefik \
  --disable servicelb \
  --disable-network-policy \
  --flannel-backend=none \
  --cluster-cidr=10.43.0.0/16,2001:db8:1:10::/112 \
  --kube-controller-manager-arg=node-cidr-mask-size-ipv6=112 \
  --service-cidr=10.96.0.0/12,2001:db8:1:11::/112"

curl -sfL https://get.k3s.io | sh -


#### CILIUM INSTALL #####

helm repo add cilium https://helm.cilium.io/ || true
helm repo update
helm install cilium cilium/cilium --version v1.17.3 \
  --namespace kube-system --create-namespace \
  --set installCRDs=true \
  --set ipam.mode=cluster-pool \
  --set kubeProxyReplacement=true \
  --set cluster.name=srv6-cluster \
  --set cluster.id=1 \
  --set operator.replicas=1 \
  --set cleanCiliumState=true \
  --set cleanCiliumBpfState=true \
  --set bgpControlPlane.enabled=true \
  --set ipv4.enabled=false \
  --set service.cidr=2001:db8:1:11::/112 \
  --set ipam.operator.clusterPoolIPv6PodCIDRList="2001:db8:1:13::/112" \
  --set ipv6NativeRoutingCIDR=2001:db8:1:13::/112 \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true
