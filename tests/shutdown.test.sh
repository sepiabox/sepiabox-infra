#!/usr/bin/env bash
# Checks the compiled kill-switch template (S-030).
# Usage: tests/shutdown.test.sh <compiled shutdown/main.json>
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
of_type() { jq -c "$resources | map(select(.type == \"$1\"))[0]" "$template"; }
variable() { jq -r --arg name "$1" '.variables[$name]' "$template"; }

automation="$(of_type Microsoft.Automation/automationAccounts)"
runbook="$(of_type Microsoft.Automation/automationAccounts/runbooks)"
role="$(of_type Microsoft.Authorization/roleAssignments)"
webhook="$(of_type Microsoft.Automation/automationAccounts/webhooks)"
group="$(of_type Microsoft.Insights/actionGroups)"

check "automation account is sepiabox-automation" "$(jq -r '.name' <<<"$automation")" "sepiabox-automation"
check "automation account is on the free tier" "$(jq -r '.properties.sku.name' <<<"$automation")" "Free"
check "automation account has a managed identity" "$(jq -r '.identity.type' <<<"$automation")" "SystemAssigned"
check "runbook is Stop-Sepiabox" "$(jq -r '.name' <<<"$runbook")" "[format('{0}/{1}', 'sepiabox-automation', 'Stop-Sepiabox')]"
check "runbook runs on PowerShell 7.2" "$(jq -r '.properties.runbookType' <<<"$runbook")" "PowerShell72"
check "identity gets the role in contributorRoleId" "$(jq -r '.properties.roleDefinitionId' <<<"$role")" "[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', variables('contributorRoleId'))]"
check "contributorRoleId is the built-in Contributor role" "$(variable contributorRoleId)" "b24988ac-6180-42a0-ab88-20f7382dd24c"
check "role is assigned at resource group scope" "$(jq -r '.scope // "resource group"' <<<"$role")" "resource group"
check "webhook is created only with a generated URL" "$(jq -r '.condition' <<<"$webhook")" "[not(empty(parameters('webhookUri')))]"
check "action group is created only with a generated URL" "$(jq -r '.condition' <<<"$group")" "[not(empty(parameters('webhookUri')))]"
check "webhook URL is a secure parameter" "$(jq -r '.parameters.webhookUri.type' "$template")" "securestring"
check "action group name comes from actionGroupName" "$(jq -r '.name' <<<"$group")" "[variables('actionGroupName')]"
check "actionGroupName is sepiabox-shutdown" "$(variable actionGroupName)" "sepiabox-shutdown"
check "action group starts the runbook" "$(jq -r '.properties.automationRunbookReceivers[0].runbookName' <<<"$group")" "Stop-Sepiabox"
check "action group calls the webhook" "$(jq -r '.properties.automationRunbookReceivers[0].serviceUri' <<<"$group")" "[parameters('webhookUri')]"

# The runbook code is uploaded from the checkout, never fetched from a public URL (private repos).
check "runbook has no content link" "$(jq '.properties | has("publishContentLink")' <<<"$runbook")" "false"
check "template fetches nothing from raw.githubusercontent.com" "$(grep -c 'raw.githubusercontent.com' "$template" || true)" "0"
check "workflow fetches nothing from raw.githubusercontent.com" "$(grep -c 'raw.githubusercontent.com' "$workflow" || true)" "0"
check "workflow publishes the runbook after each shutdown deployment" "$(grep -c 'scripts/publish-runbook.sh' "$workflow")" "$(grep -c 'template-file shutdown/main.bicep' "$workflow")"

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
