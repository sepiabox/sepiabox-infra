// Kill switch (S-030): at €45 the budget calls this action group, which starts the Stop-Sepiabox
// runbook. The runbook stops what is billed by use and keeps all data; scripts/resume.sh undoes it.
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Raw URL of automation/Stop-Sepiabox.ps1, pinned to a commit.')
param runbookContentUri string

@description('Webhook URL from the Automation generateUri API. Empty keeps the existing webhook and action group.')
@secure()
param webhookUri string = ''

@description('When the webhook stops working; the deploy workflow creates it once, so give it a long life.')
param webhookExpiry string = dateTimeAdd(utcNow(), 'P5Y')

var actionGroupName = 'sepiabox-shutdown'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource automation 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: 'sepiabox-automation'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Free'
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automation
  name: 'Stop-Sepiabox'
  location: location
  properties: {
    runbookType: 'PowerShell72'
    description: 'Stops the web ingress, PostgreSQL and the manifests queue; keeps all data.'
    publishContentLink: {
      uri: runbookContentUri
    }
  }
}

// The runbook changes resources in this group only.
resource runbookCanManageGroup 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, automation.id, contributorRoleId)
  properties: {
    principalId: automation.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
  }
}

// A webhook's URL can only be set when it is created, so the webhook and the action group that
// calls it are deployed only when the workflow passes a freshly generated URL.
resource webhook 'Microsoft.Automation/automationAccounts/webhooks@2015-10-31' = if (!empty(webhookUri)) {
  parent: automation
  name: 'budget-90-percent'
  properties: {
    isEnabled: true
    expiryTime: webhookExpiry
    uri: webhookUri
    runbook: {
      name: runbook.name
    }
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(webhookUri)) {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'sbx-stop'
    enabled: true
    automationRunbookReceivers: [
      {
        name: 'stop-sepiabox'
        automationAccountId: automation.id
        runbookName: runbook.name
        webhookResourceId: webhook.id
        isGlobalRunbook: false
        serviceUri: webhookUri
        useCommonAlertSchema: false
      }
    ]
  }
}

output actionGroupId string = resourceId('Microsoft.Insights/actionGroups', actionGroupName)
output automationPrincipalId string = automation.identity.principalId
