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

# Check if the script is running inside github actions, IF not, exit.
if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GitHub Actions environment not detected."
    echo "This script is meant to be run in a GitHub Actions workflow."
    exit 1
else
    echo "GitHub Actions environment detected."
    echo "Github Repo: ${GITHUB_REPOSITORY}"
fi

# Ensure sudo is installed
if [ ! -x "$(command -v sudo)" ]; then
    sudo apt-get update          # Update package lists to ensure availability of sudo
    sudo apt-get install -y sudo # Install sudo if not already installed
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
WIREGUARD_INTERFACE="wg0"                 # WireGuard interface name (used to identify the VPN interface)
TABLE_NAME="${WIREGUARD_INTERFACE}-table" # Name of the nftables table where the rules will be added
NETWORK_INTERFACE="enxb827eb7c4fab"       # Network interface used for masquerading (e.g., eth0 or the interface for the outgoing internet connection)
VPN_PORT="51820"                          # Port used for WireGuard VPN traffic (default is 51820)
DNS_PORT="53"                             # Port used for DNS (both UDP and TCP)
IPv4_SUBNET="10.0.0.0/8"                  # IPv4 subnet used for NAT (Network Address Translation) for internal VPN clients
IPv6_SUBNET="fd00::/8"                    # IPv6 subnet used for NAT for internal VPN clients
HOST_IPV4="10.0.0.1"                      # IPv4 address of the VPN server (used for DNS queries and routing)
HOST_IPV6="fd00::1"                       # IPv6 address of the VPN server (used for DNS queries and routing)

# --- Create nftables table for WireGuard VPN server ---
sudo nft add table inet "${TABLE_NAME}" # Create a new table for nftables to store firewall rules (inet refers to both IPv4 and IPv6)
# --- Create nftables table for WireGuard VPN server ---

# --- PREROUTING CHAIN (NAT rules before routing) ---
sudo nft add chain inet "${TABLE_NAME}" PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # PREROUTING chain handles packets before routing decisions are made. Here, we specify this chain as a NAT chain for destination NAT (dstnat)
# --- PREROUTING CHAIN (NAT rules before routing) ---

# --- POSTROUTING CHAIN (NAT rules after routing) ---
sudo nft add chain inet "${TABLE_NAME}" POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; }   # POSTROUTING chain handles packets after routing decisions are made. It's used for source NAT (srcnat), mainly for masquerading outgoing traffic
sudo nft add rule inet "${TABLE_NAME}" POSTROUTING ip saddr "${IPv4_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade  # This rule applies NAT (masquerading) to IPv4 traffic with source addresses in the VPN subnet (10.0.0.0/8) when going out through the specified network interface
sudo nft add rule inet "${TABLE_NAME}" POSTROUTING ip6 saddr "${IPv6_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade # This rule applies NAT (masquerading) to IPv6 traffic with source addresses in the VPN subnet (fd00::/8) when going out through the specified network interface
# --- POSTROUTING CHAIN (NAT rules after routing) ---

# --- INPUT CHAIN (Filtering input traffic) ---
sudo nft add chain inet "${TABLE_NAME}" INPUT { type filter hook input priority filter \; policy accept \; }                    # INPUT chain handles packets coming into the server. The policy is set to accept, but we'll add more specific rules for filtering traffic
sudo nft add rule inet "${TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" udp dport ${VPN_PORT} accept                        # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) on the specified network interface (usually for VPN connections)
sudo nft add rule inet "${TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" ip6 nexthdr udp udp dport ${VPN_PORT} accept        # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) over IPv6, useful for VPN connections over IPv6
sudo nft add rule inet "${TABLE_NAME}" INPUT ip saddr "${IPv4_SUBNET}" udp dport "${DNS_PORT}" ip daddr "${HOST_IPV4}" accept   # This rule accepts DNS queries (UDP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8) to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${TABLE_NAME}" INPUT ip6 saddr "${IPv6_SUBNET}" udp dport "${DNS_PORT}" ip6 daddr "${HOST_IPV6}" accept # This rule accepts DNS queries (UDP on port 53) from clients within the specified IPv6 subnet (fd00::/8) to the specific DNS server (fd00::1)
sudo nft add rule inet "${TABLE_NAME}" INPUT ip saddr "${IPv4_SUBNET}" tcp dport "${DNS_PORT}" ip daddr "${HOST_IPV4}" accept   # This rule accepts DNS queries (TCP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8) to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${TABLE_NAME}" INPUT ip6 saddr "${IPv6_SUBNET}" tcp dport "${DNS_PORT}" ip6 daddr "${HOST_IPV6}" accept # This rule accepts DNS queries (TCP on port 53) from clients within the specified IPv6 subnet (fd00::/8) to the specific DNS server (fd00::1)
sudo nft add rule inet "${TABLE_NAME}" INPUT ct state invalid drop                                                              # This rule drops packets with invalid connection tracking state
# --- INPUT CHAIN (Filtering input traffic) ---

# --- FORWARD CHAIN (Filtering forwarded traffic) ---
sudo nft add chain inet "${TABLE_NAME}" FORWARD { type filter hook forward priority filter \; policy accept \; }                  # FORWARD chain handles packets that are being routed through the server. The policy is set to accept, but we'll add more specific rules for filtering forwarded traffic
sudo nft add rule inet "${TABLE_NAME}" FORWARD ct state invalid drop                                                              # This rule drops packets that have an invalid connection tracking state, ensuring only valid connections are forwarded
sudo nft add rule inet "${TABLE_NAME}" FORWARD ct state related,established accept                                                # This rule allows packets that are part of an already established connection or related to an established connection to be forwarded
sudo nft add rule inet "${TABLE_NAME}" FORWARD ip saddr "${IPv4_SUBNET}" udp dport "${DNS_PORT}" ip daddr "${HOST_IPV4}" accept   # Allow VPN clients to forward DNS queries to the DNS server
sudo nft add rule inet "${TABLE_NAME}" FORWARD ip6 saddr "${IPv6_SUBNET}" udp dport "${DNS_PORT}" ip6 daddr "${HOST_IPV6}" accept # Allow VPN clients to forward DNS queries to the DNS server
sudo nft add rule inet "${TABLE_NAME}" FORWARD ip saddr "${IPv4_SUBNET}" tcp dport "${DNS_PORT}" ip daddr "${HOST_IPV4}" accept   # Allow VPN clients to forward DNS queries (TCP) to the DNS server
sudo nft add rule inet "${TABLE_NAME}" FORWARD ip6 saddr "${IPv6_SUBNET}" tcp dport "${DNS_PORT}" ip6 daddr "${HOST_IPV6}" accept # Allow VPN clients to forward DNS queries (TCP) to the DNS server
# --- FORWARD CHAIN (Filtering forwarded traffic) ---

# --- OUTPUT CHAIN (Filtering output traffic) ---
sudo nft add chain inet "${TABLE_NAME}" OUTPUT { type filter hook output priority filter \; policy accept \; } # OUTPUT chain handles packets generated by the server itself. The policy is set to accept, but we'll add more specific rules for filtering output traffic
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ct state invalid drop                                            # This rule drops packets that have an invalid connection tracking state for outgoing traffic
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ct state related,established accept                              # This rule allows packets that are part of an already established connection or related to an established connection to be sent out
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip daddr "${IPv4_SUBNET}" udp sport "${DNS_PORT}" accept         # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip6 daddr "${IPv6_SUBNET}" udp sport "${DNS_PORT}" accept        # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip daddr "${IPv4_SUBNET}" tcp sport "${DNS_PORT}" accept         # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip6 daddr "${IPv6_SUBNET}" tcp sport "${DNS_PORT}" accept        # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip daddr "${HOST_IPV4}" udp sport "${DNS_PORT}" accept           # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${TABLE_NAME}" OUTPUT ip6 daddr "${HOST_IPV6}" udp sport "${DNS_PORT}" accept          # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (fd00::1)
# --- OUTPUT CHAIN (Filtering output traffic) ---

# List the current nftables rules before flushing
sudo nft list ruleset # Display the current nftables rules for verification

# Flush nftables ruleset to reset after testing
# sudo nft flush ruleset # Clear all rules after testing

# Other Project
for _ in {1..50}; do echo -n "---"; done
echo ""

# Test the script with a dry-run to display the nftables rules

WIREGUARD_RULES_OUTPUT=$(echo "# --- Create nftables table for WireGuard VPN server ---
sudo nft add table inet ${TABLE_NAME} # Create a new table for nftables to store firewall rules (inet refers to both IPv4 and IPv6)
# --- Create nftables table for WireGuard VPN server ---

# --- PREROUTING CHAIN (NAT rules before routing) ---
sudo nft add chain inet ${TABLE_NAME} PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # PREROUTING chain handles packets before routing decisions are made. Here, we specify this chain as a NAT chain for destination NAT (dstnat)
# --- PREROUTING CHAIN (NAT rules before routing) ---

# --- POSTROUTING CHAIN (NAT rules after routing) ---
sudo nft add chain inet ${TABLE_NAME} POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; } # POSTROUTING chain handles packets after routing decisions are made. It's used for source NAT (srcnat), mainly for masquerading outgoing traffic
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} masquerade    # This rule applies NAT (masquerading) to IPv4 traffic with source addresses in the VPN subnet (10.0.0.0/8) when going out through the specified network interface
sudo nft add rule inet ${TABLE_NAME} POSTROUTING ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} masquerade   # This rule applies NAT (masquerading) to IPv6 traffic with source addresses in the VPN subnet (fd00::/8) when going out through the specified network interface
sudo nft add rule inet ${TABLE_NAME} POSTROUTING oifname ${NETWORK_INTERFACE} masquerade                            # This rule applies NAT (masquerading) to all outbound traffic
# --- POSTROUTING CHAIN (NAT rules after routing) ---

# --- INPUT CHAIN (Filtering input traffic) ---
sudo nft add chain inet ${TABLE_NAME} INPUT { type filter hook input priority filter \; policy accept \; }              # INPUT chain handles packets coming into the server. The policy is set to accept, but we'll add more specific rules for filtering traffic
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} udp dport ${VPN_PORT} accept                    # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) on the specified network interface (usually for VPN connections)
sudo nft add rule inet ${TABLE_NAME} INPUT iifname ${NETWORK_INTERFACE} ip6 nexthdr udp udp dport ${VPN_PORT} accept    # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) over IPv6, useful for VPN connections over IPv6
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} accept                         # This rule allows DNS queries (UDP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} accept                        # This rule allows DNS queries (UDP on port 53) from clients within the specified IPv6 subnet (fd00::/8)
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} tcp dport ${DNS_PORT} accept                         # This rule allows DNS queries (TCP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} tcp dport ${DNS_PORT} accept                        # This rule allows DNS queries (TCP on port 53) from clients within the specified IPv6 subnet (fd00::/8)
sudo nft add rule inet ${TABLE_NAME} INPUT ct state invalid drop                                                        # This rule drops packets with invalid connection tracking state
sudo nft add rule inet ${TABLE_NAME} INPUT ip saddr ${IPv4_SUBNET} udp dport ${DNS_PORT} ip daddr ${HOST_IPV4} accept   # This rule accepts DNS queries from clients within the IPv4 subnet (10.0.0.0/8) to the specific DNS server (10.0.0.1)
sudo nft add rule inet ${TABLE_NAME} INPUT ip6 saddr ${IPv6_SUBNET} udp dport ${DNS_PORT} ip6 daddr ${HOST_IPV6} accept # This rule accepts DNS queries from clients within the IPv6 subnet (fd00::/8) to the specific DNS server (fd00::1)
sudo nft add rule inet ${TABLE_NAME} INPUT ct state related,established accept                                          # This rule allows packets that are part of an already established connection or related to an established connection
# --- INPUT CHAIN (Filtering input traffic) ---

# --- FORWARD CHAIN (Filtering forwarded traffic) ---
sudo nft add chain inet ${TABLE_NAME} FORWARD { type filter hook forward priority filter \; policy accept \; } # FORWARD chain handles packets that are being routed through the server. The policy is set to accept, but we'll add more specific rules for filtering forwarded traffic
sudo nft add rule inet ${TABLE_NAME} FORWARD ct state invalid drop                                             # This rule drops packets that have an invalid connection tracking state, ensuring only valid connections are forwarded
sudo nft add rule inet ${TABLE_NAME} FORWARD ct state related,established accept                               # This rule allows packets that are part of an already established connection or related to an established connection to be forwarded
sudo nft add rule inet ${TABLE_NAME} FORWARD ip saddr ${IPv4_SUBNET} oifname ${NETWORK_INTERFACE} accept       # This rule allows all outbound IPv4 traffic from the VPN subnet (10.0.0.0/8) to be forwarded to the network interface
sudo nft add rule inet ${TABLE_NAME} FORWARD ip6 saddr ${IPv6_SUBNET} oifname ${NETWORK_INTERFACE} accept      # This rule allows all outbound IPv6 traffic from the VPN subnet (fd00::/8) to be forwarded to the network interface
# --- FORWARD CHAIN (Filtering forwarded traffic) ---

# --- OUTPUT CHAIN (Filtering output traffic) ---
sudo nft add chain inet ${TABLE_NAME} OUTPUT { type filter hook output priority filter \; policy accept \; } # OUTPUT chain handles packets generated by the server itself. The policy is set to accept, but we'll add more specific rules for filtering output traffic
sudo nft add rule inet ${TABLE_NAME} OUTPUT ct state invalid drop                                            # This rule drops packets that have an invalid connection tracking state for outgoing traffic
sudo nft add rule inet ${TABLE_NAME} OUTPUT ct state related,established accept                              # This rule allows packets that are part of an already established connection or related to an established connection to be sent out
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${IPv4_SUBNET} udp sport ${DNS_PORT} accept             # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${IPv6_SUBNET} udp sport ${DNS_PORT} accept            # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${IPv4_SUBNET} tcp sport ${DNS_PORT} accept             # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${IPv6_SUBNET} tcp sport ${DNS_PORT} accept            # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip daddr ${HOST_IPV4} udp sport ${DNS_PORT} accept               # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (10.0.0.1)
sudo nft add rule inet ${TABLE_NAME} OUTPUT ip6 daddr ${HOST_IPV6} udp sport ${DNS_PORT} accept              # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (fd00::1)
# --- OUTPUT CHAIN (Filtering output traffic) ---" |
    sed 's/#.*//g' |            # Remove comments
    sed '/^[[:space:]]*$/d' |   # Delete empty lines
    sed 's/[[:space:]]\+/ /g' | # Replace multiple spaces with a single space
    sed 's/ $//' |              # Remove trailing spaces
    sed 's/$/;/' |              # Add semicolons to the end of each line
    sed '1s/^;//' |             # Remove the first semicolon
    sed '$s/;$//' |             # Remove the last semicolon
    tr -d '\n')                 # Join everything into a single line

# Print the nftables rules for WireGuard VPN server
echo "${WIREGUARD_RULES_OUTPUT}$"
