#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# scripts/acr-build-push.sh — Build & Push to Azure Container Registry
# ═══════════════════════════════════════════════════════════════
# Prerequisites: az CLI logged in, Docker daemon running locally
# Usage: bash scripts/acr-build-push.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration variables — edit these before running ───────
RESOURCE_GROUP="qrforge-rg"
LOCATION="${LOCATION:-koreacentral}"
ACR_NAME="qrforgeacr$(openssl rand -hex 3)"   # Must be globally unique; override if needed
IMAGE_TAG="qrforge-frontend:v1"
# ───────────────────────────────────────────────────────────────

echo "▶ [1/5] Running identity verification…"
bash "$(dirname "$0")/identity.sh"

echo ""
echo "▶ [2/5] Creating resource group: ${RESOURCE_GROUP} in ${LOCATION}…"
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --output table

echo ""
echo "▶ [3/5] Creating Azure Container Registry: ${ACR_NAME} (Basic SKU)…"
az acr create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ACR_NAME}" \
  --sku Basic \
  --admin-enabled false \
  --output table

echo ""
echo "▶ [4/5] Building image via ACR Tasks (az acr build)…"
echo "        *** SCREENSHOT THIS OUTPUT for Task 1 ***"
echo ""
# az acr build uses ACR Tasks: builds the Dockerfile remotely on Azure,
# never needs a local Docker daemon, and pushes directly to the registry.
az acr build \
  --registry "${ACR_NAME}" \
  --image "${IMAGE_TAG}" \
  ./frontend \
  --file ./frontend/Dockerfile

echo ""
echo "▶ [5/5] (Alternative) Classic docker build + tag + push flow:"
echo "        Uncomment the lines below if you prefer local docker build."
echo ""
# az acr login --name "${ACR_NAME}"
# docker build -t "${IMAGE_TAG}" ./frontend
# docker tag "${IMAGE_TAG}" "${ACR_NAME}.azurecr.io/${IMAGE_TAG}"
# docker push "${ACR_NAME}.azurecr.io/${IMAGE_TAG}"

echo ""
echo "✅ ACR build complete!"
echo "   Registry : ${ACR_NAME}.azurecr.io"
echo "   Image    : ${ACR_NAME}.azurecr.io/${IMAGE_TAG}"
echo ""
echo "   Save these values for the AKS deploy:"
echo "   export ACR_NAME=${ACR_NAME}"
echo "   export RESOURCE_GROUP=${RESOURCE_GROUP}"
