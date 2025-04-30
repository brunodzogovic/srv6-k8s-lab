#!/bin/bash

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

# Apply modifications
if [[ "$cluster_choice" == "1" ]]; then
    echo
    echo "You chose Cluster 1."
    CLUSTER1_CONF="./cluster1/routers/frr1.conf"

    echo "Adjusting hostname inside ${CLUSTER1_CONF} to '${device_hostname}'..."

    if [[ -f "$CLUSTER1_CONF" ]]; then
        sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CLUSTER1_CONF"
        echo "Updated hostname inside frr1.conf!"
    else
        echo "ERROR: $CLUSTER1_CONF not found!"
        exit 1
    fi

elif [[ "$cluster_choice" == "2" ]]; then
    echo
    echo "You chose Cluster 2."
    CLUSTER2_CONF="./cluster2/routers/frr2.conf"

    echo "Adjusting hostname inside ${CLUSTER2_CONF} to '${device_hostname}'..."

    if [[ -f "$CLUSTER2_CONF" ]]; then
        sed -i "s/^hostname .*/hostname ${device_hostname}/" "$CLUSTER2_CONF"
        echo "Updated hostname inside frr2.conf!"
    else
        echo "ERROR: $CLUSTER2_CONF not found!"
        exit 1
    fi

else
    echo "Invalid choice. Exiting."
    exit 1
fi

        echo
        echo "Would you like to update IP addresses and BGP settings in the config? (y/n)"
        read -rp "> " update_ip_choice

        if [[ "$update_ip_choice" == "y" ]]; then
            read -rp "Enter this node's IPv6 address (e.g., 2001:db8:2::1): " local_ipv6
            read -rp "Enter the BGP peer's IPv6 address (e.g., 2001:db8:1::1): " peer_ipv6
            read -rp "Enter this node's router-id (IPv4, e.g., 192.168.2.4): " local_router_id
            read -rp "Enter the BGP peer's router-id (IPv4, e.g., 192.168.2.3): " peer_router_id

            # Replace relevant lines in the config
            sed -i "s|ipv6 address .*| ipv6 address ${local_ipv6}/64|" "$CLUSTER2_CONF"
            sed -i "s|bgp router-id .*| bgp router-id ${local_router_id}|" "$CLUSTER2_CONF"
            sed -i "s|neighbor .* remote-as .*| neighbor ${peer_router_id} remote-as 65001|" "$CLUSTER2_CONF"
            sed -i "s|neighbor .* activate| neighbor ${peer_router_id} activate|" "$CLUSTER2_CONF"

            echo "✅ Updated IPv6 and BGP configuration."
        else
            echo "Skipping IP update."
        fi

echo
echo "Node preparation complete ✅"

