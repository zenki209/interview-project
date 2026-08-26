# Minikube Microservices Demo

A fully scripted local Kubernetes environment demonstrating microservices, Helm package management, Istio service mesh traffic control, and a complete observability stack — all running on minikube with two nodes.

---

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │           Kubernetes Cluster             │
                        │                                          │
  Browser               │  ┌──────────────────────────────────┐   │
     │                  │  │        istio-system namespace     │   │
     ▼                  │  │  istiod · ingressgateway          │   │
  NodePort              │  │  Kiali · Prometheus · Grafana     │   │
     │                  │  │  Jaeger                           │   │
     ▼                  │  └──────────────────────────────────┘   │
  Istio IngressGateway  │                                          │
     │                  │  ┌──────────────────────────────────┐   │
     │  Gateway         │  │          dev namespace            │   │
     ▼                  │  │                                   │   │
  VirtualService        │  │  frontend ──────► product-service │   │
     │                  │  │      │                            │   │
     ▼                  │  │      ├──────► order-service       │   │
  frontend              │  │      │            │               │   │
  [Flask + Envoy]       │  │      │            └► product-svc  │   │
                        │  │      │                            │   │
                        │  │      └──────► review-service      │   │
                        │  │               ├── v1 (80%)        │   │
                        │  │               └── v2 (20%)        │   │
                        │  └──────────────────────────────────┘   │
                        │                                          │
                        │  Node 1: minikube (control-plane)        │
                        │  Node 2: minikube-m02 (worker)           │
                        └─────────────────────────────────────────┘
```

Every pod runs with an **Envoy proxy sidecar** injected by Istio. All service-to-service traffic flows through the sidecars, enabling observability, retries, timeouts, and circuit-breaking without any changes to application code.

---

## Microservices

| Service | Language | Role |
|---------|----------|------|
| `frontend` | Python Flask | Renders the UI; fans out calls to product, review, and order services |
| `product-service` | Python Flask | Serves the product catalog |
| `order-service` | Python Flask | Creates orders; calls product-service internally |
| `review-service v1` | Python Flask | Returns reviews without star ratings |
| `review-service v2` | Python Flask | Returns reviews with numeric star ratings |

`review-service` has two versions deployed simultaneously. Istio routes **80 % of traffic to v1** and **20 % to v2** by default, demonstrating a canary deployment. The split is configurable without rebuilding any image.

---

## File Structure

```
.
├── common.sh                          # Shared config and logging — sourced by all scripts
├── 01-init-cluster.sh                 # Install tools + start minikube (1 master + 1 worker)
├── 02-install-helm-istio.sh           # Install Helm + Istio + label dev namespace
├── 03-deploy-app.sh                   # (optional) Deploy the standalone Flask demo app
├── 04-install-kiali.sh                # Install observability stack
├── 05-deploy-microservices.sh         # Build images + deploy full microservices via Helm
│
├── services/                          # Microservice source code
│   ├── frontend/
│   │   ├── app.py                     # Flask app — calls product, order, review services
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   ├── product-service/
│   │   ├── app.py                     # Product catalog API
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   ├── order-service/
│   │   ├── app.py                     # Order creation — calls product-service
│   │   ├── requirements.txt
│   │   └── Dockerfile
│   └── review-service/
│       ├── app.py                     # v1 — reviews without ratings
│       ├── app_v2.py                  # v2 — reviews with star ratings
│       ├── requirements.txt
│       ├── Dockerfile                 # Builds v1 image (runs app.py)
│       └── Dockerfile.v2              # Builds v2 image (runs app_v2.py)
│
├── helm-chart/
│   ├── demo-python-app/               # Standalone single-app chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── gateway.yaml
│   │       ├── virtualservice.yaml
│   │       └── destinationrule.yaml
│   │
│   └── microservices/                 # Full microservices chart
│       ├── Chart.yaml
│       ├── values.yaml                # Replica counts, images, traffic weights, Istio policies
│       └── templates/
│           ├── frontend-deployment.yaml
│           ├── frontend-service.yaml
│           ├── product-deployment.yaml
│           ├── product-service.yaml
│           ├── order-deployment.yaml
│           ├── order-service.yaml
│           ├── review-v1-deployment.yaml
│           ├── review-v2-deployment.yaml
│           ├── review-service.yaml
│           ├── gateway.yaml           # Istio Gateway — single entry point
│           ├── vs-frontend.yaml       # Routes IngressGateway → frontend
│           ├── vs-product.yaml        # Timeout + retries for product-service
│           ├── vs-order.yaml          # Timeout + retries for order-service
│           ├── vs-review.yaml         # Traffic split v1/v2 by weight
│           ├── dr-product.yaml        # Load balancer + circuit breaker
│           ├── dr-order.yaml          # Load balancer + circuit breaker
│           └── dr-review.yaml         # Subsets v1/v2 + circuit breaker
│
└── README.md
```

---

## Prerequisites

| Requirement | Minimum |
|-------------|---------|
| OS | Linux (amd64) |
| CPU | 2 cores |
| RAM | 6 GB |
| Disk | 20 GB free |
| Privileges | `sudo` (Docker install only) |
| Internet | Required on first run (image pulls) |

---

## Quick Start

Run each script in order. Each step is idempotent — safe to re-run if something fails.

```bash
# 1. Provision the cluster
./01-init-cluster.sh

# 2. Install Helm and Istio
./02-install-helm-istio.sh

# 3. Install the observability stack
./04-install-kiali.sh

# 4. Build and deploy the microservices
./05-deploy-microservices.sh
```

The app URL and Kiali URL are printed at the end of each relevant step.

---

## Script Reference

### `common.sh`

Sourced by every script. Edit this file to change cluster-wide defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NODES` | `2` | Total nodes (1 master + 1 worker) |
| `CPUS_PER_NODE` | `2` | vCPUs allocated per node |
| `MEMORY_PER_NODE` | `2048` | MB of RAM per node |
| `DISK_SIZE` | `20g` | Disk per node |
| `NAMESPACE` | `dev` | Kubernetes namespace for the app |
| `APP_IMAGE` | `demo-python-app:latest` | Image for the standalone demo |
| `HELM_RELEASE` | `demo-python-app` | Helm release name for the standalone demo |
| `ISTIO_PROFILE` | `default` | Istio installation profile |

---

### `01-init-cluster.sh` — Cluster Provisioning

Installs Docker, kubectl, and minikube, then starts a two-node cluster.

```
Steps:
  1. System check     — verifies CPU ≥ 2, warns if RAM < 4 GB
  2. Docker           — installs via get.docker.com if missing
  3. kubectl          — downloads latest stable to ~/.local/bin
  4. minikube         — downloads latest to ~/.local/bin
  5. Cluster start    — minikube start --nodes 2 --driver docker
  6. Node label       — labels worker node with node-role.kubernetes.io/worker
```

**Result:**
```
NAME           ROLES           STATUS   VERSION
minikube       control-plane   Ready    v1.35.x
minikube-m02   worker          Ready    v1.35.x
```

---

### `02-install-helm-istio.sh` — Helm + Istio

Installs the Helm package manager and the Istio service mesh. Run once per cluster.

```
Steps:
  1. Helm      — installs v3 via official script to ~/.local/bin
  2. istioctl  — downloads via istio.io/downloadIstio to ~/.local/bin
  3. Istio     — installs with 'default' profile (istiod + ingressgateway)
               — ingressgateway patched to NodePort (no minikube tunnel needed)
  4. Namespace — creates 'dev' namespace, labels istio-injection=enabled
```

---

### `04-install-kiali.sh` — Observability Stack

Installs four Istio addon components from the official Istio release manifests, pinned to the installed Istio version.

| Component | Role |
|-----------|------|
| **Prometheus** | Scrapes metrics from every Envoy sidecar |
| **Kiali** | Live service mesh topology, traffic rates, config validation |
| **Grafana** | Pre-built Istio dashboards (latency, error rate, throughput) |
| **Jaeger** | Distributed tracing — full request path across services |

Kiali is patched to `NodePort` for direct browser access. The other tools use `kubectl port-forward`.

---

### `05-deploy-microservices.sh` — Build and Deploy

Builds all five Docker images, loads them into every minikube node, and deploys via Helm.

```bash
./05-deploy-microservices.sh                          # default 80/20 split
./05-deploy-microservices.sh --v1-weight 50 --v2-weight 50   # 50/50 canary
```

```
Steps:
  1. Prerequisite check  — verifies cluster, Helm, and Istio are ready
  2. Docker builds       — ms-frontend, ms-product, ms-order, ms-review:v1, ms-review:v2
  3. Image load          — minikube image load to all nodes (no registry needed)
  4. Helm deploy         — helm upgrade --install microservices ./helm-chart/microservices
  5. Warm-up traffic     — sends 30 requests so Kiali graph populates on first open
```

**Docker images built:**

| Image | Source |
|-------|--------|
| `ms-frontend:latest` | `services/frontend/` |
| `ms-product:latest` | `services/product-service/` |
| `ms-order:latest` | `services/order-service/` |
| `ms-review:v1` | `services/review-service/Dockerfile` |
| `ms-review:v2` | `services/review-service/Dockerfile.v2` |

---

## Helm Chart — `microservices`

### Key `values.yaml` Settings

```yaml
# Replica counts per service
frontend:
  replicas: 1
productService:
  replicas: 1
orderService:
  replicas: 1
reviewService:
  v1:
    replicas: 1
  v2:
    replicas: 1

  # Canary traffic split — must sum to 100
  traffic:
    v1Weight: 80
    v2Weight: 20

  # Per-service Istio policies
  istio:
    timeout: "5s"
    retries:
      attempts: 2
      perTryTimeout: "2s"
    outlierDetection:
      consecutive5xxErrors: 3
      interval: "10s"
      baseEjectionTime: "30s"
```

### Template Reference

| Template | Kubernetes Kind | Purpose |
|----------|----------------|---------|
| `*-deployment.yaml` | `Deployment` | Runs the service pods; replica count from `values.yaml` |
| `*-service.yaml` | `Service` (ClusterIP) | Internal DNS endpoint; not exposed externally |
| `gateway.yaml` | `Gateway` | Single Istio edge listener on port 80 |
| `vs-frontend.yaml` | `VirtualService` | Routes IngressGateway traffic to the frontend |
| `vs-product.yaml` | `VirtualService` | Timeout + retries for product-service calls |
| `vs-order.yaml` | `VirtualService` | Timeout + retries for order-service calls |
| `vs-review.yaml` | `VirtualService` | **Traffic split** — routes v1Weight% to v1, v2Weight% to v2 |
| `dr-product.yaml` | `DestinationRule` | Round-robin load balancing + circuit breaker |
| `dr-order.yaml` | `DestinationRule` | Round-robin load balancing + circuit breaker |
| `dr-review.yaml` | `DestinationRule` | Defines `v1` and `v2` subsets by pod label; circuit breaker |

---

## Istio Traffic Management

### Traffic Splitting (Canary Deployment)

`review-service` runs two versions simultaneously. Istio routes between them by matching pod labels (`version: v1` / `version: v2`) defined as subsets in the `DestinationRule`.

```
Request → review-service (ClusterIP)
              │
              ├── 80% → subset v1 (pods with label version: v1)  — no star ratings
              └── 20% → subset v2 (pods with label version: v2)  — star ratings shown
```

Adjust the split without rebuilding any image:

```bash
helm upgrade microservices ./helm-chart/microservices -n dev \
  --set reviewService.traffic.v1Weight=50 \
  --set reviewService.traffic.v2Weight=50
```

### Retries and Timeouts

Each internal service has its own `VirtualService` policy:

| Service | Timeout | Retries | Retry On |
|---------|---------|---------|----------|
| product-service | 5s | 3 × 2s | 5xx, reset, connect-failure |
| order-service | 10s | 2 × 4s | 5xx, reset, connect-failure |
| review-service | 5s | 2 × 2s | 5xx, reset, connect-failure |

### Circuit Breaker

All backend services have outlier detection via `DestinationRule`. If a pod returns **3 consecutive 5xx errors**, Istio ejects it from the load-balancing pool for **30 seconds** and retries with healthy pods.

---

## Observability

### Kiali — Service Mesh Console

Kiali reads Prometheus metrics and Istio configuration to render a live graph of all service-to-service traffic, request rates, error rates, and health.

The graph shows the full call chain:
```
IngressGateway → frontend → product-service
                          → order-service → product-service
                          → review-service (v1 / v2 split visible)
```

### Access URLs

| Tool | Access |
|------|--------|
| **App** | `http://<minikube ip>:<ingress nodeport>` |
| **Kiali** | `http://<minikube ip>:<kiali nodeport>` |
| **Grafana** | `kubectl port-forward svc/grafana 3000:3000 -n istio-system` → `http://localhost:3000` |
| **Jaeger** | `kubectl port-forward svc/tracing 16686:80 -n istio-system` → `http://localhost:16686` |
| **Prometheus** | `kubectl port-forward svc/prometheus 9090:9090 -n istio-system` → `http://localhost:9090` |

Get live URLs:
```bash
echo "App:   http://$(minikube ip):$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')"
echo "Kiali: http://$(minikube ip):$(kubectl -n istio-system get svc kiali -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')"
```

---

## Common Operations

### Scaling

```bash
# Scale a specific service (no rebuild)
helm upgrade microservices ./helm-chart/microservices -n dev \
  --set productService.replicas=3

# Scale all at once
helm upgrade microservices ./helm-chart/microservices -n dev \
  --set productService.replicas=2 \
  --set orderService.replicas=2 \
  --set reviewService.v1.replicas=2 \
  --set reviewService.v2.replicas=1
```

### Canary Traffic Shift

```bash
# Gradual rollout: 50/50
helm upgrade microservices ./helm-chart/microservices -n dev \
  --set reviewService.traffic.v1Weight=50 \
  --set reviewService.traffic.v2Weight=50

# Full cutover to v2
helm upgrade microservices ./helm-chart/microservices -n dev \
  --set reviewService.traffic.v1Weight=0 \
  --set reviewService.traffic.v2Weight=100
```

### Helm Release Management

```bash
helm list -n dev                           # list releases
helm history microservices -n dev          # revision history
helm rollback microservices -n dev         # roll back one revision
helm rollback microservices 1 -n dev       # roll back to revision 1
```

### Debugging

```bash
# Pod status — each should show 2/2 (app + Envoy sidecar)
kubectl get pods -n dev -o wide

# Istio resource overview
kubectl get gateway,virtualservice,destinationrule -n dev

# Envoy sync status across all pods
istioctl proxy-status

# Detect misconfigured Istio resources
istioctl analyze -n dev

# App container logs
kubectl logs -n dev -l app=frontend -c frontend -f
kubectl logs -n dev -l app=review-service -c review-service -f

# Envoy sidecar access logs (shows every inbound/outbound request)
kubectl logs -n dev <pod-name> -c istio-proxy -f
```

### Cluster Lifecycle

```bash
minikube stop      # pause — state is preserved
minikube start     # resume
minikube delete    # destroy everything
```

---

## Rebuilding a Service

After editing source code in `services/<name>/`:

```bash
# Rebuild just one image and redeploy
docker build -t ms-product:latest ./services/product-service/
minikube image load ms-product:latest --overwrite=true
helm upgrade microservices ./helm-chart/microservices -n dev

# Or re-run the full deploy script
./05-deploy-microservices.sh
```
