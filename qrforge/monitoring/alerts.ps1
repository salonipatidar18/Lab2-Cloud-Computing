# ═══════════════════════════════════════════════════════════════
# monitoring/alerts.ps1 — Create Azure Monitor Alert Rules (PowerShell)
# ═══════════════════════════════════════════════════════════════
param(
    [Parameter(Mandatory=$true)]
    [string]$AlertEmail,
    [string]$ResourceGroup = "qrforge-rg",
    [string]$ClusterName = "qrforge-aks",
    [string]$ActionGroupName = "qrforge-alerts",
    [string]$LogWorkspaceName = "qrforge-logs"
)

$ErrorActionPreference = "Stop"

Write-Host "▶ Identity verification…" -ForegroundColor Cyan
& "$PSScriptRoot\..\scripts\identity.ps1"

Write-Host "`n▶ [1/4] Getting resource IDs…" -ForegroundColor Yellow
$ClusterId = (az aks show --resource-group $ResourceGroup --name $ClusterName --query id -o tsv).Trim()
$LogWorkspaceId = (az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $LogWorkspaceName --query id -o tsv 2>$null)
if ($LogWorkspaceId) { $LogWorkspaceId = $LogWorkspaceId.Trim() }

Write-Host "        Cluster ID: $ClusterId"
Write-Host "        Log Workspace ID: $LogWorkspaceId"

Write-Host "`n▶ [2/4] Creating Action Group with email receiver: $AlertEmail…" -ForegroundColor Yellow
az monitor action-group create `
    --resource-group $ResourceGroup `
    --name $ActionGroupName `
    --short-name "qrforge" `
    --action email "qrforge-email" $AlertEmail `
    --output table

$ActionGroupId = (az monitor action-group show --resource-group $ResourceGroup --name $ActionGroupName --query id -o tsv).Trim()

Write-Host "`n▶ [3/4] Creating Alert Rule 1: CPU > 75% for 5 minutes…" -ForegroundColor Yellow
az monitor metrics alert create `
    --name "qrforge-high-cpu" `
    --resource-group $ResourceGroup `
    --scopes $ClusterId `
    --condition "avg Percentage CPU > 75" `
    --window-size "5m" `
    --evaluation-frequency "1m" `
    --severity 2 `
    --description "QRForge frontend CPU utilization exceeded 75% for 5 minutes" `
    --action $ActionGroupId `
    --output table

Write-Host "`n▶ [4/4] Creating Alert Rule 2: Pod restarts > 3 in 10 minutes…" -ForegroundColor Yellow
if ($LogWorkspaceId) {
    az monitor scheduled-query create `
        --name "qrforge-pod-restarts" `
        --resource-group $ResourceGroup `
        --scopes $LogWorkspaceId `
        --condition-query "KubePodInventory | where TimeGenerated >= ago(10m) | where Namespace == 'qrforge' | where Name startswith 'qrforge-frontend' | summarize MaxRestarts = max(PodRestartCount) by Name | where MaxRestarts > 3" `
        --condition "count > 0" `
        --evaluation-frequency "PT5M" `
        --window-size "PT10M" `
        --severity 1 `
        --description "QRForge frontend pods restarted more than 3 times in 10 minutes" `
        --action-groups $ActionGroupId `
        --output table
} else {
    Write-Host "  SKIPPED: Log workspace ID not found. Configure restart alert in portal." -ForegroundColor Yellow
}

Write-Host "`n✅ Alerts configured successfully for $AlertEmail!" -ForegroundColor Green
