#!/bin/bash
set -e

# Clean slate
ip netns delete ns1 2>/dev/null || true
ip netns delete ns2 2>/dev/null || true
ip netns delete ns3 2>/dev/null || true
ip link delete veth0 2>/dev/null || true
ip link delete veth2 2>/dev/null || true

# Create namespaces
ip netns add ns1
ip netns add ns2
ip netns add ns3

# Create veth pairs
ip link add veth0 type veth peer name veth1
ip link add veth2 type veth peer name veth3

# Connect veth1 <-> ns1
ip link set veth1 netns ns1
# Connect veth0 <-> ns2
ip link set veth0 netns ns2

# Connect veth2 <-> ns2
ip link set veth2 netns ns2
# Connect veth3 <-> ns3
ip link set veth3 netns ns3

# Assign IPs
# ns1 side
ip netns exec ns1 ip addr add 10.0.1.1/24 dev veth1
ip netns exec ns1 ip link set veth1 up
ip netns exec ns1 ip link set lo up

# ns2 sides
ip netns exec ns2 ip addr add 10.0.1.2/24 dev veth0
ip netns exec ns2 ip addr add 10.0.2.1/24 dev veth2
ip netns exec ns2 ip link set veth0 up
ip netns exec ns2 ip link set veth2 up
ip netns exec ns2 ip link set lo up

# ns3 side
ip netns exec ns3 ip addr add 10.0.2.2/24 dev veth3
ip netns exec ns3 ip link set veth3 up
ip netns exec ns3 ip link set lo up

# Enable IP forwarding on ns2 (router)
ip netns exec ns2 sysctl -w net.ipv4.ip_forward=1

# Set up routes
# ns1: route to ns3 via ns2
ip netns exec ns1 ip route add 10.0.2.0/24 via 10.0.1.2

# ns3: route to ns1 via ns2
ip netns exec ns3 ip route add 10.0.1.0/24 via 10.0.2.1

# Test connectivity
echo -e "\n➡️ Testing ping from ns1 to ns3 (across ns2)..."
ip netns exec ns1 ping -c 4 10.0.2.2

echo -e "\n⬅️ Testing ping from ns3 to ns1 (across ns2)..."
ip netns exec ns3 ping -c 4 10.0.1.1

