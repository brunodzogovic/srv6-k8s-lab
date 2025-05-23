#!/bin/bash
set -euo pipefail

K3D_NET="k3d-net"
CLUSTER_NAME=""
CLUSTER_DIR=""
COMPOSE_FILE=""
KUBECONFIG_FILE=""

# 🔍 Detect running k3d cluster
if command -v k3d &>/dev/null; then
  echo "🔍 Detecting running k3d cluster..."
  CLUSTER_NAME=$(k3d cluster list -o json 2>/dev/null | jq -r '.[0].name' || echo "")
  if [[ -n "$CLUSTER_NAME" && "$CLUSTER_NAME" != "null" ]]; then
    echo "📛 Detected active cluster: $CLUSTER_NAME"

    for dir in ./cluster*/; do
      [[ -f "$dir/cluster.env" ]] || continue
      if grep -q "^CLUSTER_NAME=\"$CLUSTER_NAME\"$" "$dir/cluster.env"; then
        CLUSTER_DIR="$dir"
        [[ -f "$CLUSTER_DIR/docker-compose.yml" ]] && COMPOSE_FILE="$CLUSTER_DIR/docker-compose.yml"
        break
      fi
    done
    KUBECONFIG_FILE="$HOME/.kube/k3d-${CLUSTER_NAME}.yaml"
  else
    CLUSTER_NAME=""
  fi
else
  echo "⚠️  k3d not installed. Skipping cluster detection."
fi

# 🔍 Detect running FRR router via docker-compose
detect_frr() {
  for dir in ./cluster*/; do
    [[ -f "$dir/docker-compose.yml" ]] || continue
    if docker compose -f "$dir/docker-compose.yml" ps -q | grep -q .; then
      CLUSTER_DIR="$dir"
      COMPOSE_FILE="$dir/docker-compose.yml"
      return 0
    fi
  done
  return 1
}

# Exit only if neither k3d nor FRR is found
if [[ -z "$CLUSTER_NAME" ]] && ! detect_frr; then
  echo "✅ Nothing to clean: no running k3d cluster or FRR router detected."
  exit 0
fi

# 🧹 Prompt for full cleanup
echo
echo "📍 Cluster directory: ${CLUSTER_DIR:-N/A}"
echo "⚙️ Compose file: ${COMPOSE_FILE:-N/A}"

read -p "⚠️  Do you want to proceed with cleanup? (y/n): " yn
case $yn in
  [yY] ) echo "🧹 Proceeding with cleanup...";;
  [nN] ) echo "❌ Exiting."; exit 0;;
  * ) echo "❌ Invalid response."; exit 1;;
esac

# 🗑️ k3d Cluster Cleanup
if [[ -n "$CLUSTER_NAME" ]]; then
  echo "🔍 Attempting to uninstall Cilium..."
  helm uninstall cilium -n kube-system 2>/dev/null || true

  echo "🧽 Cleaning up Cilium BGP CRDs (ignore if missing)..."
  kubectl delete ciliumloadbalancerippool --all --ignore-not-found || true
  kubectl delete ciliumbgpadvertisement --all --ignore-not-found || true
  kubectl delete ciliumbgpclusterconfig --all --ignore-not-found || true
  kubectl delete ciliumbgppeerconfig --all --ignore-not-found || true

  echo "🗑️ Deleting k3d cluster..."
  k3d cluster delete "$CLUSTER_NAME" || true

  if [[ -f "$KUBECONFIG_FILE" ]]; then
    echo "🧽 Removing kubeconfig file: $KUBECONFIG_FILE"
    rm -f "$KUBECONFIG_FILE"
  fi
else
  echo "ℹ️ No k3d cluster to remove."
fi

# 🔌 Docker network cleanup
if docker network ls --format '{{.Name}}' | grep -q "^${K3D_NET}$"; then
  echo "📦 Removing containers attached to Docker network: $K3D_NET"
  CONTAINERS=$(docker network inspect "$K3D_NET" -f '{{range .Containers}}{{.Name}} {{end}}')
  if [[ -n "$CONTAINERS" ]]; then
    docker rm -f $CONTAINERS || true
  fi
  echo "🧯 Removing Docker network '$K3D_NET'..."
  docker network rm "$K3D_NET" || true
else
  echo "ℹ️ Docker network '$K3D_NET' not found."
fi

# 🛑 FRR router cleanup (optional)
if [[ -n "$COMPOSE_FILE" ]]; then
  echo
  read -p "🛑 Do you want to stop the FRR router? (y/n): " cleanup_frr
  if [[ "$cleanup_frr" =~ ^[yY]$ ]]; then
    echo "📦 Stopping FRR router using: $COMPOSE_FILE"
    docker compose -f "$COMPOSE_FILE" down || true
    echo "✅ FRR router stopped."
  else
    echo "ℹ️ Skipping FRR cleanup."
  fi
else
  echo "ℹ️ No active FRR router found."
fi

echo
echo "✅ Cleanup complete."

