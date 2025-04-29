#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG="kind-config/kind-cluster2.yaml"
BGP_POLICY_FILE="bgp-peering-policy.yaml"

echo "🧹 Starting cleanup for $CLUSTER_NAME..."

# Delete Kubernetes cluster
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo "Deleting KinD cluster: $CLUSTER_NAME..."
    kind delete cluster --name $CLUSTER_NAME
    echo "✅ KinD cluster deleted."
else
    echo "⚠️ No KinD cluster named '$CLUSTER_NAME' found. Skipping deletion."
fi

# Remove generated Kind config file if exists
if [ -f "$KIND_CONFIG" ]; then
    echo "Removing Kind config file: $KIND_CONFIG..."
    rm -f "$KIND_CONFIG"
    echo "✅ Kind config file removed."
fi

# Remove generated BGP peering policy file if exists
if [ -f "$BGP_POLICY_FILE" ]; then
    echo "Removing BGP peering policy file: $BGP_POLICY_FILE..."
    rm -f "$BGP_POLICY_FILE"
    echo "✅ BGP peering policy file removed."
fi

echo "🎉 Cleanup complete for $CLUSTER_NAME."

