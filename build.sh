#!/bin/bash
set -euo pipefail

echo ""
echo "=== [INFO] Starting FRR image build process ==="
echo ""

# --- Step 1: Pull latest stable FRR release tag from GitHub ---
echo "[INFO] Fetching latest stable FRR release tag from GitHub..."

LATEST_TAG=$(curl -s https://api.github.com/repos/FRRouting/frr/tags \
    | jq -r '.[].name' \
    | grep '^frr-[0-9]\+\.[0-9]\+\(\.[0-9]\+\)\?$' \
    | sort -Vr \
    | head -n1)

if [[ -z "$LATEST_TAG" ]]; then
    echo "[ERROR] Failed to fetch latest FRR tag!"
    exit 1
fi

FRR_VERSION=$(echo "$LATEST_TAG" | sed 's/^frr-//')

echo "[INFO] Latest stable detected FRR version: ${FRR_VERSION}"
echo ""

# --- Step 2: Update frr.conf files under routers/ for both clusters ---
for cluster in cluster1 cluster2; do
    FRR_CONF_PATH="${cluster}/routers/frr.conf"
    if [ -f "$FRR_CONF_PATH" ]; then
        echo "[INFO] Updating frr.conf for ${cluster} at ${FRR_CONF_PATH}..."
        sed -i "s/^frr version .*/frr version ${FRR_VERSION}/" "$FRR_CONF_PATH"
    else
        echo "[WARNING] No frr.conf found for ${cluster}, skipping."
    fi
done

echo ""

# --- Step 3: Update docker-compose.yml files for both clusters ---
for cluster in cluster1 cluster2; do
    COMPOSE_PATH="${cluster}/docker-compose.yml"
    if [ -f "$COMPOSE_PATH" ]; then
        echo "[INFO] Updating Docker image version in docker-compose.yml for ${cluster}..."
        sed -i "s|brunodzogovic/frr:[^ ]*|brunodzogovic/frr:${FRR_VERSION}|g" "$COMPOSE_PATH"
    else
        echo "[WARNING] No docker-compose.yml found for ${cluster}, skipping."
    fi
done

echo ""

# --- Step 4: Build the Docker image (ONLY version tag) ---
echo "[INFO] Building Docker image with tag brunodzogovic/frr:${FRR_VERSION} ..."
docker build --network=host -t brunodzogovic/frr:${FRR_VERSION} -f Dockerfile .

echo ""

# --- Step 5: Prune dangling images ---
echo "[INFO] Cleaning up dangling Docker images..."
docker image prune --force

echo ""
echo "=== [INFO] Build process complete! ==="
echo "[INFO] Built Docker image: brunodzogovic/frr:${FRR_VERSION}"
echo ""

