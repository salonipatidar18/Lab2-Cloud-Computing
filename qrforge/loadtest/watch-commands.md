# QRForge — Load Test Watch Commands
# ══════════════════════════════════════════════════════════════════
# Run these commands in SEPARATE terminal windows WHILE the load test runs.
# Each terminal shows a different aspect of the autoscaling behavior.
# Start all terminals before running loadtest/run-hey.sh
# ══════════════════════════════════════════════════════════════════

## 🔵 TERMINAL 1 — Identity Verification (run first, screenshot the output)

```bash
# Run this BEFORE every screenshot
echo "=== STUDENT IDENTITY VERIFICATION ===" && \
az account show --query "{Azure_Email: user.name, Subscription_ID: id}" -o table && \
echo "OS User: $(whoami) | Host: $(hostname) | Date: $(date)"
```

---

## 🟢 TERMINAL 2 — Watch HPA scaling in real time

```bash
# -w streams continuous updates. Screenshot when REPLICAS column changes.
kubectl get hpa -n qrforge -w
```

**Expected output progression:**
```
NAME                REFERENCE                      TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
qrforge-frontend    Deployment/qrforge-frontend    10%/50%         1         5         1          5m
qrforge-frontend    Deployment/qrforge-frontend    78%/50%         1         5         1          6m
qrforge-frontend    Deployment/qrforge-frontend    78%/50%         1         5         2          6m30s
qrforge-frontend    Deployment/qrforge-frontend    92%/50%         1         5         3          7m
```

---

## 🟡 TERMINAL 3 — Watch pod lifecycle (creation during scale-up)

```bash
kubectl get pods -n qrforge -w
```

**Expected output:**
```
NAME                                READY   STATUS    RESTARTS   AGE
qrforge-frontend-5d7b8c9f4-xk2p7   1/1     Running   0          10m
qrforge-frontend-5d7b8c9f4-ab3q1   0/1     Pending   0          5s   ← scale-up
qrforge-frontend-5d7b8c9f4-ab3q1   0/1     Running   0          8s
qrforge-frontend-5d7b8c9f4-ab3q1   1/1     Running   0          18s  ← readiness passed
```

---

## 🟠 TERMINAL 4 — CPU/Memory per pod (updates every 5s)

```bash
# Requires metrics-server to be running
watch -n 5 kubectl top pods -n qrforge
```

Or without `watch`:
```bash
while true; do
  echo "--- $(date) ---"
  kubectl top pods -n qrforge
  sleep 5
done
```

---

## 🔴 TERMINAL 5 — Detailed HPA status (run on demand)

```bash
kubectl describe hpa qrforge-frontend -n qrforge
```

**Key fields to screenshot:**
- `Conditions:` — look for `ScalingActive=True`, `AbleToScale=True`
- `Events:` — shows scaling decisions with timestamps
- `Metrics:` — `resource cpu on pods  ... / 50%` shows actual vs target

---

## 🟣 TERMINAL 6 — Services and external IP

```bash
kubectl get svc -n qrforge
kubectl get pods,svc,hpa -n qrforge
```

---

## 📸 Screenshot Checklist

| # | What to Screenshot | Command / Portal Page |
|---|---|---|
| 1 | **Student identity** | Terminal 1 output above |
| 2 | **ACR build logs / Push** | `az acr build …` error (`TasksOperationsNotAllowed`) & `docker push` digest |
| 3 | **AKS creation** | `az aks create …` output (scripts/aks-create.sh) |
| 4 | **Initial state (before load)** | `kubectl get pods,svc,hpa -n qrforge` |
| 5 | **HPA scaling up** | Terminal 2 — REPLICAS column increasing |
| 6 | **Pods during load** | Terminal 3 — new pods in Pending/Running |
| 7 | **CPU per pod** | Terminal 4 — top pods during peak load |
| 8 | **HPA describe** | Terminal 5 output |
| 9 | **Azure Monitor Dashboard** | Portal → Dashboard → QRForge Monitoring |
| 10 | **CPU tile (portal)** | Container Insights → CPU graph, all pods |
| 11 | **Replica count tile** | Portal → replica count graph showing 1→N→1 |
| 12 | **Alert rule triggered** | Portal → Monitor → Alerts → Alert History |
| 13 | **Alert email** | Your inbox — email from Azure Monitor |
| 14 | **Scale-down** | Terminal 2 — REPLICAS decreasing after load stops |

---

## ⚙️ Quick Reference Commands

```bash
# Get external IP
kubectl get svc qrforge-frontend -n qrforge -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Manually trigger a single heavy request (to verify the endpoint works)
EXTERNAL_IP=$(kubectl get svc qrforge-frontend -n qrforge -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl "http://${EXTERNAL_IP}/api/heavy?size=2000&n=5"

# Check readiness probe
curl "http://${EXTERNAL_IP}/readyz"

# Check Prometheus metrics
curl "http://${EXTERNAL_IP}/metrics" | grep -E 'http_requests|qr_generated'

# Force HPA to re-evaluate now (useful for testing)
kubectl patch hpa qrforge-frontend -n qrforge \
  -p '{"metadata":{"annotations":{"force-refresh":"'$(date +%s)'"}}}'
```
