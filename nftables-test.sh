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

# Enable IP forwarding for both IPv4 and IPv6
sudo sysctl -w net.ipv4.ip_forward=1          # Enable IPv4 forwarding
sudo sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding

# Flush any existing rules to start fresh
sudo nft flush ruleset # Remove all existing nftables rules to avoid conflicts

# Define variables for interfaces, subnets, and ports
TABLE_NAME="wg_rules"               # Name of the nftables table
NETWORK_INTERFACE="enxb827eb7c4fab" # Network interface for masquerading (e.g., eth0)
WIREGUARD_INTERFACE="wg0"           # WireGuard interface name
VPN_PORT="51820"                    # VPN port (WireGuard)
DNS_PORT="53"                       # DNS port (both UDP and TCP)
IPv4_SUBNET="10.0.0.0/8"            # IPv4 subnet to be used for NAT
IPv6_SUBNET="fd00::/8"              # IPv6 subnet to be used for NAT
HOST_IPV4="10.0.0.1"                # IPv4 address of the VPN server
HOST_IPV6="fd00::1"                 # IPv6 address of the VPN server

# Create nftables table and add chains
sudo nft add table inet ${TABLE_NAME} # Create a new table for rules

# PREROUTING chain
sudo nft add chain inet ${TABLE_NAME} PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # Create a chain for NAT rules in the PREROUTING phase

# POSTROUTING chain
sudo nft add chain inet ${TABLE_NAME} POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; } # Create a chain for NAT rules in the POSTROUTING phase
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} masquerade    # Add a rule for IPv4 masquerading
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} masquerade   # Add a rule for IPv6 masquerading
sudo nft add rule inet ${TABLE_NAME} POSTROUTING oifname ${NETWORK_INTERFACE} masquerade                            # Add a rule for masquerading all outbound traffic

# INPUT chain
sudo nft add chain inet ${TABLE_NAME} INPUT { type filter hook input priority filter \; policy accept \; }              # Create a chain for filtering input traffic
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} udp dport ${VPN_PORT} accept                    # Allow incoming WireGuard traffic on the interface (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} ip6 nexthdr udp udp dport ${VPN_PORT} accept    # Allow incoming WireGuard traffic on the interface (IPv6)
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} accept                         # Allow DNS UDP traffic only from private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} accept                        # Allow DNS UDP traffic only from private IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} tcp dport ${DNS_PORT} accept                         # Allow DNS TCP traffic only from private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} tcp dport ${DNS_PORT} accept                        # Allow DNS TCP traffic only from private IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ct state invalid drop                                                        # Drop packets with invalid connection tracking state
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} ip daddr ${HOST_IPV4} accept   # Allow DNS queries to a specific DNS server (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} ip6 daddr ${HOST_IPV6} accept # Allow DNS queries to a specific DNS server (IPv6)
sudo nft add rule inet ${TABLE_NAME} INPUT ct state related,established accept                                          # Allow related and established connections

# FORWARD chain
sudo nft add chain inet ${TABLE_NAME} FORWARD { type filter hook forward priority filter \; policy accept \; } # Create a chain for filtering forwarded traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ct state invalid drop                                             # Drop packets with invalid connection tracking state
sudo nft add rule inet ${TABLE_NAME} FORWARD ct state related,established accept                               # Allow related and established connections
sudo nft add rule inet ${TABLE_NAME} FORWARD ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} accept       # Allow all outbound IPv4 traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} accept      # Allow all outbound IPv6 traffic

# OUTPUT chain
sudo nft add chain inet ${TABLE_NAME} OUTPUT { type filter hook output priority filter \; policy accept \; } # Create a chain for filtering output traffic
sudo nft add rule inet ${TABLE_NAME} OUTPUT ct state invalid drop                                            # Drop packets with invalid connection tracking state
sudo nft add rule inet ${TABLE_NAME} OUTPUT ct state related,established accept                              # Allow related and established connections
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${IPv4_SUBNET} udp sport ${DNS_PORT} accept             # Allow DNS UDP traffic to private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${IPv6_SUBNET} udp sport ${DNS_PORT} accept            # Allow DNS UDP traffic to private IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${IPv4_SUBNET} tcp sport ${DNS_PORT} accept             # Allow DNS TCP traffic to private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${IPv6_SUBNET} tcp sport ${DNS_PORT} accept            # Allow DNS TCP traffic to private IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${HOST_IPV4} udp sport ${DNS_PORT} accept               # Allow DNS queries to a specific DNS server (IPv4)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${HOST_IPV6} udp sport ${DNS_PORT} accept              # Allow DNS queries to a specific DNS server (IPv6)

# List the current nftables rules before flushing
sudo nft list ruleset # Display the current nftables rules for verification

# Flush nftables ruleset to reset after testing
# sudo nft flush ruleset # Clear all rules after testing

# Other Project
for i in {1..50}; do echo -n "---"; done
echo ""

# Different Project.

TABLE_NAME="wg_rules"     # Name of the nftables table
IPv4_SUBNET="10.0.0.0/8"  # IPv4 subnet to be used for NAT
IPv6_SUBNET="fd00::/8"    # IPv6 subnet to be used for NAT
DNS_PORT="53"             # DNS port (both UDP and TCP)
WIREGUARD_INTERFACE="wg0" # WireGuard interface name

echo "# Enable IP forwarding for both IPv4 and IPv6
sudo sysctl -w net.ipv4.ip_forward=1          # Enable IPv4 forwarding
sudo sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding

# Create nftables table and add chains
sudo nft add table inet ${TABLE_NAME} # Create a new table for rules

# PREROUTING chain
sudo nft add chain inet ${TABLE_NAME} PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # Create a chain for NAT rules in the PREROUTING phase

# POSTROUTING chain
sudo nft add chain inet ${TABLE_NAME} POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; } # Create a chain for NAT rules in the POSTROUTING phase
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} masquerade    # Add a rule for IPv4 masquerading
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} masquerade   # Add a rule for IPv6 masquerading

# INPUT chain
sudo nft add chain inet ${TABLE_NAME} INPUT { type filter hook input priority filter \; policy accept \; }           # Create a chain for filtering input traffic
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} udp dport ${VPN_PORT} accept                 # Allow incoming WireGuard traffic on the interface (IPv4)
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} ip6 nexthdr udp udp dport ${VPN_PORT} accept # Allow incoming WireGuard traffic on the interface (IPv6)
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} accept                      # Allow DNS UDP traffic only from private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} accept                     # Allow DNS UDP traffic only from private IPv6 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} tcp dport ${DNS_PORT} accept                      # Allow DNS TCP traffic only from private IPv4 subnet
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} tcp dport ${DNS_PORT} accept                     # Allow DNS TCP traffic only from private IPv6 subnet

# FORWARD chain
sudo nft add chain inet ${TABLE_NAME} FORWARD { type filter hook forward priority filter \; policy accept \; } # Create a chain for filtering forwarded traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} accept     # Allow all outbound IPv4 traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} accept    # Allow all outbound IPv6 traffic" |
    sed 's/#.*//g' |            # Remove comments
    sed 's/[[:space:]]\+/ /g' | # Replace multiple spaces with a single space
    sed 's/ $//' |              # Remove trailing spaces
    sed 's/$/;/' |              # Add semicolons to the end of each line
    sed '1s/^;//' |             # Remove the first semicolon
    sed '$s/;$//' |             # Remove the last semicolon
    sed '/^[[:space:]]*$/d' |   # Delete empty lines
    sed 's/%$//' |              # Remove the trailing percent sign
    sed 's/;;\+/;/g' |          # Replace two or more semicolons with one
    tr -d '\n'                  # Join everything into a single line
