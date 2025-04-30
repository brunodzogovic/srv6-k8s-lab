#!/bin/bash

set -e

echo "🔧 Preparing node for deployment..."
echo

# Enable IPv6 forwarding and Segment Routing
echo "⚙️  Configuring sysctl for SRv6 support..."
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.all.seg6_enabled=1
sysctl -w net.ipv6.conf.default.seg6_enabled=1
sysctl -w net.ipv6.conf.all.seg6_require_hmac=0

echo
echo "📌 Choose your cluster:"
echo "1) Cluster 1"
echo "2) Cluster 2"
read -rp "Enter your choice (1 or 2): " cluster_choice

# Determine cluster-specific paths
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

# Load environment variables
if [[ ! -f "$ENV_FILE" ]]; then
    echo "❌ Env file not found: $ENV_FILE"
    exit 1
fi
echo "📄 Loading environment variables from $ENV_FILE"
# shellcheck source=/dev/null
source "$ENV_FILE"

# Display loaded values for confirmation
echo
echo "📋 Loaded settings:"
echo "  LOCAL_IPV6:       $LOCAL_IPV6"
echo "  LOCAL_IPV4:       $LOCAL_IPV4"
echo "  PEER_IPV4:        $PEER_IPV4"
echo "  ADVERTISED_IPV6:  $ADVERTISED_IPV6"
echo "  LOCAL_ASN:        $LOCAL_ASN"
echo "  PEER_ASN:         $PEER_ASN"

read -rp "Are these values correct? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ Aborting."
    exit 1
fi

# Inject hostname
device_hostname=$(hostname)
echo "🖥️  Updating hostname in FRR config to: $device_hostname"
sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CONF_FILE"

# Update IPv6 address
sed -i "s|^\s*ipv6 address .*| ipv6 address ${LOCAL_IPV6}|" "$CONF_FILE"

# Update BGP router ID
sed -i "s|^\s*bgp router-id .*| bgp router-id ${LOCAL_IPV4}|" "$CONF_FILE"

# Update BGP ASN & Peer
sed -i "s|^\s*router bgp .*|router bgp ${LOCAL_ASN}|" "$CONF_FILE"
sed -i "s|^\s*neighbor .* remote-as .*| neighbor ${PEER_IPV4} remote-as ${PEER_ASN}|" "$CONF_FILE"
sed -i "s|^\s*neighbor .* activate| neighbor ${PEER_IPV4} activate|" "$CONF_FILE"

# Update advertised IPv6 network
sed -i "s|^\s*network .*|  network ${ADVERTISED_IPV6}|" "$CONF_FILE"

echo "✅ FRR config updated successfully."

# Start Docker Compose
echo "🐳 Launching FRR container using Docker Compose..."
docker compose -f "$COMPOSE_FILE" up -d

echo "✅ Node preparation complete."
