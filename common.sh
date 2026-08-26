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

# ─── Shared Config ────────────────────────────────────────────────────────────
CLUSTER_NODES=2          # 1 control-plane + 1 worker
CPUS_PER_NODE=2
MEMORY_PER_NODE=2048     # MB
DISK_SIZE=20g
NAMESPACE="dev"
APP_IMAGE="demo-python-app:latest"
APP_DIR="/tmp/demo-python-app"

# Helm
HELM_CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/helm-chart/demo-python-app"
HELM_RELEASE="demo-python-app"

# Istio
ISTIO_PROFILE="default"   # default = istiod + ingressgateway
