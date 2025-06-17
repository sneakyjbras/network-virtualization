#!/bin/bash
# lab3a_part3_fixed.sh - Full Network Emulation for Lab 4.3 (fixed interface bring-up)
# Usage: sudo bash lab3a_part3_fixed.sh

set -e

# --- Cleanup previous namespaces, bridges, and veths ---
echo "Cleaning up..."
# Delete namespaces
for ns in H1 H2 H3 H4 H5 H6 H7 R1 R2; do
    ip netns delete $ns 2>/dev/null || true
done

# Delete bridges
for br in brA brB brC; do
    ip link set $br down 2>/dev/null || true
    ip link delete $br type bridge 2>/dev/null || true
done

# Delete standalone veths
for v in vH1 vH2 vH3 vH4 vH5 vH6 vH7 vR1A vR1B vR1D vR2D vR2C bH1 bH2 bH3 bH4 bH5 bH6 bH7 bR1A bR1B bR2C; do
    ip link delete $v 2>/dev/null || true
done

echo "Cleanup done."

# --- 1. Create namespaces ---
for ns in H1 H2 H3 H4 H5 H6 H7 R1 R2; do
    ip netns add $ns
done

# --- 2. Create bridges (switches) ---
for br in brA brB brC; do
    ip link add name $br type bridge
    ip link set $br up
done

# --- 3. Create and attach veth pairs ---

# Hosts to bridges
declare -A host_br_map=( ["H1"]=brA ["H2"]=brA ["H5"]=brB ["H6"]=brB ["H7"]=brB ["H3"]=brC ["H4"]=brC )
for host in "${!host_br_map[@]}"; do
    br="${host_br_map[$host]}"
    veth_host="v${host}"
    veth_br="b${host}"
    ip link add "$veth_host" type veth peer name "$veth_br"
    ip link set "$veth_host" netns "$host"
    ip link set "$veth_br" master "$br"
    ip link set "$veth_br" up
done

# Routers to bridges
# R1-A <-> brA
ip link add vR1A type veth peer name bR1A
ip link set vR1A netns R1
ip link set bR1A master brA
ip link set bR1A up

# R1-B <-> brB
ip link add vR1B type veth peer name bR1B
ip link set vR1B netns R1
ip link set bR1B master brB
ip link set bR1B up

# R2-C <-> brC
ip link add vR2C type veth peer name bR2C
ip link set vR2C netns R2
ip link set bR2C master brC
ip link set bR2C up

# Core link R1-D <-> R2-D
ip link add vR1D type veth peer name vR2D
ip link set vR1D netns R1
ip link set vR2D netns R2

# --- 4. Assign IP addresses ---

# Hosts
ip netns exec H1 ip addr add 10.0.1.11/24 dev vH1
ip netns exec H2 ip addr add 10.0.1.12/24 dev vH2
ip netns exec H5 ip addr add 10.0.2.51/24 dev vH5
ip netns exec H6 ip addr add 10.0.2.52/24 dev vH6
ip netns exec H7 ip addr add 10.0.2.53/24 dev vH7
ip netns exec H3 ip addr add 10.0.3.31/24 dev vH3
ip netns exec H4 ip addr add 10.0.3.32/24 dev vH4

# Routers
ip netns exec R1 ip addr add 10.0.1.1/24 dev vR1A
ip netns exec R1 ip addr add 10.0.2.1/24 dev vR1B
ip netns exec R1 ip addr add 10.0.4.1/30 dev vR1D

ip netns exec R2 ip addr add 10.0.4.2/30 dev vR2D
ip netns exec R2 ip addr add 10.0.3.1/24 dev vR2C

# --- Bring up interfaces inside each namespace ---
for ns in H1 H2 H3 H4 H5 H6 H7 R1 R2; do
    # bring up loopback
    ip netns exec "$ns" ip link set lo up
    # bring up all veth interfaces (strip @ suffix)
    ip netns exec "$ns" bash -c 'for iface in $(ip -o link show | awk -F": " "{print \$2}" | cut -d@ -f1); do
        ip link set "$iface" up
    done'
done

# --- 5. Enable IP forwarding on routers ---
ip netns exec R1 sysctl -w net.ipv4.ip_forward=1 > /dev/null
ip netns exec R2 sysctl -w net.ipv4.ip_forward=1 > /dev/null

# --- 6. Configure static routes ---

# Hosts: default via local router
for h in H1 H2; do ip netns exec $h ip route add default via 10.0.1.1; done
for h in H5 H6 H7; do ip netns exec $h ip route add default via 10.0.2.1; done
for h in H3 H4; do ip netns exec $h ip route add default via 10.0.3.1; done

# R1: routes to subnets behind R2
ip netns exec R1 ip route add 10.0.3.0/24 via 10.0.4.2
# R2: routes to subnets behind R1
ip netns exec R2 ip route add 10.0.1.0/24 via 10.0.4.1
ip netns exec R2 ip route add 10.0.2.0/24 via 10.0.4.1

echo "Setup complete. Test connectivity (e.g., ping from H1 to H4)."


# --- 7. Connectivity Test ---
echo
echo "Testing connectivity between all hosts..."
declare -A ips=(
    [H1]=10.0.1.11
    [H2]=10.0.1.12
    [H5]=10.0.2.51
    [H6]=10.0.2.52
    [H7]=10.0.2.53
    [H3]=10.0.3.31
    [H4]=10.0.3.32
)

for src in "${!ips[@]}"; do
    for dst in "${!ips[@]}"; do
        if [ "$src" != "$dst" ]; then
            echo "➡️ $src -> $dst (${ips[$dst]})"
            ip netns exec $src ping -c 2 -W 1 ${ips[$dst]}                 && echo "   ✔ Success" || echo "   ✖ Failure"
            echo
        fi
    done
done

echo "All tests completed."
