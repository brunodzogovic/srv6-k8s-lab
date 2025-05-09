#!/bin/bash

set -e

echo "Preparing node for deployment..."
echo

# Enable IPv6 forwarding and Segment Routing
echo "Configuring sysctl for SRv6 support..."
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.all.seg6_enabled=1
sysctl -w net.ipv6.conf.default.seg6_enabled=1
sysctl -w net.ipv6.conf.all.seg6_require_hmac=0

echo
echo "Checking and installing dependencies..."

# Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found! Installing..."
    apt-get update
    apt-get install -y \
        ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "✅ Docker installed"
else
    echo "✅ Docker is already installed"
fi

# Docker Compose
if ! docker compose version &> /dev/null; then
    echo "Docker Compose plugin not found, installing..."
    apt-get install -y docker-compose-plugin
else
    echo "✅ Docker Compose is already installed"
fi

# Helm
if ! command -v helm &> /dev/null; then
    echo "Helm not found! Installing..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ Helm installed"
else
    echo "✅ Helm already installed"
fi

############################################
#### Select cluster and tool versions   ####
############################################

echo
echo "Select your cluster:"
echo "1) Cluster 1"
echo "2) Cluster 2"
read -p "Enter your choice (1 or 2): " cluster_choice

device_hostname=$(hostname)

if [[ "$cluster_choice" == "1" ]]; then
    ENV_FILE="./cluster1/cluster.env"
    CONF_FILE="./cluster1/routers/frr1.conf"
    COMPOSE_FILE="./cluster1/docker-compose.yml"
elif [[ "$cluster_choice" == "2" ]]; then
    ENV_FILE="./cluster2/cluster.env"
    CONF_FILE="./cluster2/routers/frr2.conf"
    COMPOSE_FILE="./cluster2/docker-compose.yml"
else
    echo "❌ Invalid cluster choice."
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ ERROR: $ENV_FILE not found."
    exit 1
fi

# ===== Select Cilium Version =====
echo
echo "🔢 Select Cilium version:"
echo "1) Enter a specific version"
echo "2) Automatically detect latest stable"
read -p "Your choice: " cilium_version_choice

if [[ "$cilium_version_choice" == "1" ]]; then
    read -p "Enter desired Cilium version (e.g., 1.16.9): " CILIUM_VERSION
else
    echo "🔍 Fetching latest stable Cilium version..."
    CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/main/stable.txt)
    echo "✅ Using Cilium version: $CILIUM_VERSION"
fi

# ===== Select k3s Version =====
echo
echo "🔢 Select k3s version:"
echo "1) Enter a specific version (e.g., v1.31.7+k3s1)"
echo "2) Automatically detect latest stable"
read -p "Your choice: " k3s_version_choice

if [[ "$k3s_version_choice" == "1" ]]; then
    read -p "Enter desired k3s version (e.g., v1.31.7+k3s1): " K3S_VERSION
else
    echo "🔍 Fetching latest stable k3s version..."
    K3S_VERSION=$(curl -s https://raw.githubusercontent.com/k3s-io/k3s/refs/heads/master/channel.yaml | grep "latest:" | awk '{print $2}')
    echo "✅ Using k3s version: $K3S_VERSION"
fi

# ===== Inject Versions into ENV File =====
# Cilium version
if grep -q '^CILIUM_VERSION=' "$ENV_FILE"; then
    sed -i "s/^CILIUM_VERSION=.*/CILIUM_VERSION=${CILIUM_VERSION}/" "$ENV_FILE"
else
    echo "CILIUM_VERSION=${CILIUM_VERSION}" >> "$ENV_FILE"
fi

# k3s version
if grep -q '^K3S_VERSION=' "$ENV_FILE"; then
    sed -i "s/^K3S_VERSION=.*/K3S_VERSION=${K3S_VERSION}/" "$ENV_FILE"
else
    echo "K3S_VERSION=${K3S_VERSION}" >> "$ENV_FILE"
fi

# Load full env
source "$ENV_FILE"

# ===== Install Cilium CLI if needed =====
CURRENT_CLI_VERSION=$(cilium version 2>/dev/null | grep -oP 'Client: v\K[0-9.]+')
if [[ "$CURRENT_CLI_VERSION" == "$CILIUM_VERSION" ]]; then
    echo "✅ Cilium CLI version $CILIUM_VERSION already installed"
else
    echo "Installing Cilium CLI version $CILIUM_VERSION..."
    curl -L --fail --retry 5 --retry-connrefused --connect-timeout 5 \
        "https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_VERSION}/cilium-linux-amd64.tar.gz" \
        | tar xzvf - -C /usr/local/bin
    chmod +x /usr/local/bin/cilium
    echo "✅ Cilium CLI $CILIUM_VERSION installed"
fi

# ===== Update FRR Config =====
if [[ -f "$CONF_FILE" ]]; then
    echo "🔧 Updating IPs in $CONF_FILE..."

    sed -i "s|^\s*ipv6 address .*| ipv6 address ${LOCAL_IPV6}|" "$CONF_FILE"
    sed -i "s|^\s*bgp router-id .*| bgp router-id ${LOCAL_IPV4}|" "$CONF_FILE"

    if ! grep -q "neighbor CILIUM remote-as ${LOCAL_ASN}" "$CONF_FILE"; then
      sed -i "/neighbor CILIUM peer-group/a \ neighbor CILIUM remote-as ${LOCAL_ASN}" "$CONF_FILE"
    fi

    if ! grep -q "neighbor ${PEER_IPV4} remote-as ${PEER_ASN}" "$CONF_FILE"; then
      sed -i "/router bgp/a \ neighbor ${PEER_IPV4} remote-as ${PEER_ASN}" "$CONF_FILE"
    fi

    if grep -q "address-family ipv6 unicast" "$CONF_FILE" && \
       ! grep -q "neighbor ${PEER_IPV4} activate" "$CONF_FILE"; then
      sed -i "/address-family ipv6 unicast/a \  neighbor ${PEER_IPV4} activate" "$CONF_FILE"
    fi

    sed -i "s|^\s*network .*|  network ${ADVERTISED_IPV6}|" "$CONF_FILE"
    sed -i "s|^\s*sid .*|   sid ${STATIC_SID} locator ${LOCATOR_NAME} behavior ${SID_BEHAVIOR}|" "$CONF_FILE"
    sed -i "s|^\s*prefix .*|    prefix ${LOCATOR_PREFIX} block-len 40 node-len 24 func-bits 16|" "$CONF_FILE"

    echo "✅ BGP and SRv6 settings updated"
else
    echo "❌ ERROR: Could not find config file: $CONF_FILE"
    exit 1
fi

echo "🔧 Setting hostname in $CONF_FILE to '${device_hostname}'..."
sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CONF_FILE"
echo "✅ Hostname updated"

# BGP listen ranges
sed -i '/^\s*bgp listen range .* peer-group CILIUM/d' "$CONF_FILE"
[[ ! $(grep "bgp listen range ${LB_POOL_V4}" "$CONF_FILE") ]] && sed -i "/neighbor CILIUM peer-group/a \ bgp listen range ${LB_POOL_V4} peer-group CILIUM" "$CONF_FILE"
[[ ! $(grep "bgp listen range ${LB_POOL_V6}" "$CONF_FILE") ]] && sed -i "/neighbor CILIUM peer-group/a \ bgp listen range ${LB_POOL_V6} peer-group CILIUM" "$CONF_FILE"
echo "✅ BGP listen ranges updated"

echo "🚀 Starting FRR using Docker Compose..."
docker compose -f "$COMPOSE_FILE" up -d

echo
echo "✅ Node preparation complete"

