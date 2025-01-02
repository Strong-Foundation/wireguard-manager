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
WIREGUARD_DNS_PORT="53"                                                                            # DNS port for both UDP and TCP traffic (commonly used for DNS queries)
WIREGUARD_IPv4_SUBNET="10.0.0.0/8"                                                                 # IPv4 subnet for VPN clients to route their traffic through
WIREGUARD_IPv6_SUBNET="fd00::/8"                                                                   # IPv6 subnet for VPN clients to route their traffic through
WIREGUARD_HOST_IPV4="10.0.0.1"                                                                     # IPv4 address of the WireGuard server (used by clients for routing)
WIREGUARD_HOST_IPV6="fd00::1"                                                                      # IPv6 address of the WireGuard server (used by clients for routing)
PRIVATE_LOCAL_IPV4_SUBNET="10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 127.0.0.0/8" # List of private IPv4 subnets to block for additional security
PRIVATE_LOCAL_IPV6_SUBNET="fc00::/7, fec0::/10, ::1/128, ::/128, 2001:db8::/32"                    # List of private IPv6 subnets to block for additional security

# --- Create a nftables table for WireGuard VPN server ---
sudo nft add table inet "${WIREGUARD_TABLE_NAME}" # Create a new nftables table specific to the WireGuard interface to manage VPN-related rules

# --- PREROUTING CHAIN (NAT before routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" PREROUTING "{ type nat hook prerouting priority dstnat ; policy accept ; }" # Handle packets before routing, typically for destination NAT

# --- INPUT CHAIN (Filter incoming traffic to the server) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" INPUT "{ type filter hook input priority filter ; policy accept ; }"                                                                                               # Handle packets arriving at the WireGuard server, default accept policy
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ct state invalid log prefix "DROP_INVALID_INPUT_STATE" drop                                                                                                   # Drop packets in an invalid connection state (e.g., malformed or attack traffic)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" udp dport ${WIREGUARD_VPN_PORT} log prefix "ACCEPT_INPUT_WIREGUARD_PORT_UDP" accept                                            # Accept incoming UDP packets on the WireGuard port from the default network interface
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT iifname "${NETWORK_INTERFACE}" ip6 nexthdr udp udp dport ${WIREGUARD_VPN_PORT} log prefix "ACCEPT_INPUT_WIREGUARD_PORT_IPV6_UDP" accept                       # Accept incoming IPv6 UDP packets on the WireGuard port
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" log prefix "ACCEPT_INPUT_DNS_QUERY_IPV4_UDP" accept   # Accept IPv4 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" log prefix "ACCEPT_INPUT_DNS_QUERY_IPV6_UDP" accept # Accept IPv6 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" log prefix "ACCEPT_INPUT_DNS_QUERY_IPV4_TCP" accept   # Accept IPv4 DNS queries (TCP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" INPUT ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" log prefix "ACCEPT_INPUT_DNS_QUERY_IPV6_TCP" accept # Accept IPv6 DNS queries (TCP) from VPN clients to the WireGuard server

# --- FORWARD CHAIN (Filter forwarded traffic) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" FORWARD "{ type filter hook forward priority filter ; policy accept ; }"                                                                                               # Handle packets being forwarded through the WireGuard server, default accept policy
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state invalid log prefix "DROP_INVALID_FORWARDED_PACKETS" drop                                                                                               # Drop packets with an invalid connection tracking state that are being forwarded
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ct state related,established log prefix "ACCEPT_RELATED_ESTABLISHED_FORWARD" accept                                                                             # Accept packets related to or part of established connections
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" log prefix "ACCEPT_FORWARD_DNS_QUERY_IPV4_UDP" accept   # Forward IPv4 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" udp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" log prefix "ACCEPT_FORWARD_DNS_QUERY_IPV6_UDP" accept # Forward IPv6 DNS queries (UDP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip saddr "${WIREGUARD_IPv4_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip daddr "${WIREGUARD_HOST_IPV4}" log prefix "ACCEPT_FORWARD_DNS_QUERY_IPV4_TCP" accept   # Forward IPv4 DNS queries (TCP) from VPN clients to the WireGuard server
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" FORWARD ip6 saddr "${WIREGUARD_IPv6_SUBNET}" tcp dport "${WIREGUARD_DNS_PORT}" ip6 daddr "${WIREGUARD_HOST_IPV6}" log prefix "ACCEPT_FORWARD_DNS_QUERY_IPV6_TCP" accept # Forward IPv6 DNS queries (TCP) from VPN clients to the WireGuard server

# --- OUTPUT CHAIN (Filter outgoing traffic from the server) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" OUTPUT "{ type filter hook output priority filter ; policy accept ; }"                                                              # Handle packets generated by the WireGuard server, default accept policy
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state invalid log prefix "DROP_INVALID_OUTPUT_STATE" drop                                                                  # Drop outgoing packets with invalid connection states
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ct state related,established log prefix "ACCEPT_RELATED_ESTABLISHED_OUTPUT" accept                                            # Allow outgoing packets that are part of established or related connections
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_QUERY_IPV4_UDP" accept    # Allow server-generated IPv4 DNS queries (UDP) to clients in the IPv4 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" udp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_QUERY_IPV6_UDP" accept   # Allow server-generated IPv6 DNS queries (UDP) to clients in the IPv6 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_IPv4_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_QUERY_IPV4_TCP" accept    # Allow server-generated IPv4 DNS queries (TCP) to clients in the IPv4 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_IPv6_SUBNET}" tcp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_QUERY_IPV6_TCP" accept   # Allow server-generated IPv6 DNS queries (TCP) to clients in the IPv6 subnet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip daddr "${WIREGUARD_HOST_IPV4}" udp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_TO_SERVER_IPV4_UDP" accept  # Allow outgoing DNS queries (UDP) to the WireGuard server's IPv4 address
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" OUTPUT ip6 daddr "${WIREGUARD_HOST_IPV6}" udp sport "${WIREGUARD_DNS_PORT}" log prefix "ACCEPT_OUTPUT_DNS_TO_SERVER_IPV6_UDP" accept # Allow outgoing DNS queries (UDP) to the WireGuard server's IPv6 address

# --- POSTROUTING CHAIN (NAT after routing) ---
sudo nft add chain inet "${WIREGUARD_TABLE_NAME}" POSTROUTING "{ type nat hook postrouting priority srcnat ; policy accept ; }"                                                      # Handle packets after routing, typically for source NAT (masquerading)
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip saddr "${WIREGUARD_IPv4_SUBNET}" oifname "${NETWORK_INTERFACE}" log prefix "MASQUERADE_VPN_IPV4_TRAFFIC" masquerade  # Masquerade IPv4 packets from VPN clients when routing them to the internet
sudo nft add rule inet "${WIREGUARD_TABLE_NAME}" POSTROUTING ip6 saddr "${WIREGUARD_IPv6_SUBNET}" oifname "${NETWORK_INTERFACE}" log prefix "MASQUERADE_VPN_IPV6_TRAFFIC" masquerade # Masquerade IPv6 packets from VPN clients when routing them to the internet

# View the nftables ruleset to verify the configuration
sudo nft list ruleset

# View all the blocked logs.
# journalctl -f
