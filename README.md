# Minikube Python Demo

A four-step bash setup that provisions a local Kubernetes cluster, installs Helm, Istio, and a full observability stack (Kiali, Prometheus, Grafana, Jaeger), then deploys a Python Flask app with service-mesh traffic management.

---

## Architecture Overview

```
Browser
  │
  ▼
Istio IngressGateway (NodePort)
  │  binds to → Gateway resource
  ▼
VirtualService  ──── timeout / retries / routing rules
  │
  ▼
Service (ClusterIP)
  │
  ├─▶ Pod 1 [Flask app + Envoy sidecar]  ← node: minikube (control-plane)
  └─▶ Pod 2 [Flask app + Envoy sidecar]  ← node: minikube-m02 (worker)

DestinationRule  ──── load balancing / circuit-breaker / connection pool

Observability (istio-system namespace)
  ├── Kiali       — service mesh topology & health console
  ├── Prometheus  — metrics scraping & storage
  ├── Grafana     — metrics dashboards
  └── Jaeger      — distributed tracing
```

Every pod gets an **Envoy proxy sidecar** injected by Istio. All traffic flows through these sidecars, giving you observability, retries, timeouts, and circuit-breaking without touching app code.

---

## File Structure

```
.
├── common.sh                          # Shared config and logging (sourced by all scripts)
├── 01-init-cluster.sh                 # Install tools + start minikube cluster
├── 02-install-helm-istio.sh           # Install Helm + Istio + configure namespace
├── 03-deploy-app.sh                   # Build image + helm install/upgrade
├── 04-install-kiali.sh                # Install observability stack (Kiali, Prometheus, Grafana, Jaeger)
├── helm-chart/
│   └── demo-python-app/
│       ├── Chart.yaml                 # Chart metadata
│       ├── values.yaml                # All tuneable defaults
│       └── templates/
│           ├── deployment.yaml        # Kubernetes Deployment + ReplicaSet config
│           ├── service.yaml           # Kubernetes Service (ClusterIP)
│           ├── gateway.yaml           # Istio Gateway
│           ├── virtualservice.yaml    # Istio VirtualService
│           └── destinationrule.yaml   # Istio DestinationRule
└── README.md
```

---

## Prerequisites

| Requirement | Minimum |
|-------------|---------|
| OS          | Linux (amd64) |
| CPU         | 2 cores |
| RAM         | 6 GB (Istio + observability stack) |
| Disk        | 20 GB free |
| Privileges  | `sudo` (for Docker install only) |

---

## Quick Start

```bash
./01-init-cluster.sh          # ~3 min  — cluster up
./02-install-helm-istio.sh    # ~3 min  — Helm + Istio ready
./03-deploy-app.sh            # ~1 min  — app deployed to dev namespace
./04-install-kiali.sh         # ~2 min  — observability stack live
```

---

## Script Details

### `common.sh`

Sourced by every script. Single place to change any default.

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLUSTER_NODES` | `2` | Total nodes (1 master + 1 worker) |
| `CPUS_PER_NODE` | `2` | vCPUs per node |
| `MEMORY_PER_NODE` | `2048` MB | RAM per node |
| `DISK_SIZE` | `20g` | Disk per node |
| `NAMESPACE` | `dev` | Kubernetes namespace for the app |
| `APP_IMAGE` | `demo-python-app:latest` | Docker image name and tag |
| `APP_DIR` | `/tmp/demo-python-app` | Temp dir for app source |
| `HELM_RELEASE` | `demo-python-app` | Helm release name |
| `ISTIO_PROFILE` | `default` | Istio installation profile |

---

### `01-init-cluster.sh`

Installs CLI tools and starts the cluster. Safe to re-run — existing installs are detected.

| Step | Action |
|------|--------|
| System check | Verifies ≥2 CPUs; warns if RAM < 4 GB |
| Docker | Installs via `get.docker.com` if missing; confirms daemon is running |
| kubectl | Downloads latest stable to `~/.local/bin` |
| minikube | Downloads latest to `~/.local/bin` |
| Cluster start | `minikube start --nodes 2 --driver docker`; waits for both nodes `Ready`; labels worker |

---

### `02-install-helm-istio.sh`

Installs the package manager and service mesh. Only needs to run once per cluster.

| Step | Action |
|------|--------|
| Helm | Installs via official script to `~/.local/bin` |
| istioctl | Downloads to `~/.local/bin` via `istio.io/downloadIstio` |
| Istio | Installs with `default` profile (istiod + ingressgateway); gateway patched to `NodePort` — no `minikube tunnel` needed |
| Namespace | Creates `dev` namespace labeled `istio-injection=enabled` for automatic sidecar injection |

---

### `03-deploy-app.sh`

Builds the Docker image and deploys or upgrades via Helm into the `dev` namespace. Re-run any time.

```bash
./03-deploy-app.sh                # 2 replicas (default)
./03-deploy-app.sh --replicas 4   # scale up
```

| Step | Action |
|------|--------|
| Guards | Exits early if cluster / Helm / Istio are not ready |
| Source files | Writes `app.py`, `requirements.txt`, `Dockerfile` to `/tmp/demo-python-app/` |
| Docker build | Builds `demo-python-app:latest` on the host Docker daemon |
| Image load | `minikube image load` pushes the image to **all** nodes — required for multi-node clusters |
| Helm deploy | `helm upgrade --install` applies the chart; `--wait` blocks until pods are ready |

---

### `04-install-kiali.sh`

Installs the full Istio observability stack from the official Istio addon manifests, pinned to the installed Istio version. Kiali is patched to `NodePort` for direct browser access.

| Tool | Role | Access |
|------|------|--------|
| **Prometheus** | Scrapes metrics from all Envoy sidecars | `kubectl port-forward svc/prometheus 9090:9090 -n istio-system` |
| **Kiali** | Service mesh topology, traffic rates, health, config validation | NodePort (URL printed on install) |
| **Grafana** | Pre-built Istio dashboards (request rate, latency, error rate) | `kubectl port-forward svc/grafana 3000:3000 -n istio-system` |
| **Jaeger** | Distributed tracing — see full request path across services | `kubectl port-forward svc/tracing 16686:80 -n istio-system` |

---

## Helm Chart

### `values.yaml` — tuneable defaults

```yaml
replicaSet:
  replicas: 2             # ← change this to scale
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # max extra pods during rollout
      maxUnavailable: 0   # zero-downtime: always keep N pods live

image:
  name: demo-python-app
  tag: latest
  pullPolicy: Never       # loaded directly into minikube, no registry needed

service:
  type: ClusterIP         # traffic enters via Istio IngressGateway, not directly
  port: 80
  targetPort: 5000

istio:
  gateway:
    host: "*"
  virtualservice:
    timeout: "10s"
    retries:
      attempts: 3
      perTryTimeout: "3s"
  destinationrule:
    loadBalancer: ROUND_ROBIN   # ROUND_ROBIN | LEAST_CONN | RANDOM
    connectionPool:
      maxConnections: 100
      http1MaxPendingRequests: 100
    outlierDetection:
      consecutive5xxErrors: 5
      interval: "10s"
      baseEjectionTime: "30s"
```

### Template Breakdown

| Template | Kind | Purpose |
|----------|------|---------|
| `deployment.yaml` | `Deployment` | Manages the ReplicaSet; drives replica count and rolling update strategy from `replicaSet.*` values |
| `service.yaml` | `Service` (ClusterIP) | Internal cluster endpoint; not exposed directly to outside |
| `gateway.yaml` | `Gateway` | Istio edge listener — binds to the ingressgateway pod on port 80 |
| `virtualservice.yaml` | `VirtualService` | Per-request timeout, automatic retries, traffic weight routing |
| `destinationrule.yaml` | `DestinationRule` | Load-balancing algorithm, connection pool, circuit-breaker (outlier detection) |

---

## Istio Components

### Gateway
Entry point for external traffic. Accepts HTTP on port 80 for any hostname and hands off to the VirtualService.

### VirtualService
Defines how traffic is routed after entering the gateway:
- **Timeout** — drops requests exceeding `10s`
- **Retries** — retries on `5xx`, connection failures, resets (3 attempts × 3s each)
- **Weight** — `100%` to the single service; split to enable canary deployments

### DestinationRule
Defines how Istio connects to the pods:
- **Load balancer** — `ROUND_ROBIN` distributes evenly across healthy pods
- **Connection pool** — caps concurrent connections to prevent overload
- **Outlier detection** — ejects pods returning 5+ consecutive errors for 30s (circuit-breaker)

---

## Kiali — Service Mesh Observability

Kiali reads from Prometheus and the Istio control plane to provide:

- **Graph view** — live topology of services, workloads, and traffic rates
- **Health indicators** — request success rate, error rate, latency per service
- **Config validation** — flags misconfigured Istio resources (missing gateways, invalid selectors)
- **Tracing integration** — links to Jaeger traces directly from a service card

Generate traffic to populate the graph:
```bash
for i in $(seq 1 100); do curl -s http://<minikube-ip>:<ingress-port> > /dev/null; done
```

---

## Scaling

```bash
# Via the deploy script (rebuilds + upgrades)
./03-deploy-app.sh --replicas 4

# Via Helm only (no rebuild)
helm upgrade demo-python-app ./helm-chart/demo-python-app \
  -n dev --set replicaSet.replicas=4

# Inspect the ReplicaSet Kubernetes creates
kubectl get replicaset -n dev
```

---

## Useful Commands

```bash
# ── Cluster ────────────────────────────────────────────────────────────────
kubectl get nodes -o wide

# ── App pods (2/2 READY = Flask app + Envoy sidecar) ──────────────────────
kubectl get pods -n dev -o wide
kubectl get replicaset -n dev

# ── Istio resources ────────────────────────────────────────────────────────
kubectl get gateway,virtualservice,destinationrule -n dev
istioctl proxy-status                              # Envoy sync state
istioctl analyze -n dev                            # config health check

# ── App logs ───────────────────────────────────────────────────────────────
kubectl logs -n dev -l app=demo-python-app -c demo-python-app -f
kubectl logs -n dev <pod-name> -c istio-proxy      # Envoy sidecar traffic log

# ── Observability ──────────────────────────────────────────────────────────
kubectl get pods -n istio-system                   # Kiali, Prometheus, Grafana, Jaeger
kubectl port-forward svc/grafana 3000:3000 -n istio-system
kubectl port-forward svc/tracing 16686:80 -n istio-system
kubectl port-forward svc/prometheus 9090:9090 -n istio-system

# ── Helm ───────────────────────────────────────────────────────────────────
helm list -n dev
helm history demo-python-app -n dev
helm rollback demo-python-app -n dev               # roll back one revision

# ── Cluster lifecycle ──────────────────────────────────────────────────────
minikube dashboard
minikube stop
minikube delete
```
