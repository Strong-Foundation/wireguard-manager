#!/bin/bash

# WireGuard and nftables Configuration Script
# This script configures nftables rules to work with a WireGuard VPN server.
# It ensures that the necessary packages are installed, IP forwarding is enabled,
# and secure nftables rules are created for NAT, DNS, and firewall filtering.

# Check if the script is running inside a GitHub Actions environment
if [ -z "$GITHUB_REPOSITORY" ]; then
    # If the GITHUB_REPOSITORY variable is not set, it is not a GitHub Actions environment
    echo "GitHub Actions environment not detected."
    echo "This script is meant to be run in a GitHub Actions workflow."
    exit 1 # Exit with error since this script is meant for GitHub Actions
else
    # If GITHUB_REPOSITORY is set, confirm the environment and display the repository name
    echo "GitHub Actions environment detected."
    echo "GitHub Repo: ${GITHUB_REPOSITORY}"
fi

# Ensure `sudo` is installed on the system
if [ ! -x "$(command -v sudo)" ]; then
    echo "Installing 'sudo'..."
    sudo apt-get update          # Update the system's package list to get the latest metadata
    sudo apt-get install -y sudo # Install sudo if not already present
fi

# Ensure `nftables` is installed
if [ ! -x "$(command -v nft)" ]; then
    echo "Installing 'nftables'..."
    sudo apt-get update              # Update the system's package list
    sudo apt-get install -y nftables # Install nftables if not already present
fi

# Ensure `coreutils` is installed (provides `cat` command)
if [ ! -x "$(command -v cat)" ]; then
    echo "Installing 'coreutils'..."
    sudo apt-get update               # Update the system's package list
    sudo apt-get install -y coreutils # Install coreutils if not already present
fi

# Enable IP forwarding for both IPv4 and IPv6
# This ensures that the server can forward packets between network interfaces.
echo "Checking IP forwarding settings..."

# Check and enable IPv4 forwarding if not already enabled
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "IPv4 forwarding is disabled. Enabling now..."
    sudo sysctl -w net.ipv4.ip_forward=1 # Enable IPv4 forwarding at runtime
fi

# Check and enable IPv6 forwarding if not already enabled
if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" != "1" ]; then
    echo "IPv6 forwarding is disabled. Enabling now..."
    sudo sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding at runtime
fi

# Flush existing nftables rules to avoid conflicts
if [ $(echo "$(nft list ruleset)" | wc -l) -ge 2 ]; then
    echo "Flushing existing nftables rules..."
    sudo nft flush ruleset # Clear all existing rules in nftables
fi

# Define variables for interfaces, subnets, and ports
WIREGUARD_INTERFACE="wg0"                           # WireGuard interface name (used to identify the VPN interface)
WIREGUARD_TABLE_NAME="${WIREGUARD_INTERFACE}-table" # Name of the nftables table where the rules will be added
NETWORK_INTERFACE="enxb827eb7c4fab"                 # Network interface used for masquerading (e.g., eth0 or the interface for the outgoing internet connection)
WIREGUARD_VPN_PORT="51820"                          # Port used for WireGuard VPN traffic (default is 51820)
WIREGUARD_DNS_PORT="53"                             # Port used for DNS (both UDP and TCP)
WIREGUARD_IPv4_SUBNET="10.0.0.0/8"                  # IPv4 subnet used for NAT (Network Address Translation) for internal VPN clients
WIREGUARD_IPv6_SUBNET="fd00::/8"                    # IPv6 subnet used for NAT for internal VPN clients
WIREGUARD_HOST_IPV4="10.0.0.1"                      # Define the server's IPv4 address (WireGuard server's private IP)
WIREGUARD_HOST_IPV6="fd00::1"                       # Define the server's IPv6 address (WireGuard server's private IP)

# --- Create nftables table for WireGuard VPN server ---
sudo nft add table inet "${WIREGUARD_TABLE_NAME}" # Create a new table for nftables to store firewall rules (inet refers to both IPv4 and IPv6)
# --- Create nftables table for WireGuard VPN server ---

# --- PREROUTING CHAIN (NAT rules before routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" PREROUTING { type nat hook prerouting priority dstnat \; policy accept \; } # PREROUTING chain handles packets before routing decisions are made. Here, we specify this chain as a NAT chain for destination NAT (dstnat)
# --- PREROUTING CHAIN (NAT rules before routing) ---

# --- INPUT CHAIN (Filtering input traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" INPUT { type filter hook input priority filter \; policy accept \; }                                                  # INPUT chain handles packets coming into the server. The policy is set to accept, but we'll add more specific rules for filtering traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" udp dport ${WIREGUARD_VPN_PORT} accept                                            # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) on the specified network interface (usually for VPN connections)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" ip6 nexthdr udp udp dport ${WIREGUARD_VPN_PORT} accept                            # This rule accepts incoming UDP traffic destined for the WireGuard VPN port (51820) over IPv6, useful for VPN connections over IPv6
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # This rule accepts DNS queries (UDP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8) to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # This rule accepts DNS queries (UDP on port 53) from clients within the specified IPv6 subnet (fd00::/8) to the specific DNS server (fd00::1)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # This rule accepts DNS queries (TCP on port 53) from clients within the specified IPv4 subnet (10.0.0.0/8) to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # This rule accepts DNS queries (TCP on port 53) from clients within the specified IPv6 subnet (fd00::/8) to the specific DNS server (fd00::1)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ct state invalid drop                                                                                            # This rule drops packets with invalid connection tracking state
# --- INPUT CHAIN (Filtering input traffic) ---

# --- FORWARD CHAIN (Filtering forwarded traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" FORWARD { type filter hook forward priority filter \; policy accept \; }                                                # FORWARD chain handles packets that are being routed through the server. The policy is set to accept, but we'll add more specific rules for filtering forwarded traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state invalid drop                                                                                            # This rule drops packets that have an invalid connection tracking state, ensuring only valid connections are forwarded
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state related,established accept                                                                              # This rule allows packets that are part of an already established connection or related to an established connection to be forwarded
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Allow VPN clients to forward DNS queries to the DNS server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Allow VPN clients to forward DNS queries to the DNS server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Allow VPN clients to forward DNS queries (TCP) to the DNS server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Allow VPN clients to forward DNS queries (TCP) to the DNS server
# --- FORWARD CHAIN (Filtering forwarded traffic) ---

# --- OUTPUT CHAIN (Filtering output traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" OUTPUT { type filter hook output priority filter \; policy accept \; }              # OUTPUT chain handles packets generated by the server itself. The policy is set to accept, but we'll add more specific rules for filtering output traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state invalid drop                                                         # This rule drops packets that have an invalid connection tracking state for outgoing traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state related,established accept                                           # This rule allows packets that are part of an already established connection or related to an established connection to be sent out
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" accept  # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" accept # This rule allows outgoing DNS queries (UDP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" accept  # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv4 subnet (10.0.0.0/8)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" accept # This rule allows outgoing DNS queries (TCP on port 53) from the server to clients within the IPv6 subnet (fd00::/8)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_HOST_IPV4}" udp sport "${WIREGUARD_DNS_PORT}" accept    # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (10.0.0.1)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_HOST_IPV6}" udp sport "${WIREGUARD_DNS_PORT}" accept   # This rule allows outgoing DNS queries (UDP on port 53) from the server to the specific DNS server (fd00::1)
# --- OUTPUT CHAIN (Filtering output traffic) ---

# --- POSTROUTING CHAIN (NAT rules after routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" POSTROUTING { type nat hook postrouting priority srcnat \; policy accept \; }             # POSTROUTING chain handles packets after routing decisions are made. It's used for source NAT (srcnat), mainly for masquerading outgoing traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip saddr "${WIREGUARD_IPv4_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade  # This rule applies NAT (masquerading) to IPv4 traffic with source addresses in the VPN subnet (10.0.0.0/8) when going out through the specified network interface
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip6 saddr "${WIREGUARD_IPv6_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade # This rule applies NAT (masquerading) to IPv6 traffic with source addresses in the VPN subnet (fd00::/8) when going out through the specified network interface
# --- POSTROUTING CHAIN (NAT rules after routing) ---

# View all the blocked logs.
# journalctl -f
