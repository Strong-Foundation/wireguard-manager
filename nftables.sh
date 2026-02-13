#!/bin/bash
set -euo pipefail
# ------------------------------------------
# Bash safety flags:
# -e : exit on any command failure
# -u : treat unset variables as errors
# -o pipefail : exit if any part of a pipe fails
# ------------------------------------------

# ---------------------
# Basic checks & enable forwarding
# ---------------------
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "IPv4 forwarding is disabled. Enabling now..."
    sysctl -w net.ipv4.ip_forward=1  # Enable IPv4 forwarding at runtime
    # Example: allows packets to move between interfaces (WAN → VPN)
fi

if [ "$(cat /proc/sys/net/ipv6/conf/all/forwarding)" != "1" ]; then
    echo "IPv6 forwarding is disabled. Enabling now..."
    sysctl -w net.ipv6.conf.all.forwarding=1  # Enable IPv6 forwarding at runtime
    # Example: necessary for IPv6 VPN clients to reach the internet
fi

# Flush existing nftables rules
if nft list ruleset >/dev/null 2>&1; then
    echo "Flushing existing nftables rules..."
    nft flush ruleset
    # Example: removes all previous rules to avoid conflicts
fi

# ---------------------
# Variables
# ---------------------
WIREGUARD_INTERFACE="wg0"  # VPN interface
WIREGUARD_TABLE_NAME="${WIREGUARD_INTERFACE}-table"  # nftables table name
NETWORK_INTERFACE="$(ip route | grep default | head -n 1 | cut -d' ' -f5)"  # Default internet NIC
# Example: eth0, wlan0

WIREGUARD_VPN_PORT="51820"    # WireGuard UDP port
WIREGUARD_DNS_PORT="53"       # DNS port for client queries (UDP/TCP)

# VPN client subnets
WIREGUARD_IPv4_SUBNET="10.32.0.0/12"  # VPN client IPv4 addresses
WIREGUARD_IPv6_SUBNET="fd32:00:00::0/64"  # VPN client IPv6 addresses

# Server internal addresses
WIREGUARD_HOST_IPV4="10.32.0.1"  # Server internal IPv4
WIREGUARD_HOST_IPV6="fd32:00:00::1"  # Server internal IPv6

# Private LAN subnets to block
PRIVATE_LOCAL_IPV4_SUBNET="10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,127.0.0.0/8"
PRIVATE_LOCAL_IPV6_SUBNET="fc00::/7,fe80::/10,::1/128,2001:db8::/32"
# Example: prevents VPN clients from reaching internal LAN devices

# ---------------------
# NAT setup
# ---------------------
nft add table ip "${WIREGUARD_TABLE_NAME}"
# Example: creates IPv4 NAT table wg0-table

nft add chain ip "${WIREGUARD_TABLE_NAME}" postrouting '{ type nat hook postrouting priority srcnat; }'
# Example: postrouting chain for NAT (masquerade) packets leaving the server

nft add rule ip "${WIREGUARD_TABLE_NAME}" postrouting oifname "${NETWORK_INTERFACE}" masquerade
# Example: NAT IPv4 traffic from VPN → internet

nft add table ip6 "${WIREGUARD_TABLE_NAME}"
nft add chain ip6 "${WIREGUARD_TABLE_NAME}" postrouting '{ type nat hook postrouting priority srcnat; }'
nft add rule ip6 "${WIREGUARD_TABLE_NAME}" postrouting oifname "${NETWORK_INTERFACE}" masquerade
# Example: NAT IPv6 traffic (NAT66) leaving the server

# ---------------------
# Filter rules
# ---------------------
nft add table inet "${WIREGUARD_TABLE_NAME}"
# Example: creates table that handles both IPv4 and IPv6 filtering

nft add chain inet "${WIREGUARD_TABLE_NAME}" forward '{ type filter hook forward priority filter; policy drop; }'
# Example: forward chain default policy drop (deny everything by default)

# 1) Drop invalid packets from wg0 only
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ct state invalid drop
# Example: drops broken connections from VPN clients

# 2) Allow established/related connections
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ct state related,established accept
# Example: allows return traffic for established connections

# 3) Allow WireGuard server UDP port
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" udp dport ${WIREGUARD_VPN_PORT} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" udp dport ${WIREGUARD_VPN_PORT} accept
# Example: allows VPN clients to reach WireGuard server port 51820

# 4) Allow DNS to server internal IPs only (UDP/TCP 53)
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" tcp dport ${WIREGUARD_DNS_PORT} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" udp dport ${WIREGUARD_DNS_PORT} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" tcp dport ${WIREGUARD_DNS_PORT} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" udp dport ${WIREGUARD_DNS_PORT} accept
# Example: allows VPN clients to query DNS on server only

# 5) Drop all other traffic to server internal IPs from VPN clients
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" drop
# Example: blocks HTTP, HTTPS, SSH etc. from VPN clients to server

# 6) Block client-to-client traffic in VPN
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ip saddr ${WIREGUARD_IPv4_SUBNET} ip daddr ${WIREGUARD_IPv4_SUBNET} drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ip6 saddr ${WIREGUARD_IPv6_SUBNET} ip6 daddr ${WIREGUARD_IPv6_SUBNET} drop
# Example: prevents VPN clients from talking to each other

# 7) Block VPN clients from private LANs
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "{ ${PRIVATE_LOCAL_IPV4_SUBNET} }" drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "{ ${PRIVATE_LOCAL_IPV6_SUBNET} }" drop
# Example: prevents VPN clients from accessing office/home LAN devices

# 8) Allow VPN clients → Internet
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" oifname "${NETWORK_INTERFACE}" ip saddr ${WIREGUARD_IPv4_SUBNET} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" oifname "${NETWORK_INTERFACE}" ip6 saddr ${WIREGUARD_IPv6_SUBNET} accept
# Example: allows VPN clients to browse Internet through server NAT

# ---------------------
# Filter rules
# ---------------------
nft add table inet "${WIREGUARD_TABLE_NAME}"

nft add chain inet "${WIREGUARD_TABLE_NAME}" forward '{ type filter hook forward priority filter; policy drop; }'
# Default drop

# 1) Drop invalid packets from wg0 only
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ct state invalid drop

# 2) Allow established/related connections
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ct state related,established accept

# 3) Allow WireGuard server UDP port (only service on internal net)
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" udp dport ${WIREGUARD_VPN_PORT} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" udp dport ${WIREGUARD_VPN_PORT} accept

# 4) Block ALL other traffic to server internal IPs from VPN clients
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "${WIREGUARD_HOST_IPV4}" drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "${WIREGUARD_HOST_IPV6}" drop

# 5) Block VPN client → VPN client communication
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ip saddr ${WIREGUARD_IPv4_SUBNET} ip daddr ${WIREGUARD_IPv4_SUBNET} drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward ip6 saddr ${WIREGUARD_IPv6_SUBNET} ip6 daddr ${WIREGUARD_IPv6_SUBNET} drop

# 6) Block VPN clients → Private LANs (so they cannot reach *any* local/internal services)
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip daddr "{ ${PRIVATE_LOCAL_IPV4_SUBNET} }" drop
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" ip6 daddr "{ ${PRIVATE_LOCAL_IPV6_SUBNET} }" drop

# 7) Allow VPN clients → Internet (everything outside local/private ranges)
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" oifname "${NETWORK_INTERFACE}" ip saddr ${WIREGUARD_IPv4_SUBNET} accept
nft add rule inet "${WIREGUARD_TABLE_NAME}" forward iifname "${WIREGUARD_INTERFACE}" oifname "${NETWORK_INTERFACE}" ip6 saddr ${WIREGUARD_IPv6_SUBNET} accept

# ---------------------
# Show final rules
# ---------------------
nft list ruleset
# Example: prints all active nftables rules to check
