#!/bin/bash

set -e

CLUSTER_NAME="cluster2"

# Color helpers
green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }

echo "\nStarting cluster cleanup..."

# Check if KinD cluster exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Deleting KinD cluster '$CLUSTER_NAME'..."
  kind delete cluster --name "$CLUSTER_NAME"
  green "✅ KinD cluster '$CLUSTER_NAME' deleted."
else
  red "❌ KinD cluster '$CLUSTER_NAME' not found. Skipping KinD cleanup."
fi

# Delete BGP config if exists (optional but clean)
echo "\nCleaning up Cilium BGP configs if any exist..."
if kubectl get ciliumbgpclusterconfigs.cilium.io cluster2-bgp-config &>/dev/null; then
  kubectl delete ciliumbgpclusterconfigs.cilium.io cluster2-bgp-config
  green "✅ Deleted Cilium BGP ClusterConfig."
else
  red "❌ No Cilium BGP ClusterConfig found."
fi

# Delete leftover cilium install if any (optional)
echo "\nCleaning up Cilium installation if any..."
if helm list -n kube-system | grep -q "cilium"; then
  helm uninstall cilium -n kube-system || true
  green "✅ Cilium helm release removed."
else
  red "❌ No Cilium helm release found."
fi

# Final reminder
echo "\n\U0001F389 Cleanup finished!\n"
echo "Note: Generated KinD config and BGP YAML files were preserved as per policy."
