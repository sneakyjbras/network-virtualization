# Linux Namespace Networking and Terraform Deployment Experiments

## Table of Contents

- [Introduction](#introduction)
- [Two-Node Network with Linux Namespaces and Veth](#two-node-network-with-linux-namespaces-and-veth)
  - [Objective](#objective)
  - [Network Topology](#network-topology)
  - [Steps Performed](#steps-performed)
    - [1. Create Namespace](#1-create-namespace)
    - [2. Create veth Pair](#2-create-veth-pair)
    - [3. Assign Interfaces to Namespace](#3-assign-interfaces-to-namespace)
    - [4. Assign IP Addresses](#4-assign-ip-addresses)
    - [5. Bring Interfaces Up](#5-bring-interfaces-up)
    - [6. Test Connectivity](#6-test-connectivity)
  - [Summary](#summary)
- [Three-Node Network with Namespaces and Static Routing](#three-node-network-with-namespaces-and-static-routing)
  - [Objective](#objective-1)
  - [Network Topology](#network-topology-1)
  - [Steps Performed](#steps-performed-1)
    - [1. Cleanup](#1-cleanup)
    - [2. Create Namespaces](#2-create-namespaces)
    - [3. Create veth Pairs](#3-create-veth-pairs)
    - [4. Assign IP Addresses](#4-assign-ip-addresses)
    - [5. Bring Interfaces Up](#5-bring-interfaces-up-1)
    - [6. Enable Routing on the Router Namespace](#6-enable-routing-on-the-router-namespace)
    - [7. Add Static Routes](#7-add-static-routes)
    - [8. Test Connectivity](#8-test-connectivity-1)
  - [Summary](#summary-1)
- [Full Multi-Subnet Network Emulation with Bridges and Routers](#full-multi-subnet-network-emulation-with-bridges-and-routers)
  - [Objective](#objective-2)
  - [Topology & IP Plan](#topology--ip-plan)
  - [Implementation Steps](#implementation-steps)
  - [Summary](#summary-2)
- [Docker Container Deployment with Terraform (Load Balancer & Web Servers)](#docker-container-deployment-with-terraform-load-balancer--web-servers)
  - [Overview](#overview)
  - [Terraform Workflow and Infrastructure Setup](#terraform-workflow-and-infrastructure-setup)
  - [IP Address Allocation](#ip-address-allocation)
  - [Web Server Accessibility Testing](#web-server-accessibility-testing)
  - [Load Balancer Request Distribution](#load-balancer-request-distribution)
  - [Port Mapping and Browser Access](#port-mapping-and-browser-access)
  - [Resilience to a Backend Server Failure](#resilience-to-a-backend-server-failure)
  - [Scaling Out to Three Web Servers](#scaling-out-to-three-web-servers)
  - [Evaluation of Design Choices](#evaluation-of-design-choices)

## Introduction

Linux network **namespaces** provide isolated networking contexts within a single Linux host, allowing the simulation of multiple separate networked nodes in user space. In combination with **virtual Ethernet (veth)** pairs (which act as virtual patch cables), one can construct complex network topologies without any physical hardware. These experiments demonstrate a progressive approach to virtual networking using namespaces and veth interfaces, starting from a simple two-node link and expanding to a multi-node routed network with bridges (simulated switches). Finally, a container-based deployment is managed with **Docker** and **Terraform**, illustrating how similar networking concepts apply to container networks in a declarative infrastructure setup.

The objectives of these experiments are to explore how isolated network stacks can communicate through virtual links, to practice setting up static routing and bridging in a fully virtual environment, and to evaluate the use of infrastructure-as-code tools for deploying networked services. Each phase builds on the previous, moving from fundamental namespace connectivity to more complex scenarios including multiple subnets, routers, and an automated containerized environment. All configurations are performed in Linux user space, making the experiments reproducible and safe to run on a single host.

## Two-Node Network with Linux Namespaces and Veth

### 🧠 Objective

Simulate a minimal network with **two nodes**: the default (global) network namespace and one additional Linux network namespace, connected by a point-to-point link using a **veth pair**. This will verify that two isolated namespaces can communicate when linked and properly configured.

### 🖼️ Network Topology

```
[default namespace] <---> [examplens]
       veth0               veth1
   10.0.0.1/24         10.0.0.2/24
```

- `veth0` resides in the default namespace (representing the first node).  
- `veth1` is moved into the `examplens` namespace (representing the second node).  
- Both interfaces form the two ends of a virtual Ethernet cable linking the two nodes.

### ⚙️ Steps Performed

#### 1. Create Namespace

A new network namespace called `examplens` is created to represent the second node in isolation.

```bash
ip netns add examplens
```

#### 2. Create veth Pair

A pair of virtual Ethernet interfaces is created. These two endpoints (named `veth0` and `veth1`) form a connected pair, functioning as a virtual link between the default namespace and the new `examplens` namespace.

```bash
ip link add veth0 type veth peer name veth1
```

#### 3. Assign Interfaces to Namespace

One end of the veth pair is moved into the new namespace so that each namespace holds one end of the virtual link.

```bash
ip link set veth1 netns examplens
```

#### 4. Assign IP Addresses

IP addresses are assigned in the same subnet to each veth endpoint, allowing IP-level connectivity.

```bash
ip addr add 10.0.0.1/24 dev veth0
ip netns exec examplens ip addr add 10.0.0.2/24 dev veth1
```

#### 5. Bring Interfaces Up

Both veth endpoints and the loopback interface in the new namespace are activated so that the link becomes operational.

```bash
ip link set veth0 up
ip netns exec examplens ip link set veth1 up
ip netns exec examplens ip link set lo up
```

#### 6. Test Connectivity

Bidirectional connectivity is confirmed with ICMP echo requests.

```bash
ping -c 4 10.0.0.2
ip netns exec examplens ping -c 4 10.0.0.1
```

### Summary

- A veth pair simulated a physical link.  
- One end was moved into a separate namespace.  
- IPs were configured and interfaces brought up.  
- Successful pings in both directions verified connectivity.

## Three-Node Network with Namespaces and Static Routing

### 🧠 Objective

Extend the virtual network to **three nodes** in a linear topology. One node (`ns2`) will function as a router interconnecting two subnets via static routing and IP forwarding.

### 🖼️ Network Topology

```
[ns1] <---> [ns2] <---> [ns3]
   |           |           |
 veth1       veth0       veth2
   |           |           |
10.0.1.1   10.0.1.2   10.0.2.1   10.0.2.2
```

- `ns1` and `ns3` are endpoints on separate subnets.  
- `ns2` routes between subnets 10.0.1.0/24 and 10.0.2.0/24.

### ⚙️ Steps Performed

#### 1. Cleanup

Any existing namespaces or veth interfaces are removed to ensure a pristine environment.

#### 2. Create Namespaces

```bash
ip netns add ns1
ip netns add ns2
ip netns add ns3
```

#### 3. Create veth Pairs

```bash
ip link add veth0 type veth peer name veth1
ip link add veth2 type veth peer name veth3
```

Interfaces are assigned:

```bash
ip link set veth1 netns ns1
ip link set veth0 netns ns2
ip link set veth2 netns ns2
ip link set veth3 netns ns3
```

#### 4. Assign IP Addresses

```bash
ip netns exec ns1 ip addr add 10.0.1.1/24 dev veth1
ip netns exec ns2 ip addr add 10.0.1.2/24 dev veth0
ip netns exec ns2 ip addr add 10.0.2.1/24 dev veth2
ip netns exec ns3 ip addr add 10.0.2.2/24 dev veth3
```

#### 5. Bring Interfaces Up

```bash
ip netns exec ns1 ip link set veth1 up
ip netns exec ns2 ip link set veth0 up
ip netns exec ns2 ip link set veth2 up
ip netns exec ns3 ip link set veth3 up
ip netns exec ns1 ip link set lo up
ip netns exec ns2 ip link set lo up
ip netns exec ns3 ip link set lo up
```

#### 6. Enable Routing on the Router Namespace

```bash
ip netns exec ns2 sysctl -w net.ipv4.ip_forward=1
```

#### 7. Add Static Routes

```bash
ip netns exec ns1 ip route add 10.0.2.0/24 via 10.0.1.2
ip netns exec ns3 ip route add 10.0.1.0/24 via 10.0.2.1
```

#### 8. Test Connectivity

```bash
ip netns exec ns1 ping -c 4 10.0.2.2
ip netns exec ns3 ping -c 4 10.0.1.1
```

### Summary

- Three namespaces connected by veth.  
- IP forwarding enabled on `ns2`.  
- Static routes configured.  
- End-to-end pings confirmed routing functionality.

## Full Multi-Subnet Network Emulation with Bridges and Routers

### 🧠 Objective

Simulate a multi-router environment with seven host namespaces (H1–H7), two routers (R1, R2), and three LAN segments bridged by Linux bridges.

### 🖼️ Topology & IP Plan

| Segment | Bridge | Subnet       | Devices              |
|---------|--------|--------------|----------------------|
| A       | brA    | 10.0.1.0/24  | H1 (10.0.1.11), H2 (10.0.1.12) |
| B       | brB    | 10.0.2.0/24  | H5 (10.0.2.51), H6 (10.0.2.52), H7 (10.0.2.53) |
| C       | brC    | 10.0.3.0/24  | H3 (10.0.3.31), H4 (10.0.3.32) |
| D (core)| none   | 10.0.4.0/30  | R1↔R2 core link     |

### ⚙️ Implementation Steps

```bash
# Full setup and connectivity test outline:

echo "=== Cleanup ==="
# Remove existing namespaces, veths, and bridges.

echo "=== Create namespaces ==="
# Create H1–H7, R1, R2.

echo "=== Create bridges A, B, C ==="
# Create brA, brB, brC.

echo "=== Attach hosts to bridges ==="
# For each host, create and attach veth pair to appropriate bridge.

echo "=== Routers & core link ==="
# Attach R1 to brA and brB; R2 to brC.
# Create veth pair for core link between R1 and R2.

echo "=== IP addressing & bring-up ==="
# Assign IPs as per plan; bring interfaces and bridges up.

echo "=== Enable routing ==="
# Enable IPv4 forwarding on R1 and R2.

echo "=== Static routes ==="
# Hosts: default route via respective router.
# Routers: routes to other LANs via core link.

echo "=== Connectivity Tests ==="
# Ping between hosts on different segments to verify routing.
```

### Summary

- Emulated LAN segments with Linux bridges.  
- Connected hosts and routers via veth.  
- Enabled routing and static routes.  
- Verified inter-LAN connectivity across R1 and R2.

## Docker Container Deployment with Terraform (Load Balancer & Web Servers)

### Overview

Terraform was used to deploy two web server containers (`web1`, `web2`) and one Nginx load balancer container (`load_balancer`) on Docker. A test script (`run.sh`) validated connectivity, load balancing behavior, resilience, and scaling.

### Terraform Workflow and Infrastructure Setup

```bash
terraform init
terraform plan
terraform apply -auto-approve
terraform destroy -auto-approve
```

- **init:** downloads provider and prepares state.  
- **plan:** previews infrastructure changes.  
- **apply:** provisions containers and network.  
- **destroy:** cleans up resources.

### IP Address Allocation

| Container         | Internal IP  | Host Port Mapping   |
|-------------------|--------------|---------------------|
| **web1**          | 172.18.0.2   | —                   |
| **web2**          | 172.18.0.3   | —                   |
| **load_balancer** | 172.18.0.4   | 8080 → 80           |

### Web Server Accessibility Testing

```bash
curl http://172.18.0.2
curl http://172.18.0.3
```

Both servers responded correctly, confirming reachability.

### Load Balancer Request Distribution

```bash
for i in {1..4}; do curl -s http://172.18.0.4; echo; done
```

Responses alternated between Web Server 1 and 2, demonstrating round-robin distribution.

### Port Mapping and Browser Access

- Host port 8080 is mapped to LB container port 80.  
- Access via `http://localhost:8080/` shows alternating content in a browser.

### Resilience to a Backend Server Failure

```bash
docker stop web1
for i in {1..3}; do curl -s http://localhost:8080; echo; done
```

All responses came from Web Server 2 only, showing LB resilience.

### Scaling Out to Three Web Servers

1. Update Terraform config:

```diff
-count = 2
+count = 3
 message = "Web Server ${count.index + 1}"
```

2. Apply changes:

```bash
terraform plan
terraform apply
```

3. Verify distribution:

```bash
for i in {1..6}; do curl -s http://localhost:8080; echo; done
```

Responses cycled through Web Server 1, 2, 3.

### Evaluation of Design Choices

| Decision                              | Pros                                                                        | Cons / Alternatives                                                                                |
|---------------------------------------|-----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Terraform + Docker provider           | Declarative, reproducible, stateful; easy teardown                          | Tightly coupled to Docker; consider Kubernetes or cloud LB for production scalability.             |
| `count` for scaling                   | Simple numeric scaling                                                      | Lacks descriptive resource naming; modules or dynamic blocks offer more maintainability.           |
| Nginx load balancer in container      | Lightweight and familiar; quick deployment                                  | Single point of failure; HAProxy or multiple LB instances provide better high availability.       |
| Bash test script (`run.sh`)           | Quick sanity checks; integrates with apply                                  | Not part of CI/CD; Terratest or similar frameworks enable automated integration testing.           |

*End of Report.*
