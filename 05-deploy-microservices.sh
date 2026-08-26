#!/usr/bin/env bash
# Step 5: Build all microservice images and deploy via Helm.
# Replaces the single-app release with a full microservices topology.
#
# Services deployed:
#   frontend        — UI; calls product, order, and review services
#   product-service — product catalog
#   order-service   — order creation (calls product-service)
#   review-service  — reviews; v1 (no ratings) and v2 (star ratings)
#
# Istio demonstrates:
#   - Traffic splitting  : review-service 80% v1 / 20% v2 (canary)
#   - Retries / timeouts : per-service VirtualService policies
#   - Circuit breaker    : outlier detection on all backend services
#   - Full observability : Kiali graph shows all service-to-service calls
#
# Usage:
#   ./05-deploy-microservices.sh
#   ./05-deploy-microservices.sh --v1-weight 50 --v2-weight 50   # 50/50 split
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

SERVICES_DIR="${SCRIPT_DIR}/services"
CHART_DIR="${SCRIPT_DIR}/helm-chart/microservices"
HELM_RELEASE_MS="microservices"

# Traffic split defaults (can be overridden via flags)
V1_WEIGHT=80
V2_WEIGHT=20

# ─── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --v1-weight) V1_WEIGHT="$2"; shift 2 ;;
    --v2-weight) V2_WEIGHT="$2"; shift 2 ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Guards ───────────────────────────────────────────────────────────────────
check_prerequisites() {
  local ok=true
  kubectl cluster-info &>/dev/null \
    || { log_error "No cluster. Run ./01-init-cluster.sh first."; ok=false; }
  command -v helm &>/dev/null \
    || { log_error "Helm not found. Run ./02-install-helm-istio.sh first."; ok=false; }
  kubectl -n istio-system get deployment istiod &>/dev/null 2>&1 \
    || { log_error "Istio not installed. Run ./02-install-helm-istio.sh first."; ok=false; }
  [[ "$ok" == "true" ]] || exit 1
  log_info "Prerequisites OK. Traffic split: review-service v1=${V1_WEIGHT}% v2=${V2_WEIGHT}%"
}

# ─── Build & Load Images ──────────────────────────────────────────────────────
build_and_load_images() {
  log_section "Building Docker Images"

  declare -A BUILDS=(
    ["ms-frontend:latest"]="${SERVICES_DIR}/frontend"
    ["ms-product:latest"]="${SERVICES_DIR}/product-service"
    ["ms-order:latest"]="${SERVICES_DIR}/order-service"
    ["ms-review:v1"]="${SERVICES_DIR}/review-service"
  )

  for image in "${!BUILDS[@]}"; do
    local context="${BUILDS[$image]}"
    log_info "Building ${image}..."
    docker build -t "${image}" "${context}" -q
  done

  # review v2 uses a different Dockerfile in the same context
  log_info "Building ms-review:v2..."
  docker build -t "ms-review:v2" \
    -f "${SERVICES_DIR}/review-service/Dockerfile.v2" \
    "${SERVICES_DIR}/review-service" -q

  log_info "Loading all images into minikube nodes..."
  for image in ms-frontend:latest ms-product:latest ms-order:latest ms-review:v1 ms-review:v2; do
    log_info "  Loading ${image}..."
    minikube image load "${image}" --overwrite=true
  done

  log_info "All images ready on all nodes."
}

# ─── Helm Deploy ──────────────────────────────────────────────────────────────
helm_deploy() {
  log_section "Helm Deploy — microservices (v1=${V1_WEIGHT}% v2=${V2_WEIGHT}%)"

  # Remove old single-app release if present (it owns the Gateway for host:"*")
  if helm status demo-python-app -n "${NAMESPACE_MS}" &>/dev/null 2>&1; then
    log_info "Removing old demo-python-app release..."
    helm uninstall demo-python-app -n "${NAMESPACE_MS}"
  fi

  helm upgrade --install "${HELM_RELEASE_MS}" "${CHART_DIR}" \
    --namespace "${NAMESPACE_MS}" \
    --set reviewService.traffic.v1Weight="${V1_WEIGHT}" \
    --set reviewService.traffic.v2Weight="${V2_WEIGHT}" \
    --wait \
    --timeout 180s

  echo ""
  log_info "Helm release:"
  helm status "${HELM_RELEASE_MS}" -n "${NAMESPACE_MS}" | grep -E "STATUS|DEPLOYED|NAMESPACE|REVISION"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  log_section "Microservices Deployment Complete!"

  local minikube_ip ingress_port kiali_port
  minikube_ip=$(minikube ip)
  ingress_port=$(kubectl -n istio-system get svc istio-ingressgateway \
    -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  kiali_port=$(kubectl -n istio-system get svc kiali \
    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "—")

  echo ""
  echo "  Service topology:"
  echo "    Browser → IngressGateway → frontend"
  echo "                               ├── product-service"
  echo "                               ├── review-service (${V1_WEIGHT}% v1 / ${V2_WEIGHT}% v2)"
  echo "                               └── order-service → product-service"
  echo ""
  printf "  %-10s %s\n" "App:"   "http://${minikube_ip}:${ingress_port}"
  printf "  %-10s %s\n" "Kiali:" "http://${minikube_ip}:${kiali_port}"
  echo ""
  echo "  Pods in namespace '${NAMESPACE_MS}':"
  kubectl get pods -n "${NAMESPACE_MS}" -o wide
  echo ""
  echo "  Adjust traffic split (no rebuild needed):"
  echo "    helm upgrade ${HELM_RELEASE_MS} ${CHART_DIR} -n ${NAMESPACE_MS} \\"
  echo "      --set reviewService.traffic.v1Weight=50 \\"
  echo "      --set reviewService.traffic.v2Weight=50"
  echo ""
  echo "  Istio commands:"
  echo "    istioctl proxy-status"
  echo "    kubectl get vs,dr,gateway -n ${NAMESPACE_MS}"
  echo ""

  # Generate warm-up traffic so Kiali graph populates immediately
  log_info "Sending 30 warm-up requests to populate Kiali graph..."
  local app_url="http://${minikube_ip}:${ingress_port}"
  for i in $(seq 1 30); do
    curl -s "${app_url}" > /dev/null || true
  done
  log_info "Done. Open Kiali to see the live service graph."

  if command -v xdg-open &>/dev/null; then
    xdg-open "${app_url}" 2>/dev/null &
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
echo -e "${BLUE}   05 — Microservices Deploy${NC}"
echo -e "${BLUE}   frontend · product · order · review v1/v2${NC}"
echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

check_prerequisites
build_and_load_images
helm_deploy
print_summary
