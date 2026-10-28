# QRForge 🔷 — Cloud Computing Lab 2
### Kubernetes Microservices, Horizontal Pod Autoscaling (HPA) & Full-Stack Azure Observability

![Kubernetes](https://img.shields.io/badge/Kubernetes-AKS-326CE5?logo=kubernetes&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-Cloud-0078D4?logo=microsoftazure&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Multi--stage-2496ED?logo=docker&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-Azure_Managed-E6522C?logo=prometheus&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-Cache-DC382D?logo=redis&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-20_Alpine-339933?logo=nodedotjs&logoColor=white)

QRForge is a production-grade, two-tier cloud microservices application designed for high-concurrency dynamic QR code generation with Redis caching, Horizontal Pod Autoscaling (HPA v2), container health probing, and enterprise Azure observability.

---

## 🏗️ System Architecture

```mermaid
graph TB
    Client((👤 User / Locust Load Test)) -->|HTTP 80| LB[Azure Load Balancer\nPublic IP]
    LB --> FE1[Frontend Pod 1\nNode.js Express / Alpine]
    LB --> FE2[Frontend Pod 2\nNode.js Express / Alpine]
    LB --> FE3[Frontend Pod 3-5\nNode.js Express / Alpine]

    subgraph AKS["🐳 Azure Kubernetes Service (AKS): qrforge-aks"]
        subgraph NS["namespace: qrforge"]
            FE1 & FE2 & FE3
            HPA[🔄 HPA v2\nmin: 1, max: 5\nTarget CPU: 50%]
            Redis[(🗄️ Redis 7\nClusterIP Service)]
        end
        HPA -->|scales replicas 1 to 5| FE1 & FE2 & FE3
    end

    FE1 & FE2 & FE3 -->|TCP 6379 Cache Lookup| Redis

    subgraph Azure["☁️ Azure Monitor & Observability Pipeline"]
        AMA[Azure Monitor Metrics Agent\nPrometheus Scraper]
        LAW[📊 Log Analytics Workspace\n500 MB/day Cap Protection]
        Dashboard[📈 Azure Portal Dashboard\n4 Real-time Tiles]
        Alerts[🔔 Alert Rules\nCPU > 75m | Restarts > 3]
        AG[📧 Action Group: qrforge-alerts\nEmail Receiver]
    end

    FE1 & FE2 & FE3 -->|/metrics endpoint| AMA
    AMA --> LAW
    LAW --> Dashboard
    LAW --> Alerts
    Alerts --> AG

    subgraph ACR["🐋 Azure Container Registry"]
        Img[qrforgeacrhrzsue.azurecr.io\nqrforge-frontend:v1]
    end

    Img -->|imagePull| FE1 & FE2 & FE3

    subgraph Build["🔄 Container Build Pipeline"]
        Dev[Local Workstation] -->|docker build| LocalImg[qrforge-frontend:v1]
        LocalImg -->|az acr login + docker push| Img
    end
```

---

## ✨ Key Features & Engineering Highlights

1. **Two-Tier Resilient Architecture:**
   - **Frontend:** Express.js rendering high-resolution dynamic QR codes across 8 designer templates, packaged as a hardened Alpine Linux container running under UID 1001.
   - **Backend:** In-memory Redis 7 cache with TTL caching, segregated health and readiness probes (`/healthz` and `/readyz`), and automatic degradation recovery.
2. **Horizontal Pod Autoscaling (HPA v2):**
   - Configured with `minReplicas: 1`, `maxReplicas: 5`, and average CPU utilization target of `50%`.
   - Pod resource requests (`cpu: 100m, memory: 128Mi`) and limits (`cpu: 200m, memory: 256Mi`) with Linux CFS CPU throttling controls.
3. **Enterprise Observability & Guardrails:**
   - **Azure Container Insights & Managed Prometheus:** Automated scraping of `/metrics` endpoint with Prometheus recording rules.
   - **Cost Protection:** Applied `container-azm-ms-agentconfig` ConfigMap to suppress high-volume stdout/stderr container logs, keeping Log Analytics ingestion comfortably within the free 500 MB/day tier.
   - **Alerting:** Configured Azure Scheduled Query Alert rules for High CPU (`> 75m` in a 5-minute evaluation window) and Pod Restarts (`> 3` in 10 minutes).
4. **Calibrated Load Generation & Chaos Verification:**
   - Automated stress testing profiles using Locust and Hey.
   - Comprehensive telemetry capture validating pod lifecycle states, OOMKills, thread-blocking latency spikes, and horizontal scale-out lag.

---

## 📁 Repository Structure

```
├── qrforge/
│   ├── frontend/                    ← Node.js Express application
│   │   ├── server.js                ← Main server (QR gen, Redis cache, Prometheus)
│   │   ├── templates.json           ← 8 design template definitions
│   │   ├── package.json
│   │   ├── Dockerfile               ← Multi-stage Docker build (Alpine runner)
│   │   └── public/                  ← Web UI frontend
│   ├── docker-compose.yml           ← Local container orchestration
│   ├── k8s/                         ← Kubernetes production manifests
│   │   ├── namespace.yaml           ← Dedicated namespace: qrforge
│   │   ├── redis-deployment.yaml    ← Redis cache deployment
│   │   ├── redis-service.yaml       ← Internal ClusterIP service
│   │   ├── deployment.yaml          ← Frontend deployment with requests/limits
│   │   ├── service.yaml             ← Azure LoadBalancer service (Port 80)
│   │   └── hpa.yaml                 ← HorizontalPodAutoscaler v2 configuration
│   ├── monitoring/                  ← Observability configurations
│   │   ├── container-azm-ms-agentconfig.yaml ← Log Analytics ingestion filter
│   │   ├── dashboard.json           ← 4-tile Azure Portal dashboard template
│   │   ├── alerts.ps1 / alerts.sh   ← Automated alert rule provisioning
│   │   └── kql-queries.md           ← Pre-built KQL monitoring queries
│   ├── loadtest/                    ← Stress testing suites
│   │   ├── locust-gentle.py         ← Calibrated scale profile (20 users)
│   │   ├── locust-heavy.py          ← Stress load profile (50 users)
│   │   └── collect-evidence.ps1     ← Real-time telemetry logger
│   └── scripts/                     ← Automation scripts
│       ├── identity.ps1 / identity.sh
│       ├── acr-build-push.ps1 / acr-build-push.sh
│       └── aks-create.ps1 / aks-create.sh
└── README.md                        ← Project overview & architecture
```

---

## ⚙️ Quick Start & Deployment Guide

### 1. Local Development (Docker Compose)
```bash
cd qrforge
docker compose up --build -d
curl -i http://localhost:3000/healthz
curl -i http://localhost:3000/readyz
```

### 2. Build & Push Image to Azure Container Registry
```powershell
az acr login --name <YOUR_ACR_NAME>
docker build -t qrforge-frontend:v1 ./frontend -f ./frontend/Dockerfile
docker tag qrforge-frontend:v1 <YOUR_ACR_NAME>.azurecr.io/qrforge-frontend:v1
docker push <YOUR_ACR_NAME>.azurecr.io/qrforge-frontend:v1
```

### 3. Deploy Kubernetes Manifests to AKS
```powershell
az aks get-credentials --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME>
kubectl apply -f ./k8s/namespace.yaml
kubectl apply -f ./k8s/redis-deployment.yaml
kubectl apply -f ./k8s/redis-service.yaml
kubectl apply -f ./k8s/deployment.yaml
kubectl apply -f ./k8s/service.yaml
kubectl apply -f ./k8s/hpa.yaml
```

### 4. Enable Observability & Ingestion Filter
```powershell
# Apply log ingestion filter to protect Log Analytics 500 MB/day free limit
kubectl apply -f ./monitoring/container-azm-ms-agentconfig.yaml

# Provision Azure Alert Rules
.\monitoring\alerts.ps1
```

---

## ⚠️ Key Operational Findings & Deviations

1. **VM SKU Restricted (`Standard_B2s` → `Standard_B2s_v2`):**  
   Due to subscription quota restrictions across allowed regions, `Standard_B2s_v2` (2 vCPUs, 4 GiB RAM) was deployed in `koreacentral`.
2. **ACR Tasks Disabled (`az acr build` → Local Docker Build & Push):**  
   `az acr build` returned `TasksOperationsNotAllowed` on the student subscription tier. The build pipeline seamlessly fell back to local multi-stage Docker compilation and direct authenticated push via `az acr login`.
3. **Node Pool Multi-Node Scaling:**  
   Monitoring infrastructure (`ama-logs`, `ama-metrics`, `metrics-server`, and CNI) required >630m CPU. A 2-node cluster was provisioned, providing 4 total vCPUs to support horizontal pod scale-out up to 5 replicas without pending status bottlenecks.
4. **Resource Requests Autoscale Dependency:**  
   Verified that removing `resources.requests.cpu` causes `kubectl describe hpa` to display `ScalingActive: False` with `FailedGetResourceMetric`, because Kubernetes requires requested millicores to calculate the scaling percentage.
5. **Memory Sizing vs. CPU Throttling:**  
   Uncompressed high-resolution QR rendering can allocate significant RAM per operation. Calibrating memory limits and container concurrency prevents OOMKill crashes (Exit Code 137) while allowing CFS CPU throttling to smoothly trigger HPA scale-up.

---

> *Note: Detailed laboratory report, experimental graphs, and reflection answers are documented in the project submission PDF.*
