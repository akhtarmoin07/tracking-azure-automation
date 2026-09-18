# SPORTFIVE deployment and operations

**Status:** local implementation; no Azure deployment or 150-user performance validation. See the [whole workflow](../WORKFLOW.md). The new workload uses `rg-sfavd-lab`; existing `RG-AVD-LAB` holds only the Terraform backend.

## Design and sizing

`infra/main.tf` composes eight modules: **network, avd, profiles, session_hosts, autoscale, automation, backup, monitoring**. One environment has one state. Hosts use private NICs, outbound NAT, Entra join, pinned Windows 11 multi-session images/installers and managed identities. Profiles use same-region Premium SMB with private DNS/endpoint and Kerberos. NAT permits outbound traffic; corporate application connectivity, licensing and tenant policies remain prerequisites.

| Setting | Current planning basis |
|---|---|
| Users and hosts | 150 concurrent users; provisional 5 sessions/host; `ceil(150/5)+1 = 31` D4s_v5 hosts, 124 vCPUs |
| Failure reserve | 150 configured slots after one host is unavailable; existing sessions do not migrate |
| Profile storage | 5,625 GiB: 150 x rounded 30-GiB allowance x 1.25; dynamic profile cap 30,000 MiB |
| Premium provisioned v1 | 8,625 baseline IOPS, 663 MiB/s from provisioning formulas; actual performance unmeasured |
| Budget | 10,000/month in subscription billing currency; notifications, not a spending cap |

The previous North Europe quota read found only **4 regional/family vCPUs**. Preflight blocks this fleet until sufficient quota exists. Quota does not guarantee regional availability. Reassess session density, profile growth/attach storms and provisioned v2 before production.

Cost model, public North Europe USD rates read 2026-09-18: compute $0.214/host-hour, P10 disks $19.71/month, Files $0.176/GiB-month, incremental snapshots $0.15/GiB-month. With 31 hosts running 286 hours/month, 31 disks, 5,625 GiB, an assumed 4,500 GiB of retained changed snapshots and $1,000 other-usage allowance: **$5,173/month**, or **$6,208 with 20% contingency**. At 730 compute hours: **$9,743 including contingency**. These scenarios exclude licenses/taxes; occupied sessions can prevent deallocation. Refresh prices and convert the budget if billing currency differs. Sources: [retail pricing](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices), [Files provisioning](https://learn.microsoft.com/en-us/azure/storage/files/understanding-billing#provisioned-v1-provisioning-detail), [VM sizing](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/session-host-virtual-machine-sizing-guidelines).

## Configure once

- Edit **`infra/terraform.tfvars`**: replace marked group/AVD enterprise-application object IDs, unique profile-storage name, operations email, patched image version, immutable installer URLs and SHA256 digests. Passwords stay outside source. Null dates are generated at deployment; the original budget month is retained on updates.
- **`infra/backend.tf`** targets `statetfmoin` / `tfstate` / `sportfive/lab.tfstate`. The blob container stores state; profile files use a separate new account. Use separate state keys for other environments. Restrict backend/artifact access, enable state versioning/soft delete and ensure runner network reachability.
- Install PowerShell 7.4+, Terraform 1.14.6 and Azure CLI. The deployment identity needs workload Contributor, required role-assignment permissions (AVD power role at subscription scope), backend Storage Blob Data Contributor and tenant application administration/consent permissions. Reader-only audit identity remains separate. Register Compute, Network, Storage, DesktopVirtualization, Insights, OperationalInsights, Automation and RecoveryServices providers.
- Tenant owner prepares finance/profile-admin security groups, eligible user licenses, supported patched OS, [Entra Kerberos prerequisites](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-identity-auth-hybrid-identities-enable), the storage application's specific MFA policy exception and [AVD SSO](https://learn.microsoft.com/en-us/azure/virtual-desktop/configure-single-sign-on). Deployment does not broadly change tenant security policy. Hybrid corporate applications may need AD/network connectivity.

## Run locally or through GitHub

Local deployment reads the same committed HCL as GitHub; no separate configuration JSON is needed. Sign in with `az login --tenant <tenant-id>` and supply `TF_VAR_admin_password` securely in the process environment. Use a private working directory outside this OneDrive repository:

```powershell
$work = "$env:LOCALAPPDATA/SPORTFIVE/avd-lab"
./scripts/deployment/Invoke-Deployment.ps1 -WorkingDirectory $work -Mode Plan
./scripts/deployment/Invoke-Deployment.ps1 -WorkingDirectory $work -Mode Deploy
./scripts/deployment/Invoke-Deployment.ps1 -WorkingDirectory $work -Mode Verify
```

`Deploy` checks prerequisites, creates and checks a fresh saved plan, applies it, prepares profiles, verifies runtime, then activates the requested schedules/access. Deletion/replacement plans are rejected. New publication stays disabled until checks pass; existing enabled access is preserved on updates. A failure stops deployment and retains resources/evidence for investigation.

Profile setup grants only the generated storage application's expected consent, adds private-link identifiers/cloud-group support, obtains directory group SIDs, and initializes/verifies root ACLs through a host identity with temporary share-scoped privilege. Finance gets root traversal/create-folder rights, administrators full control, and CREATOR OWNER inherited modify. Differing ACLs on populated shares are refused; temporary privilege is revoked afterward. Real user isolation still requires acceptance.

`enable_audit_schedules=true` requests automatic activation after checks. `enable_user_access=false` keeps publication off; after tenant setup, restrict the finance group to pilot members and set it true to request publication in the same flow, with an SSO configuration check. Expand membership only after acceptance. Only expected access/schedule/alert changes are permitted in the activation plan.

For GitHub, set variables **AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID** and secret **VM_ADMIN_PASSWORD**, available to both jobs. There is no `TF_BACKEND` or `TF_CONFIG_JSON`. Configure OIDC subjects for `lab-plan`/`lab`, required reviewers on `lab`, protected `main`, and a runner able to reach the backend. Dispatch the deployment workflow; apply defaults off. Saved plans contain secrets and expire after one day. Offline validation is reusable and runs first.

## Operation and acceptance

Berlin weekdays: **07:00 warm-up → 07:35 readiness audit → 08:00 breadth-first peak → 18:00 depth-first → 20:00 empty-host deallocation → 20:30 audit**. No forced logoff; disconnected sessions remain occupied. Weekend minimum is zero with Start VM on Connect. SYSTEM host checks run every 15 minutes while powered on. AMA/DCR and service diagnostics feed Log Analytics, alerts and the operations Action Group.

**Heartbeat v1.1:** Running + Available + accepting sessions contributes capacity. Old/missing/invalid/future heartbeat warns independently; unavailable/drained hosts and missing required data still fail readiness. Historical lab replay remains two ready hosts, seven slots, two warnings. This changes audit interpretation; it does not fix stale Azure telemetry. The audit has Reader access and never restarts hosts, logs off users or deletes profiles.

Runtime verification checks bootstrap success, every expected host registered, a managed-identity audit, and host/audit log ingestion. It does not prove user sign-in. Before production record: two-user FSLogix attachment/roaming/isolation; staged 5/25/75/150-user peak and host-loss measurements; CPU/RAM/input delay/logon p50/p95/SMB latency; scaling/DST behavior; alert delivery; backup and alternate-location restore. Queries are in `monitoring/queries`.

Backups: 23:00 snapshots, 14 daily/4 weekly retention; snapshot-only backup is not regional disaster recovery. Never restore over a mounted profile. Retention scripts report candidates only. For host changes, use `AVD-Maintenance`, drain and wait for active/disconnected sessions to reach zero; pilot before expansion. Disabling established access/schedules or replacing resources requires a separate reviewed maintenance plan. Never use `terraform destroy` as rollback.

Offline checks (no Azure credentials):

```powershell
./scripts/Test-Repository.ps1
terraform -chdir=infra init -backend=false -input=false -lockfile=readonly
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra validate
terraform -chdir=infra test
```
