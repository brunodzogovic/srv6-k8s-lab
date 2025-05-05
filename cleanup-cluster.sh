#!/bin/bash

set -e

CLUSTER_NAME="cluster2"

# Delete the Helm release of Cilium
echo "🗑️  Uninstalling Cilium via Helm..."
helm uninstall cilium -n kube-system || true

# Uninstall K3s (if this was a standalone K3s node)
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  echo "🗑️  Uninstalling K3s..."
  /usr/local/bin/k3s-uninstall.sh
else
  echo "ℹ️  K3s uninstall script not found. You may need to uninstall K3s manually."
fi

echo "✅ Cleanup complete for ${CLUSTER_NAME}."

