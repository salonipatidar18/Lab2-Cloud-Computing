#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# scripts/identity.sh — Student Identity Verification
# Run this BEFORE every screenshot command to prove your identity
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

echo "╔══════════════════════════════════════════════╗"
echo "║       STUDENT IDENTITY VERIFICATION          ║"
echo "╚══════════════════════════════════════════════╝"
az account show --query "{Azure_Email: user.name, Subscription_ID: id}" -o table
echo ""
echo "OS User : $(whoami)"
echo "Hostname: $(hostname)"
echo "Date    : $(date)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
