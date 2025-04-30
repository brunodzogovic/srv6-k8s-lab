#!/bin/bash

set -e

echo
echo "🚀 Cluster Initialization"
echo "========================="
echo "Choose which cluster to initialize:"
echo "1) Cluster 1"
echo "2) Cluster 2"
echo

read -rp "Enter your choice (1 or 2): " cluster_choice

case "$cluster_choice" in
  1)
    start_script="./cluster1/setup-cluster1.sh"
    ;;
  2)
    start_script="./cluster2/setup-cluster2.sh"
    ;;
  *)
    echo "❌ Invalid selection. Please enter 1 or 2."
    exit 1
    ;;
esac

# Check if the setup script exists
if [[ ! -f "$start_script" ]]; then
  echo "❌ ERROR: Setup script not found at $start_script"
  exit 1
fi

echo
echo "📦 Running $start_script ..."
bash "$start_script"
