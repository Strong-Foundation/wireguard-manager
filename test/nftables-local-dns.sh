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
if [ "$(nft list ruleset | wc -l)" -ge 2 ]; then
    echo "Flushing existing nftables rules..."
    sudo nft flush ruleset # Clear all existing rules in nftables
fi

# Define variables for interfaces, subnets, and ports
WIREGUARD_INTERFACE="wg0"                           # WireGuard interface name, identifying the VPN interface for traffic routing
WIREGUARD_TABLE_NAME="${WIREGUARD_INTERFACE}-table" # Name of the nftables table where all WireGuard-related rules are stored
NETWORK_INTERFACE="enxb827eb7c4fab"                 # Outbound network interface (e.g., eth0), used for internet-bound traffic masquerading
WIREGUARD_VPN_PORT="51820"                          # UDP port used for WireGuard VPN communication (default WireGuard port)
WIREGUARD_DNS_PORT="53"                             # Port used for DNS traffic (UDP and TCP) from VPN clients
WIREGUARD_IPv4_SUBNET="10.0.0.0/8"                  # IPv4 subnet assigned to VPN clients for NAT and routing
WIREGUARD_IPv6_SUBNET="fd00::/8"                    # IPv6 subnet assigned to VPN clients for NAT and routing
WIREGUARD_HOST_IPV4="10.0.0.1"                      # IPv4 address of the WireGuard server (private IP for VPN clients)
WIREGUARD_HOST_IPV6="fd00::1"                       # IPv6 address of the WireGuard server (private IP for VPN clients)

# --- Create nftables table for WireGuard VPN server ---
sudo nft add table inet "${WIREGUARD_TABLE_NAME}" # Create a new nftables table named after the WireGuard interface for managing VPN traffic rules

# --- PREROUTING CHAIN (NAT rules before routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" PREROUTING "{ type nat hook prerouting priority dstnat ; policy accept ; }" # PREROUTING chain processes incoming packets before routing, typically for destination NAT (e.g., forwarding requests)

# --- INPUT CHAIN (Filtering input traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" INPUT "{ type filter hook input priority filter ; policy accept ; }"                                                  # INPUT chain processes packets addressed to the server, policy is initially set to accept
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" udp dport ${WIREGUARD_VPN_PORT} accept                                            # Allow incoming UDP packets on WireGuard VPN port from the specified network interface
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" ip6 nexthdr udp udp dport ${WIREGUARD_VPN_PORT} accept                            # Allow incoming IPv6 UDP packets on WireGuard VPN port from the specified network interface
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Allow IPv4 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Allow IPv6 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Allow IPv4 DNS queries (TCP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Allow IPv6 DNS queries (TCP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ct state invalid drop                                                                                            # Drop packets with an invalid connection tracking state to maintain security

# --- FORWARD CHAIN (Filtering forwarded traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" FORWARD "{ type filter hook forward priority filter ; policy accept ; }"                                                # FORWARD chain processes packets routed through the server, policy set to accept initially
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state invalid drop                                                                                            # Drop forwarded packets with an invalid connection tracking state
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state related,established accept                                                                              # Allow forwarding of packets that are part of established or related connections
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Forward IPv4 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Forward IPv6 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" accept   # Forward IPv4 DNS queries (TCP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" accept # Forward IPv6 DNS queries (TCP) from VPN clients to the WireGuard server

# --- OUTPUT CHAIN (Filtering output traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" OUTPUT "{ type filter hook output priority filter ; policy accept ; }"              # OUTPUT chain processes packets generated by the server, policy set to accept initially
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state invalid drop                                                         # Drop outgoing packets with an invalid connection tracking state
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state related,established accept                                           # Allow outgoing packets that are part of established or related connections
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" accept  # Allow server-generated DNS queries (UDP) to clients in the IPv4 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" accept # Allow server-generated DNS queries (UDP) to clients in the IPv6 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" accept  # Allow server-generated DNS queries (TCP) to clients in the IPv4 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" accept # Allow server-generated DNS queries (TCP) to clients in the IPv6 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_HOST_IPV4}" udp sport "${WIREGUARD_DNS_PORT}" accept    # Allow outgoing DNS queries (UDP) to the WireGuard server's IPv4 address
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_HOST_IPV6}" udp sport "${WIREGUARD_DNS_PORT}" accept   # Allow outgoing DNS queries (UDP) to the WireGuard server's IPv6 address

# --- POSTROUTING CHAIN (NAT rules after routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" POSTROUTING "{ type nat hook postrouting priority srcnat ; policy accept ; }"             # POSTROUTING chain processes packets after routing, typically for source NAT (masquerading)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip saddr "${WIREGUARD_IPv4_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade  # Apply NAT (masquerading) to IPv4 packets from VPN clients when forwarded to the internet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip6 saddr "${WIREGUARD_IPv6_SUBNET}" oifname "${NETWORK_INTERFACE}" masquerade # Apply NAT (masquerading) to IPv6 packets from VPN clients when forwarded to the internet

# View the nftables ruleset to verify the configuration
nft list ruleset

# View all the blocked logs.
# journalctl -f