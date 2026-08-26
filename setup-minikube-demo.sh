#!/usr/bin/env bash
# Minikube cluster setup: 1 master + 1 worker, with a sample Python Flask demo app.
set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${BLUE}════════════════════════════════════════${NC}"; \
                echo -e "${BLUE}  $*${NC}"; \
                echo -e "${BLUE}════════════════════════════════════════${NC}\n"; }

# ─── Config ───────────────────────────────────────────────────────────────────
CLUSTER_NODES=2          # 1 control-plane + 1 worker
CPUS_PER_NODE=2
MEMORY_PER_NODE=2048     # MB
DISK_SIZE=20g
NAMESPACE="demo"
APP_IMAGE="demo-python-app:latest"
APP_DIR="/tmp/demo-python-app"
NODE_PORT=30080

# ─── 1. System Check ──────────────────────────────────────────────────────────
check_requirements() {
  log_section "1. Checking System Requirements"

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

# ─── 2. Install Docker ────────────────────────────────────────────────────────
install_docker() {
  log_section "2. Docker"

  if command -v docker &>/dev/null; then
    log_info "Docker already installed: $(docker --version)"
  else
    log_info "Installing Docker via get.docker.com..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log_warn "Docker installed. Starting a new shell group so minikube can use it..."
  fi

  # Ensure docker daemon is running (check without sudo first)
  if ! docker info &>/dev/null; then
    log_info "Docker daemon not reachable, attempting to start..."
    sudo systemctl start docker || log_warn "Could not auto-start docker; please ensure it is running."
    sleep 2
  fi

  log_info "Docker OK."
}

# ─── 3. Install kubectl ───────────────────────────────────────────────────────
install_kubectl() {
  log_section "3. kubectl"

  if command -v kubectl &>/dev/null; then
    log_info "kubectl already installed: $(kubectl version --client 2>/dev/null | head -1)"
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

# ─── 4. Install minikube ─────────────────────────────────────────────────────
install_minikube() {
  log_section "4. minikube"

  if command -v minikube &>/dev/null; then
    log_info "minikube already installed: $(minikube version --short 2>/dev/null)"
    return
  fi

  mkdir -p "$HOME/.local/bin"
  log_info "Downloading minikube..."
  curl -fsSLo "$HOME/.local/bin/minikube" \
    "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
  chmod +x "$HOME/.local/bin/minikube"
  log_info "minikube installed to ~/.local/bin/minikube"
}

# ─── 5. Start Cluster ─────────────────────────────────────────────────────────
start_cluster() {
  log_section "5. Starting minikube Cluster (1 master + 1 worker)"

  # Clean up any previous cluster to ensure a fresh state
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

  # Label the worker node explicitly
  local worker_node
  worker_node=$(kubectl get nodes --no-headers \
    | grep -v 'control-plane' | awk '{print $1}' | head -1)

  if [[ -n "${worker_node}" ]]; then
    kubectl label node "${worker_node}" \
      node-role.kubernetes.io/worker=worker --overwrite
    log_info "Labeled '${worker_node}' as worker."
  fi

  echo ""
  log_info "Cluster nodes:"
  kubectl get nodes -o wide
}

# ─── 6. Create Python Flask App ───────────────────────────────────────────────
create_app_files() {
  log_section "6. Creating Python Flask Demo App"

  mkdir -p "${APP_DIR}"

  # app.py
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
    node = os.environ.get("NODE_NAME", "unknown")
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
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
    }}
    .card {{
      background: white;
      border-radius: 16px;
      padding: 48px 60px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.4);
      max-width: 560px;
      width: 90%;
      text-align: center;
    }}
    .logo {{ font-size: 3rem; margin-bottom: 8px; }}
    h1 {{ color: #1a1a2e; font-size: 1.8rem; margin-bottom: 8px; }}
    .subtitle {{ color: #666; margin-bottom: 32px; font-size: 0.95rem; }}
    .info-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 16px;
      margin-top: 24px;
    }}
    .info-box {{
      background: #f0f4ff;
      border-radius: 10px;
      padding: 14px;
      border-left: 4px solid #3498db;
    }}
    .info-label {{ font-size: 0.75rem; color: #888; text-transform: uppercase; letter-spacing: 1px; }}
    .info-value {{ font-size: 0.95rem; color: #1a1a2e; font-weight: 600; margin-top: 4px;
                   word-break: break-all; }}
    .k8s-badge {{
      display: inline-block;
      background: #3498db;
      color: white;
      border-radius: 20px;
      padding: 6px 18px;
      font-size: 0.85rem;
      margin-top: 28px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🐍</div>
    <h1>Hello from Kubernetes!</h1>
    <p class="subtitle">Python Flask running on a minikube cluster</p>
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
    <span class="k8s-badge">☸ Running on minikube</span>
  </div>
</body>
</html>"""

@app.route("/health")
def health():
    return {"status": "ok"}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

  # requirements.txt
  cat > "${APP_DIR}/requirements.txt" <<'EOF'
flask==3.0.3
EOF

  # Dockerfile
  cat > "${APP_DIR}/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

  log_info "App files created at ${APP_DIR}/"
}

# ─── 7. Build Image & Load Into All Nodes ────────────────────────────────────
build_image() {
  log_section "7. Building Docker Image and Loading Into Cluster"

  # Build on the host Docker daemon
  docker build -t "${APP_IMAGE}" "${APP_DIR}"
  log_info "Image built locally: ${APP_IMAGE}"

  # Load into all minikube nodes (required for multi-node clusters)
  log_info "Loading image into all minikube nodes..."
  minikube image load "${APP_IMAGE}" --overwrite=true
  log_info "Image loaded into cluster."
}

# ─── 8. Deploy to Kubernetes ─────────────────────────────────────────────────
deploy_app() {
  log_section "8. Deploying to Kubernetes"

  # Create namespace (idempotent)
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  # Write manifest to a temp file to avoid heredoc quoting issues
  local manifest
  manifest=$(mktemp /tmp/k8s-manifest-XXXXXX.yaml)

  cat > "${manifest}" <<MANIFEST
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-python-app
  namespace: ${NAMESPACE}
  labels:
    app: demo-python-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-python-app
  template:
    metadata:
      labels:
        app: demo-python-app
    spec:
      containers:
      - name: demo-python-app
        image: ${APP_IMAGE}
        imagePullPolicy: Never
        ports:
        - containerPort: 5000
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 10
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /health
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: demo-python-app
  namespace: ${NAMESPACE}
spec:
  type: NodePort
  selector:
    app: demo-python-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 5000
    nodePort: ${NODE_PORT}
MANIFEST

  kubectl apply -f "${manifest}"
  rm -f "${manifest}"

  log_info "Waiting for pods to become ready..."
  kubectl rollout status deployment/demo-python-app \
    -n "${NAMESPACE}" --timeout=120s

  echo ""
  log_info "Pods:"
  kubectl get pods -n "${NAMESPACE}" -o wide
}

# ─── 9. Print Summary ─────────────────────────────────────────────────────────
print_summary() {
  log_section "Setup Complete!"

  local minikube_ip
  minikube_ip=$(minikube ip)
  local app_url="http://${minikube_ip}:${NODE_PORT}"

  echo -e "  ${GREEN}Demo URL:${NC}  ${app_url}"
  echo ""
  echo "  Cluster nodes:"
  kubectl get nodes
  echo ""
  echo "  Pods in namespace '${NAMESPACE}':"
  kubectl get pods -n "${NAMESPACE}"
  echo ""
  echo "  Handy commands:"
  echo "    minikube dashboard                              # Web UI"
  echo "    kubectl get pods -n ${NAMESPACE} -o wide        # Pod placement"
  echo "    kubectl logs -n ${NAMESPACE} -l app=demo-python-app  # App logs"
  echo "    kubectl scale deploy/demo-python-app -n ${NAMESPACE} --replicas=4"
  echo "    minikube stop                                   # Pause cluster"
  echo "    minikube delete                                 # Remove cluster"
  echo ""

  # Open browser if available (non-fatal)
  if command -v xdg-open &>/dev/null; then
    xdg-open "${app_url}" 2>/dev/null &
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  echo -e "\n${BLUE}██████████████████████████████████████████${NC}"
  echo -e "${BLUE}   Minikube Demo Cluster Installer${NC}"
  echo -e "${BLUE}   1 master + 1 worker • Python Flask demo${NC}"
  echo -e "${BLUE}██████████████████████████████████████████${NC}\n"

  check_requirements
  install_docker
  install_kubectl
  install_minikube
  start_cluster
  create_app_files
  build_image
  deploy_app
  print_summary
}

main "$@"
