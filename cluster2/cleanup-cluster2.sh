#!/bin/bash

set -e

CLUSTER_NAME="cluster2"
KIND_CONFIG_FILE="./kind-config/kind-cluster2.yaml"

echo "Cleaning up KinD cluster: $CLUSTER_NAME..."

# Delete the kind cluster
kind delete cluster --name "$CLUSTER_NAME"

echo "KinD cluster $CLUSTER_NAME deleted ✅"

# Optionally clean Helm releases (if you want to reset Cilium manually too)
echo "Cleaning Helm releases..."
helm uninstall cilium --namespace kube-system || true

# Clean up Kubernetes leftovers (if any)
echo "Cleaning up Kubernetes configs..."
kubectl delete -f bgp-peering-policy.yaml --ignore-not-found=true || true

echo "Cleanup completed ✅"

# ⚡️ Important: DO NOT remove kind config file!
echo "Preserved $KIND_CONFIG_FILE for future deployments 🚀"

