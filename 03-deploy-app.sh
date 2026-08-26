#!/usr/bin/env bash
# Step 3: Build the Docker image and deploy / upgrade via Helm.
# Re-run any time you change app code or want to adjust values (e.g. replicas).
#
# Usage:
#   ./03-deploy-app.sh                     # deploy with defaults (2 replicas)
#   ./03-deploy-app.sh --replicas 4        # override replica count
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ─── Argument Parsing ─────────────────────────────────────────────────────────
REPLICAS=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --replicas) REPLICAS="$2"; shift 2 ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Guards ───────────────────────────────────────────────────────────────────
check_prerequisites() {
  local ok=true
  kubectl cluster-info &>/dev/null || { log_error "No cluster. Run ./01-init-cluster.sh first."; ok=false; }
  command -v helm    &>/dev/null || { log_error "Helm not found. Run ./02-install-helm-istio.sh first."; ok=false; }
  command -v istioctl &>/dev/null || { log_error "istioctl not found. Run ./02-install-helm-istio.sh first."; ok=false; }
  kubectl -n istio-system get deployment istiod &>/dev/null 2>&1 \
    || { log_error "Istio not installed. Run ./02-install-helm-istio.sh first."; ok=false; }
  [[ "$ok" == "true" ]] || exit 1
  log_info "Prerequisites OK. Deploying ${REPLICAS} replica(s)."
}

# ─── App Source Files ─────────────────────────────────────────────────────────
create_app_files() {
  log_section "Writing App Source"

  mkdir -p "${APP_DIR}"

  cat > "${APP_DIR}/app.py" <<'PYEOF'
from flask import Flask
import os, socket

app = Flask(__name__)

@app.route("/")
def home():
    hostname = socket.gethostname()
    try:
        pod_ip = socket.gethostbyname(hostname)
    except Exception:
        pod_ip = "unknown"
    node      = os.environ.get("NODE_NAME", "unknown")
    namespace = os.environ.get("POD_NAMESPACE", "unknown")

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Python Demo on Kubernetes</title>
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: 'Segoe UI', Arial, sans-serif;
      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
      min-height: 100vh; display: flex; justify-content: center; align-items: center;
    }}
    .card {{
      background: white; border-radius: 16px; padding: 48px 60px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.4); max-width: 560px; width: 90%; text-align: center;
    }}
    .logo  {{ font-size: 3rem; margin-bottom: 8px; }}
    h1     {{ color: #1a1a2e; font-size: 1.8rem; margin-bottom: 8px; }}
    .subtitle {{ color: #666; margin-bottom: 32px; font-size: 0.95rem; }}
    .info-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 24px; }}
    .info-box {{
      background: #f0f4ff; border-radius: 10px; padding: 14px; border-left: 4px solid #3498db;
    }}
    .info-label {{ font-size: 0.75rem; color: #888; text-transform: uppercase; letter-spacing: 1px; }}
    .info-value {{ font-size: 0.95rem; color: #1a1a2e; font-weight: 600; margin-top: 4px; word-break: break-all; }}
    .badge {{
      display: inline-block; background: #3498db; color: white;
      border-radius: 20px; padding: 6px 18px; font-size: 0.85rem; margin-top: 28px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🐍</div>
    <h1>Hello from Kubernetes!</h1>
    <p class="subtitle">Python Flask · Helm · Istio service mesh</p>
    <div class="info-grid">
      <div class="info-box">
        <div class="info-label">Pod Name</div>
        <div class="info-value">{hostname}</div>
      </div>
      <div class="info-box">
        <div class="info-label">Pod IP</div>
        <div class="info-value">{pod_ip}</div>
      </div>
      <div class="info-box">
        <div class="info-label">Node</div>
        <div class="info-value">{node}</div>
      </div>
      <div class="info-box">
        <div class="info-label">Namespace</div>
        <div class="info-value">{namespace}</div>
      </div>
    </div>
    <span class="badge">☸ Istio sidecar active</span>
  </div>
</body>
</html>"""

@app.route("/health")
def health():
    return {"status": "ok"}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

  cat > "${APP_DIR}/requirements.txt" <<'EOF'
flask==3.0.3
EOF

  cat > "${APP_DIR}/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

  log_info "Source written to ${APP_DIR}/"
}

# ─── Docker Build + Load ──────────────────────────────────────────────────────
build_and_load_image() {
  log_section "Building Docker Image"

  docker build -t "${APP_IMAGE}" "${APP_DIR}"
  log_info "Built: ${APP_IMAGE}"

  log_info "Loading into all minikube nodes..."
  minikube image load "${APP_IMAGE}" --overwrite=true
  log_info "Image available on all nodes."
}

# ─── Helm Deploy ──────────────────────────────────────────────────────────────
helm_deploy() {
  log_section "Helm Deploy — ${HELM_RELEASE} (replicas=${REPLICAS})"

  helm upgrade --install "${HELM_RELEASE}" "${HELM_CHART_DIR}" \
    --namespace "${NAMESPACE}" \
    --set replicaSet.replicas="${REPLICAS}" \
    --set image.name="${APP_IMAGE%%:*}" \
    --set image.tag="${APP_IMAGE##*:}" \
    --wait \
    --timeout 120s

  echo ""
  log_info "Helm release status:"
  helm status "${HELM_RELEASE}" -n "${NAMESPACE}" | grep -E "STATUS|DEPLOYED|NAMESPACE"

  echo ""
  log_info "Pods (each has 2 containers: app + istio-proxy sidecar):"
  kubectl get pods -n "${NAMESPACE}" -o wide
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  log_section "Deployment Complete!"

  local ingress_port
  ingress_port=$(kubectl -n istio-system get service istio-ingressgateway \
    -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
  local app_url="http://$(minikube ip):${ingress_port}"

  echo -e "  ${GREEN}App URL:${NC}  ${app_url}"
  echo ""
  echo "  Scale replicas:"
  echo "    ./03-deploy-app.sh --replicas 4"
  echo "    helm upgrade ${HELM_RELEASE} ./helm-chart/demo-python-app -n ${NAMESPACE} --set replicaSet.replicas=4"
  echo ""
  echo "  Istio traffic commands:"
  echo "    istioctl proxy-status                             # Envoy sync status"
  echo "    istioctl analyze -n ${NAMESPACE}                  # Config health check"
  echo "    kubectl get virtualservice,gateway,destinationrule -n ${NAMESPACE}"
  echo ""
  echo "  Helm commands:"
  echo "    helm list -n ${NAMESPACE}                         # List releases"
  echo "    helm history ${HELM_RELEASE} -n ${NAMESPACE}      # Rollout history"
  echo "    helm rollback ${HELM_RELEASE} -n ${NAMESPACE}     # Roll back one version"
  echo ""

  if command -v xdg-open &>/dev/null; then
    xdg-open "${app_url}" 2>/dev/null &
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
echo -e "${BLUE}   03 — Build & Deploy (Helm + Istio)${NC}"
echo -e "${BLUE}   replicas=${REPLICAS}${NC}"
echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

check_prerequisites
create_app_files
build_and_load_image
helm_deploy
print_summary
