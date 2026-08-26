#!/usr/bin/env bash
# Step 2: Install Helm and Istio, then prepare the demo namespace.
# Run after 01-init-cluster.sh. Only needs to run once per cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ─── Guard ────────────────────────────────────────────────────────────────────
check_cluster() {
  if ! kubectl cluster-info &>/dev/null; then
    log_error "No running cluster found. Run ./01-init-cluster.sh first."
    exit 1
  fi
  log_info "Cluster is up."
}

# ─── Helm ─────────────────────────────────────────────────────────────────────
install_helm() {
  log_section "Helm"

  if command -v helm &>/dev/null; then
    log_info "Already installed: $(helm version --short)"
    return
  fi

  log_info "Downloading Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | HELM_INSTALL_DIR="$HOME/.local/bin" USE_SUDO=false bash
  log_info "Helm installed: $(helm version --short)"
}

# ─── Istio ────────────────────────────────────────────────────────────────────
install_istioctl() {
  if command -v istioctl &>/dev/null; then
    log_info "istioctl already installed: $(istioctl version --remote=false 2>/dev/null | head -1)"
    return
  fi

  log_info "Downloading istioctl..."
  # Download to /tmp so the extracted istio-X.Y.Z/ dir doesn't land in the project
  pushd /tmp > /dev/null
  curl -fsSL https://istio.io/downloadIstio | TARGET_ARCH=x86_64 sh - 2>/dev/null
  local istio_dir
  istio_dir=$(ls -d /tmp/istio-* 2>/dev/null | sort -V | tail -1)
  cp "${istio_dir}/bin/istioctl" "$HOME/.local/bin/istioctl"
  chmod +x "$HOME/.local/bin/istioctl"
  rm -rf "${istio_dir}"
  popd > /dev/null
  log_info "istioctl installed: $(istioctl version --remote=false 2>/dev/null | head -1)"
}

install_istio() {
  log_section "Istio"

  install_istioctl

  # Skip if istiod already running
  if kubectl -n istio-system get deployment istiod &>/dev/null 2>&1; then
    log_info "Istio already installed in the cluster."
  else
    log_info "Installing Istio (profile: ${ISTIO_PROFILE}) — this takes ~2 minutes..."

    # Use NodePort so the ingress gateway is reachable without minikube tunnel
    local op_file
    op_file=$(mktemp /tmp/istio-op-XXXXXX.yaml)
    cat > "${op_file}" <<EOF
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: ${ISTIO_PROFILE}
  components:
    ingressGateways:
    - name: istio-ingressgateway
      enabled: true
      k8s:
        service:
          type: NodePort
EOF
    istioctl install -f "${op_file}" -y
    rm -f "${op_file}"
  fi

  log_info "Waiting for istiod..."
  kubectl rollout status deployment/istiod \
    -n istio-system --timeout=180s

  log_info "Waiting for ingress gateway..."
  kubectl rollout status deployment/istio-ingressgateway \
    -n istio-system --timeout=120s

  echo ""
  log_info "Istio pods:"
  kubectl get pods -n istio-system
}

# ─── Namespace ────────────────────────────────────────────────────────────────
setup_namespace() {
  log_section "Configuring Namespace '${NAMESPACE}'"

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  # Istio will automatically inject an Envoy sidecar into every pod in this namespace
  kubectl label namespace "${NAMESPACE}" istio-injection=enabled --overwrite

  log_info "Namespace '${NAMESPACE}' ready with sidecar injection enabled."
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  log_section "Helm + Istio Ready"

  local ingress_port
  ingress_port=$(kubectl -n istio-system get service istio-ingressgateway \
    -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

  echo "  Istio ingress gateway : http://$(minikube ip):${ingress_port}"
  echo ""
  echo "  Traffic flow:"
  echo "    Browser → Istio IngressGateway (NodePort ${ingress_port})"
  echo "    → Istio Gateway resource → VirtualService routing"
  echo "    → Service (ClusterIP) → Envoy sidecar → Flask pod"
  echo ""
  log_info "Next step: run ./03-deploy-app.sh"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
echo -e "${BLUE}   02 — Helm + Istio${NC}"
echo -e "${BLUE}   Package manager + service mesh${NC}"
echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

check_cluster
install_helm
install_istio
setup_namespace
print_summary
