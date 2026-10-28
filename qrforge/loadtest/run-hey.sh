#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# loadtest/run-hey.sh — Load test with 'hey' HTTP load generator
# ═══════════════════════════════════════════════════════════════
# 'hey' sends HTTP requests as fast as possible with -c concurrency
# for -z duration. This will overwhelm the QR generation CPU on a
# Standard_B2s_v2 node and trigger HPA to scale up.
#
# Install 'hey':
#   Linux/macOS: go install github.com/rakyll/hey@latest
#   Or download binary: https://github.com/rakyll/hey/releases
#   Windows: winget install hey (or download the .exe)
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────
EXTERNAL_IP="${EXTERNAL_IP:-$(kubectl get svc qrforge-frontend -n qrforge -o jsonpath='{.status.loadBalancer.ingress[0].ip}')}"
DURATION="4m"        # Run for 4 minutes (short enough to save credits)
CONCURRENCY=50       # 50 parallel workers
QR_SIZE=2000         # Large QR = CPU-intensive (2000×2000 px)
QR_N=10              # 10 QR codes per request
# ───────────────────────────────────────────────────────────────

echo "╔══════════════════════════════════════════════╗"
echo "║         QRForge Load Test — hey              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Identity verification (run before screenshot):"
bash "$(dirname "$0")/../scripts/identity.sh"

echo ""
echo "Target URL  : http://${EXTERNAL_IP}/api/heavy?size=${QR_SIZE}&n=${QR_N}"
echo "Duration    : ${DURATION}"
echo "Concurrency : ${CONCURRENCY}"
echo ""
echo "▶ Starting load test — watch in another terminal:"
echo "  kubectl get hpa -n qrforge -w"
echo "  kubectl get pods -n qrforge -w"
echo "  kubectl top pods -n qrforge"
echo ""
echo "Starting in 5 seconds…"
sleep 5

# ─── Phase 1: Warm-up (lower concurrency) ─────────────────────
echo "── PHASE 1: Warm-up (20 workers, 30s) ──"
hey -z 30s -c 20 \
  "http://${EXTERNAL_IP}/api/heavy?size=${QR_SIZE}&n=${QR_N}"

echo ""
echo "── PHASE 2: Full load (${CONCURRENCY} workers, ${DURATION}) ──"
echo "    *** SCREENSHOT hey output + kubectl get hpa ***"
hey -z "${DURATION}" \
  -c "${CONCURRENCY}" \
  -t 60 \
  "http://${EXTERNAL_IP}/api/heavy?size=${QR_SIZE}&n=${QR_N}"

echo ""
echo "✅ Load test complete!"
echo "   Wait 60-90 seconds and observe HPA scaling back down."
echo "   Check: kubectl describe hpa qrforge-frontend -n qrforge"
