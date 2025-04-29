#!/bin/bash

set -e


CLUSTER_NAME="cluster2"

echo "🧹 Cleaning up cluster: $CLUSTER_NAME..."

# Delete only the Kind cluster
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  kind delete cluster --name "$CLUSTER_NAME"
  echo "✅ Cluster '$CLUSTER_NAME' deleted."
else
  echo "ℹ️ Cluster '$CLUSTER_NAME' does not exist. Nothing to do."
fi

# Optionally clean Helm releases (if you want to reset Cilium manually too)
echo "Cleaning Helm releases..."
helm uninstall cilium --namespace kube-system || true

echo "Cleanup completed ✅"

