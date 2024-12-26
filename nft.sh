#!/bin/bash

# Define variables for network interface, subnets, and ports
TABLE_NAME="WIREGUARD_WG0"          # Name of the nftables table
NETWORK_INTERFACE="enxb827eb7c4fab" # Network interface (e.g., eth0)
IPV4_SUBNET="10.0.0.0/8"            # IPv4 subnet to be used for NAT
IPV6_SUBNET="fd00:00:00::0/8"       # IPv6 subnet to be used for NAT
DNS_PORT="53"                       # Port for DNS traffic
VPN_PORT="51820"                    # Port for WireGuard VPN

# Enable IP forwarding for both IPv4 and IPv6
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Create nftables table
nft add table inet $TABLE_NAME

# Add chains with default policies
nft add chain inet $TABLE_NAME PREROUTING { type nat hook prerouting priority 0 \; }
nft add chain inet $TABLE_NAME INPUT { type filter hook input priority 0 \; }
nft add chain inet $TABLE_NAME FORWARD { type filter hook forward priority 0 \; }
nft add chain inet $TABLE_NAME POSTROUTING { type nat hook postrouting priority 100 \; }

# Allow VPN traffic
nft add rule inet $TABLE_NAME INPUT ip protocol udp dport $VPN_PORT accept

# Prevent IP spoofing
nft add rule inet $TABLE_NAME INPUT ip saddr $IPV4_SUBNET accept
nft add rule inet $TABLE_NAME INPUT ip6 saddr $IPV6_SUBNET accept

# Allow established/related connections
nft add rule inet $TABLE_NAME FORWARD ct state established,related accept

# Allow DNS traffic for IPv4 (UDP and TCP)
nft add rule inet $TABLE_NAME INPUT ip protocol udp dport $DNS_PORT accept
nft add rule inet $TABLE_NAME INPUT ip protocol tcp dport $DNS_PORT accept

# Allow DNS traffic for IPv6 (UDP and TCP)
nft add rule inet $TABLE_NAME INPUT ip6 nexthdr udp dport $DNS_PORT accept
nft add rule inet $TABLE_NAME INPUT ip6 nexthdr tcp dport $DNS_PORT accept

# Allow DNS forwarding for IPv4 (UDP)
nft add rule inet $TABLE_NAME FORWARD ip protocol udp dport $DNS_PORT accept
nft add rule inet $TABLE_NAME FORWARD ip protocol udp sport $DNS_PORT accept

# Allow DNS forwarding for IPv6 (UDP)
nft add rule inet $TABLE_NAME FORWARD ip6 nexthdr udp dport $DNS_PORT accept
nft add rule inet $TABLE_NAME FORWARD ip6 nexthdr udp sport $DNS_PORT accept

# Drop all other traffic
nft add rule inet $TABLE_NAME INPUT drop
nft add rule inet $TABLE_NAME FORWARD drop

# NAT masquerading
nft add rule inet $TABLE_NAME POSTROUTING ip saddr $IPV4_SUBNET oifname $NETWORK_INTERFACE masquerade
nft add rule inet $TABLE_NAME POSTROUTING ip6 saddr $IPV6_SUBNET oifname $NETWORK_INTERFACE masquerade

# Comments explaining purpose
# This script ensures secure and minimal traffic rules with optimized order for efficiency.
