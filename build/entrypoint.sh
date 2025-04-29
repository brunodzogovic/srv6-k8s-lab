#!/bin/bash
set -e

# Clean leftover crash logs
rm -rf /var/tmp/frr/*

# Lower file descriptor limit (optional)
ulimit -n 100000

# Start mgmtd first (required for SRv6 config acceptance)
echo "[entrypoint] Starting mgmtd..."
/usr/lib/frr/mgmtd -d

# Start core daemons
echo "[entrypoint] Starting FRR daemons..."
/usr/lib/frr/frrinit.sh start

# Wait a few seconds for daemons to be fully ready
sleep 2

# Load configuration automatically via vtysh
echo "[entrypoint] Loading configuration file..."
vtysh -f /etc/frr/frr.conf

# Save configuration to FRR running database (optional)
vtysh -c 'write memory'

# Keep container alive
tail -f /dev/null
