#!/usr/bin/env bash
# Step 4: Install the Istio observability stack.
#   - Prometheus  — metrics backend (required by Kiali)
#   - Kiali       — service mesh console (topology, traffic, health)
#   - Grafana     — metrics dashboards
#   - Jaeger      — distributed tracing
#
# Kiali is exposed via NodePort so no port-forward or tunnel is needed.
# Run after 02-install-helm-istio.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Derive the release branch from the installed istioctl (e.g. 1.30.3 → release-1.30)
ISTIO_VERSION=$(istioctl version --remote=false 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
ADDON_BASE="https://raw.githubusercontent.com/istio/istio/release-${ISTIO_VERSION}/samples/addons"

# ─── Guard ────────────────────────────────────────────────────────────────────
check_prerequisites() {
  kubectl cluster-info &>/dev/null \
    || { log_error "No cluster. Run ./01-init-cluster.sh first."; exit 1; }
  kubectl -n istio-system get deployment istiod &>/dev/null 2>&1 \
    || { log_error "Istio not installed. Run ./02-install-helm-istio.sh first."; exit 1; }
  log_info "Prerequisites OK (Istio ${ISTIO_VERSION} detected)."
}

# ─── Install Addons ───────────────────────────────────────────────────────────
install_addons() {
  log_section "Installing Observability Addons"

  declare -A ADDONS=(
    [Prometheus]="${ADDON_BASE}/prometheus.yaml"
    [Grafana]="${ADDON_BASE}/grafana.yaml"
    [Jaeger]="${ADDON_BASE}/jaeger.yaml"
    [Kiali]="${ADDON_BASE}/kiali.yaml"
  )

  # Install in dependency order: Prometheus first, Kiali last
  for name in Prometheus Grafana Jaeger Kiali; do
    log_info "Applying ${name}..."
    kubectl apply -f "${ADDONS[$name]}" 2>&1 | grep -v "^Warning:"
  done

  # Kiali CRDs can take a moment to register; apply a second time to be safe
  log_info "Re-applying Kiali to ensure CRD registration..."
  kubectl apply -f "${ADDONS[Kiali]}" 2>&1 | grep -v "^Warning:" || true
}

# ─── Wait for Readiness ───────────────────────────────────────────────────────
wait_for_addons() {
  log_section "Waiting for Addon Pods"

  local deployments=(prometheus grafana kiali)
  for dep in "${deployments[@]}"; do
    log_info "Waiting for ${dep}..."
    kubectl rollout status deployment/"${dep}" \
      -n istio-system --timeout=180s
  done

  # Jaeger runs as a single pod (not a Deployment in older addon manifests)
  if kubectl -n istio-system get deployment jaeger &>/dev/null 2>&1; then
    log_info "Waiting for jaeger..."
    kubectl rollout status deployment/jaeger -n istio-system --timeout=120s
  fi

  echo ""
  log_info "Addon pods:"
  kubectl get pods -n istio-system
}

# ─── Expose Kiali via NodePort ────────────────────────────────────────────────
expose_kiali() {
  log_section "Exposing Kiali via NodePort"

  # Kiali service defaults to ClusterIP — patch it to NodePort
  kubectl patch svc kiali -n istio-system \
    -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || true

  KIALI_PORT=$(kubectl -n istio-system get svc kiali \
    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')

  log_info "Kiali NodePort: ${KIALI_PORT}"
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  log_section "Observability Stack Ready"

  local minikube_ip
  minikube_ip=$(minikube ip)

  local kiali_port grafana_port
  kiali_port=$(kubectl -n istio-system get svc kiali \
    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "—")
  grafana_port=$(kubectl -n istio-system get svc grafana \
    -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "—")

  echo ""
  printf "  %-12s %s\n" "Tool" "URL"
  printf "  %-12s %s\n" "────" "─────────────────────────────"
  printf "  %-12s %s\n" "Kiali"      "http://${minikube_ip}:${kiali_port}"
  printf "  %-12s %s\n" "Grafana"    "kubectl port-forward svc/grafana 3000:3000 -n istio-system"
  printf "  %-12s %s\n" "Jaeger"     "kubectl port-forward svc/tracing 16686:80 -n istio-system"
  printf "  %-12s %s\n" "Prometheus" "kubectl port-forward svc/prometheus 9090:9090 -n istio-system"
  echo ""
  echo "  Kiali shows live traffic topology once requests flow through the mesh."
  echo "  Generate some traffic first:"
  echo ""
  local ingress_port
  ingress_port=$(kubectl -n istio-system get svc istio-ingressgateway \
    -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  echo "    for i in \$(seq 1 50); do curl -s http://${minikube_ip}:${ingress_port} > /dev/null; done"
  echo ""
  echo "  Then open Kiali: http://${minikube_ip}:${kiali_port}"
  echo ""

  if command -v xdg-open &>/dev/null; then
    xdg-open "http://${minikube_ip}:${kiali_port}" 2>/dev/null &
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
echo -e "${BLUE}   04 — Observability Stack${NC}"
echo -e "${BLUE}   Prometheus · Kiali · Grafana · Jaeger${NC}"
echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

check_prerequisites
install_addons
wait_for_addons
expose_kiali
print_summary
