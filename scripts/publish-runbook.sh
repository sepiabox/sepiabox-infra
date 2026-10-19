#!/usr/bin/env bash
# Uploads automation/Stop-Sepiabox.ps1 to the Automation account and publishes it (S-030).
# Run after every deployment of shutdown/main.bicep, which only creates the runbook's shell.
set -euo pipefail

RG="${RG:-rg-sepiabox}"
AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-sepiabox-automation}"
RUNBOOK="${RUNBOOK:-Stop-Sepiabox}"
RUNBOOK_FILE="${RUNBOOK_FILE:-$(dirname "$0")/../automation/Stop-Sepiabox.ps1}"

# The automation commands live in an az extension; install it without asking.
az config set extension.use_dynamic_install=yes_without_prompt --only-show-errors

echo "Uploading $RUNBOOK_FILE to $AUTOMATION_ACCOUNT/$RUNBOOK..."
az automation runbook replace-content \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK" \
  --content "@$RUNBOOK_FILE"

echo "Publishing $RUNBOOK..."
az automation runbook publish \
  --resource-group "$RG" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --name "$RUNBOOK"
