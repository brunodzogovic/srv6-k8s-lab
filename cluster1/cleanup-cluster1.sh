#!/bin/bash

set -e

CLUSTER_NAME="cluster1"
KIND_CONFIG="cluster1/kind-config/kind-cluster1.yaml"
CILIUM_RELEASE_NAME="cilium"
BGP_CLUSTER_CONFIG_NAME="cluster1-bgp-config"

# Color helpers
green() { echo -e "\033[32m$1\033[0m"; }
red() { echo -e "\033[31m$1\033[0m"; }

echo "\n🧹 Starting cleanup for Cluster 1..."

# Delete KinD cluster if exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo "⚠️  Deleting KinD cluster '$CLUSTER_NAME'..."
  kind delete cluster --name "$CLUSTER_NAME"
  green "✅ KinD cluster '$CLUSTER_NAME' deleted."
else
  red "❌ KinD cluster '$CLUSTER_NAME' not found. Skipping cluster deletion."
fi

# Note: We do NOT remove files or docker resources, as user may reuse them.

