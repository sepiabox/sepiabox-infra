# sepiabox-infra

Account-level Azure setup for Sepiabox: everything that does not ship with a version of the app.

The app itself (Container Apps, PostgreSQL, Blob Storage, Service Bus) is described by the .NET Aspire AppHost in [sepiabox-platform](https://github.com/sepiabox/sepiabox-platform) and deployed from there.

## What lives here

- **Budget and alerts.** A monthly budget of €50 with email alerts at €25, at €40 and when the month's forecast passes €50, plus daily cost anomaly alerts.
- **Kill switch.** At €45 an Automation runbook runs [`scripts/emergency-stop.sh`](scripts/emergency-stop.sh), which stops everything billed by use and keeps all data.
- **Azure Policy.** "Allowed resource types" on the resource group, so only the services in the architecture can be created.
- **Log Analytics daily cap**, so telemetry stays inside the free 5 GB a month.
- **GitHub to Azure access** through OIDC federated credentials. No secret is stored in GitHub.
- **DNS** for `sepiabox.com` and `app.sepiabox.com`.

## Budget and alerts

[`budget/main.bicep`](budget/main.bicep) creates, at subscription scope:

- the `sepiabox-monthly` budget: €50 a month, e-mails at 50% and 80% of actual cost and when the forecast reaches 100%;
- the `sepiabox-daily-anomaly` alert: a daily e-mail when Cost Management detects unusual spending.

[`deploy-budget.yml`](.github/workflows/deploy-budget.yml) deploys it on every push to `main` that touches `budget/`, on demand, and on the 1st of each month (which renews the anomaly alert's one-year schedule). It signs in with OIDC and needs these repository variables, plus a `production` environment:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Entra ID app with a federated credential for this repository's `production` environment |
| `BUDGET_ALERT_EMAILS` | Comma-separated e-mail addresses for the alerts |

CI compiles the Bicep and runs [`tests/budget.test.sh`](tests/budget.test.sh) on every pull request; it needs no Azure access.

## Region

Everything runs in **France Central**, in one resource group: `rg-sepiabox`.

## Emergency stop

```bash
az login
./scripts/emergency-stop.sh
```

The web app stops taking traffic, PostgreSQL stops and the processing queue is disabled. Blob Storage keeps billing, about US$ 6 a month for 1 TB. A stopped PostgreSQL server restarts by itself after 7 days.

## License

[GNU Affero General Public License v3.0](LICENSE).
