#!/bin/bash

# Ensure sudo is installed
if [ ! -x "$(command -v sudo)" ]; then
    apt-get update
    apt-get install -y sudo
fi

# Ensure nftables is installed
if [ ! -x "$(command -v nft)" ]; then
    sudo apt-get update
    sudo apt-get install -y nftables
fi

# Define variables for interfaces, subnets, and ports
TABLE_NAME="wg_rules"               # Name of the nftables table
NETWORK_INTERFACE="enxb827eb7c4fab" # Network interface for masquerading (e.g., eth0)
VPN_PORT="51820"                    # VPN port (WireGuard)
DNS_PORT="53"                       # DNS port (both UDP and TCP)
IPv4_SUBNET="10.0.0.0/8"            # IPv4 subnet to be used for NAT
IPv6_SUBNET="fd00::/8"              # IPv6 subnet to be used for NAT

# Enable IP forwarding for both IPv4 and IPv6
sysctl -w net.ipv4.ip_forward=1          # Enable IPv4 forwarding
sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding

# Flush any existing rules to start fresh
nft flush ruleset

# Create nftables table and add chains
nft add table inet ${TABLE_NAME}

# INPUT chain - Allow incoming traffic
nft add chain inet ${TABLE_NAME} INPUT { type filter hook input priority filter \; policy accept \; }
nft add rule inet ${TABLE_NAME} INPUT ip protocol udp udp dport ${VPN_PORT} accept # Allow VPN traffic
nft add rule inet ${TABLE_NAME} INPUT ip protocol udp udp dport ${DNS_PORT} accept # Allow UDP DNS requests
nft add rule inet ${TABLE_NAME} INPUT ip protocol tcp tcp dport ${DNS_PORT} accept # Allow TCP DNS requests

# FORWARD chain - Allow forwarding traffic
nft add chain inet ${TABLE_NAME} FORWARD { type filter hook forward priority filter \; policy accept \; }
nft add rule inet ${TABLE_NAME} FORWARD ip protocol udp udp dport ${DNS_PORT} accept # Allow forwarding of DNS requests (UDP)
nft add rule inet ${TABLE_NAME} FORWARD ip protocol udp udp sport ${DNS_PORT} accept # Allow forwarding of DNS responses (UDP)
nft add rule inet ${TABLE_NAME} FORWARD ip protocol tcp tcp dport ${DNS_PORT} accept # Allow forwarding of DNS requests (TCP)
nft add rule inet ${TABLE_NAME} FORWARD ip protocol tcp tcp sport ${DNS_PORT} accept # Allow forwarding of DNS responses (TCP)

# POSTROUTING chain - Enable NAT (Masquerading) for both IPv4 and IPv6
nft add chain inet ${TABLE_NAME} POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; }
nft add rule inet ${TABLE_NAME} POSTROUTING ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} masquerade  # IPv4 masquerading
nft add rule inet ${TABLE_NAME} POSTROUTING ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} masquerade # IPv6 masquerading

# List the current nftables rules before flushing
nft list ruleset

# Flush nftables ruleset to reset after testing
nft flush ruleset
