#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# scripts/aks-create.sh — Create AKS cluster, attach ACR, get creds
# ═══════════════════════════════════════════════════════════════
# Prerequisites: acr-build-push.sh completed; $ACR_NAME exported
# Usage: ACR_NAME=<your-acr> bash scripts/aks-create.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-qrforge-rg}"
LOCATION="${LOCATION:-eastus}"
CLUSTER_NAME="${CLUSTER_NAME:-qrforge-aks}"
ACR_NAME="${ACR_NAME:?ACR_NAME must be set. Export it from acr-build-push.sh}"
NODE_COUNT=1
NODE_VM_SIZE="Standard_B2s"
LOG_WORKSPACE_NAME="qrforge-logs"
# ───────────────────────────────────────────────────────────────

echo "▶ Identity verification…"
bash "$(dirname "$0")/identity.sh"

echo ""
echo "▶ [1/5] Creating Log Analytics workspace for Container Insights…"
LOG_WORKSPACE_ID=$(az monitor log-analytics workspace create \
  --resource-group "${RESOURCE_GROUP}" \
  --workspace-name "${LOG_WORKSPACE_NAME}" \
  --location "${LOCATION}" \
  --query id -o tsv)

echo "        Workspace ID: ${LOG_WORKSPACE_ID}"

echo ""
echo "▶ [2/5] Creating AKS cluster: ${CLUSTER_NAME}"
echo "        Node SKU: ${NODE_VM_SIZE}, Count: ${NODE_COUNT}"
echo "        *** SCREENSHOT THIS OUTPUT ***"
echo ""
az aks create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --node-count "${NODE_COUNT}" \
  --node-vm-size "${NODE_VM_SIZE}" \
  --attach-acr "${ACR_NAME}" \
  --enable-addons monitoring \
  --workspace-resource-id "${LOG_WORKSPACE_ID}" \
  --enable-managed-identity \
  --generate-ssh-keys \
  --output table

echo ""
echo "▶ [3/5] Getting credentials (merges into ~/.kube/config)…"
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${CLUSTER_NAME}" \
  --overwrite-existing

echo ""
echo "▶ [4/5] Verifying cluster connection…"
kubectl get nodes

echo ""
echo "▶ [5/5] Enabling metrics server (for HPA CPU metrics)…"
# On AKS the metrics server is usually pre-installed.
# This command verifies it's present.
kubectl get deployment metrics-server -n kube-system 2>/dev/null \
  && echo "  metrics-server: already installed" \
  || echo "  NOTE: metrics-server not found — apply the official manifest if HPA CPU metrics don't work"

echo ""
echo "✅ AKS cluster ready!"
echo "   Cluster : ${CLUSTER_NAME}"
echo "   RG      : ${RESOURCE_GROUP}"
echo ""
echo "Next: update k8s/deployment.yaml image placeholder, then:"
echo "  sed -i 's/<ACR_NAME>/${ACR_NAME}/g' k8s/deployment.yaml"
echo "  kubectl apply -f k8s/"
