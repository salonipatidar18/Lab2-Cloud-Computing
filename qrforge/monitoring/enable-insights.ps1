# ═══════════════════════════════════════════════════════════════
# monitoring/enable-insights.ps1 — Configure Container Insights (PowerShell)
# ═══════════════════════════════════════════════════════════════
param(
    [string]$ResourceGroup = "qrforge-rg",
    [string]$ClusterName = "qrforge-aks"
)

$ErrorActionPreference = "Stop"

Write-Host "▶ Identity verification…" -ForegroundColor Cyan
& "$PSScriptRoot\..\scripts\identity.ps1"

Write-Host "`n▶ [1/3] Applying container-azm-ms-agentconfig ConfigMap…" -ForegroundColor Yellow
Write-Host "        Disabling stdout/stderr collection to protect 500 MB/day free quota"
kubectl apply -f "$PSScriptRoot\container-azm-ms-agentconfig.yaml"

Write-Host "`n▶ [2/3] Applying Prometheus scrape ConfigMap for AMA-Metrics…" -ForegroundColor Yellow
kubectl apply -f "$PSScriptRoot\..\k8s\prometheus-configmap.yaml"

Write-Host "`n▶ [3/3] Verifying AMA agents are running…" -ForegroundColor Yellow
kubectl get pods -n kube-system | Select-String -Pattern "ama-|omsagent|azure-monitor"

Write-Host "`n✅ Container Insights configured!" -ForegroundColor Green
Write-Host "   • stdout/stderr collection: DISABLED (protects free quota)"
Write-Host "   • Prometheus scraping:      ENABLED (QRForge /metrics)"
Write-Host "   • Metrics:                  ENABLED"
