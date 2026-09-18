# SPORTFIVE AVD infrastructure and operations

An end-to-end **repository implementation** of the supplied SPORTFIVE AVD redesign: Terraform provisions an isolated Azure lab; PowerShell configures and audits it; Azure Monitor, native AVD autoscale and Azure Backup provide the operating controls.

**Status:** local implementation; no Azure deployment. The supplied ZIP and available chat text informed the code; image-only or missing chat replies could not establish current Azure health.

Start with [deployment instructions](docs/DEPLOYMENT.md). The selected scope is a completely new environment, kept local until you create a remote repository. The existing `RG-AVD-LAB` is not the deployment target.

Terraform is split into **eight reusable modules**: network, AVD, profiles, session hosts, autoscale, Automation, backup and monitoring. [Architecture](docs/ARCHITECTURE.md) explains the module interfaces. One local PowerShell entry point drives preflight, plan, apply and runtime verification; tenant identity/ACL setup and user acceptance remain explicit prerequisites to publishing.

[View the lightweight architecture diagram](docs/ARCHITECTURE.md).

The audit now follows the later lab's **v1.1 heartbeat behavior**: stale telemetry
warns while Running/Available hosts accepting sessions still contribute capacity.
See [the code-change explanation and lab result](docs/HEARTBEAT-CHANGE.md).

| Area | Implementation |
|---|---|
| Desktop delivery | One pooled host pool, workspace, desktop application group, Entra group access |
| Session hosts | 31 planned Windows 11 multi-session VMs (150 concurrent sessions + one-host reserve), Entra join, managed identities, pinned installers, FSLogix, local health task |
| Profiles | Same-region Premium Azure Files SMB, private endpoint/DNS, Entra Kerberos, share RBAC, ACL setup guide |
| Scaling | 07:00 warm-up; breadth-first at 08:00 peak; depth-first after 18:00; zero-session deallocation; weekend policy |
| Monitoring | AMA, DCR, Log Analytics, AVD diagnostics, file/FSLogix/scaling/audit alerts, Action Group, budget |
| Scheduled operations | PowerShell 7.4 Automation runtime, Reader identity, embedded audit core, 07:35 and 20:30 jobs |
| Protection | Profile snapshot backups, soft delete, retention candidates without deletion, restore/pilot runbooks |
| Delivery | Local automatic deployment with saved-plan apply and runtime evidence; offline PR checks and optional future OIDC workflow |

The workload target is **150 finance users**, conservatively planned as 150 concurrent sessions. With the provisional five-session limit, `ceil(150 / 5) + 1` gives **31 hosts**, retaining 150 configured slots after one host is unavailable. Terraform rejects insufficient configured capacity. This is arithmetic, not a performance guarantee: validate the session density, VM SKU, profile capacity/IOPS, logon load and budget before deployment. The current 100-GiB profile share and 500 budget alert are still unvalidated placeholders; see [architecture](docs/ARCHITECTURE.md).

```powershell
# PowerShell 7.4+, Terraform 1.14.6; no Azure credentials required for these checks.
./scripts/Test-Repository.ps1
terraform -chdir=infra init -backend=false
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra test
```

Validated locally on 2026-09-13: Terraform formatting/schema checks, 4 mocked Terraform tests, 50 PowerShell checks and PSScriptAnalyzer passed. Those results predate the 150-user sizing change. Two capacity regression cases have since been added; the updated six Terraform tests have not been run locally. Azure deployment and user acceptance remain untested. Downloaded tools and provider caches are excluded from the repository; install the stated tool versions and run `terraform init` to recreate dependencies.

Use [identity and ACL setup](docs/IDENTITY-AND-PROFILES.md) and [operations/acceptance](docs/OPERATIONS.md) for the remaining live checks. Azure subscription IDs, group IDs, image/build selection, installer digests, backend configuration and credentials are supplied by the environment owner.

The audit only reads Azure. It never powers off VMs, logs users off, changes profile permissions or deletes profiles. Existing sessions remain on their original host; changing the load-balancing phase does not move them.

GitHub deployment reads committed `infra/terraform.tfvars` and `infra/backend.tf`. Fill the marked placeholders; keep `VM_ADMIN_PASSWORD` in GitHub Secrets. The three Azure identity variables remain unchanged. The optional local PowerShell helper uses its own JSON configuration.
