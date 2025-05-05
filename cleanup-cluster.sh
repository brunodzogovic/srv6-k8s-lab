#!/bin/bash

set -e

echo "🧹 Starting K3s-based cluster cleanup..."

# Uninstall Cilium if installed
if helm list -n kube-system 2>/dev/null | grep -q cilium; then
  echo "🗑️  Uninstalling Cilium via Helm..."
  helm uninstall cilium -n kube-system || true
else
  echo "ℹ️  Cilium not found or already uninstalled."
fi

# Uninstall K3s if installed
if [ -f "/usr/local/bin/k3s-uninstall.sh" ]; then
  echo "🗑️  Uninstalling K3s..."
  /usr/local/bin/k3s-uninstall.sh || true
else
  echo "⚠️  K3s uninstall script not found. Is K3s actually installed?"
fi

echo "✅ K3s cleanup complete."

