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
