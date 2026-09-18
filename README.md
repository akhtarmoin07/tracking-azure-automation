# SPORTFIVE AVD

Terraform and PowerShell implementation of the 150-finance-user AVD redesign: eight modules, pooled desktops, private FSLogix storage, autoscale, monitoring, audits and backup.

- [Compact deployment and operations guide](docs/GUIDE.md)
- [Complete workflow diagram](WORKFLOW.md)
- [Workload configuration](infra/terraform.tfvars) / [State backend](infra/backend.tf)

Planning target: **31 hosts, 5,625-GiB profile share, 10,000 monthly budget alert**. Session density and costs remain assumptions pending workload measurements. Tenant inputs and adequate Azure quota are required. Nothing has been deployed or performance-validated.

Local and GitHub deployment use the same `terraform.tfvars`; passwords stay in secrets. Generated plans, state, provider caches and tools are excluded from source.
