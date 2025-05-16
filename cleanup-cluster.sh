#!/bin/bash
set -euo pipefail

CLUSTER_NAME="srv6-cluster"
K3D_NET="k3d-net"
COMPOSE_FILE=""

# 🔍 Locate cluster directory that defines this CLUSTER_NAME
for dir in ./cluster*/; do
  [[ -f "$dir/cluster.env" ]] || continue
  if grep -q "^CLUSTER_NAME=\"$CLUSTER_NAME\"$" "$dir/cluster.env"; then
    CLUSTER_DIR="$dir"
    if [[ -f "$CLUSTER_DIR/docker-compose.yml" ]]; then
      COMPOSE_FILE="$CLUSTER_DIR/docker-compose.yml"
    fi
    break
  fi
done

if [[ -z "${CLUSTER_DIR:-}" ]]; then
  echo "❌ Could not find a cluster directory that defines CLUSTER_NAME=\"$CLUSTER_NAME\""
  exit 1
fi

echo "📍 Cluster matched in directory: $CLUSTER_DIR"

read -p "⚠️  Do you want to proceed with $CLUSTER_NAME cleanup? (y/n): " yn
case $yn in
  [yY] ) echo "🧹 Proceeding with cleanup of $CLUSTER_NAME...";;
  [nN] ) echo "❌ Exiting."; exit 0;;
  * ) echo "❌ Invalid response."; exit 1;;
esac

echo "🔍 Attempting to uninstall Cilium (if present)..."
helm uninstall cilium -n kube-system 2>/dev/null || true

echo "🧽 Cleaning up Cilium BGP-related CRDs (ignore errors if missing)..."
kubectl delete ciliumloadbalancerippool --all --ignore-not-found || true
kubectl delete ciliumbgpadvertisement --all --ignore-not-found || true
kubectl delete ciliumbgpclusterconfig --all --ignore-not-found || true
kubectl delete ciliumbgppeerconfig --all --ignore-not-found || true

echo "🗑️ Deleting k3d cluster (if exists)..."
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  k3d cluster delete "$CLUSTER_NAME"
else
  echo "ℹ️ k3d cluster '$CLUSTER_NAME' not found."
fi

KUBECONFIG_FILE="$HOME/.kube/k3d-${CLUSTER_NAME}.yaml"
if [[ -f "$KUBECONFIG_FILE" ]]; then
  echo "🧽 Removing kubeconfig file: $KUBECONFIG_FILE"
  rm -f "$KUBECONFIG_FILE"
fi

echo "🔌 Checking for Docker network '$K3D_NET'..."
if docker network ls --format '{{.Name}}' | grep -q "^${K3D_NET}$"; then
  echo "📦 Stopping any containers still attached to $K3D_NET..."
  CONTAINERS=$(docker network inspect "$K3D_NET" -f '{{range .Containers}}{{.Name}} {{end}}')
  if [[ -n "$CONTAINERS" ]]; then
    docker rm -f $CONTAINERS || true
  fi

  echo "🧯 Removing Docker network '$K3D_NET'..."
  docker network rm "$K3D_NET" || true
else
  echo "ℹ️ Network '$K3D_NET' not found."
fi

echo
read -p "🛑 Do you want to also stop the FRR router (via docker-compose)? (y/n): " cleanup_frr
if [[ "$cleanup_frr" =~ ^[yY]$ ]]; then
  if [[ -n "$COMPOSE_FILE" ]]; then
    echo "📦 Bringing down FRR router using: $COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" down || true
  else
    echo "⚠️  Could not find a compose file for cluster '$CLUSTER_NAME', skipping FRR cleanup."
  fi
else
  echo "ℹ️  Skipping FRR cleanup."
fi

echo
echo "✅ Cleanup complete for $CLUSTER_NAME."

