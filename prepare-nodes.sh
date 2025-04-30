#!/bin/bash

echo "Preparing node for deployment..."
source ./cluster2/cluster.env
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

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

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

# Check if 'kind' is installed
if ! command -v kind &> /dev/null; then
    echo "KinD not found! Installing KinD..."
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
    chmod +x ./kind
    mv ./kind /usr/local/bin/kind
    echo "KinD installed successfully ✅"
else
    echo "KinD already installed ✅"
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

# Check if 'kubectl' is installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found! Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x ./kubectl
    mv ./kubectl /usr/local/bin/kubectl
    echo "kubectl installed successfully ✅"
else
    echo "kubectl already installed ✅"
fi

echo
echo "Choose your cluster:"
echo "1) Cluster 1"
echo "2) Cluster 2"
read -p "Enter your choice (1 or 2): " cluster_choice

# Get the current hostname
device_hostname=$(hostname)

echo
read -p "Enter local IPv6 address (e.g., 2001:db8:2::1/64): " LOCAL_IPV6
read -p "Enter local IPv4 address (e.g., 192.168.2.4): " LOCAL_IPV4
read -p "Enter peer IPv4 address (e.g., 192.168.2.3): " PEER_IPV4
read -p "Enter advertised IPv6 network (e.g., 2001:db8:2::/64): " ADVERTISED_IPV6

echo "You entered:"
echo "  Local IPv6: $LOCAL_IPV6"
echo "  Local IPv4 (router ID): $LOCAL_IPV4"
echo "  Peer IPv4: $PEER_IPV4"
echo "  Advertised IPv6 Network: $ADVERTISED_IPV6"

read -p "Are these correct? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ Aborting configuration."
    exit 1
fi

CONF_FILE=""
if [[ "$cluster_choice" == "1" ]]; then
    CONF_FILE="./cluster1/routers/frr1.conf"
elif [[ "$cluster_choice" == "2" ]]; then
    CONF_FILE="./cluster2/routers/frr2.conf"
fi

if [[ -f "$CONF_FILE" ]]; then
    echo "Updating IPs inside $CONF_FILE..."

    sed -i "s|^\s*ipv6 address .*| ipv6 address ${LOCAL_IPV6}|" "$CONF_FILE"
    sed -i "s|^\s*bgp router-id .*| bgp router-id ${LOCAL_IPV4}|" "$CONF_FILE"
    sed -i "s|^\s*neighbor .* remote-as| neighbor ${PEER_IPV4} remote-as|" "$CONF_FILE"
    sed -i "s|^\s*neighbor .* activate| neighbor ${PEER_IPV4} activate|" "$CONF_FILE"
    sed -i "s|^\s*network .*|  network ${ADVERTISED_IPV6}|" "$CONF_FILE"

    echo "✅ FRR configuration updated with new IPs."
else
    echo "❌ ERROR: Could not find config file: $CONF_FILE"
    exit 1
fi

# Apply modifications
if [[ "$cluster_choice" == "1" ]]; then
    echo
    echo "You chose Cluster 1."
    CLUSTER1_CONF="./cluster1/routers/frr1.conf"
    COMPOSE_FILE="./cluster1/docker-compose.yml"

    echo "Adjusting hostname inside ${CLUSTER1_CONF} to '${device_hostname}'..."

    if [[ -f "$CLUSTER1_CONF" ]]; then
        sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CLUSTER1_CONF"
        echo "Updated hostname inside frr1.conf!"
    else
        echo "ERROR: $CLUSTER1_CONF not found!"
        exit 1
    fi

    echo "Starting FRR using Docker Compose..."
    docker compose -f "$COMPOSE_FILE" up -d

elif [[ "$cluster_choice" == "2" ]]; then
    echo
    echo "You chose Cluster 2."
    CLUSTER2_CONF="./cluster2/routers/frr2.conf"
    COMPOSE_FILE="./cluster2/docker-compose.yml"

    echo "Adjusting hostname inside ${CLUSTER2_CONF} to '${device_hostname}'..."

    if [[ -f "$CLUSTER2_CONF" ]]; then
        sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CLUSTER2_CONF"
        echo "Updated hostname inside frr2.conf!"
    else
        echo "ERROR: $CLUSTER2_CONF not found!"
        exit 1
    fi

    echo "Starting FRR using Docker Compose..."
    docker-compose -f "$COMPOSE_FILE" up -d

else
    echo "Invalid choice. Exiting."
    exit 1
fi

echo
echo "Node preparation complete ✅"
