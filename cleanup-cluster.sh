#!/bin/bash

set -e

echo "🧼 Cleaning up active Kubernetes cluster (but keeping FRR routing)..."

# Detect the active FRR container
frr_container=$(docker ps --format '{{.Names}}' | grep -E '^frr[12]$' || true)

if [[ -z "$frr_container" ]]; then
  echo "❌ No active FRR container found (frr1 or frr2). Cannot determine cluster context."
  exit 1
fi

if [[ "$frr_container" == "frr1" ]]; then
  echo "🔍 Detected FRR container: frr1 → cleaning up Cluster 1"
  ./cluster1/cleanup-cluster1.sh
elif [[ "$frr_container" == "frr2" ]]; then
  echo "🔍 Detected FRR container: frr2 → cleaning up Cluster 2"
  ./cluster2/cleanup-cluster2.sh
else
  echo "❌ Unrecognized FRR container: $frr_container"
  exit 1
fi

echo "✅ Cluster cleanup complete (FRR remains active)."
