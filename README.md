# Lab 4.1 – Two-Node Network (Namespaces and Veth)

## 🧠 Objective

Simulate a network with **two nodes**: the default (global) namespace and one Linux network namespace using a **veth pair**.

---

## 🖼️ Network Topology

```
[default namespace] <---> [examplens]
       veth0               veth1
   10.0.0.1/24         10.0.0.2/24
```

- `veth0` remains in the default namespace.
- `veth1` is moved into the `examplens` namespace.

---

## ⚙️ Steps Performed

### 1. Create Namespace
```bash
ip netns add examplens
```

### 2. Create veth Pair
```bash
ip link add veth0 type veth peer name veth1
```

### 3. Assign Interfaces to Namespaces
```bash
ip link set veth1 netns examplens
```

### 4. Assign IP Addresses
```bash
ip addr add 10.0.0.1/24 dev veth0
ip netns exec examplens ip addr add 10.0.0.2/24 dev veth1
```

### 5. Bring Interfaces Up
```bash
ip link set veth0 up
ip netns exec examplens ip link set veth1 up
ip netns exec examplens ip link set lo up
```

### 6. Test Connectivity
```bash
ping -c 4 10.0.0.2
ip netns exec examplens ping -c 4 10.0.0.1
```

---

## ✅ Summary

- Created a veth pair to simulate a point-to-point link.
- Moved one end of the pair into a namespace.
- Assigned IPs and tested connectivity between namespaces.

---

# Lab 4.2 – Three-Node Network (Namespaces and Routing)

## 🧠 Objective

Simulate a linear network with **three nodes** using **Linux namespaces** and **virtual Ethernet interfaces** (`veth`). One node acts as a router to enable connectivity between the two endpoints.

---

## 🖼️ Network Topology

```
[ns1] <---> [ns2] <---> [ns3]
   |           |           |
 veth1       veth0       veth2
   |           |           |
10.0.1.1   10.0.1.2   10.0.2.1   10.0.2.2
```

- `ns1` and `ns3` are endpoint hosts.
- `ns2` is a **router** connecting two subnets:
  - `10.0.1.0/24` between `ns1` and `ns2`
  - `10.0.2.0/24` between `ns2` and `ns3`

---

## ⚙️ Steps Performed

### 1. Cleanup
Ensure a clean environment by deleting any previously created namespaces or interfaces.

### 2. Create Namespaces
```bash
ip netns add ns1
ip netns add ns2
ip netns add ns3
```

### 3. Create veth Pairs
Two `veth` pairs are created to simulate physical links:
- `veth0 <-> veth1`
- `veth2 <-> veth3`

Interfaces are then assigned to namespaces:
- `veth1 → ns1`
- `veth0` and `veth2 → ns2`
- `veth3 → ns3`

### 4. Assign IP Addresses
Each interface receives an IP:
- `ns1`: `10.0.1.1/24` on `veth1`
- `ns2`: `10.0.1.2/24` on `veth0`, `10.0.2.1/24` on `veth2`
- `ns3`: `10.0.2.2/24` on `veth3`

### 5. Bring Interfaces Up
Interfaces and loopback devices are activated using:
```bash
ip link set <interface> up
```

### 6. Enable Routing on ns2
To allow packet forwarding:
```bash
ip netns exec ns2 sysctl -w net.ipv4.ip_forward=1
```

### 7. Add Static Routes
Static routes are added manually to reach remote subnets:
- In `ns1`:
  ```bash
  ip route add 10.0.2.0/24 via 10.0.1.2
  ```
- In `ns3`:
  ```bash
  ip route add 10.0.1.0/24 via 10.0.2.1
  ```

### 8. Test Connectivity
Use `ping` to confirm bidirectional communication:
- From `ns1` to `ns3`: passes through `ns2`
- From `ns3` to `ns1`: response routed back through `ns2`

---

## Part 4.3 – Full Network Emulation

### 🧠 Objective  
Emulate the full multi-subnet topology with **seven hosts** (H1–H7), **two routers** (R1, R2), and **three LAN segments** bridged as switches.

### 🖼️ Topology & IP Plan

| Segment | Bridge | Subnet       | Devices                  |
|---------|--------|--------------|--------------------------|
| A       | brA    | 10.0.1.0/24  | H1 (10.0.1.11), H2 (10.0.1.12)  |
| B       | brB    | 10.0.2.0/24  | H5 (10.0.2.51), H6 (10.0.2.52), H7 (10.0.2.53) |
| C       | brC    | 10.0.3.0/24  | H3 (10.0.3.31), H4 (10.0.3.32)         |
| D (core)| none   | 10.0.4.0/30  | R1↔R2 core link         |

```bash
# Full setup + connectivity tests (lab3a_part3_with_tests.sh)

set -e

echo "=== Cleanup ==="
# Remove namespaces, bridges, veths...

echo "=== Create namespaces ==="
# H1–H7, R1, R2

echo "=== Create bridges A, B, C ==="
# brA, brB, brC

echo "=== Attach hosts to bridges ==="
# veth pairs Hx<->bHx

echo "=== Routers & core link ==="
# R1↔brA/brB, R2↔brC, core R1D↔R2D

echo "=== IP addressing & bring-up ==="
# Assign IPs and bring interfaces up

echo "=== Enable routing ==="
# sysctl inside R1, R2

echo "=== Static routes ==="
# default routes on hosts
# inter-router routes

echo "=== Connectivity Tests ==="
# Ping H1↔H4, H7↔H2, etc.
```

---

## ✅ Summary

- **Namespaces** simulate isolated network nodes.
- **veth pairs** simulate physical links between those nodes.
- **Static routing** and **IP forwarding** allow cross-namespace communication.
- This lab emulates a basic **routed network**, completely in Linux userspace.

# Deployment & Testing Report

## Overview
This report correlates the Terraform configuration (`main.tf`) and the test automation script (`run.sh`) with the lab requirements outlined in Step 5. It explains what we did, how each action answers the lab questions, and evaluates the design choices made.

---

## 1. Terraform Workflow & Explanations

```bash
# Initialize the working directory
terraform init
```
- **What we did:** Initialized Terraform, downloaded providers, and set up the backend.
- **Why it matters:** Prepares the environment for planning and applying infrastructure changes.

```bash
terraform plan
```
- **What we did:** Generated an execution plan without making changes.
- **Why it matters:** Verifies that the configuration is syntactically correct and shows intended actions (initial deploy, no-drift checks).

```bash
terraform apply -auto-approve
```
- **What we did:** Applied the plan to create two web containers (`web1`, `web2`) and one load balancer (`lb`).
- **Why it matters:** Deploys the infrastructure in a declarative, repeatable manner.

```bash
terraform destroy -auto-approve
```
- **What we did:** Cleaned up all created Docker containers.
- **Why it matters:** Ensures no resources are left running and Terraform state matches reality.

> **Correlation with `run.sh`:** The script automates connectivity tests after deployment, invoked immediately following `terraform apply`.

---

## 2. IP Addresses Assigned

| Resource        | Container IP    | Host Port Mapping |
|-----------------|-----------------|-------------------|
| **web1**        | `172.18.0.2`    | —                 |
| **web2**        | `172.18.0.3`    | —                 |
| **load_balancer** | `172.18.0.4`    | `8080 → 80`       |

- **How we gathered this:**  
  - `docker inspect` or `terraform state show`  
  - Confirmed via `run.sh` outputs (it echoes IPs before testing).

---

## 3. Web Servers Accessibility

```bash
# From client host
curl http://172.18.0.2    # Expect Web Server 1
curl http://172.18.0.3    # Expect Web Server 2
```
- **What we did:** Tested direct connectivity to each backend.
- **Lab Q3 Answered:** Demonstrates that both web servers are running and reachable.

---

## 4. Load Balancer Distribution

```bash
# Round-robin check
for i in {1..4}; do curl -s http://172.18.0.4; echo; done
```
- **What we saw:** Alternating responses:
  ```
  <h1>Web Server 1</h1>
  <h1>Web Server 2</h1>
  <h1>Web Server 1</h1>
  <h1>Web Server 2</h1>
  ```
- **Lab Q4 Answered:** Confirms correct request distribution by Nginx LB.

---

## 5. Port Mapping & Browser Testing

- **Port mapping:** `8080` on host ↔ `80` in LB container.
- **Browser URL:** `http://localhost:8080/`
- **What we did:**  
  - Visited in browser.  
  - Observed the same round-robin behavior (steps mirrored with `curl`).
- **Lab Q5–Q6 Answered:** Validates host-to-container port mapping for browser access.

---

## 6. Resilience: Single-Server Down

```bash
docker stop web1      # Simulate failure of Server 1
for i in {1..3}; do curl -s http://localhost:8080; echo; done
```
- **Observed:** All responses from Web Server 2 only.
- **Lab Q7 Answered:** Shows LB resilience—continues serving traffic when one backend is down.

---

## 7. Scaling to Three Web Servers

1. **Terraform change:**  
   ```diff
   resource "docker_container" "web" {
     count = 2
   - message = "Web Server ${count.index + 1}"
   + count   = 3
   + message = "Web Server ${count.index + 1}"
   ```
2. **Commands:**  
   ```bash
   terraform plan    # Detects addition of web[2]
   terraform apply   # Creates web3 without destroying existing
   ```
3. **Verification:**  
   ```bash
   for i in {1..6}; do curl -s http://localhost:8080; echo; done
   ```
   - **Output cycle:** 1, 2, 3, 1, 2, 3
- **Lab Q8 Answered:** Demonstrates seamless incremental scaling via Terraform `count`.

---

## Evaluation of Design Choices

| Choice                                  | Pros                                                                 | Cons / Alternatives                                                           |
|-----------------------------------------|----------------------------------------------------------------------|-------------------------------------------------------------------------------|
| **Terraform + Docker provider**         | Declarative, reproducible, stateful                                   | Tightly couples infrastructure with Docker; consider higher-level orchestrators (e.g., Kubernetes) for real-world scale |
| **`count` for scaling**                 | Simple numeric scaling                                              | Lacks semantic clarity for complex deployments; modules or dynamic blocks could improve maintainability           |
| **Nginx-based LB in container**         | Lightweight, familiar configuration                                 | Single point of failure; production-grade LB (HAProxy, AWS ELB) offers better HA and metrics                       |
| **`run.sh` for testing**                | Quick, scriptable sanity checks                                      | Could integrate with CI/CD pipelines and automated testing frameworks (e.g., Terratest)                             |

---

*End of Report.*
