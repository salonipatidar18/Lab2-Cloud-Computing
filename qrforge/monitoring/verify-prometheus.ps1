# QRForge - Prometheus Metric Verification Script
# Queries Azure Managed Prometheus (qrforge-amw) for real metrics

$ErrorActionPreference = "Stop"

$amwBase = "https://qrforge-amw-cnc5b0hxdma4dahg.koreacentral.prometheus.monitor.azure.com/api/v1/query"

Write-Host "Obtaining Azure Monitor Prometheus access token..." -ForegroundColor Cyan
$token = (az account get-access-token --resource https://prometheus.monitor.azure.com --query accessToken -o tsv)
$headers = @{ Authorization = "Bearer $token" }

Write-Host "`n[Query 1] HTTP Request Rate (req/sec): sum(rate(http_requests_total{app=""qrforge-frontend""}[5m]))" -ForegroundColor Yellow
$qRate = "sum(rate(http_requests_total{app=`"qrforge-frontend`"}[5m]))"
$uriRate = "$amwBase`?query=$([System.Uri]::EscapeDataString($qRate))"
$resRate = Invoke-RestMethod -Uri $uriRate -Headers $headers -Method Get
$rateVal = $resRate.data.result[0].value[1]
Write-Host "Request Rate: $rateVal req/s" -ForegroundColor Green

Write-Host "`n[Query 2] P95 Request Latency (seconds): histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app=""qrforge-frontend""}[5m])) by (le))" -ForegroundColor Yellow
$qP95 = "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{app=`"qrforge-frontend`"}[5m])) by (le))"
$uriP95 = "$amwBase`?query=$([System.Uri]::EscapeDataString($qP95))"
$resP95 = Invoke-RestMethod -Uri $uriP95 -Headers $headers -Method Get
$p95Val = $resP95.data.result[0].value[1]
Write-Host "P95 Latency: $p95Val seconds" -ForegroundColor Green

Write-Host "`n[Query 3] Top http_requests_total Series:" -ForegroundColor Yellow
$qTotal = "http_requests_total{app=`"qrforge-frontend`"}"
$uriTotal = "$amwBase`?query=$([System.Uri]::EscapeDataString($qTotal))"
$resTotal = Invoke-RestMethod -Uri $uriTotal -Headers $headers -Method Get
$resTotal.data.result | Select-Object -First 5 | ForEach-Object {
    [PSCustomObject]@{
        Route  = $_.metric.route
        Method = $_.metric.method
        Status = $_.metric.status
        Count  = $_.value[1]
    }
} | Format-Table -AutoSize
