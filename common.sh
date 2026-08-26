#!/usr/bin/env bash
# Shared config and logging helpers — sourced by other scripts.

# ─── Colors & Logging ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() {
  echo -e "\n${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $*${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

# ─── Rollback ─────────────────────────────────────────────────────────────────
# Usage: helm_rollback <release> <namespace> [revision]
#   revision omitted → rolls back to the previous revision (Helm default)
#   revision = 0     → same as omitted
#   revision = N     → rolls back to exact revision N
helm_rollback() {
  local release="$1"
  local namespace="$2"
  local revision="${3:-0}"   # 0 means "previous" in Helm

  log_section "Rolling Back — ${release} (namespace: ${namespace})"

  # Show history before rolling back so the user can see what's happening
  log_info "Release history:"
  helm history "${release}" -n "${namespace}" \
    --output table 2>/dev/null || { log_error "No history found for '${release}' in '${namespace}'."; exit 1; }
  echo ""

  if [[ "${revision}" -eq 0 ]]; then
    log_info "Target: previous revision (no specific version given)"
    helm rollback "${release}" -n "${namespace}" --wait --timeout 120s
  else
    log_info "Target: revision ${revision}"
    helm rollback "${release}" "${revision}" -n "${namespace}" --wait --timeout 120s
  fi

  echo ""
  log_info "Rollback complete. Current state:"
  helm history "${release}" -n "${namespace}" --output table | tail -3
}

# ─── Shared Config ────────────────────────────────────────────────────────────
CLUSTER_NODES=2          # 1 control-plane + 1 worker
CPUS_PER_NODE=2
MEMORY_PER_NODE=2048     # MB
DISK_SIZE=20g
NAMESPACE_DEMO="dev-python-demo"   # standalone Flask demo app
NAMESPACE_MS="dev-microservices"   # full microservices topology
APP_IMAGE="demo-python-app:latest"
APP_DIR="/tmp/demo-python-app"

# Helm
HELM_CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helm-chart/demo-python-app"
HELM_RELEASE="demo-python-app"

# Istio
ISTIO_PROFILE="default"   # default = istiod + ingressgateway
