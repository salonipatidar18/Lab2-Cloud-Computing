# QRForge — KQL Queries for Azure Monitor / Log Analytics
# ══════════════════════════════════════════════════════════════════
# Paste each query into:
#   Azure Portal → Log Analytics Workspace → Logs
# Or use the Metrics Explorer for Prometheus-based metrics.
# All queries assume the workspace is connected to your AKS cluster.
# ══════════════════════════════════════════════════════════════════

---

## 1. Average CPU Utilization per Pod (Last 30 Minutes)

```kql
// Source: Container Insights Perf table (cadvisor metrics via AMA-Metrics)
Perf
| where TimeGenerated >= ago(30m)
| where ObjectName == "K8SContainer"
| where CounterName == "cpuUsageNanoCores"
| where InstanceName contains "qrforge-frontend"
| summarize
    AvgCPU_mCores = avg(CounterValue) / 1_000_000,  // nanocores → millicores
    MaxCPU_mCores = max(CounterValue) / 1_000_000
    by bin(TimeGenerated, 1m), PodName = tostring(split(InstanceName, "/")[1])
| order by TimeGenerated desc
```

**Alternative using InsightsMetrics (newer AMA-based ingestion):**

```kql
InsightsMetrics
| where TimeGenerated >= ago(30m)
| where Namespace == "container.azm.ms/Kubernetes/container"
| where Name == "cpuUsageNanoCores"
| extend PodName = tostring(parse_json(Tags)["container.azm.ms/pod"])
| where PodName startswith "qrforge-frontend"
| summarize AvgCPU_mCores = avg(Val) / 1_000_000 by bin(TimeGenerated, 1m), PodName
| render timechart
```

---

## 2. Memory Working Set Trend over Time

```kql
// Working Set = memory actively used (not reclaimable)
InsightsMetrics
| where TimeGenerated >= ago(1h)
| where Namespace == "container.azm.ms/Kubernetes/container"
| where Name == "memoryWorkingSetBytes"
| extend PodName = tostring(parse_json(Tags)["container.azm.ms/pod"])
| where PodName startswith "qrforge-frontend"
| summarize AvgMemMB = avg(Val) / (1024 * 1024) by bin(TimeGenerated, 1m), PodName
| render timechart
```

---

## 3a. Total HTTP Request Count (from Prometheus custom metrics)

```kql
// Requires Prometheus scraping to be enabled (prometheus-configmap.yaml applied).
// Metrics appear in the InsightsMetrics table with Namespace = "prometheus".
InsightsMetrics
| where TimeGenerated >= ago(30m)
| where Namespace == "prometheus"
| where Name == "http_requests_total"
| extend
    Route  = tostring(parse_json(Tags)["route"]),
    Status = tostring(parse_json(Tags)["status"]),
    Method = tostring(parse_json(Tags)["method"])
| summarize TotalRequests = sum(Val) by bin(TimeGenerated, 1m), Route, Status
| order by TimeGenerated desc
| render timechart
```

---

## 3b. P95 HTTP Request Latency (Prometheus histogram)

```kql
// http_request_duration_seconds_bucket exported by prom-client
// Azure Monitor stores histogram buckets as individual series (le label = upper bound)
InsightsMetrics
| where TimeGenerated >= ago(30m)
| where Namespace == "prometheus"
| where Name == "http_request_duration_seconds_bucket"
| extend
    le    = todouble(tostring(parse_json(Tags)["le"])),
    route = tostring(parse_json(Tags)["route"])
| where route == "/api/heavy" or route == "/api/qr"
| summarize
    Bucket_Count = sum(Val)
    by bin(TimeGenerated, 1m), route, le
| order by TimeGenerated, le asc
// Note: True percentile from histograms requires aggregating bucket counts.
// For a quick view, filter to le="1" (requests under 1s) vs le="+Inf" (all).
```

**Simpler P95 approximation using summarize percentile (if raw duration is stored):**

```kql
InsightsMetrics
| where TimeGenerated >= ago(30m)
| where Namespace == "prometheus"
| where Name == "http_request_duration_seconds_sum"
| extend route = tostring(parse_json(Tags)["route"])
| summarize TotalDuration = sum(Val) by bin(TimeGenerated, 1m), route
| render timechart
```

---

## 4. Active Replica Count During Autoscaling

```kql
// Count distinct qrforge-frontend pods that are Running at each minute
KubePodInventory
| where TimeGenerated >= ago(1h)
| where Namespace == "qrforge"
| where Name startswith "qrforge-frontend"
| where PodStatus == "Running"
| summarize ReplicaCount = dcount(Name) by bin(TimeGenerated, 1m)
| render timechart
```

**Alternative — from kube-state metrics (if available):**

```kql
InsightsMetrics
| where TimeGenerated >= ago(1h)
| where Namespace == "prometheus"
| where Name == "kube_deployment_status_replicas_available"
| extend DeploymentName = tostring(parse_json(Tags)["deployment"])
| where DeploymentName == "qrforge-frontend"
| summarize Replicas = max(Val) by bin(TimeGenerated, 1m)
| render timechart
```

---

## 5. Pod Restart Count in Last 10 Minutes

```kql
KubePodInventory
| where TimeGenerated >= ago(10m)
| where Namespace == "qrforge"
| where Name startswith "qrforge-frontend"
| summarize
    MaxRestarts = max(PodRestartCount),
    MinRestarts = min(PodRestartCount)
    by Name
| extend RestartsDelta = MaxRestarts - MinRestarts
| where RestartsDelta > 0
| project Name, RestartsDelta, MaxRestarts
| order by RestartsDelta desc
```

---

## 6. Composite: CPU + Replica Count Correlation (for reflection question e)

```kql
// Overlay CPU utilization and replica count to show scale-up trigger
let cpu = InsightsMetrics
| where TimeGenerated >= ago(1h)
| where Namespace == "container.azm.ms/Kubernetes/container"
| where Name == "cpuUsageNanoCores"
| extend PodName = tostring(parse_json(Tags)["container.azm.ms/pod"])
| where PodName startswith "qrforge-frontend"
| summarize AvgCPU_mCores = avg(Val)/1e6 by bin(TimeGenerated, 1m);
let replicas = KubePodInventory
| where TimeGenerated >= ago(1h)
| where Namespace == "qrforge"
| where Name startswith "qrforge-frontend"
| where PodStatus == "Running"
| summarize Replicas = dcount(Name) by bin(TimeGenerated, 1m);
cpu | join kind=leftouter replicas on TimeGenerated
| project TimeGenerated, AvgCPU_mCores, Replicas
| render timechart
```
