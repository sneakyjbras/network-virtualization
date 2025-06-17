#!/bin/bash
set -e

# Configurable
NS_NAME="examplens"
VETH_HOST="veth0"
VETH_NS="veth1"
IP_HOST="10.0.0.1/24"
IP_NS="10.0.0.2/24"

# Clean up any previous run
ip netns delete $NS_NAME 2>/dev/null || true
ip link delete $VETH_HOST 2>/dev/null || true

# Create namespace
ip netns add $NS_NAME

# Create veth pair
ip link add $VETH_HOST type veth peer name $VETH_NS

# Move one side to the namespace
ip link set $VETH_NS netns $NS_NAME

# Assign IPs
ip addr add $IP_HOST dev $VETH_HOST
ip netns exec $NS_NAME ip addr add $IP_NS dev $VETH_NS

# Bring interfaces up
ip link set $VETH_HOST up
ip netns exec $NS_NAME ip link set $VETH_NS up
ip netns exec $NS_NAME ip link set lo up

# Test connectivity (from default to namespace)
echo "Testing ping from default namespace to $NS_NAME..."
ping -c 4 10.0.0.2

echo "Testing ping from $NS_NAME to default namespace..."
ip netns exec $NS_NAME ping -c 4 10.0.0.1

