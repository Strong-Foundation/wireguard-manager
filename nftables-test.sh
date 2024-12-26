#!/bin/bash

# WireGuard and nftables Configuration Script
# This script sets up basic nftables rules for a WireGuard VPN server with NAT and DNS forwarding.
# It ensures required packages are installed, IP forwarding is enabled, and nftables rules are configured securely.
#
# Usage:
#   Run this script as root or with sudo privileges.
#
# Sections:
#   1. Prerequisites Check
#   2. IP Forwarding Enablement
#   3. nftables Configuration (Masquerading, DNS, VPN)
#   4. Security Enhancements (Restrictive Policies)
#   5. Support for Both IPv4 and IPv6
#   6. Final Rule Display for Verification

# Ensure sudo is installed
if [ ! -x "$(command -v sudo)" ]; then
    apt-get update          # Update package lists to ensure availability of sudo
    apt-get install -y sudo # Install sudo if not already installed
fi

# Ensure nftables is installed
if [ ! -x "$(command -v nft)" ]; then
    sudo apt-get update              # Update package lists to ensure availability of nftables
    sudo apt-get install -y nftables # Install nftables if not already installed
fi

# Define variables for interfaces, subnets, and ports
TABLE_NAME="wg_rules"               # Name of the nftables table
NETWORK_INTERFACE="enxb827eb7c4fab" # Network interface for masquerading (e.g., eth0)
VPN_PORT="51820"                    # VPN port (WireGuard)
DNS_PORT="53"                       # DNS port (both UDP and TCP)
IPv4_SUBNET="10.0.0.0/8"            # IPv4 subnet to be used for NAT
IPv6_SUBNET="fd00::/8"              # IPv6 subnet to be used for NAT

# Enable IP forwarding for both IPv4 and IPv6
sudo sysctl -w net.ipv4.ip_forward=1          # Enable IPv4 forwarding
sudo sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding

# Flush any existing rules to start fresh
sudo nft flush ruleset # Remove all existing nftables rules to avoid conflicts

# Create nftables table and add chains
sudo nft add table inet ${TABLE_NAME} # Create a new table for rules

# PREROUTING chain
sudo nft add chain inet ${TABLE_NAME} PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # Create a chain for NAT rules in the PREROUTING phase

# POSTROUTING chain
sudo nft add chain inet ${TABLE_NAME} POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; } # Create a chain for NAT rules in the POSTROUTING phase
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} masquerade    # Add a rule for IPv4 masquerading
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} masquerade   # Add a rule for IPv6 masquerading

# INPUT chain
sudo nft add chain inet ${TABLE_NAME} INPUT { type filter hook input priority filter \; policy accept \; } # Create a chain for filtering input traffic
sudo nft add rule inet ${TABLE_NAME} INPUT ip protocol udp udp dport ${VPN_PORT} accept                    # Allow incoming WireGuard traffic (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 nexthdr udp udp dport ${VPN_PORT} accept                    # Allow incoming WireGuard traffic (IPv6)
sudo nft add rule inet ${TABLE_NAME} INPUT ip protocol udp udp dport ${DNS_PORT} accept                    # Allow incoming DNS requests over UDP (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 nexthdr udp udp dport ${DNS_PORT} accept                    # Allow incoming DNS requests over UDP (IPv6)
sudo nft add rule inet ${TABLE_NAME} INPUT ip protocol tcp tcp dport ${DNS_PORT} accept                    # Allow incoming DNS requests over TCP (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 nexthdr tcp tcp dport ${DNS_PORT} accept                    # Allow incoming DNS requests over TCP (IPv6)

# FORWARD chain
sudo nft add chain inet ${TABLE_NAME} FORWARD { type filter hook forward priority filter \; policy accept \; } # Create a chain for filtering forwarded traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ip protocol udp udp dport ${DNS_PORT} accept                      # Allow forwarding of DNS requests over UDP (IPv4)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 nexthdr udp udp dport ${DNS_PORT} accept                      # Allow forwarding of DNS requests over UDP (IPv6)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip protocol udp udp sport ${DNS_PORT} accept                      # Allow forwarding of DNS responses over UDP (IPv4)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 nexthdr udp udp sport ${DNS_PORT} accept                      # Allow forwarding of DNS responses over UDP (IPv6)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip protocol tcp tcp dport ${DNS_PORT} accept                      # Allow forwarding of DNS requests over TCP (IPv4)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 nexthdr tcp tcp dport ${DNS_PORT} accept                      # Allow forwarding of DNS requests over TCP (IPv6)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip protocol tcp tcp sport ${DNS_PORT} accept                      # Allow forwarding of DNS responses over TCP (IPv4)
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 nexthdr tcp tcp sport ${DNS_PORT} accept                      # Allow forwarding of DNS responses over TCP (IPv6)

# Security Enhancements: Set restrictive policies by default
sudo nft add rule inet ${TABLE_NAME} INPUT drop   # Set the default policy to drop all input traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD drop # Set the default policy to drop all forwarded traffic

# Explicitly allow DNS traffic from the VPN subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} accept  # Allow UDP DNS traffic from IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} accept # Allow UDP DNS traffic from IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} tcp dport ${DNS_PORT} accept  # Allow TCP DNS traffic from IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} tcp dport ${DNS_PORT} accept # Allow TCP DNS traffic from IPv6 subnet

# Explicitly allow VPN traffic on the network interface
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} udp dport ${VPN_PORT} accept                 # Allow incoming WireGuard traffic on the interface (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} ip6 nexthdr udp udp dport ${VPN_PORT} accept # Allow incoming WireGuard traffic on the interface (IPv6)

# List the current nftables rules before flushing
sudo nft list ruleset # Display the current nftables rules for verification

# Flush nftables ruleset to reset after testing
sudo nft flush ruleset # Clear all rules after testing
