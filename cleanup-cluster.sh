#!/bin/bash
set -euo pipefail

# Identify the currently running cluster name from k3d
echo "🔍 Detecting running k3d cluster..."
CLUSTER_NAME=$(k3d cluster list -o json | jq -r '.[0].name' 2>/dev/null || echo "")

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "❌ No active k3d cluster found. Exiting."
  exit 1
fi

echo "📛 Detected active cluster: $CLUSTER_NAME"

# Match cluster directory
CLUSTER_DIR=""
COMPOSE_FILE=""
for dir in ./cluster*/; do
  [[ -f "$dir/cluster.env" ]] || continue
  if grep -q "^CLUSTER_NAME=\"$CLUSTER_NAME\"$" "$dir/cluster.env"; then
    CLUSTER_DIR="$dir"
    [[ -f "$CLUSTER_DIR/docker-compose.yml" ]] && COMPOSE_FILE="$CLUSTER_DIR/docker-compose.yml"
    break
  fi
done

if [[ -z "$CLUSTER_DIR" ]]; then
  echo "❌ Could not locate directory for cluster: $CLUSTER_NAME"
  exit 1
fi

echo "📍 Cluster matched in directory: $CLUSTER_DIR"

read -p "⚠️  Proceed with cleanup of cluster '$CLUSTER_NAME'? (y/n): " yn
case $yn in
  [yY]) echo "🧹 Cleaning up $CLUSTER_NAME...";;
  [nN]) echo "❌ Cancelled."; exit 0;;
  *) echo "❌ Invalid input."; exit 1;;
esac

echo "🔍 Uninstalling Cilium (if present)..."
helm uninstall cilium -n kube-system 2>/dev/null || true

echo "🧽 Removing BGP-related Cilium CRDs..."
kubectl delete ciliumloadbalancerippool --all --ignore-not-found || true
kubectl delete ciliumbgpadvertisement --all --ignore-not-found || true
kubectl delete ciliumbgpclusterconfig --all --ignore-not-found || true
kubectl delete ciliumbgppeerconfig --all --ignore-not-found || true

echo "🗑️ Deleting k3d cluster '$CLUSTER_NAME'..."
k3d cluster delete "$CLUSTER_NAME"

KUBECONFIG_FILE="$HOME/.kube/k3d-${CLUSTER_NAME}.yaml"
[[ -f "$KUBECONFIG_FILE" ]] && rm -f "$KUBECONFIG_FILE"

K3D_NET="k3d-net"
echo "🔌 Checking for Docker network '$K3D_NET'..."
if docker network inspect "$K3D_NET" &>/dev/null; then
  echo "📦 Removing containers from $K3D_NET..."
  CONTAINERS=$(docker network inspect "$K3D_NET" -f '{{range .Containers}}{{.Name}} {{end}}')
  [[ -n "$CONTAINERS" ]] && docker rm -f $CONTAINERS || true
  echo "🧯 Removing network..."
  docker network rm "$K3D_NET"
else
  echo "ℹ️ Network '$K3D_NET' not found."
fi

echo
read -p "🛑 Stop FRR router as well? (y/n): " cleanup_frr
if [[ "$cleanup_frr" =~ ^[yY]$ ]]; then
  if [[ -n "$COMPOSE_FILE" ]]; then
    echo "📦 Bringing down FRR using docker-compose..."
    docker compose -f "$COMPOSE_FILE" down || true
  else
    echo "⚠️  No compose file found in $CLUSTER_DIR."
  fi
else
  echo "ℹ️  Skipping FRR shutdown."
fi

echo
echo "✅ Cleanup complete for $CLUSTER_NAME."

