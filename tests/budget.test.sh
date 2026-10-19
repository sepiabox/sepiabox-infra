#!/usr/bin/env bash
# Checks the compiled budget template and the deploy workflow (S-029, S-030).
# Usage: tests/budget.test.sh <compiled budget/main.json>
set -euo pipefail

template="${1:?usage: $0 <compiled main.json>}"
workflow="$(dirname "$0")/../.github/workflows/deploy.yml"
failures=0

check() {
  local description="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description: expected '$expected', got '$actual'"
    failures=$((failures + 1))
  fi
}

resources='[.resources | if type == "object" then to_entries | map(.value)[] else .[] end]'
budget="$(jq -c "$resources | map(select(.type == \"Microsoft.Consumption/budgets\"))[0]" "$template")"
anomaly="$(jq -c "$resources | map(select(.type == \"Microsoft.CostManagement/scheduledActions\"))[0]" "$template")"

check "budget amount defaults to 50" "$(jq -r '.parameters.amount.defaultValue' "$template")" "50"
check "budget uses the amount parameter" "$(jq -r '.properties.amount' <<<"$budget")" "[parameters('amount')]"
check "budget is monthly" "$(jq -r '.properties.timeGrain' <<<"$budget")" "Monthly"
check "actual-cost thresholds" "$(jq -c '[.properties.notifications[] | select(.thresholdType == "Actual") | .threshold] | sort' <<<"$budget")" "[50,80,90]"
check "90% notification calls the shutdown action group" "$(jq -c '[.properties.notifications[] | select(.threshold == 90) | .contactGroups[]]' <<<"$budget")" '["[parameters('"'"'shutdownActionGroupId'"'"')]"]'
check "shutdown action group defaults to sepiabox-shutdown in rg-sepiabox" "$(jq -r '.parameters.shutdownActionGroupId.defaultValue' "$template" | grep -c '/resourceGroups/rg-sepiabox/providers/Microsoft.Insights/actionGroups/sepiabox-shutdown')" "1"
check "only the 90% notification starts the shutdown" "$(jq '[.properties.notifications[] | select(.contactGroups != null)] | length' <<<"$budget")" "1"
check "forecast thresholds" "$(jq -c '[.properties.notifications[] | select(.thresholdType == "Forecasted") | .threshold]' <<<"$budget")" "[100]"
check "every notification is enabled" "$(jq -r '[.properties.notifications[] | .enabled] | all' <<<"$budget")" "true"
check "anomaly alert is an InsightAlert" "$(jq -r '.kind' <<<"$anomaly")" "InsightAlert"
check "anomaly alert runs daily" "$(jq -r '.properties.schedule.frequency' <<<"$anomaly")" "Daily"

# The workflow must sign in with OIDC (federated credential) and never carry a secret.
check "workflow can request an OIDC token" "$(grep -c 'id-token: write' "$workflow")" "1"
check "every deploy job signs in with azure/login" "$(grep -c 'uses: azure/login@' "$workflow")" "$(grep -c 'environment: production' "$workflow")"
check "workflow has no client secret or creds" "$(grep -Eci 'client-secret|creds:|password' "$workflow" || true)" "0"
check "workflow reads no repository secrets" "$(grep -c 'secrets\.' "$workflow" || true)" "0"

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
