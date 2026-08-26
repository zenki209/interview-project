#!/usr/bin/env bash
# Step 1: Install dependencies and start the minikube cluster.
# Run this once. After this succeeds, run 02-deploy-app.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ─── System Check ─────────────────────────────────────────────────────────────
check_requirements() {
  log_section "Checking System Requirements"

  local cpu_count ram_mb
  cpu_count=$(nproc)
  ram_mb=$(free -m | awk '/^Mem:/{print $2}')

  log_info "CPUs available  : ${cpu_count}"
  log_info "RAM available   : ${ram_mb} MB"

  if (( cpu_count < 2 )); then
    log_error "Need at least 2 CPUs. Found: ${cpu_count}"
    exit 1
  fi
  if (( ram_mb < 3500 )); then
    log_warn "Low RAM (${ram_mb} MB). Recommend ≥4 GB for a stable 2-node cluster."
  fi

  log_info "Requirements check passed."
}

# ─── Install Docker ───────────────────────────────────────────────────────────
install_docker() {
  log_section "Docker"

  if command -v docker &>/dev/null; then
    log_info "Already installed: $(docker --version)"
  else
    log_info "Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log_warn "Docker installed. You may need to log out and back in for group changes."
  fi

  if ! docker info &>/dev/null; then
    log_info "Docker daemon not reachable, attempting to start..."
    sudo systemctl start docker || log_warn "Could not start docker; ensure it is running."
    sleep 2
  fi

  log_info "Docker OK."
}

# ─── Install kubectl ──────────────────────────────────────────────────────────
install_kubectl() {
  log_section "kubectl"

  if command -v kubectl &>/dev/null; then
    log_info "Already installed: $(kubectl version --client 2>/dev/null | head -1)"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  log_info "Downloading kubectl..."
  local version
  version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo "$HOME/.local/bin/kubectl" \
    "https://dl.k8s.io/release/${version}/bin/linux/amd64/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
  log_info "kubectl ${version} installed to ~/.local/bin/kubectl"
}

# ─── Install minikube ─────────────────────────────────────────────────────────
install_minikube() {
  log_section "minikube"

  if command -v minikube &>/dev/null; then
    log_info "Already installed: $(minikube version --short 2>/dev/null)"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  log_info "Downloading minikube..."
  curl -fsSLo "$HOME/.local/bin/minikube" \
    "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
  chmod +x "$HOME/.local/bin/minikube"
  log_info "minikube installed to ~/.local/bin/minikube"
}

# ─── Start Cluster ────────────────────────────────────────────────────────────
start_cluster() {
  log_section "Starting minikube Cluster (1 master + 1 worker)"

  minikube delete --all --purge 2>/dev/null && log_info "Old cluster removed." || true

  log_info "Starting ${CLUSTER_NODES}-node cluster (this takes ~2-3 minutes)..."
  minikube start \
    --nodes "${CLUSTER_NODES}" \
    --cpus "${CPUS_PER_NODE}" \
    --memory "${MEMORY_PER_NODE}" \
    --disk-size "${DISK_SIZE}" \
    --driver docker \
    --kubernetes-version stable

  log_info "Waiting for all nodes to be Ready..."
  kubectl wait --for=condition=Ready nodes --all --timeout=120s

  # Label the worker node
  local worker_node
  worker_node=$(kubectl get nodes --no-headers \
    | grep -v 'control-plane' | awk '{print $1}' | head -1)

  if [[ -n "${worker_node}" ]]; then
    kubectl label node "${worker_node}" \
      node-role.kubernetes.io/worker=worker --overwrite
    log_info "Labeled '${worker_node}' as worker."
  fi

  echo ""
  log_info "Cluster ready:"
  kubectl get nodes -o wide
  echo ""
  log_info "Next step: run ./02-deploy-app.sh"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
echo -e "${BLUE}   01 — Cluster Init${NC}"
echo -e "${BLUE}   Install deps + start minikube${NC}"
echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

check_requirements
install_docker
install_kubectl
install_minikube
start_cluster
