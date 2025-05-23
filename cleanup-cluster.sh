#!/bin/bash
set -euo pipefail

# Detect active k3d cluster (by presence of kubeconfig)
echo "🔍 Detecting running k3d cluster..."
CLUSTER_DIR=""
COMPOSE_FILE=""
ENV_FILE=""
NETWORK_NAME=""

for dir in ./cluster*/; do
  if [[ -f "$dir/cluster.env" ]]; then
    source "$dir/cluster.env"
    CLUSTER_NAME_FROM_ENV="${CLUSTER_NAME:-}"
    if [[ -n "$CLUSTER_NAME_FROM_ENV" ]]; then
      if k3d cluster list | grep -q "$CLUSTER_NAME_FROM_ENV"; then
        CLUSTER_DIR="$dir"
        COMPOSE_FILE="$dir/docker-compose.yml"
        ENV_FILE="$dir/cluster.env"
        break
      fi
    fi
  fi
done

# If no active cluster found, check if any cluster.env exists anyway
if [[ -z "$CLUSTER_DIR" ]]; then
  for dir in ./cluster*/; do
    if [[ -f "$dir/cluster.env" ]]; then
      CLUSTER_DIR="$dir"
      COMPOSE_FILE="$dir/docker-compose.yml"
      ENV_FILE="$dir/cluster.env"
      source "$ENV_FILE"
      break
    fi
  done
fi

if [[ -z "${CLUSTER_DIR:-}" || -z "${ENV_FILE:-}" ]]; then
  echo "❌ No cluster.env or cluster directory found. Aborting."
  exit 1
fi

echo
echo "📍 Cluster directory: $CLUSTER_DIR"
echo "⚙️ Compose file: $COMPOSE_FILE"

read -p "⚠️  Do you want to proceed with cleanup? (y/n): " yn
case $yn in
  [yY]) echo "🧹 Proceeding with cleanup...";;
  *) echo "❌ Aborting."; exit 1;;
esac

# Uninstall Cilium if still installed
helm uninstall cilium -n kube-system 2>/dev/null || true

# Delete Cilium BGP resources
kubectl delete ciliumloadbalancerippool --all --ignore-not-found || true
kubectl delete ciliumbgpadvertisement --all --ignore-not-found || true
kubectl delete ciliumbgpclusterconfig --all --ignore-not-found || true
kubectl delete ciliumbgppeerconfig --all --ignore-not-found || true

# Delete k3d cluster
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "🗑️ Deleting k3d cluster '$CLUSTER_NAME'..."
  k3d cluster delete "$CLUSTER_NAME"
else
  echo "ℹ️ No k3d cluster to remove."
fi

# Remove kubeconfig
KUBECONFIG_FILE="$HOME/.kube/k3d-${CLUSTER_NAME}.yaml"
if [[ -f "$KUBECONFIG_FILE" ]]; then
  echo "🧽 Removing kubeconfig file: $KUBECONFIG_FILE"
  rm -f "$KUBECONFIG_FILE"
fi

# Remove Docker network
if [[ -n "${NETWORK_NAME:-}" ]]; then
  echo "🔌 Checking for Docker network '$NETWORK_NAME'..."
  if docker network inspect "$NETWORK_NAME" &>/dev/null; then
    echo "📦 Stopping containers on '$NETWORK_NAME'..."
    CONTAINERS=$(docker network inspect "$NETWORK_NAME" -f '{{range .Containers}}{{.Name}} {{end}}')
    if [[ -n "$CONTAINERS" ]]; then
      docker rm -f $CONTAINERS || true
    fi
    echo "🧯 Removing Docker network '$NETWORK_NAME'..."
    docker network rm "$NETWORK_NAME" || true
  else
    echo "ℹ️ Docker network '$NETWORK_NAME' not found."
  fi
fi

# Clean dangling images
echo "Removing dangling images"
docker system prune -a --volumes -f

# Ask if we want to stop FRR router
echo
read -p "🛑 Do you want to stop the FRR router? (y/n): " cleanup_frr
if [[ "$cleanup_frr" =~ ^[yY]$ ]]; then
  # Try to detect which FRR container is running
  FRR_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^frr[12]$' | head -n1 || true)
  if [[ -n "$FRR_CONTAINER" ]]; then
    echo "🔍 Found running FRR container: $FRR_CONTAINER"
    if [[ "$FRR_CONTAINER" == "frr1" ]]; then
      COMPOSE_FILE="./cluster1/docker-compose.yml"
      PROJECT_NAME="cluster1"
    elif [[ "$FRR_CONTAINER" == "frr2" ]]; then
      COMPOSE_FILE="./cluster2/docker-compose.yml"
      PROJECT_NAME="cluster2"
    else
      echo "⚠️ Unknown FRR container '$FRR_CONTAINER'. Skipping cleanup."
      exit 1
    fi

    echo "📦 Stopping $FRR_CONTAINER using docker-compose project: $PROJECT_NAME"
    docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" down --remove-orphans || true
  else
    echo "ℹ️ No running FRR container found."
  fi
else
  echo "ℹ️ Skipping FRR cleanup."
fi

echo
echo "✅ Cleanup complete."
