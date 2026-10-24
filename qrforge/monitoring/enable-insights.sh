#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# monitoring/enable-insights.sh
# Enable Container Insights + restrict logging to protect free quota
# ═══════════════════════════════════════════════════════════════
# Azure Monitor free tier: 500 MB/day for logs.
# Without restrictions, AKS stdout/stderr floods this quota in hours.
# This script configures the agent to collect ONLY metrics (not raw logs).
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-qrforge-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-qrforge-aks}"
# ───────────────────────────────────────────────────────────────

echo "▶ Identity verification…"
bash "$(dirname "$0")/../scripts/identity.sh"

echo ""
echo "▶ [1/3] Applying container-azm-ms-agentconfig ConfigMap…"
echo "        This disables stdout/stderr collection (saves log quota)"
kubectl apply -f - <<'YAML'
# container-azm-ms-agentconfig — Controls what the AMA-Logs agent collects.
# Official docs: https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-agent-config
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system
data:
  schema-version: v1
  config-version: ver1
  log-data-collection-settings: |-
    # ── Log collection settings ──────────────────────────────
    [log_collection_settings]
      [log_collection_settings.stdout]
        # DISABLED to protect the 500 MB/day free quota.
        # Re-enable for debugging by setting enabled = true.
        enabled = false
        exclude_namespaces = ["kube-system"]

      [log_collection_settings.stderr]
        # DISABLED — same reason as stdout.
        enabled = false
        exclude_namespaces = ["kube-system"]

      [log_collection_settings.env_var]
        # Collect environment variables from containers (lightweight)
        enabled = true

      [log_collection_settings.enrich_container_logs]
        enabled = true

  metric-collection-settings: |-
    # ── Metrics collection settings ──────────────────────────
    [metric_collection_settings.collect_kube_system_pv_metrics]
      enabled = true
YAML

echo ""
echo "▶ [2/3] Applying Prometheus scrape ConfigMap for AMA-Metrics…"
kubectl apply -f "$(dirname "$0")/../k8s/prometheus-configmap.yaml"

echo ""
echo "▶ [3/3] Verifying AMA agents are running…"
kubectl get pods -n kube-system | grep -E 'ama-|omsagent|azure-monitor'

echo ""
echo "✅ Container Insights configured!"
echo "   • stdout/stderr collection: DISABLED (protects free quota)"
echo "   • Prometheus scraping:      ENABLED (QRForge /metrics)"
echo "   • Metrics:                  ENABLED"
echo ""
echo "   Wait ~5 minutes, then check Azure Portal:"
echo "   AKS > Monitoring > Insights"
