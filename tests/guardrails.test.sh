#!/usr/bin/env bash
# Checks the compiled guardrails template (S-031).
# Usage: tests/guardrails.test.sh <compiled guardrails/main.json>
set -euo pipefail

template="${1:?usage: $0 <compiled main.json>}"
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

policy="$(of_type Microsoft.Authorization/policyAssignments)"
workspace="$(of_type Microsoft.OperationalInsights/workspaces)"

# Exactly the services in docs/architecture.md (sepiabox-platform), plus what S-030 deploys here.
expected_types='[
  "Microsoft.App/containerApps",
  "Microsoft.App/jobs",
  "Microsoft.App/managedEnvironments",
  "Microsoft.Automation/automationAccounts",
  "Microsoft.Automation/automationAccounts/runbooks",
  "Microsoft.CognitiveServices/accounts",
  "Microsoft.CognitiveServices/accounts/projects",
  "Microsoft.ContainerRegistry/registries",
  "Microsoft.DBforPostgreSQL/flexibleServers",
  "Microsoft.EventGrid/systemTopics",
  "Microsoft.Insights/actionGroups",
  "Microsoft.Insights/components",
  "Microsoft.KeyVault/vaults",
  "Microsoft.ManagedIdentity/userAssignedIdentities",
  "Microsoft.OperationalInsights/workspaces",
  "Microsoft.ServiceBus/namespaces",
  "Microsoft.Storage/storageAccounts"
]'

check "policy is the built-in Allowed resource types" "$(jq -r '.variables.allowedResourceTypesPolicyId' "$template")" "a08ec900-254a-4555-9bf5-e42af04b5c5c"
check "assignment uses that definition" "$(jq -r '.properties.policyDefinitionId' <<<"$policy")" "[tenantResourceId('Microsoft.Authorization/policyDefinitions', variables('allowedResourceTypesPolicyId'))]"
check "policy is enforced" "$(jq -r '.properties.enforcementMode' <<<"$policy")" "Default"
check "policy takes the allowed list" "$(jq -r '.properties.parameters.listOfResourceTypesAllowed.value' <<<"$policy")" "[variables('allowedResourceTypes')]"
check "allowed list is exactly the architecture's types" "$(jq -c '.variables.allowedResourceTypes | sort' "$template")" "$(jq -c 'sort' <<<"$expected_types")"
check "workspace is sepiabox-logs" "$(jq -r '.name' <<<"$workspace")" "sepiabox-logs"
check "workspace daily cap is 0.15 GB" "$(jq -r '.properties.workspaceCapping.dailyQuotaGb' <<<"$workspace")" "[json('0.15')]"
check "workspace keeps logs 30 days" "$(jq -r '.properties.retentionInDays' <<<"$workspace")" "30"
check "workspace id is an output" "$(jq -r '.outputs.logAnalyticsWorkspaceId.value' "$template")" "[resourceId('Microsoft.OperationalInsights/workspaces', 'sepiabox-logs')]"

if (( failures > 0 )); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
