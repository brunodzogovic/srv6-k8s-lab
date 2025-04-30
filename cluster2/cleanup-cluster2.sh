#!/bin/bash

set -e

CLUSTER_NAME="cluster2"

# Color helpers
green() { echo -e "\033[32m$1\033[0m"; }
red()   { echo -e "\033[31m$1\033[0m"; }

echo -e "\n🧼 Starting cleanup for KinD cluster: $CLUSTER_NAME\n"

# Step 1: Clean up Cilium BEFORE deleting cluster
echo "🔍 Cleaning up Cilium resources..."

if helm list -n kube-system | grep -q "cilium"; then
  echo "   Uninstalling Cilium Helm release..."
  helm uninstall cilium -n kube-system || true
  green "✅ Cilium Helm release removed."
else
  red "❌ No Cilium Helm release found."
fi

if kubectl get ciliumbgpclusterconfigs.cilium.io cluster2-bgp-config &>/dev/null; then
  echo "   Deleting CiliumBGPClusterConfig..."
  kubectl delete ciliumbgpclusterconfigs.cilium.io cluster2-bgp-config
  green "✅ Deleted BGP ClusterConfig."
else
  red "❌ No CiliumBGPClusterConfig found."
fi

if kubectl get ciliumbgppeerconfigs.cilium.io cilium-peer &>/dev/null; then
  echo "   Deleting CiliumBGPPeerConfig..."
  kubectl delete ciliumbgppeerconfigs.cilium.io cilium-peer
  green "✅ Deleted BGPPeerConfig."
else
  red "❌ No CiliumBGPPeerConfig found."
fi

# Step 2: Delete KinD cluster
echo -e "\n🗑️  Deleting KinD cluster '$CLUSTER_NAME'..."
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  kind delete cluster --name "$CLUSTER_NAME"
  green "✅ KinD cluster '$CLUSTER_NAME' deleted."
else
  red "❌ No KinD cluster named '$CLUSTER_NAME' was found."
fi

# Final message
echo -e "\n🎉 Cleanup complete."
green "🔒 Docker Compose (FRR) was NOT touched."
echo "📝 Any generated Kind configs and BGP YAMLs are preserved."
