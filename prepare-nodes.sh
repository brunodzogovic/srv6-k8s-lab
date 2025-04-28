#!/bin/bash

# The script enables necessary forwarding on the machine and builds a fresh FRR Docker image 
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv6.conf.all.seg6_enabled=1
sysctl -w net.ipv6.conf.default.seg6_enabled=1
sysctl -w net.ipv6.conf.all.seg6_require_hmac=0

docker build --network=host -t brunodzogovic/frr:latest .
