# QRForge - Timeline Evidence Collector
# Logs HPA targets/replicas, pod CPU/mem, and ready pod count every 15 seconds.

param(
    [int]$IntervalSeconds = 15,
    [int]$TotalMinutes = 15,
    [string]$LogFileName = "timeline.log"
)

$resultsDir = Join-Path $PSScriptRoot "results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$logFile = Join-Path $resultsDir $LogFileName
$startTime = Get-Date
$endTime = $startTime.AddMinutes($TotalMinutes)

"================================================================" | Out-File -FilePath $logFile -Append -Encoding utf8
"QRForge Load Test Timeline Log Started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Append -Encoding utf8
"================================================================" | Out-File -FilePath $logFile -Append -Encoding utf8

while ((Get-Date) -lt $endTime) {
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # 1. HPA targets and replicas via structured JSON
    $hpaJsonRaw = kubectl get hpa qrforge-frontend -n qrforge -o json 2>$null
    $hpaTargets = "N/A"
    $hpaReplicas = "N/A"
    if ($hpaJsonRaw) {
        try {
            $hpaObj = $hpaJsonRaw | ConvertFrom-Json
            $currentUtil = ($hpaObj.status.currentMetrics | Where-Object { $_.type -eq 'Resource' -and $_.resource.name -eq 'cpu' }).resource.current.averageUtilization
            $targetUtil = ($hpaObj.spec.metrics | Where-Object { $_.type -eq 'Resource' -and $_.resource.name -eq 'cpu' }).resource.target.averageUtilization
            if ($null -ne $currentUtil) {
                $hpaTargets = "$($currentUtil)%/$($targetUtil)%"
            } else {
                $hpaTargets = "<unknown>/$($targetUtil)%"
            }
            $hpaReplicas = $hpaObj.status.currentReplicas
        } catch {
            $hpaTargets = "ParseErr"
            $hpaReplicas = "ParseErr"
        }
    }

    # 2. Count of frontend pods in Ready state
    $readyPods = (kubectl get pods -n qrforge -l app=qrforge-frontend --no-headers 2>$null | Where-Object { $_ -match "1/1\s+Running" }).Count

    # 3. Top pods
    $topPods = kubectl top pods -n qrforge --no-headers 2>$null | Out-String

    # Log entry
    $logEntry = "[$now] HPA: Targets=$hpaTargets, Replicas=$hpaReplicas | ReadyPods=$readyPods"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding utf8
    if ($topPods.Trim()) {
        $topPods.Trim().Split("`n") | ForEach-Object {
            "    $_" | Out-File -FilePath $logFile -Append -Encoding utf8
        }
    }

    Start-Sleep -Seconds $IntervalSeconds
}

"================================================================" | Out-File -FilePath $logFile -Append -Encoding utf8
"QRForge Load Test Timeline Log Completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Append -Encoding utf8
"================================================================" | Out-File -FilePath $logFile -Append -Encoding utf8
