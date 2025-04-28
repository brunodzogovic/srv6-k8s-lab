#!/bin/bash
set -e

# Clean leftover crashlogs
rm -rf /var/tmp/frr/*

# Optional: Lower FD limit to avoid warnings
ulimit -n 100000

# Start mgmtd daemon first
/usr/lib/frr/mgmtd -d

# Start FRR properly using frrinit
/usr/lib/frr/frrinit.sh start

# Keep container alive
tail -f /dev/null

