# sepiabox-infra

Account-level Azure setup for Sepiabox: everything that does not ship with a version of the app.

The app itself (Container Apps, PostgreSQL, Blob Storage, Service Bus) is described by the .NET Aspire AppHost in [sepiabox-platform](https://github.com/sepiabox/sepiabox-platform) and deployed from there.

## What lives here

- **Budget and alerts.** A monthly budget of €50 with email alerts at €25, at €40 and when the month's forecast passes €50, plus daily cost anomaly alerts.
- **Kill switch.** At €45 the [`Stop-Sepiabox`](automation/Stop-Sepiabox.ps1) runbook stops everything billed by use and keeps all data.
- **Azure Policy.** "Allowed resource types" on the resource group, so only the services in the architecture can be created.
- **Log Analytics daily cap**, so telemetry stays inside the free 5 GB a month.
- **GitHub to Azure access** through OIDC federated credentials. No secret is stored in GitHub.
- **DNS** for `sepiabox.com` and `app.sepiabox.com`.

## Budget and alerts

[`budget/main.bicep`](budget/main.bicep) creates, at subscription scope:

- the `sepiabox-monthly` budget: €50 a month, e-mails at 50%, 80% and 90% of actual cost and when the forecast reaches 100%; at 90% it also starts the kill switch;
- the `sepiabox-daily-anomaly` alert: a daily e-mail when Cost Management detects unusual spending.

[`deploy.yml`](.github/workflows/deploy.yml) deploys the guardrails, the kill switch and then the budget on every push to `main` that touches `guardrails/`, `budget/`, `shutdown/` or `automation/`, on demand, and on the 1st of each month (which renews the anomaly alert's one-year schedule). It signs in with OIDC and needs these repository variables, plus a `production` environment:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Entra ID app with a federated credential for this repository's `production` environment |
| `BUDGET_ALERT_EMAILS` | Comma-separated e-mail addresses for the alerts |

CI compiles and lints the Bicep, checks the compiled templates ([`tests/budget.test.sh`](tests/budget.test.sh), [`tests/shutdown.test.sh`](tests/shutdown.test.sh), [`tests/guardrails.test.sh`](tests/guardrails.test.sh)), runs ShellCheck and the runbook's Pester tests on every pull request; it needs no Azure access.

## Kill switch at €45

[`shutdown/main.bicep`](shutdown/main.bicep) creates, in `rg-sepiabox`:

- the `sepiabox-automation` Automation account (free tier) with a system-assigned identity that is Contributor on the resource group;
- the [`Stop-Sepiabox`](automation/Stop-Sepiabox.ps1) runbook (PowerShell 7.2), which disables the ingress of `sepiabox-web`, stops the `sepiabox-pg` PostgreSQL server and disables the `manifests` queue of `sepiabox-bus`;
- the `budget-90-percent` webhook and the `sepiabox-shutdown` action group that calls it. The budget's 90% notification points at this action group.

The template creates only the runbook's shell; [`scripts/publish-runbook.sh`](scripts/publish-runbook.sh) uploads and publishes its code from the checked-out repository after each deployment, so the repository can be private. A webhook's URL can only be read when it is generated, so the deploy workflow creates the webhook and the action group once and leaves them alone afterwards. Run the workflow by hand with **rotate_webhook** to replace the URL.

## Guardrails

[`guardrails/main.bicep`](guardrails/main.bicep) creates, in `rg-sepiabox`:

- the `sepiabox-allowed-resource-types` assignment of the built-in **Allowed resource types** policy, listing only the services in the architecture (Container Apps, their environment, its managed certificates and jobs, PostgreSQL Flexible Server, Storage, Service Bus, Event Grid system topics, Key Vault, Log Analytics, Application Insights, user-assigned identities, Automation, Container Registry and action groups). Anything else is refused at creation. To allow a new type, add it to the list and to [`tests/guardrails.test.sh`](tests/guardrails.test.sh) in the same pull request;
- the `sepiabox-logs` Log Analytics workspace, capped at 0.15 GB a day (inside the free 5 GB a month) with 30 days of retention. Its id is the `logAnalyticsWorkspaceId` output, for Application Insights in the app (S-032).

## Region

Everything runs in **France Central**, in one resource group: `rg-sepiabox`.

## Emergency stop and resume

```bash
az login
./scripts/emergency-stop.sh   # the same as the kill switch, by hand
./scripts/resume.sh           # PostgreSQL, the queue and then web traffic come back
```

The web app stops taking traffic, PostgreSQL stops and the processing queue is disabled. Blob Storage keeps billing, about US$ 6 a month for 1 TB. A stopped PostgreSQL server restarts by itself after 7 days.

## License

[GNU Affero General Public License v3.0](LICENSE).
