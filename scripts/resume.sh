#!/usr/bin/env bash
# Undoes emergency-stop.sh and the Stop-Sepiabox runbook: traffic, PostgreSQL and the queue come back.
set -euo pipefail

RG="${RG:-rg-sepiabox}"
WEB_APP="${WEB_APP:-sepiabox-web}"
WEB_PORT="${WEB_PORT:-8080}"
PG_SERVER="${PG_SERVER:-sepiabox-pg}"
SB_NAMESPACE="${SB_NAMESPACE:-sepiabox-sb}"
SB_QUEUE="${SB_QUEUE:-manifests}"

echo "Starting PostgreSQL server $PG_SERVER..."
az postgres flexible-server start -g "$RG" -n "$PG_SERVER"

echo "Enabling queue $SB_QUEUE..."
az servicebus queue update -g "$RG" --namespace-name "$SB_NAMESPACE" -n "$SB_QUEUE" --status Active

# Last, so nobody reaches the app before its database is back.
echo "Enabling external ingress on $WEB_APP (port $WEB_PORT)..."
az containerapp ingress enable -g "$RG" -n "$WEB_APP" --type external --target-port "$WEB_PORT" --transport auto

echo "Done. Sepiabox is running again."
