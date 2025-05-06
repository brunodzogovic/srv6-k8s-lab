#!/bin/bash
set -e

# Load environment to determine cluster
if [[ -f "cluster1/cluster.env" && -f "cluster2/cluster.env" ]]; then
  echo "Which cluster do you want to clean up?"
  select CLUSTER_NAME in "cluster1" "cluster2"; do
    [[ -n "$CLUSTER_NAME" ]] && break
  done
elif [[ -f "cluster1/cluster.env" ]]; then
  CLUSTER_NAME="cluster1"
elif [[ -f "cluster2/cluster.env" ]]; then
  CLUSTER_NAME="cluster2"
else
  echo "❌ Could not find any cluster.env files in cluster1/ or cluster2/"
  exit 1
fi

ENV_FILE="${CLUSTER_NAME}/cluster.env"
COMPOSE_FILE="${CLUSTER_NAME}/docker-compose.yml"

# Confirm cleanup
read -p "Do you want to proceed with $CLUSTER_NAME destruction? (y/n): " yn
case $yn in
  [yY] ) echo "🧹 Proceeding with cleanup of $CLUSTER_NAME...";;
  [nN] ) echo "❌ Exiting."; exit 0;;
  * ) echo "❌ Invalid response."; exit 1;;
esac

echo "📍 Cluster selected: $CLUSTER_NAME"
source "$ENV_FILE"

# Uninstall Cilium if installed
echo "🔍 Checking for Cilium installation..."
if helm list -n kube-system 2>/dev/null | grep -q cilium; then
  echo "🗑️  Uninstalling Cilium via Helm..."
  helm uninstall cilium -n kube-system || true
else
  echo "ℹ️  Cilium not found or already uninstalled."
fi

# Uninstall K3s
echo "🔍 Checking for K3s..."
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  echo "🗑️  Uninstalling K3s..."
  /usr/local/bin/k3s-uninstall.sh || true
else
  echo "⚠️  K3s uninstall script not found. Is K3s installed?"
fi

# Ask about FRR router
echo
read -p "🛑 Do you want to also stop the FRR router (via docker-compose)? (y/n): " cleanup_frr
if [[ "$cleanup_frr" =~ ^[yY]$ ]]; then
  if [[ -f "$COMPOSE_FILE" ]]; then
    echo "📦 Bringing down FRR router using: $COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" down || true
  else
    echo "⚠️  Could not find $COMPOSE_FILE"
  fi
else
  echo "ℹ️  Skipping FRR cleanup."
fi

echo
echo "✅ Cleanup complete for $CLUSTER_NAME."

