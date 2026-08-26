# Minikube Microservices Demo

A fully scripted local Kubernetes environment demonstrating microservices, Helm package management, Istio service mesh traffic control, and a complete observability stack — all running on minikube with two nodes.

Two independent applications are deployed in **separate namespaces** on the same cluster, demonstrating namespace isolation and multi-application hosting on shared infrastructure.

---

## Architecture

```
                     ┌───────────────────────────────────────────────────┐
                     │                Kubernetes Cluster                 │
                     │                                                   │
  Browser            │  ┌─────────────────────────────────────────────┐  │
     │               │  │             istio-system namespace          │  │
     ▼               │  │  istiod  ·  ingressgateway (NodePort)       │  │
  NodePort           │  │  Kiali   ·  Prometheus  ·Grafana  ·Jaeger   │  |
     │               │  └─────────────────────────────────────────────┘  │
     ▼               │                         │                         │
  Istio              │          ┌──────────────┴──────────────┐          │
  IngressGateway     │          │  path-based routing         │          │
     │               │          ▼                             ▼          │
     │               │  ┌──────────────────┐  ┌───────────────────────┐  │
     │               │  │ dev-python-demo  │  │  dev-microservices    │  │
     │               │  │                  │  │                       │  │
     ├── /demo ────► │  │  demo-python-app │  │  frontend             │  │
     │               │  │  [Flask + Envoy] │  │    ├── product-svc    │  │
     └── / ───────►  │  │                  │  │    ├── order-svc      │  │
                     │  │                  │  │    │     └── product  │  │
                     │  └──────────────────┘  │    └── review-svc     │  │
                     │                        │          ├── v1 (80%) │  │
                     │                        │          └── v2 (20%) │  │
                     │                        └───────────────────────┘  │
                     │                                                   │
                     │  Node 1: minikube (control-plane)                 │
                     │  Node 2: minikube-m02 (worker)                    │
                     └───────────────────────────────────────────────────┘
```

### Namespace Separation

| Namespace | Application | URL Path | Purpose |
|-----------|-------------|----------|---------|
| `dev-python-demo` | Standalone Flask demo | `/demo` | Single-app deployment with Istio sidecar |
| `dev-microservices` | Full microservices | `/` | Multi-service topology with canary traffic split |
| `istio-system` | Istio + observability | — | Shared service mesh control plane and tooling |

Both applications share **one IngressGateway NodePort**. Istio uses path-based routing to direct traffic to the correct namespace. Each namespace has its own Gateway, VirtualService, and DestinationRule resources — completely isolated from each other.

Every pod runs with an **Envoy proxy sidecar** injected by Istio, enabling observability, retries, timeouts, and circuit-breaking without any changes to application code.

---

## Microservices (`dev-microservices`)

| Service | Role |
|---------|------|
| `frontend` | Renders the UI; fans out to product, review, and order services |
| `product-service` | Serves the product catalog |
| `order-service` | Creates orders; calls product-service internally |
| `review-service v1` | Returns reviews without star ratings |
| `review-service v2` | Returns reviews with numeric star ratings |

`review-service` runs both versions simultaneously. Istio routes **80% to v1** and **20% to v2** by default, demonstrating a canary deployment. The split is configurable without any image rebuild.

---

## File Structure

```
.
├── common.sh                          # Shared config and logging — sourced by all scripts
├── 01-init-cluster.sh                 # Install tools + start minikube (1 master + 1 worker)
├── 02-install-helm-istio.sh           # Install Helm + Istio + create both namespaces
├── 03-deploy-app.sh                   # Build + deploy standalone Flask app → dev-python-demo
├── 04-install-kiali.sh                # Install observability stack (Kiali, Prometheus, Grafana, Jaeger)
├── 05-deploy-microservices.sh         # Build + deploy microservices → dev-microservices
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
│   ├── demo-python-app/               # Standalone Flask app chart → dev-python-demo
│   │   ├── Chart.yaml
│   │   ├── values.yaml                # replicaSet, image, Istio path prefix (/demo)
│   │   └── templates/
│   │       ├── deployment.yaml        # Deployment with ReplicaSet strategy
│   │       ├── service.yaml           # ClusterIP service
│   │       ├── gateway.yaml           # Istio Gateway
│   │       ├── virtualservice.yaml    # Matches /demo, rewrites URI to / before forwarding
│   │       └── destinationrule.yaml   # Load balancer + circuit breaker
│   │
│   └── microservices/                 # Full microservices chart → dev-microservices
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
│           ├── gateway.yaml           # Istio Gateway — entry point for /
│           ├── vs-frontend.yaml       # Routes / → frontend
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

# 2. Install Helm and Istio, create both namespaces
./02-install-helm-istio.sh

# 3. Install the observability stack
./04-install-kiali.sh

# 4. Deploy the standalone Flask demo app → dev-python-demo
./03-deploy-app.sh

# 5. Build and deploy the microservices → dev-microservices
./05-deploy-microservices.sh
```

After step 5, both applications are live on the same NodePort:

```
http://<minikube-ip>:<port>/demo   → dev-python-demo  (standalone Flask app)
http://<minikube-ip>:<port>/       → dev-microservices (microservices frontend)
```

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
| `NAMESPACE_DEMO` | `dev-python-demo` | Namespace for the standalone Flask demo app |
| `NAMESPACE_MS` | `dev-microservices` | Namespace for the full microservices deployment |
| `APP_IMAGE` | `demo-python-app:latest` | Docker image for the standalone demo |
| `HELM_RELEASE` | `demo-python-app` | Helm release name for the standalone demo |
| `ISTIO_PROFILE` | `default` | Istio installation profile |

---

### `01-init-cluster.sh` — Cluster Provisioning

Installs Docker, kubectl, and minikube, then starts a two-node cluster.

```
Steps:
  1. System check  — verifies CPU ≥ 2, warns if RAM < 4 GB
  2. Docker        — installs via get.docker.com if missing
  3. kubectl       — downloads latest stable to ~/.local/bin
  4. minikube      — downloads latest to ~/.local/bin
  5. Cluster start — minikube start --nodes 2 --driver docker
  6. Node label    — labels worker node with node-role.kubernetes.io/worker
```

**Result:**
```
NAME           ROLES           STATUS   VERSION
minikube       control-plane   Ready    v1.35.x
minikube-m02   worker          Ready    v1.35.x
```

---

### `02-install-helm-istio.sh` — Helm + Istio + Namespaces

Installs the Helm package manager and the Istio service mesh, then provisions both application namespaces. Run once per cluster.

```
Steps:
  1. Helm           — installs v3 via official script to ~/.local/bin
  2. istioctl       — downloads via istio.io/downloadIstio to ~/.local/bin
  3. Istio install  — default profile (istiod + ingressgateway)
                    — ingressgateway patched to NodePort (no minikube tunnel)
  4. Namespaces     — creates dev-python-demo and dev-microservices
                    — labels both with istio-injection=enabled
```

Both namespaces are ready for deployment after this step.

---

### `03-deploy-app.sh` — Standalone Demo App

Builds the standalone Flask demo image and deploys it into the `dev-python-demo` namespace via Helm.

```bash
./03-deploy-app.sh                # 2 replicas (default)
./03-deploy-app.sh --replicas 4   # scale up
```

```
Steps:
  1. Prerequisite check — verifies cluster, Helm, and Istio are ready
  2. Source files       — writes app.py, requirements.txt, Dockerfile to /tmp/
  3. Docker build       — builds demo-python-app:latest on the host daemon
  4. Image load         — minikube image load to all nodes
  5. Helm deploy        — helm upgrade --install into dev-python-demo
```

The app is served at `http://<minikube-ip>:<port>/demo`. Istio rewrites the `/demo` prefix to `/` before forwarding to the Flask app, so the application code requires no changes.

---

### `04-install-kiali.sh` — Observability Stack

Installs four Istio addon components from the official Istio release manifests, pinned to the installed Istio version.

| Component | Role |
|-----------|------|
| **Prometheus** | Scrapes metrics from every Envoy sidecar in all namespaces |
| **Kiali** | Live service mesh topology, traffic rates, health, config validation |
| **Grafana** | Pre-built Istio dashboards (latency, error rate, throughput) |
| **Jaeger** | Distributed tracing — full request path across services |

Kiali is patched to `NodePort` for direct browser access. The other tools use `kubectl port-forward`.

---

### `05-deploy-microservices.sh` — Microservices Build and Deploy

Builds all five Docker images, loads them into every minikube node, and deploys via Helm into `dev-microservices`.

```bash
./05-deploy-microservices.sh                               # default 80/20 split
./05-deploy-microservices.sh --v1-weight 50 --v2-weight 50 # 50/50 canary
```

```
Steps:
  1. Prerequisite check — verifies cluster, Helm, and Istio are ready
  2. Docker builds      — ms-frontend, ms-product, ms-order, ms-review:v1, ms-review:v2
  3. Image load         — minikube image load to all nodes (no registry needed)
  4. Helm deploy        — helm upgrade --install microservices into dev-microservices
  5. Warm-up traffic    — sends 30 requests so Kiali graph populates on first open
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

## Helm Charts

### `demo-python-app` — `dev-python-demo` namespace

Key `values.yaml` settings:

```yaml
replicaSet:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0

istio:
  gateway:
    host: "*"
  virtualservice:
    pathPrefix: /demo    # matched by IngressGateway; rewritten to / before forwarding
    timeout: "10s"
    retries:
      attempts: 3
      perTryTimeout: "3s"
```

### `microservices` — `dev-microservices` namespace

Key `values.yaml` settings:

```yaml
reviewService:
  v1:
    replicas: 1
  v2:
    replicas: 1
  traffic:
    v1Weight: 80   # % routed to v1 (no star ratings)
    v2Weight: 20   # % routed to v2 (star ratings)
```

### Template Reference

| Template | Kind | Purpose |
|----------|------|---------|
| `deployment.yaml` | `Deployment` | Runs pods; replica count and rolling update strategy from `values.yaml` |
| `service.yaml` | `Service` (ClusterIP) | Internal DNS endpoint; not exposed externally |
| `gateway.yaml` | `Gateway` | Istio edge listener on port 80 |
| `virtualservice.yaml` (demo) | `VirtualService` | Matches `/demo`, rewrites to `/`, routes to app |
| `vs-frontend.yaml` | `VirtualService` | Routes `/` to the microservices frontend |
| `vs-product/order/review.yaml` | `VirtualService` | Per-service timeout, retries, and traffic split |
| `dr-*.yaml` | `DestinationRule` | Load-balancing algorithm, connection pool, circuit breaker |
| `dr-review.yaml` | `DestinationRule` | Defines `v1` and `v2` subsets by pod label for canary routing |

---

## Istio Traffic Management

### Path-Based Namespace Routing

A single Istio IngressGateway NodePort serves both applications. Istio routes traffic by URL path:

```
GET /demo/...  →  VirtualService (dev-python-demo)
                    └── rewrite /demo → /
                    └── route to demo-python-app.dev-python-demo

GET /...       →  VirtualService (dev-microservices)
                    └── route to frontend.dev-microservices
```

### Canary Traffic Split (`review-service`)

```
Request → review-service (ClusterIP, dev-microservices)
              │
              ├── 80% → subset v1 (version: v1 pods)  — no star ratings
              └── 20% → subset v2 (version: v2 pods)  — star ratings
```

Adjust the split without rebuilding or restarting pods:

```bash
helm upgrade microservices ./helm-chart/microservices -n dev-microservices \
  --set reviewService.traffic.v1Weight=50 \
  --set reviewService.traffic.v2Weight=50
```

### Retries and Timeouts

| Service | Timeout | Retries | Retry On |
|---------|---------|---------|----------|
| product-service | 5s | 3 × 2s | 5xx, reset, connect-failure |
| order-service | 10s | 2 × 4s | 5xx, reset, connect-failure |
| review-service | 5s | 2 × 2s | 5xx, reset, connect-failure |

### Circuit Breaker

All backend services use `outlierDetection` in their `DestinationRule`. A pod is ejected from the pool for **30 seconds** after **3 consecutive 5xx errors**.

---

## Observability

### Access URLs

| Tool | Access |
|------|--------|
| **Demo app** | `http://<minikube-ip>:<port>/demo` |
| **Microservices** | `http://<minikube-ip>:<port>/` |
| **Kiali** | `http://<minikube-ip>:<kiali-port>` |
| **Grafana** | `kubectl port-forward svc/grafana 3000:3000 -n istio-system` |
| **Jaeger** | `kubectl port-forward svc/tracing 16686:80 -n istio-system` |
| **Prometheus** | `kubectl port-forward svc/prometheus 9090:9090 -n istio-system` |

Get live URLs:
```bash
INGRESS=$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
KIALI=$(kubectl -n istio-system get svc kiali -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
IP=$(minikube ip)
echo "Demo app     : http://${IP}:${INGRESS}/demo"
echo "Microservices: http://${IP}:${INGRESS}/"
echo "Kiali        : http://${IP}:${KIALI}"
```

### Kiali Graph

Kiali shows a live topology graph per namespace. After traffic is generated, the graph shows:

- `dev-python-demo` — `IngressGateway → demo-python-app`
- `dev-microservices` — `IngressGateway → frontend → product-service / order-service / review-service (v1+v2)`

---

## Common Operations

### Scaling

```bash
# Scale the standalone demo app
helm upgrade demo-python-app ./helm-chart/demo-python-app \
  -n dev-python-demo --set replicaSet.replicas=4

# Scale a microservice (no rebuild)
helm upgrade microservices ./helm-chart/microservices \
  -n dev-microservices --set productService.replicas=3
```

### Canary Traffic Shift

```bash
# Gradual rollout: 50/50
helm upgrade microservices ./helm-chart/microservices -n dev-microservices \
  --set reviewService.traffic.v1Weight=50 \
  --set reviewService.traffic.v2Weight=50

# Full cutover to v2
helm upgrade microservices ./helm-chart/microservices -n dev-microservices \
  --set reviewService.traffic.v1Weight=0 \
  --set reviewService.traffic.v2Weight=100
```

### Helm Release Management

```bash
# List all releases across both namespaces
helm list -n dev-python-demo
helm list -n dev-microservices

# Revision history and rollback
helm history microservices -n dev-microservices
helm rollback microservices -n dev-microservices       # one revision back
helm rollback microservices 1 -n dev-microservices     # specific revision
```

### Debugging

```bash
# View pods in each namespace
kubectl get pods -n dev-python-demo -o wide
kubectl get pods -n dev-microservices -o wide

# Istio resources per namespace
kubectl get gateway,virtualservice,destinationrule -n dev-python-demo
kubectl get gateway,virtualservice,destinationrule -n dev-microservices

# Envoy sync status (all namespaces)
istioctl proxy-status

# Config validation
istioctl analyze -n dev-python-demo
istioctl analyze -n dev-microservices

# App logs
kubectl logs -n dev-microservices -l app=frontend -c frontend -f
kubectl logs -n dev-microservices -l app=review-service -c review-service -f

# Envoy sidecar access log (every inbound/outbound request)
kubectl logs -n dev-microservices <pod-name> -c istio-proxy -f
```

### Cluster Lifecycle

```bash
minikube stop      # pause — state preserved
minikube start     # resume
minikube delete    # destroy everything
```

---

## Rebuilding a Single Service

After editing source code in `services/<name>/`:

```bash
# Rebuild one image and redeploy without touching other services
docker build -t ms-product:latest ./services/product-service/
minikube image load ms-product:latest --overwrite=true
helm upgrade microservices ./helm-chart/microservices -n dev-microservices

# Full rebuild and redeploy of all microservices
./05-deploy-microservices.sh
```
