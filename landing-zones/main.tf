# One application landing zone = one var file in this folder.
#
# What the platform hands over after the merge:
#   1. Network     Airstrip spoke: VNet, two standard subnets, NSGs, routes via the
#                  firewall, peering both ways, links to the hub's private DNS zones
#   2. Identity    a deploy identity only the team's repository can use (GitHub OIDC)
#   3. Permissions Contributor on the subscription, but role assignments only for an
#                  allow-list of roles, plus DNS records for its private endpoints
#   4. State       its own Terraform state container
#   5. GitHub      environment "prod" in the team's repository, all variables set
#
# The subscription's management group placement lives in platform/terraform.tfvars.

data "terraform_remote_state" "platform" {
  backend = "azurerm"
  config  = merge(var.state_backend, { key = "management-groups.tfstate", use_azuread_auth = true })
}

data "terraform_remote_state" "connectivity" {
  backend = "azurerm"
  config  = merge(var.state_backend, { key = "connectivity.tfstate", use_azuread_auth = true })
}

data "azurerm_client_config" "current" {}

locals {
  platform                   = data.terraform_remote_state.platform.outputs
  hub                        = data.terraform_remote_state.connectivity.outputs.hub
  root_id                    = local.platform.root_id
  management_subscription_id = local.platform.subscriptions["management"][0]

  github_owner = var.github_repository == null ? null : split("/", var.github_repository)[0]
  github_repo  = var.github_repository == null ? null : split("/", var.github_repository)[1]

  state_account_id = "/subscriptions/${var.state_backend.subscription_id}/resourceGroups/${var.state_backend.resource_group_name}/providers/Microsoft.Storage/storageAccounts/${var.state_backend.storage_account_name}"
}

# ---------------------------------------------------------------------------
# 1. Network: every landing zone gets the same two subnets
# ---------------------------------------------------------------------------
locals {
  apps_prefix = cidrsubnet(var.address_space[0], 2, 0) # /24 -> x.x.x.0/26
  pe_prefix   = cidrsubnet(var.address_space[0], 3, 2) # /24 -> x.x.x.64/27

  subnets = {
    # App Service / Functions VNet integration
    apps = {
      address_prefixes = [local.apps_prefix]
      delegation = {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
      rules = {
        to-private-endpoints = {
          priority                   = 200
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          destination_port_range     = "443"
          source_address_prefix      = local.apps_prefix
          destination_address_prefix = local.pe_prefix
        }
      }
    }
    # Private endpoints for storage, Key Vault, SQL ...
    private-endpoints = {
      address_prefixes  = [local.pe_prefix]
      private_endpoints = true
      rules = {
        from-apps = {
          priority                   = 200
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          destination_port_range     = "443"
          source_address_prefix      = local.apps_prefix
          destination_address_prefix = local.pe_prefix
        }
      }
    }
  }
}

module "spoke" {
  source = "github.com/florianlenz96/azure-airstrip-landing-zone//terraform/modules/spoke?ref=ee735616c07ad179c7d9d2a61c493a62a6407976"
  providers = {
    azurerm              = azurerm
    azurerm.connectivity = azurerm.connectivity
  }

  stage                = "regional_airfield"
  root_id              = local.root_id
  subscription_id      = var.subscription_id
  name                 = var.name
  location             = var.location
  tags                 = var.tags
  address_space        = var.address_space
  other_spoke_prefixes = var.other_spoke_prefixes
  hub                  = local.hub
  subnets              = local.subnets
}

# ---------------------------------------------------------------------------
# 2. Identity: only the team's repository can use it, and only from its environment
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "vending" {
  provider = azurerm.management
  name     = "rg-${local.root_id}-lz-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_user_assigned_identity" "deploy" {
  provider            = azurerm.management
  name                = "id-${local.root_id}-${var.name}-deploy"
  location            = var.location
  resource_group_name = azurerm_resource_group.vending.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "github" {
  provider                  = azurerm.management
  count                     = var.github_repository == null ? 0 : 1
  name                      = "github-${var.github_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.deploy.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${coalesce(var.github_oidc_repository, var.github_repository)}:environment:${var.github_environment}"
}

# ---------------------------------------------------------------------------
# 3. Permissions
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "deploy_contributor" {
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

data "azurerm_role_definition" "assignable" {
  provider = azurerm.management
  for_each = toset(var.assignable_roles)
  name     = each.key
}

locals {
  assignable_role_ids = join(", ", [for r in data.azurerm_role_definition.assignable : basename(r.role_definition_id)])
}

# The team can give its app identities AcrPull, Storage Blob Data Contributor ...
# but never Owner, Contributor or User Access Administrator.
resource "azurerm_role_assignment" "deploy_constrained_rbac" {
  scope                            = "/subscriptions/${var.subscription_id}"
  role_definition_name             = "Role Based Access Control Administrator"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Landing zone ${var.name}: assign allow-listed roles only"
  condition_version                = "2.0"
  condition                        = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_ids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.assignable_role_ids}}
     )
    )
  EOT
}

# Private endpoints register their A records in the hub's zones.
resource "azurerm_role_assignment" "deploy_dns" {
  provider                         = azurerm.connectivity
  for_each                         = toset(var.private_dns_zones)
  scope                            = lookup(local.hub.private_dns_zones, each.key, "missing")
  role_definition_name             = "Private DNS Zone Contributor"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true

  lifecycle {
    precondition {
      condition     = contains(keys(local.hub.private_dns_zones), each.key)
      error_message = "${each.key} is not a hub DNS zone. Add it to connectivity/terraform.tfvars first."
    }
  }
}

# ---------------------------------------------------------------------------
# 4. State: one container per landing zone, nobody else's states in reach
# ---------------------------------------------------------------------------
resource "azurerm_storage_container" "state" {
  provider           = azurerm.management
  name               = "tfstate-${var.name}"
  storage_account_id = local.state_account_id
}

resource "azurerm_role_assignment" "deploy_state" {
  provider                         = azurerm.management
  scope                            = "${local.state_account_id}/blobServices/default/containers/${azurerm_storage_container.state.name}"
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.deploy.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---------------------------------------------------------------------------
# The contract the application's Terraform receives (GitHub variable LANDING_ZONE)
# ---------------------------------------------------------------------------
locals {
  landing_zone = {
    name                 = var.name
    subscription_id      = var.subscription_id
    location             = var.location
    tags                 = var.tags
    vnet_id              = module.spoke.network.vnet_id
    subnet_ids           = module.spoke.network.subnet_ids
    private_dns_zone_ids = { for zone in var.private_dns_zones : zone => lookup(local.hub.private_dns_zones, zone, null) }
  }

  github_variables = {
    AZURE_CLIENT_ID         = azurerm_user_assigned_identity.deploy.client_id
    AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
    AZURE_SUBSCRIPTION_ID   = var.subscription_id
    TFSTATE_SUBSCRIPTION_ID = var.state_backend.subscription_id
    TFSTATE_RESOURCE_GROUP  = var.state_backend.resource_group_name
    TFSTATE_STORAGE_ACCOUNT = var.state_backend.storage_account_name
    TFSTATE_CONTAINER       = azurerm_storage_container.state.name
    LANDING_ZONE            = jsonencode(local.landing_zone)
  }
}
