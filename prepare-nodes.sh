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
if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi

# Docker Compose plugin
if ! docker compose version &>/dev/null; then
  echo "Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
fi

# Helm
if ! command -v helm &>/dev/null; then
  echo "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# kubectl
if ! command -v kubectl &>/dev/null; then
  echo "Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm kubectl
fi

# k3d
if ! command -v k3d &>/dev/null; then
  echo "Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Prompt for versions
echo
echo "🔢 Select Cilium version:"
echo "1) Enter manually"
echo "2) Fetch latest"
read -p "Your choice: " cilium_version_choice
if [[ "$cilium_version_choice" == "1" ]]; then
  read -p "Enter Cilium version (e.g., 1.16.9): " CILIUM_VERSION
else
  CILIUM_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium/main/stable.txt)
fi

echo
echo "🔢 Select Cilium CLI version:"
echo "1) Enter manually"
echo "2) Fetch latest"
read -p "Your choice: " cli_choice
if [[ "$cli_choice" == "1" ]]; then
  read -p "Enter Cilium CLI version (e.g., 0.15.20): " CILIUM_CLI_VERSION
else
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/refs/heads/main/stable.txt)
fi

echo
echo "🔢 Select k3s version:"
echo "1) Enter manually"
echo "2) Fetch latest"
read -p "Your choice: " k3s_version_choice
if [[ "$k3s_version_choice" == "1" ]]; then
  read -p "Enter k3s version: " K3S_VERSION
else
  K3S_VERSION=$(curl -s https://raw.githubusercontent.com/k3s-io/k3s/refs/heads/master/channel.yaml | grep "latest:" | awk '{print $2}')
fi

echo
echo "Choose your cluster:"
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
  echo "❌ Invalid cluster choice. Exiting."
  exit 1
fi

# Validate
[[ -f "$ENV_FILE" ]] || { echo "❌ $ENV_FILE not found."; exit 1; }

# Load variables
source "$ENV_FILE"

# Update versions in env
grep -q '^CILIUM_VERSION=' "$ENV_FILE" && sed -i "s/^CILIUM_VERSION=.*/CILIUM_VERSION=${CILIUM_VERSION}/" "$ENV_FILE" || echo "CILIUM_VERSION=${CILIUM_VERSION}" >> "$ENV_FILE"
grep -q '^CILIUM_CLI_VERSION=' "$ENV_FILE" && sed -i "s/^CILIUM_CLI_VERSION=.*/CILIUM_CLI_VERSION=${CILIUM_CLI_VERSION}/" "$ENV_FILE" || echo "CILIUM_CLI_VERSION=${CILIUM_CLI_VERSION}" >> "$ENV_FILE"

# Install Cilium CLI
CURRENT_CLI_VERSION=$(cilium version 2>/dev/null | grep -oP 'Client: v\K[0-9.]+' || true)
if [[ "$CURRENT_CLI_VERSION" != "$CILIUM_CLI_VERSION" ]]; then
  echo "Installing Cilium CLI version $CILIUM_CLI_VERSION..."
  curl -L --fail --retry 5 --retry-connrefused --connect-timeout 5 \
    "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz" \
    | tar xzvf - -C /usr/local/bin
  chmod +x /usr/local/bin/cilium
fi

##################################################################
###### EDIT THIS PART TO CUSTOMIZE THE FRR BGP CONFIGURATION #####
##################################################################

echo "🔧 Generating FRR config at $CONF_FILE..."

cat > "$CONF_FILE" <<EOF
frr version 10.3
frr defaults traditional
hostname ${device_hostname}
log syslog informational
!
interface eth0
 ip address ${LOCAL_IPV4}/24
 ipv6 address ${LOCAL_IPV6}
exit
!
ipv6 route ${PEER_IPV6}/${PEER_MASK} eth0
!
router bgp ${LOCAL_ASN}
 bgp router-id $ROUTER_ID
 no bgp ebgp-requires-policy
 neighbor CILIUM peer-group
 neighbor CILIUM remote-as ${LOCAL_ASN}
 neighbor ${PEER_IPV4} remote-as ${PEER_ASN}
 neighbor ${PEER_IPV6} remote-as ${PEER_ASN}
 neighbor ${PEER_IPV6} interface eth0
 bgp listen range ${LOCAL_IPV6} peer-group CILIUM
 bgp listen range ${ADVERTISED_IPV4} peer-group CILIUM
 bgp listen range ${IPV4_NETWORK} peer-group CILIUM
 bgp listen range ${LB_POOL_V4} peer-group CILIUM
 redistribute connected
 redistribute static
 !
 address-family ipv4 unicast
  network ${ADVERTISED_IPV4}
  network ${LB_POOL_V4}
  neighbor ${PEER_IPV4} activate
 exit-address-family
 !
 address-family ipv6 unicast
  network ${ADVERTISED_IPV6}
  neighbor ${PEER_IPV6} activate
  neighbor CILIUM activate
 exit-address-family
exit
!
segment-routing
 srv6
  static-sids
   sid ${STATIC_SID} locator ${LOCATOR_NAME} behavior ${SID_BEHAVIOR}
  exit
  !
 exit
 !
 srv6
  locators
   locator ${LOCATOR_NAME}
    prefix ${LOCATOR_PREFIX} block-len 40 node-len 24 func-bits 16
   exit
   !
  exit
  !
  formats
   format usid-f3216
   exit
   !
   format uncompressed-f4024
   exit
   !
  exit
  !
 exit
 !
exit
!
EOF

echo "✅ FRR config written"

echo "▶️ Starting FRR using Docker Compose..."
docker compose -f "$COMPOSE_FILE" up -d

echo "🚀 Node preparation complete"

