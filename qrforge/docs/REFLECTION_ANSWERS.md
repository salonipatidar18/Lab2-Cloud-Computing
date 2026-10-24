# QRForge — Reflection Answers
# Assignment Questions (a–e)
# ══════════════════════════════════════════════════════════════════
# Instructions: Fill in your measured values in the [BLANK] sections.
# The guidance outlines the key concepts to explain.
# ══════════════════════════════════════════════════════════════════

---

## (a) Readiness Probe vs Liveness Probe — Behavior and Purpose

### Guidance

**Readiness probe** (`/readyz`): Kubernetes checks this before routing traffic to a pod.
- If it fails, the pod is **removed from the LoadBalancer endpoint set** — no new requests reach it.
- The pod is NOT restarted. It simply stops receiving traffic until readiness is restored.
- In QRForge, `/readyz` pings Redis. If Redis is down, the pod stops accepting requests.
- This prevents users from hitting a pod that can't serve QR codes (Redis dependency failure).

**Liveness probe** (`/healthz`): Kubernetes uses this to decide whether to restart the container.
- If it fails `failureThreshold` (4) consecutive times, the container is **killed and restarted**.
- In QRForge, `/healthz` only checks that the Node.js process is alive (not Redis).
- This avoids unnecessary restarts when Redis is temporarily unavailable.

**Practical difference (what you observed):**

> [BLANK: Describe what happened when you scaled down Redis or when Redis was restarting.
>  E.g., "When I ran `kubectl scale deploy redis -n qrforge --replicas=0`, within ~15 seconds
>  the frontend pods showed 0/1 READY in kubectl get pods, traffic stopped routing to them,
>  but the pods did NOT restart. When Redis came back, the pods became Ready again."]

---

## (b) Alert Latency — Why Alerts Fire Delayed

### Guidance

Azure Monitor metric alerts have a pipeline of delays:

1. **Metrics scrape interval**: The AMA-Metrics agent scrapes pods every ~30–60 seconds.
2. **Ingestion latency**: Metrics take 1–5 minutes to appear in Azure Monitor after collection.
3. **Alert evaluation window**: Our CPU alert uses a 5-minute evaluation window.
4. **Evaluation frequency**: The alert engine runs every 1 minute.

Total worst-case delay from CPU spike to email:
= scrape interval + ingestion latency + evaluation window + SMTP delivery
≈ 1 min + 3 min + 5 min + 1 min = **~10 minutes**

**Your measured values:**

| Event | Time |
|---|---|
| Load test started | [BLANK: HH:MM:SS] |
| CPU exceeded 75% (kubectl top) | [BLANK: HH:MM:SS] |
| Alert "Fired" in portal | [BLANK: HH:MM:SS] |
| Email received in inbox | [BLANK: HH:MM:SS] |
| Total alert latency | [BLANK: X minutes] |

**Why this matters**: The alert evaluation window (5 min) means a transient spike that lasts
only 2-3 minutes will NOT trigger the alert, avoiding false positives.

---

## (c) Diagnosing Slowness — Which Metrics to Check First

### Priority order for diagnosing QRForge slowness:

**1. P95/P99 HTTP Request Latency** (`http_request_duration_seconds` histogram)
   - Why first? Latency is the symptom the user observes. A spike in P95 proves slowness.
   - Check: `InsightsMetrics | where Name == "http_request_duration_seconds_sum"…`

**2. HTTP 5xx Error Rate** (`http_requests_total` label `status=~"5..+"`)
   - High error rate indicates the service is failing, not just slow.
   - Distinguish 5xx (server error) from 4xx (client error).

**3. CPU Throttling** (container CPU throttled seconds / total CPU seconds)
   - If CPU is hitting the limit (200m), the Node.js process is throttled by cgroups.
   - This is the primary cause of slowness under load since QR generation is CPU-bound.
   - Check: `InsightsMetrics | where Name == "cpuThrottledNanoCores"`

**4. Memory Saturation** (`memoryWorkingSetBytes` approaching 256Mi limit)
   - If memory approaches the limit, the Node.js GC thrashes, causing latency spikes.
   - OOM kills appear as pod restarts in KubePodInventory.

**5. Redis Latency / Connection Errors**
   - Cache miss rate spike (`cache_misses_total`) means every request hits QR generation.
   - Redis connection failures make `/readyz` return 503.

**Your findings during the load test:**

> [BLANK: "During the load test, P95 latency rose from __ ms to __ ms. CPU throttling
>  was at __% at peak load. Redis cache hit rate dropped to __% because /api/heavy
>  bypasses the cache."]

---

## (d) HPA CPU Metrics — Baseline vs Peak, and the `resources.requests` Requirement

### Baseline vs Peak CPU:

| Phase | kubectl top (millicores) | HPA CPU% | Replicas |
|---|---|---|---|
| Idle (before load) | [BLANK: ~__m] | [BLANK: ~__%] | 1 |
| Warm-up phase | [BLANK: ~__m] | [BLANK: ~__%] | [BLANK] |
| Peak load | [BLANK: ~__m] | [BLANK: ~__%] | [BLANK: 2-5] |
| After scale-up | [BLANK: ~__m per pod] | [BLANK: ~__%] | [BLANK] |

**`kubectl describe hpa` output during load:**
```
[BLANK: paste your actual describe output here]
```

### Why `resources.requests` is MANDATORY for HPA:

The HPA computes: `CPU% = actualCPU / requests.cpu × 100`

**If you REMOVE `resources.requests.cpu` from the deployment manifest and apply it:**

```bash
kubectl describe hpa qrforge-frontend -n qrforge
```

You will see:
```
Conditions:
  Type            Status  Reason                   Message
  ScalingActive   False   FailedGetResourceMetric  unable to get metrics for resource cpu:
                                                   no metrics returned from resource metrics API
  AbleToScale     True    ReadyForNewScale
```

The HPA logs `FailedGetResourceMetric` because the metrics-server cannot compute CPU percentage
without a known denominator (the request value). Without a request, `kubectl top pods` still
shows raw millicores, but the HPA cannot express that as a percentage of "what was promised to
the scheduler" — so it becomes ScalingActive=False and **autoscaling stops working entirely**.

> [BLANK: Confirm you tested this by temporarily removing requests.cpu and observe the HPA condition]

---

## (e) Latency vs Replica Count — Correlation and Scale-Up Delay

### Correlation observed:

> [BLANK: Describe what you saw. Example:
>  "Initially with 1 replica, P95 latency was ~800ms. After HPA scaled to 3 replicas (~2 minutes
>   after load started), P95 latency dropped to ~300ms. With 5 replicas, latency stabilized at
>   ~200ms, close to baseline."]

### Scale-up delay breakdown (the 2+ minutes between load start and latency drop):

| Stage | Duration | Explanation |
|---|---|---|
| Metrics scrape interval | ~30–60s | AMA-Metrics / metrics-server polls every 30–60s |
| HPA sync period | ~15s | HPA evaluates metrics every 15 seconds |
| Pod scheduling | ~5–10s | Kubernetes scheduler assigns the new pod to a node |
| Container image pull | ~10–30s | `imagePullPolicy: Always` re-checks the ACR tag |
| Application startup | ~2–5s | Node.js `server.js` starts and binds port 3000 |
| Readiness probe passes | ~10–15s | `/readyz` must succeed (initialDelay=10s + periods) |
| **Total** | **~90–150s** | **Before new pod receives any traffic** |

**Why the delay matters:**
During scale-up, the existing pods are throttled but new pods aren't yet ready. This creates
a window where latency is high and error rates may spike. The `stabilizationWindowSeconds: 0`
in the HPA scaleUp behavior minimizes this by not waiting before adding pods.

**CPU Throttling as the explanatory metric:**
The `cpu: 200m` limit means the container cannot use more than 200 millicores even if the
node has spare capacity. When the QR generation loop consumes >200m, the cgroup throttles the
process — adding latency to each request even though CPU% on the node looks low.
This is why watching `cpuThrottledNanoCores` is more diagnostic than watching `cpuUsageNanoCores`
alone.

### Measured scale-up timeline:

| Time | Event |
|---|---|
| T+0s | Load test started |
| T+[BLANK]s | HPA first detected CPU > 50% |
| T+[BLANK]s | HPA scaled to 2 replicas |
| T+[BLANK]s | New pod became Ready |
| T+[BLANK]s | P95 latency began to drop |
| T+[BLANK]s | Load stopped |
| T+[BLANK]s | HPA scaled back to 1 (60s stabilization) |
