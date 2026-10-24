#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# monitoring/alerts.sh — Create Azure Monitor Alert Rules
# ═══════════════════════════════════════════════════════════════
# Creates:
#   1. Action Group with email notification
#   2. Alert: CPU > 75% for 5 minutes
#   3. Alert: Pod restarts > 3 in 10 minutes (Log Analytics query alert)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration — edit before running ───────────────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-qrforge-rg}"
CLUSTER_NAME="${CLUSTER_NAME:-qrforge-aks}"
LOCATION="${LOCATION:-eastus}"
ALERT_EMAIL="${ALERT_EMAIL:-student@university.edu}"   # Replace with your email
ACTION_GROUP_NAME="qrforge-alerts"
LOG_WORKSPACE_NAME="qrforge-logs"
# ───────────────────────────────────────────────────────────────

echo "▶ Identity verification…"
bash "$(dirname "$0")/../scripts/identity.sh"

echo ""
echo "▶ [1/4] Getting resource IDs…"
CLUSTER_ID=$(az aks show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --query id -o tsv)

LOG_WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "${RESOURCE_GROUP}" \
  --workspace-name "${LOG_WORKSPACE_NAME}" \
  --query id -o tsv 2>/dev/null || echo "")

echo "        Cluster ID: ${CLUSTER_ID}"
echo "        Log Workspace ID: ${LOG_WORKSPACE_ID}"

echo ""
echo "▶ [2/4] Creating Action Group with email receiver…"
az monitor action-group create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACTION_GROUP_NAME}" \
  --short-name "qrforge" \
  --action email \
      "qrforge-email" \
      "${ALERT_EMAIL}" \
  --output table

ACTION_GROUP_ID=$(az monitor action-group show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACTION_GROUP_NAME}" \
  --query id -o tsv)

echo ""
echo "▶ [3/4] Creating Alert Rule 1: CPU > 75% for 5 minutes…"
# Container CPU % metric from Container Insights
# Metric: cpuExceededPercentage | Namespace: insights.container/containers
az monitor metrics alert create \
  --name "qrforge-high-cpu" \
  --resource-group "${RESOURCE_GROUP}" \
  --scopes "${CLUSTER_ID}" \
  --condition \
    "avg Percentage CPU > 75" \
  --window-size "5m" \
  --evaluation-frequency "1m" \
  --severity 2 \
  --description "QRForge frontend CPU utilization exceeded 75% for 5 minutes" \
  --action "${ACTION_GROUP_ID}" \
  --output table \
  || echo "  NOTE: If the above fails, use the portal alternative below."

# ── Portal alternative for CPU alert ──────────────────────────
# Azure Portal > Monitor > Alerts > Create alert rule
#   Scope:     Your AKS cluster resource
#   Condition: "Percentage CPU" metric > 75, aggregation=Average
#   Window:    5 minutes, Evaluation frequency: 1 minute
#   Action:    Select action group "qrforge-alerts"
#   Severity:  2 (Warning)

echo ""
echo "▶ [4/4] Creating Alert Rule 2: Pod restarts > 3 in 10 minutes (Scheduled Query)…"
if [[ -n "${LOG_WORKSPACE_ID}" ]]; then
  az monitor scheduled-query create \
    --name "qrforge-pod-restarts" \
    --resource-group "${RESOURCE_GROUP}" \
    --scopes "${LOG_WORKSPACE_ID}" \
    --condition-query \
      "KubePodInventory
       | where TimeGenerated >= ago(10m)
       | where Namespace == 'qrforge'
       | where Name startswith 'qrforge-frontend'
       | summarize MaxRestarts = max(PodRestartCount) by Name
       | where MaxRestarts > 3" \
    --condition "count > 0" \
    --evaluation-frequency "PT5M" \
    --window-size "PT10M" \
    --severity 1 \
    --description "QRForge frontend pods restarted more than 3 times in 10 minutes" \
    --action-groups "${ACTION_GROUP_ID}" \
    --output table \
    || echo "  NOTE: Scheduled query alert creation requires log workspace data to exist."
else
  echo "  SKIPPED: Log workspace not found. Create the restart alert manually in the portal."
fi

echo ""
echo "✅ Alerts configured!"
echo "   Action Group : ${ACTION_GROUP_NAME}"
echo "   Email        : ${ALERT_EMAIL}"
echo ""
echo "   Test the alerts:"
echo "   1. Run the load test: bash loadtest/run-hey.sh"
echo "   2. Watch email for alert notifications"
echo "   3. Portal: Monitor > Alerts > Alert History"
