# Pester 5 tests for automation/Stop-Sepiabox.ps1 (S-030). Az is not installed in CI, so the
# Az.Accounts cmdlets the runbook uses are declared here and mocked.
BeforeAll {
    $script:runbook = Join-Path $PSScriptRoot '..' 'automation' 'Stop-Sepiabox.ps1'

    function Connect-AzAccount { param([switch] $Identity) }
    function Get-AzContext { }
    function Invoke-AzRestMethod { param([string] $Method, [string] $Path, [string] $Payload) }

    $script:groupPath = '/subscriptions/sub-1/resourceGroups/rg-sepiabox/providers'
    $script:queuePath = "$groupPath/Microsoft.ServiceBus/namespaces/sepiabox-bus/queues/manifests?api-version=2024-01-01"
    $script:queueJson = '{"id":"q","name":"manifests","properties":{"maxDeliveryCount":5,"status":"Active"}}'
}

Describe 'Stop-Sepiabox' {
    BeforeEach {
        Mock Connect-AzAccount { }
        Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = 'sub-1' } } }
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 200; Content = $queueJson } }
    }

    It 'signs in with the managed identity' {
        & $runbook | Out-Null
        Should -Invoke Connect-AzAccount -Times 1 -Exactly -ParameterFilter { $Identity }
    }

    It 'disables ingress on sepiabox-web' {
        & $runbook | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PATCH' -and
            $Path -eq "$groupPath/Microsoft.App/containerApps/sepiabox-web?api-version=2024-03-01" -and
            ($Payload | ConvertFrom-Json).properties.configuration.ingress -eq $null
        }
    }

    It 'stops the sepiabox-pg PostgreSQL server' {
        & $runbook | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $Path -eq "$groupPath/Microsoft.DBforPostgreSQL/flexibleServers/sepiabox-pg/stop?api-version=2024-08-01"
        }
    }

    It 'disables the sepiabox-bus/manifests queue and keeps its other settings' {
        & $runbook | Out-Null
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and $Path -eq $queuePath }
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Path -eq $queuePath -and
            ($Payload | ConvertFrom-Json).properties.status -eq 'Disabled' -and
            ($Payload | ConvertFrom-Json).properties.maxDeliveryCount -eq 5
        }
    }

    It 'still runs the other steps when one fails, then reports the failure' {
        Mock Invoke-AzRestMethod { [pscustomobject]@{ StatusCode = 404; Content = 'not found' } } -ParameterFilter { $Method -eq 'PATCH' }

        { & $runbook 3>$null | Out-Null } | Should -Throw '*Disabling ingress on sepiabox-web*'
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke Invoke-AzRestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
    }
}
