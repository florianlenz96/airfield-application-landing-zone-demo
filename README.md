# Kestrel Energy platform

The Azure landing zone of Kestrel Energy (a fictional company from the talk **"Azure Landing Zones Without the Overwhelm"**). It is level 2 of [Airstrip](https://github.com/florianlenz96/azure-airstrip-landing-zone), the *Regional airfield*: management groups, guardrail policies, central logging, a hub with Azure Firewall and private DNS, and one spoke per application.

This repository holds **configuration only**. The Terraform modules come from Airstrip, pinned to a commit.

> **New app? Don't open a ticket. Open a pull request.**

## Request a landing zone

Two small edits in one pull request:

**1. `platform/terraform.tfvars`:** give the app a management group and move its subscription in.

```hcl
workloads = {
  corp   = {}
  online = {
    meter-readings = "Meter Readings"
  }
}

subscriptions = {
  management            = ["..."]
  connectivity          = ["..."]
  online-meter-readings = ["<your-subscription-id>"]
}
```

**2. `landing-zones/meter-readings.tfvars`:** the landing zone itself. The file name is its name. Start from [`TEMPLATE.tfvars.example`](landing-zones/TEMPLATE.tfvars.example).

```hcl
subscription_id   = "<your-subscription-id>"
address_space     = ["10.100.16.0/24"]
github_repository = "florianlenz96/meter-readings-api"

tags = {
  owner         = "meter-team"
  "cost-center" = "cc-4711"
  env           = "prod"
}
```

The pull request gets a plan as a comment. After the merge, `main` applies it. A few minutes later the team can deploy.

## What a landing zone contains

| | What you get | Why |
|---|---|---|
| **Placement** | Subscription in its own management group below Corp or Online | Policies apply from the first second: allowed regions, required tags, diagnostics; in Corp also "No public endpoints". |
| **Network** | Airstrip spoke: VNet with subnets `apps` (delegated to App Service) and `private-endpoints`, NSGs, routes via the firewall, peering both ways, links to the hub's private DNS zones | Every landing zone looks the same. Teams consume it; they don't build it. |
| **Identity** | A deploy identity that only the team's repository can use, via GitHub OIDC | No secrets anywhere. |
| **Permissions** | Contributor on the subscription; role assignments only for an allow-list of roles; DNS records in the hub's zones | The team is fast, and still can't make itself Owner. |
| **State** | Its own Terraform state container | Nobody else's state within reach. |
| **GitHub** | Environment `prod` in the team's repository, with every variable set | The first push deploys. |

The landing zone's contract with the app's Terraform is the GitHub variable `LANDING_ZONE`:

```json
{
  "name": "meter-readings",
  "subscription_id": "…",
  "location": "westeurope",
  "tags": { "owner": "meter-team", "cost-center": "cc-4711", "env": "prod" },
  "vnet_id": "…",
  "subnet_ids": { "apps": "…", "private-endpoints": "…" },
  "private_dns_zone_ids": { "privatelink.blob.core.windows.net": "…" }
}
```

## Deploy an app: the golden pipeline

App repositories call the platform's pipeline template and write nothing else:

```yaml
jobs:
  app:
    uses: florianlenz96/kestrel-platform/.github/workflows/app-dotnet.yml@v1
    with:
      app-name: meter-readings-api
    permissions:
      id-token: write
      contents: read
```

It builds and tests, applies the app's Terraform in `infra/` into the landing zone, pushes the container image, deploys to App Service and waits until the new commit answers. Example: [meter-readings-api](https://github.com/florianlenz96/meter-readings-api).

## Layout

| Folder | Deploys | State |
|---|---|---|
| `bootstrap/` | State storage and the two pipeline identities. Run once, locally. | local |
| `platform/` | Management groups, policies, logging, subscription placement | `management-groups.tfstate` |
| `connectivity/` | Hub VNet, Azure Firewall, private DNS zones | `connectivity.tfstate` |
| `landing-zones/` | One application landing zone per `<name>.tfvars` | `landing-zone-<name>.tfstate` |
| `scripts/platform.sh` | Plans or applies everything in that order, locally and in CI | |
| `.github/workflows/platform.yml` | Pull request: plan. `main`: apply. | |
| `.github/workflows/app-dotnet.yml` | The golden pipeline for app teams | |

## The pipeline

| Event | Identity | Does |
|---|---|---|
| Pull request | `platform-plan`: Reader on Azure, no state lock | Plans all roots, posts the plan on the pull request |
| Push to `main` | `platform-apply`: writes | Applies platform → hub → landing zones, skipping roots without changes |
| *Run workflow* with a name | `platform-apply` | Destroys one landing zone (destroy it before you delete its file) |

Both identities are user-assigned managed identities with GitHub OIDC federation, bound to the GitHub environments `platform-plan` and `platform-apply`.

## IP plan

| Range | Used by |
|---|---|
| `10.100.0.0/22` | Hub (`10.100.0.0/26` Azure Firewall) |
| `10.100.16.0/24` | meter-readings |
| `10.100.17.0/24` | next landing zone |

Each landing zone `/24`: `.0/26` apps, `.64/27` private endpoints.

## One-time setup

1. Create the platform root management group (ID `kestrel` by default). Create the management, connectivity and app subscriptions; register their resource providers with `scripts/register-providers.sh`. Move these subscriptions under the platform root before running the pipelines, so they inherit the pipeline roles. The move requires permissions on the subscription and the relevant parent groups; rights on `kestrel` alone are not sufficient. No permissions on the tenant root are needed when it is the source parent.
2. `bootstrap/`: `terraform init && terraform apply` with a user who may assign roles on the platform root and manage resources and role assignments in the management subscription. Run the printed `gh` commands. Pipeline Reader/Owner roles are scoped to the platform root, not the tenant root.
3. Create a fine-grained GitHub token for the app repositories (Administration and Environments: read and write) and store it as `LZ_GITHUB_TOKEN`.
4. Fill in the subscription IDs in `platform/terraform.tfvars` and push to `main`. The first plan imports the existing platform root management group via the `import` block in `platform/main.tf`; review the plan before applying, including any display-name change. The first apply records the import and builds the platform and the hub (about 20 minutes, mostly the firewall).
5. Tag the golden pipeline: `git tag v1 && git push origin v1`.

Use the same `root_id` in `bootstrap/terraform.tfvars` and `platform/terraform.tfvars` (for example, `kestrel`). It is a technical identifier used in Azure resource names, not a display name; do not include spaces. Set the human-readable name separately with `root_display_name` in `platform/terraform.tfvars`.

If GitHub issues an OIDC subject containing numeric IDs, such as `repo:owner@123/repository@456:environment:platform-apply`, set `github_oidc_repository = "owner@123/repository@456"` in `bootstrap/terraform.tfvars` and rerun the bootstrap apply. This updates both pipeline federated credentials. Keep `github_repository` as the ordinary `owner/repository` name for GitHub CLI commands. Azure requires an exact subject match; use the repository portion shown in the authentication error rather than guessing IDs.

For workload deployments with ID-based OIDC subjects, also set `github_oidc_repository` in the corresponding `landing-zones/<name>.tfvars`, using the workload repository's owner and repository IDs. Keep its `github_repository` unchanged for GitHub API calls. Apply the platform pipeline first to update the workload's federated credential, then rerun the workload deployment.

For every new application subscription, first move it under the platform root with an authorized account. The pipeline can then place it in its workload management group without tenant-root permissions.

After import, Terraform manages the existing root group too: a full platform destroy includes that group. Review the destroy plan before proceeding.

**Costs:** Azure Firewall Standard is the main cost while the hub exists. Destroy it after the demo.
