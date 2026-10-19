#!/usr/bin/env bash
# Stops everything Sepiabox is billed for by use. All data is kept.
# Blob Storage keeps billing; a stopped PostgreSQL server restarts by itself after 7 days.
set -euo pipefail

RG="${RG:-rg-sepiabox}"
WEB_APP="${WEB_APP:-sepiabox-web}"
PG_SERVER="${PG_SERVER:-sepiabox-pg}"
SB_NAMESPACE="${SB_NAMESPACE:-sepiabox-sb}"
SB_QUEUE="${SB_QUEUE:-media-discovered}"

echo "Disabling ingress on $WEB_APP..."
az containerapp ingress disable -g "$RG" -n "$WEB_APP"

echo "Stopping PostgreSQL server $PG_SERVER..."
az postgres flexible-server stop -g "$RG" -n "$PG_SERVER"

echo "Disabling queue $SB_QUEUE..."
az servicebus queue update -g "$RG" --namespace-name "$SB_NAMESPACE" -n "$SB_QUEUE" --status Disabled

echo "Done. Data is preserved."
