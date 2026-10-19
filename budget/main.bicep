// Monthly budget and cost alerts for the Sepiabox subscription (D-008 in sepiabox-platform).
// Azure does not stop spending on pay-as-you-go, so these alerts must exist before any paid resource.
targetScope = 'subscription'

@description('E-mail addresses that receive the budget and anomaly alerts.')
@minLength(1)
param contactEmails string[]

@description('Monthly ceiling in the billing currency (EUR).')
param amount int = 50

@description('First day of the first budget month (yyyy-MM-dd, always the 1st). Keep it fixed once deployed.')
param budgetStartDate string = '2026-10-01'

@description('Start of the anomaly alert schedule. Defaults to now, so every deployment renews it.')
param anomalyStartDate string = utcNow('yyyy-MM-ddTHH:mm:ssZ')

// The anomaly alert needs an end date; the deploy workflow runs monthly so it never lapses.
var anomalyEndDate = dateTimeAdd(anomalyStartDate, 'P1Y')

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'sepiabox-monthly'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
    }
    notifications: {
      actual50: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
      }
    }
  }
}

resource anomalyAlert 'Microsoft.CostManagement/scheduledActions@2023-11-01' = {
  name: 'sepiabox-daily-anomaly'
  kind: 'InsightAlert'
  properties: {
    displayName: 'Sepiabox daily cost anomaly'
    status: 'Enabled'
    viewId: '${subscription().id}/providers/Microsoft.CostManagement/views/ms:DailyAnomalyByResourceGroup'
    notificationEmail: contactEmails[0]
    notification: {
      to: contactEmails
      subject: 'Sepiabox: unusual Azure spending detected'
    }
    schedule: {
      frequency: 'Daily'
      startDate: anomalyStartDate
      endDate: anomalyEndDate
    }
  }
}

output budgetId string = budget.id
output anomalyAlertId string = anomalyAlert.id
