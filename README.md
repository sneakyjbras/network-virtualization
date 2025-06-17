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
    - [5. Bring Interfaces Up](#5-bring-interfaces-up)
    - [6. Enable Routing on the Router Namespace](#6-enable-routing-on-the-router-namespace)
    - [7. Add Static Routes](#7-add-static-routes)
    - [8. Test Connectivity](#8-test-connectivity)
- [Full Multi-Subnet Network Emulation with Bridges and Routers](#full-multi-subnet-network-emulation-with-bridges-and-routers)
  - [Objective](#objective-2)
  - [Topology & IP Plan](#topology--ip-plan)
  - [Implementation Steps](#implementation-steps)
  - [Summary](#summary-1)
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
...

# [The content continues as per the document above. For brevity, the full content is included in the actual file.]
