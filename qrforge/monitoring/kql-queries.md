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
// Source: Container Insights Perf table (cadvisor metrics via AMA)
Perf
| where TimeGenerated >= ago(30m)
| where ObjectName == "K8SContainer"
| where CounterName == "cpuUsageNanoCores"
| where InstanceName endswith "/frontend"
| summarize
    AvgCPU_mCores = avg(CounterValue) / 1_000_000,  // nanocores → millicores
    MaxCPU_mCores = max(CounterValue) / 1_000_000
    by bin(TimeGenerated, 1m)
| order by TimeGenerated desc
| render timechart
```

---

## 2. Memory Working Set Trend over Time

```kql
// Working Set = memory actively used (not reclaimable)
Perf
| where TimeGenerated >= ago(1h)
| where ObjectName == "K8SContainer"
| where CounterName == "memoryWorkingSetBytes"
| where InstanceName endswith "/frontend"
| summarize AvgMemMB = avg(CounterValue) / (1024 * 1024) by bin(TimeGenerated, 1m)
| order by TimeGenerated desc
| render timechart
```

---

## 3. Total HTTP Request Count & P95 Latency (Prometheus custom metrics)

### PromQL Queries (Run in Azure Monitor Workspace -> qrforge-amw -> Prometheus Explorer):

**P95 Request Latency (seconds):**
```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app="qrforge-frontend"}[5m])) by (le))
```

**HTTP Request Rate (requests/second):**
```promql
sum(rate(http_requests_total{app="qrforge-frontend"}[5m]))
```

**Total HTTP Requests Counter by Route & Status:**
```promql
sum by (route, status) (http_requests_total{app="qrforge-frontend"})
```

### Pinning PromQL Tiles to Azure Portal Dashboard:
1. In Azure Portal, navigate to **Azure Monitor workspaces** &rarr; **qrforge-amw**.
2. In the left menu under **Monitoring**, click **Prometheus explorer**.
3. Paste the PromQL query above and click **Run query**.
4. Click the **Pin to dashboard** icon (pushpin) in the upper right corner of the chart.
5. Select your target dashboard (e.g. `qrforge-monitoring-dashboard` or Private/Shared) and click **Pin**.

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

---

## 7. Azure Monitor Alert Rules Queries

### Alert 1: CPU > 75% for 5 minutes (Option A: Max Pod CPU)
> **Note on Alert Design:** This alert evaluates the **maximum (busiest) pod CPU** across frontend pods (`MaxCPU_mCores > 75`, which is 75% of the 100m CPU request) rather than the fleet-wide average. Because the Kubernetes HPA actively scales out replicas to keep the average utilization near 50%, an average across all pods would be diluted during scale-out. Targeting the busiest pod ensures the alert reliably fires when workload spikes exceed 75m for the 5-minute evaluation window.

```kql
Perf
| where TimeGenerated >= ago(5m)
| where ObjectName == "K8SContainer" and CounterName == "cpuUsageNanoCores" and InstanceName endswith "/frontend"
| summarize MaxCPU_mCores = max(CounterValue) / 1000000 by bin(TimeGenerated, 1m)
| where MaxCPU_mCores > 75
```
- **Operator:** GreaterThan 0
- **Evaluation Frequency:** 1m
- **Window Size:** 5m
- **Severity:** 2 (Warning)

### Alert 2: Pod Restarts > 3 in 10 minutes

```kql
KubePodInventory
| where TimeGenerated >= ago(10m)
| where Namespace == "qrforge"
| where Name startswith "qrforge-frontend"
| summarize MaxRestarts = max(PodRestartCount) by Name
| where MaxRestarts > 3
```
- **Operator:** GreaterThan 0
- **Evaluation Frequency:** 5m
- **Window Size:** 10m
- **Severity:** 1 (Error)
