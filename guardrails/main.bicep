// Guardrails for rg-sepiabox (S-031): only the services in the architecture can be created, and
// telemetry has a daily cap so a noisy app cannot spend the budget on logs.
targetScope = 'resourceGroup'

param location string = resourceGroup().location

// The built-in policy runs in Indexed mode, so only types with a location are checked; child
// resources such as databases, queues or blob containers need no entry.
var allowedResourceTypes = [
  'Microsoft.App/containerApps'
  'Microsoft.App/jobs'
  'Microsoft.App/managedEnvironments'
  'Microsoft.App/managedEnvironments/managedCertificates'
  'Microsoft.Automation/automationAccounts'
  'Microsoft.Automation/automationAccounts/runbooks'
  'Microsoft.ContainerRegistry/registries'
  'Microsoft.DBforPostgreSQL/flexibleServers'
  'Microsoft.EventGrid/systemTopics'
  'Microsoft.Insights/actionGroups'
  'Microsoft.Insights/components'
  'Microsoft.KeyVault/vaults'
  'Microsoft.ManagedIdentity/userAssignedIdentities'
  'Microsoft.OperationalInsights/workspaces'
  'Microsoft.ServiceBus/namespaces'
  'Microsoft.Storage/storageAccounts'
]

// Built-in "Allowed resource types".
var allowedResourceTypesPolicyId = 'a08ec900-254a-4555-9bf5-e42af04b5c5c'

resource allowedTypes 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'sepiabox-allowed-resource-types'
  properties: {
    displayName: 'Sepiabox: only the resource types in the architecture'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', allowedResourceTypesPolicyId)
    enforcementMode: 'Default'
    parameters: {
      listOfResourceTypesAllowed: {
        value: allowedResourceTypes
      }
    }
  }
}

// 0.15 GB a day stays inside the free 5 GB a month. Application Insights uses it (S-032).
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'sepiabox-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: json('0.15')
    }
  }
}

output logAnalyticsWorkspaceId string = logs.id
output allowedResourceTypes array = allowedResourceTypes
