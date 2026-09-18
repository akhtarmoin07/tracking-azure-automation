# SPORTFIVE whole workflow

```mermaid
flowchart TB
  subgraph delivery[Deployment and activation]
    Inputs["terraform.tfvars + backend.tf<br/>Secret password + Azure identity"] --> Local["Local PowerShell runner"]
    Inputs --> Git["GitHub main / manual dispatch<br/>OIDC + reviewed environment"]
    Local --> Checks["Offline checks + Azure preflight<br/>Identity, image, quota, state ownership"]
    Git --> Checks
    Checks --> Plan["Saved Terraform plan<br/>Reject deletions and replacements"]
    Plan --> Apply["Apply: 8 modules in one state<br/>Network · AVD · Profiles · Hosts<br/>Autoscale · Automation · Backup · Monitoring"]
    Apply <-->|"state / lease locking"| State["Existing Azure Blob backend<br/>statetfmoin / tfstate"]
    Apply --> Bootstrap["Entra join + pinned agent/FSLogix<br/>AMA + local health task"]
    Bootstrap --> Profiles["Storage app consent / private-link names<br/>Group claims + empty-share ACL setup<br/>Temporary privilege revoked"]
    Profiles --> Verify["Verify bootstrap, registration,<br/>managed-identity audit and log ingestion"]
    Verify -->|"failed check"| Stop["Stop before first publication<br/>Retain resources and failure evidence"]
    Tenant["Tenant prerequisites<br/>Groups, licenses, CA policy, SSO"] --> Profiles
    Tenant --> Publish
    Verify -->|"passed checks"| Publish["Restricted activation plan<br/>Enable requested audits and desktop access<br/>Publication defaults off"]
    Publish --> Evidence["Completion and runtime reports<br/>Pilot: sign-in, isolation, load, restore"]
  end

  subgraph runtime[User access and ongoing operation]
    Users["150 finance users<br/>Windows App / web client"] --> Workspace["AVD workspace + desktop group"]
    Workspace --> Pool["One pooled host pool"]
    Pool --> Hosts["31 planned private Windows 11 hosts<br/>5 sessions/host + one-host reserve"]
    Hosts -->|"SMB / Kerberos"| Private["Private DNS + Files endpoint"]
    Private --> Files["Same-region Premium Azure Files<br/>FSLogix profiles · 5625 GiB"]
    Scale["Native autoscale<br/>07:00 warm · 08:00 breadth-first<br/>18:00 depth-first · 20:00 off-peak<br/>Only empty hosts deallocate"] -.-> Hosts
    Audit["Automation / Reader identity<br/>07:35 readiness · 20:30 off-peak<br/>Heartbeat freshness warns separately"] -.->|"read-only checks"| Pool
    Audit -.->|"read-only checks"| Hosts
    Hosts -->|"AMA + DCR / health events"| Logs["Log Analytics / AVD Insights"]
    Pool -->|"AVD diagnostics"| Logs
    Files -->|"Storage diagnostics"| Logs
    Audit -->|"Job output"| Logs
    Logs --> Alerts["Monitor alerts + Action Group<br/>Operations team"]
    Budget["Cost budget / notifications"] --> Alerts
    Files --> Backup["Nightly snapshot backup<br/>14 daily + 4 weekly points"]
    Backup --> Restore["Alternate restore / pilot acceptance"]
  end

  Apply -.->|"provisions resources, not user traffic"| Pool
  Publish -.->|"grants configured group access"| Workspace
  Evidence -.->|"accept before broad rollout"| Users
```

Dashed arrows show deployment/control activity; solid runtime arrows show access and telemetry. Host/storage sizing is provisional. [Configuration, prerequisites and operating notes](docs/GUIDE.md).
