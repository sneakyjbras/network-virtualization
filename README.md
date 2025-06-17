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

## Step 3: Management of the Docker Network

In this step, we encountered and resolved a conflict between Terraform and an existing Docker network named `lab3b_net`. Below is a detailed account of the problem, our chosen resolution path, verification steps, alternative strategies, and the lessons learned.

---

### 3.1 Issue Encountered

When invoking Terraform to apply our configuration:
```bash
terraform apply
```
we received the following error:
```text
Error: Unable to create network: 
network with name lab3b_net already exists
```
This indicates that Docker already had a network resource called `lab3b_net` which Terraform was unaware of, causing a naming conflict.

---

### 3.2 Why This Happens

- **Terraform’s State vs. Reality**  
  Terraform tracks resources in its state file (`terraform.tfstate`). If a resource exists in the real world (Docker) but is *not* recorded in the state, Terraform believes it needs to be created.
- **Docker’s Idempotency Model**  
  Unlike some cloud providers, Docker will not overwrite or merge networks with identical names; it will simply refuse to create a second network of the same name.

---

### 3.3 Chosen Resolution: Importing the Existing Network

Rather than deleting or renaming, we opted to **import** the existing network into Terraform’s state. This aligns the real-world resource with Terraform’s model, preserving any existing containers or links that depend on it.

1. **Inspect the network in Docker**  
   Verify that `lab3b_net` exists:
   ```bash
   docker network ls | grep lab3b_net
   ```
   You should see a line resembling:
   ```
   ab12cd34ef56   lab3b_net   bridge   local
   ```

2. **Define the Terraform resource**  
   Ensure your `main.tf` includes:
   ```hcl
   resource "docker_network" "labnet" {
     name   = "lab3b_net"
     driver = "bridge"
   }
   ```

3. **Initialize (if necessary)**  
   ```bash
   terraform init
   ```

4. **Import into state**  
   ```bash
   terraform import docker_network.labnet lab3b_net
   ```
   - **What happens under the hood?**  
     Terraform records the real Docker network’s unique ID into its state file, effectively “adopting” that network.

5. **Inspect the imported state**  
   ```bash
   terraform state show docker_network.labnet
   ```
   You should see output mapping fields such as `id`, `name`, and `driver`.

6. **Plan & Apply**  
   ```bash
   terraform plan
   terraform apply
   ```
   Now, `plan` should indicate “No changes. Infrastructure is up-to-date.” and `apply` will complete without errors.

---

### 3.4 Verification

- **Confirm Terraform-managed status**  
  The `terraform state list` command shows:
  ```bash
  $ terraform state list
  docker_network.labnet
  ```
- **Ensure no drift**  
  Running `terraform plan` again yields:
  ```text
  No changes. Infrastructure is up-to-date.
  ```
- **Test connectivity**  
  Launch a test container attached to `lab3b_net` to verify networking:
  ```bash
  docker run --rm --network lab3b_net busybox ping -c 1 <another-container>
  ```

---

### 3.5 Alternative Strategies

While importing is non-destructive, other approaches include:

1. **Manual Removal**  
   ```bash
   docker network rm lab3b_net
   terraform apply
   ```
   > *Risk:* Containers or services attached to the network may be disrupted.

2. **Rename in Terraform**  
   Change the `name` attribute in `main.tf`:
   ```hcl
   name = "lab3b_net_v2"
   ```
   Then apply.  
   > *Use case:* You need a fresh network without affecting the existing one.

---

### 3.6 Lessons Learned

- **State Awareness**  
  Always inspect existing infrastructure before provisioning to detect naming collisions.
- **Power of `terraform import`**  
  Enables seamless alignment of Terraform state with manually created or legacy resources.
- **Idempotency**  
  Proper state management guarantees that repeated `apply` operations are safe and predictable.
- **Documentation**  
  Clearly document import steps in your team’s runbooks to aid future troubleshooting.

---

By importing the Docker network rather than deleting or renaming it, we preserved existing service relationships, achieved full Terraform management of the resource, and maintained an idempotent, declarative infrastructure workflow.
