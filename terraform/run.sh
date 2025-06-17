#!/usr/bin/env bash
# run_lab3b_all_in_one_improved.sh - Enhanced orchestration for Lab3B
# Usage: sudo bash run_lab3b_all_in_one_improved.sh

trap 'cleanup_on_failure' ERR

NET_NAME="lab3b_net"
TF_RES="docker_network.labnet"

echo "=== Lab3B Full Orchestration Script (Improved) ==="
cd "$(dirname "$0")"

# Function: cleanup on failure
cleanup_on_failure() {
  echo "⚠ An error occurred. Cleaning up Terraform-managed resources..."
  terraform destroy -auto-approve -input=false || true
  exit 1
}

# Function: initialize Terraform
initialize() {
  echo
  echo ">>> Terraform init (locking providers):"
  terraform init -input=false
  if [ ! -f .terraform.lock.hcl ]; then
    echo "❌ Terraform lock file missing!" >&2
    exit 1
  fi
}

# Function: import existing Docker network if present
import_network() {
  echo
  echo ">>> Checking for existing Docker network '${NET_NAME}'…"
  if docker network inspect "$NET_NAME" >/dev/null 2>&1; then
    if ! terraform state show "$TF_RES" >/dev/null 2>&1; then
      echo "🔄 Importing existing Docker network '${NET_NAME}' into Terraform state…"
      terraform import "$TF_RES" "$NET_NAME"
    else
      echo "✅ '${NET_NAME}' already managed in state."
    fi
  else
    echo "ℹ️  Docker network '${NET_NAME}' not found; Terraform will create it."
  fi
}

# Function: import existing Docker containers if present
import_containers() {
  echo
  echo ">>> Checking for existing Docker containers…"
  for NAME in web1 web2 haproxy client; do
    CON_ID=$(docker inspect --format='{{.Id}}' "$NAME" 2>/dev/null || true)
    if [ -n "$CON_ID" ]; then
      if ! terraform state show "docker_container.${NAME}" >/dev/null 2>&1; then
        echo "🔄 Importing container '${NAME}' (ID=${CON_ID}) into Terraform state…"
        terraform import "docker_container.${NAME}" "$CON_ID"
      else
        echo "✅ Container '${NAME}' already managed in state."
      fi
    else
      echo "ℹ️  Container '${NAME}' not found; Terraform will create it."
    fi
  done
}

# Function: generate a fresh haproxy.cfg using DNS names
generate_haproxy_cfg() {
  echo
  echo ">>> Generating haproxy.cfg for web1/web2"
  cat > haproxy.cfg << 'EOF'
global
    daemon
    maxconn 256

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http_front
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web1 web1:80 check
    server web2 web2:80 check
EOF
}

# Function: HTTP check helper (from inside client), shows which server responded
check_url() {
  local DESC=$1 TARGET=$2
  echo
  echo ">>> Testing $DESC from client:"
  for i in {1..4}; do
    # fetch full response body
    resp=$(docker exec client curl -s "$TARGET")
    # extract HTTP status
    code=$(docker exec client curl -s -o /dev/null -w "%{http_code}" "$TARGET")
    # pull out the <h1> line, which your web image uses to identify itself
    served_by=$(echo "$resp" | grep -oP '(?<=<h1>)[^<]+' || echo "unknown")
    if [ "$code" != "200" ]; then
      echo "   ✖ Request $i failed (HTTP $code)" >&2
      exit 1
    else
      echo "   ✔ Request $i OK (HTTP $code) — served by: $served_by"
    fi
  done
}

# Function: HTTP check helper on the host, shows which server responded
check_host_url() {
  local DESC=$1 URL=$2
  echo
  echo ">>> Testing $DESC on host:"
  for i in {1..4}; do
    resp=$(curl -s "$URL")
    code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
    served_by=$(echo "$resp" | grep -oP '(?<=<h1>)[^<]+' || echo "unknown")
    if [ "$code" != "200" ]; then
      echo "   ✖ Host request $i failed (HTTP $code)" >&2
      exit 1
    else
      echo "   ✔ Host request $i OK (HTTP $code) — served by: $served_by"
    fi
  done
}

# Function: check Terraform format
format_check() {
  echo
  echo ">>> Checking Terraform formatting:"
  terraform fmt -check
}

# Function: deploy initial infra
deploy() {
  format_check
  generate_haproxy_cfg

  echo
  echo ">>> Terraform plan (logged to plan.log):"
  terraform plan -input=false | tee plan.log

  echo
  echo ">>> Terraform apply (logged to apply.log):"
  terraform apply -auto-approve -input=false | tee apply.log
}

# Function: test connectivity and load balancing
test_lb() {
  echo
  echo ">>> IP assignments:"
  echo "  - haproxy: 172.18.0.10"
  echo "  - web1:    172.18.0.11"
  echo "  - web2:    172.18.0.12"
  echo "  - client:  172.18.0.20"

  echo
  echo ">>> Waiting for containers to initialize..."
  sleep 2

  check_url "load balancing" haproxy:80
  check_host_url "host access via port 8080" http://localhost:8080
}

resilience_test() {
  echo
  echo ">>> Resilience test: stopping web2"
  docker stop web2
  sleep 2

  echo ">>> Requests after stopping web2 (via load balancer):"
  for i in {1..4}; do
    resp=$(docker exec client curl -s haproxy:80)
    code=$(docker exec client curl -s -o /dev/null -w "%{http_code}" haproxy:80)
    served_by=$(echo "$resp" | grep -oP '(?<=<h1>)[^<]+' || echo "unknown")
    if [ "$code" != "200" ]; then
      echo "   ✖ Request $i failed (HTTP $code)" >&2
    else
      echo "   ✔ Request $i OK (HTTP $code) — served by: $served_by"
    fi
  done

  echo ">>> Restarting web2"
  docker start web2
  sleep 2
}

# Function: add web3 and reapply
add_web3() {
  echo
  echo ">>> Regenerating HAProxy config to include web3…"
  generate_haproxy_cfg

  echo
  echo ">>> Terraform plan for web3 only (logged to plan_web3.log):"
  terraform plan \
    -var enable_web3=true \
    -target=docker_container.web3 \
    -input=false \
  | tee plan_web3.log

  echo
  echo ">>> Terraform apply for web3 only (logged to apply_web3.log):"
  terraform apply \
    -var enable_web3=true \
    -target=docker_container.web3 \
    -auto-approve \
    -input=false \
  | tee apply_web3.log
}

test_web3() {
  echo
  echo ">>> Testing load balancing with web3 added:"
  for i in {1..6}; do
    resp=$(docker exec client curl -s haproxy:80)
    code=$(docker exec client curl -s -o /dev/null -w "%{http_code}" haproxy:80)
    served_by=$(echo "$resp" | grep -oP '(?<=<h1>)[^<]+' || echo "unknown")
    if [ "$code" != "200" ]; then
      echo "   ✖ Request $i failed (HTTP $code)" >&2
      exit 1
    else
      echo "   ✔ Request $i OK (HTTP $code) — served by: $served_by"
    fi
  done
}

# --- Main execution flow ---
initialize
import_network
import_containers
deploy
test_lb
resilience_test
add_web3
test_web3

echo
echo ">>> Cleaning up Terraform-managed resources..."
terraform destroy -auto-approve -input=false

echo
echo "=== Lab3B full orchestration complete ==="
