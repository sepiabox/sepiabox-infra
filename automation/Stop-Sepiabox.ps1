<#
.SYNOPSIS
Stops everything Sepiabox is billed for by use and keeps all data (S-030).

.DESCRIPTION
Started by the budget's 90% notification (€45) through the sepiabox-shutdown action group.
Same three operations as scripts/emergency-stop.sh; scripts/resume.sh undoes them.
Every step is attempted even if an earlier one fails, so one missing resource does not
leave the others running. Only Az.Accounts is needed, which every Automation runtime ships.
#>
param(
    # Sent by the action group; not needed, the runbook always does the same thing.
    [object] $WebhookData,
    [string] $ResourceGroup = 'rg-sepiabox',
    [string] $WebApp = 'sepiabox-web',
    [string] $PostgresServer = 'sepiabox-pg',
    [string] $ServiceBusNamespace = 'sepiabox-sb',
    [string] $Queue = 'manifests'
)

$ErrorActionPreference = 'Stop'

# The Automation account's system-assigned identity has Contributor on the resource group.
Connect-AzAccount -Identity | Out-Null
$subscriptionId = (Get-AzContext).Subscription.Id
$groupPath = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers"

function Invoke-Arm([string] $Method, [string] $Path, [string] $Payload) {
    $arguments = @{ Method = $Method; Path = $Path }
    if ($Payload) { $arguments.Payload = $Payload }
    $response = Invoke-AzRestMethod @arguments
    if ($response.StatusCode -ge 300) {
        throw "$Method $Path returned $($response.StatusCode): $($response.Content)"
    }
    $response
}

$failed = [System.Collections.Generic.List[string]]::new()
function Invoke-Step([string] $Description, [scriptblock] $Action) {
    Write-Output "$Description..."
    try {
        & $Action
    }
    catch {
        Write-Warning "$Description failed: $_"
        $failed.Add($Description)
    }
}

Invoke-Step "Disabling ingress on $WebApp" {
    # Same as `az containerapp ingress disable`: the app keeps running but takes no traffic.
    Invoke-Arm PATCH "$groupPath/Microsoft.App/containerApps/$($WebApp)?api-version=2024-03-01" `
        '{"properties":{"configuration":{"ingress":null}}}' | Out-Null
}

Invoke-Step "Stopping PostgreSQL server $PostgresServer" {
    Invoke-Arm POST "$groupPath/Microsoft.DBforPostgreSQL/flexibleServers/$PostgresServer/stop?api-version=2024-08-01" | Out-Null
}

Invoke-Step "Disabling queue $Queue" {
    # Queues have no PATCH: read the queue and write it back with only the status changed.
    $queuePath = "$groupPath/Microsoft.ServiceBus/namespaces/$ServiceBusNamespace/queues/$($Queue)?api-version=2024-01-01"
    $definition = (Invoke-Arm GET $queuePath).Content | ConvertFrom-Json
    $definition.properties.status = 'Disabled'
    $body = @{ properties = $definition.properties } | ConvertTo-Json -Depth 10 -Compress
    Invoke-Arm PUT $queuePath $body | Out-Null
}

if ($failed.Count -gt 0) {
    throw "Shutdown incomplete. Failed steps: $($failed -join '; ')"
}
Write-Output 'Done. Data is preserved.'
