#!/bin/bash
# run_lab3b_all_in_one_improved.sh - Enhanced orchestration for Lab3B
# Usage: sudo bash run_lab3b_all_in_one_improved.sh

set -e
trap 'cleanup_on_failure' ERR

echo "=== Lab3B Full Orchestration Script (Improved) ==="
cd "$(dirname "$0")"

# Function: cleanup on failure
cleanup_on_failure() {
  echo "⚠️ An error occurred. Cleaning up Terraform-managed resources..."
  terraform destroy -auto-approve -input=false || true
  exit 1
}

# Function: initialize Terraform
initialize() {
  echo
  echo ">>> Terraform init (locking providers):"
  terraform init -input=false
  # Check for lock file
  if [ ! -f .terraform.lock.hcl ]; then
    echo "❌ Terraform lock file missing!" >&2
    exit 1
  fi
}

# Function: format check
format_check() {
  echo
  echo ">>> Checking Terraform formatting:"
  terraform fmt -check
}

# Function: deploy initial infra
deploy() {
  format_check

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
  sleep 5

  echo
  echo ">>> Testing load balancing from client:"
  for i in {1..4}; do
    echo -n "Request $i: "
    if ! docker exec client curl -s haproxy:80 | head -n1; then
      echo "   ✖ Load balancing test failed!" >&2
      exit 1
    else
      echo "   ✔ OK"
    fi
  done

  echo
  echo ">>> Testing host access via port 8080:"
  if ! curl -s http://localhost:8080 | head -n1; then
    echo "   ✖ Host access test failed!" >&2
    exit 1
  else
    echo "   ✔ OK"
  fi
}

# Function: resilience test
resilience_test() {
  echo
  echo ">>> Resilience test: stopping web2"
  docker stop web2
  sleep 2
  echo ">>> Request after stopping web2:"
  if ! docker exec client curl -s haproxy:80 | head -n1; then
    echo "   ✖ Resilience test failed!" >&2
    exit 1
  else
    echo "   ✔ OK"
  fi
  echo ">>> Restarting web2"
  docker start web2
  sleep 2
}

# Function: add web3 and reapply
add_web3() {
  echo
  echo ">>> Adding web3 resource to main.tf (idempotent)"
  if ! grep -q 'docker_container" "web3"' main.tf; then
    cat << 'EOF' >> main.tf

resource "docker_container" "web3" {
  name  = "web3"
  image = docker_image.web_img.name
  networks_advanced {
    name         = docker_network.labnet.name
    ipv4_address = "172.18.0.13"
  }
}
EOF
  else
    echo "   web3 resource already present, skipping."
  fi

  echo
  echo ">>> Adding web3 backend to haproxy.cfg (idempotent)"
  if ! grep -q 'server web3' haproxy.cfg; then
    echo "    server web3 172.18.0.13:80 check" >> haproxy.cfg
  else
    echo "   web3 backend already present, skipping."
  fi

  echo
  echo ">>> Terraform plan for web3 addition (logged to plan_web3.log):"
  terraform plan -input=false | tee plan_web3.log

  echo
  echo ">>> Terraform apply for web3 addition (logged to apply_web3.log):"
  terraform apply -auto-approve -input=false | tee apply_web3.log
}

# Main execution flow
initialize
deploy
test_lb
resilience_test
add_web3

echo
echo ">>> Testing load balancing with web3 added:"
for i in {1..6}; do
  echo -n "Request $i: "
  if ! docker exec client curl -s haproxy:80 | head -n1; then
    echo "   ✖ Load balancing with web3 failed!" >&2
    exit 1
  else
    echo "   ✔ OK"
  fi
done

echo
echo ">>> Cleaning up Terraform-managed resources..."
terraform destroy -auto-approve -input=false

echo
echo "=== Lab3B full orchestration complete ==="
