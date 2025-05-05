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

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker not found! Installing Docker..."

    apt-get update
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key if not already added
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    fi

    # Add Docker's repository if not already present
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo "Docker installed successfully ✅"
else
    echo "Docker is already installed ✅"
fi

# Check if Docker Compose is installed (plugin-based)
if ! docker compose version &> /dev/null; then
    echo "Docker Compose not found! Installing Docker Compose plugin..."
    apt-get install -y docker-compose-plugin
    echo "Docker Compose plugin installed ✅"
else
    echo "Docker Compose is already installed ✅"
fi

# Check if 'helm' is installed
if ! command -v helm &> /dev/null; then
    echo "Helm not found! Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "Helm installed successfully ✅"
else
    echo "Helm already installed ✅"
fi

# Check if cilium CLI is installed
if ! command -v cilium &> /dev/null
then
    echo "Cilium CLI not found. Installing..."
    CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -L --fail --retry 5 --retry-connrefused --connect-timeout 5 \
      "https://github.com/cilium/cilium-cli/releases/download/${CLI_VERSION}/cilium-linux-amd64.tar.gz" \
      | tar xzvf - -C /usr/local/bin
    chmod +x /usr/local/bin/cilium
    echo "Cilium CLI installed ✅"
else
    echo "Cilium CLI is already installed ✅"
fi

echo
echo "Choose your cluster:"
echo "1) Cluster 1"
echo "2) Cluster 2"
read -p "Enter your choice (1 or 2): " cluster_choice

# Get the current hostname
device_hostname=$(hostname)

# Load env file
if [[ "$cluster_choice" == "1" ]]; then
    ENV_FILE="./cluster1/cluster.env"
    CONF_FILE="./cluster1/routers/frr1.conf"
    COMPOSE_FILE="./cluster1/docker-compose.yml"
elif [[ "$cluster_choice" == "2" ]]; then
    ENV_FILE="./cluster2/cluster.env"
    CONF_FILE="./cluster2/routers/frr2.conf"
    COMPOSE_FILE="./cluster2/docker-compose.yml"
else
    echo "Invalid choice. Exiting."
    exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ ERROR: $ENV_FILE not found."
    exit 1
fi

# Load variables from env file
source "$ENV_FILE"

if [[ -f "$CONF_FILE" ]]; then
    echo "Updating IPs inside $CONF_FILE..."
    sed -i "s|^\s*ipv6 address .*| ipv6 address ${LOCAL_IPV6}|" "$CONF_FILE"
    sed -i "s|^\s*bgp router-id .*| bgp router-id ${LOCAL_IPV4}|" "$CONF_FILE"
    sed -i -E "s|^\s*neighbor\s+[^ ]+\s+remote-as\s+.*| neighbor ${PEER_IPV4} remote-as ${PEER_ASN}|" "$CONF_FILE" 
    sed -i "s|^\s*neighbor .* activate| neighbor ${PEER_IPV4} activate|" "$CONF_FILE"
    sed -i "s|^\s*network .*|  network ${ADVERTISED_IPV6}|" "$CONF_FILE"
    sed -i "s|^\s*sid .*|   sid ${STATIC_SID} locator ${LOCATOR_NAME} behavior ${SID_BEHAVIOR}|" "$CONF_FILE"
    sed -i "s|^\s*prefix .*|    prefix ${LOCATOR_PREFIX} block-len 40 node-len 24 func-bits 16|" "$CONF_FILE"
    echo "✅ FRR configuration updated with new IPs."
else
    echo "❌ ERROR: Could not find config file: $CONF_FILE"
    exit 1
fi

# Update hostname in FRR config
echo "Adjusting hostname inside ${CONF_FILE} to '${device_hostname}'..."
sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CONF_FILE"
echo "Updated hostname inside FRR config!"

# Start FRR via Docker Compose
echo "Starting FRR using Docker Compose..."
docker compose -f "$COMPOSE_FILE" up -d

echo
echo "Node preparation complete ✅"

