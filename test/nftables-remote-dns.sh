#!/bin/bash

# WireGuard and nftables Configuration Script
# This script configures nftables rules to work with a WireGuard VPN server.
# It ensures that the necessary packages are installed, IP forwarding is enabled,
# and secure nftables rules are created for NAT, DNS, and firewall filtering.

# Function to check if your script is running in a GitHub Actions environment
function is-running-inside-github-action() {
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
}

# Check if the script is running inside a GitHub Actions environment
# is-running-inside-github-action

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

# Ensure 'ip' command is installed (part of iproute2 package)
if [ ! -x "$(command -v ip)" ]; then
    echo "Installing 'iproute2'..."
    sudo apt-get update              # Update the system's package list
    sudo apt-get install -y iproute2 # Install iproute2 package if not already present
fi

# Check and enable IPv4 forwarding if not already enabled
if [ "$(sudo cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "IPv4 forwarding is disabled. Enabling now..."
    sudo sysctl -w net.ipv4.ip_forward=1 # Enable IPv4 forwarding at runtime
fi

# Check and enable IPv6 forwarding if not already enabled
if [ "$(sudo cat /proc/sys/net/ipv6/conf/all/forwarding)" != "1" ]; then
    echo "IPv6 forwarding is disabled. Enabling now..."
    sudo sysctl -w net.ipv6.conf.all.forwarding=1 # Enable IPv6 forwarding at runtime
fi

# Flush existing nftables rules to avoid conflicts
if [ "$(sudo nft list ruleset 2>/dev/null | wc -l)" -ge 2 ]; then
    echo "Flushing existing nftables rules..."
    sudo nft flush ruleset # Clear all existing rules in nftables
fi

# --- Define variables for interfaces, subnets, and ports ---
WIREGUARD_INTERFACE="wg0"                                                                          # Name of the WireGuard interface for managing VPN traffic
WIREGUARD_TABLE_NAME="${WIREGUARD_INTERFACE}-table"                                                # Name of the nftables table dedicated to WireGuard traffic
NETWORK_INTERFACE="$(ip route | grep default | head --lines=1 | cut --delimiter=" " --fields=5)"   # Default network interface (e.g., eth0) for routing internet-bound traffic
WIREGUARD_VPN_PORT="51820"                                                                         # Default UDP port for WireGuard VPN communication
WIREGUARD_IPv4_SUBNET="10.0.0.0/8"                                                                 # IPv4 subnet for VPN clients to route their traffic through
WIREGUARD_IPv6_SUBNET="fd00::/8"                                                                   # IPv6 subnet for VPN clients to route their traffic through
WIREGUARD_HOST_IPV4="10.0.0.1"                                                                     # IPv4 address of the WireGuard server (used by clients for routing)
WIREGUARD_HOST_IPV6="fd00::1"                                                                      # IPv6 address of the WireGuard server (used by clients for routing)
PRIVATE_LOCAL_IPV4_SUBNET="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8" # List of private IPv4 subnets to block for additional security
PRIVATE_LOCAL_IPV6_SUBNET="fc00::/7, fec0::/10, ::1/128, ::/128, 2001:db8::/32"                    # List of private IPv6 subnets to block for additional security

# --- Create nftables table for WireGuard VPN server ---
sudo nft add table inet "${WIREGUARD_TABLE_NAME}" # Create a new nftables table specific to the WireGuard interface to manage VPN-related rules

# --- PREROUTING CHAIN (NAT rules before routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" PREROUTING "{ type nat hook prerouting priority dstnat ; policy accept ; }" # Handle packets before routing, typically for destination NAT

# --- INPUT CHAIN (Filtering input traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" INPUT "{ type filter hook input priority filter ; policy accept ; }"                                                                         # Handle packets arriving at the WireGuard server, default accept policy
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ct state invalid log prefix "DROP_INVALID_INPUT_STATE" drop                                                                             # Drop packets in an invalid connection state (e.g., malformed or attack traffic)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" udp dport ${WIREGUARD_VPN_PORT} log prefix "ACCEPT_INPUT_WIREGUARD_PORT_UDP" accept                      # Accept incoming UDP packets on the WireGuard port from the default network interface
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" ip6 nexthdr udp udp dport ${WIREGUARD_VPN_PORT} log prefix "ACCEPT_INPUT_WIREGUARD_PORT_IPV6_UDP" accept # Accept incoming IPv6 UDP packets on the WireGuard port

# --- FORWARD CHAIN (Filtering forwarded traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" FORWARD "{ type filter hook forward priority filter ; policy accept ; }"                 # Create a FORWARD chain to manage packets routed through the VPN
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state invalid drop                                                             # Drop forwarded packets with an invalid connection tracking state
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state related,established accept                                               # Allow forwarding of packets that are part of established or related connections
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" ip daddr != "${WIREGUARD_HOST_IPV4}" accept   # Allow packets with WireGuard IPv4 source not destined for the server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" ip6 daddr != "${WIREGUARD_HOST_IPV6}" accept # Allow packets with WireGuard IPv6 source not destined for the server

# --- OUTPUT CHAIN (Filtering output traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" OUTPUT "{ type filter hook output priority filter ; policy accept ; }" # Create an OUTPUT chain to manage outgoing packets
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state invalid drop                                            # Drop outgoing packets with invalid connection tracking state
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state related,established accept                              # Allow outgoing packets related to established connections

# --- POSTROUTING CHAIN (NAT rules after routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" POSTROUTING "{ type nat hook postrouting priority srcnat ; policy accept ; }"             # Define a POSTROUTING chain to apply NAT rules after packet routing
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING oifname "${NETWORK_INTERFACE}" ip saddr "${WIREGUARD_IPv4_SUBNET}" masquerade  # Apply NAT masquerading to outgoing IPv4 traffic
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING oifname "${NETWORK_INTERFACE}" ip6 saddr "${WIREGUARD_IPv6_SUBNET}" masquerade # Apply NAT masquerading to outgoing IPv6 traffic

# View the nftables ruleset to verify the configuration
sudo nft list ruleset

# View all the blocked logs.
# journalctl -f
