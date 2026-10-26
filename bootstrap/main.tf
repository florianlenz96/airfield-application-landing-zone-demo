# One-time setup, run locally by someone who can assign roles on the existing
# platform root management group and manage the management subscription:
#   - the storage account that holds every Terraform state (platform and app teams)
#   - two pipeline identities for this repository, trusted via GitHub OIDC (no secrets):
#       platform-plan   read-only, used for pull request plans
#       platform-apply  write, used on main
#
# State of this root stays local (terraform.tfstate here, git-ignored). Keep it safe.

terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {
    storage {
      data_plane_available = false # shared keys are off; manage the account through ARM only
    }
  }
  subscription_id                 = var.management_subscription_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

data "azurerm_client_config" "current" {}

locals {
  platform_root_scope = "/providers/Microsoft.Management/managementGroups/${var.root_id}"
  state_container     = "${azurerm_storage_account.state.id}/blobServices/default/containers/${azurerm_storage_container.state.name}"
}

# ---------------------------------------------------------------------------
# Terraform state
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "state" {
  name     = "rg-${var.root_id}-tfstate"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = var.state_storage_account_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # Entra ID only, for people and pipelines
  default_to_oauth_authentication = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "state" {
  name               = "tfstate"
  storage_account_id = azurerm_storage_account.state.id
}

# You, for local runs (bootstrap, debugging).
resource "azurerm_role_assignment" "you_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Pipeline identities for the platform repository
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "pipelines" {
  name     = "rg-${var.root_id}-pipelines"
  location = var.location
}

resource "azurerm_user_assigned_identity" "pipeline" {
  for_each            = toset(["plan", "apply"])
  name                = "id-${var.root_id}-platform-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.pipelines.name
}

# A job may use the identity only if it runs in the matching GitHub environment.
resource "azurerm_federated_identity_credential" "github" {
  for_each                  = azurerm_user_assigned_identity.pipeline
  name                      = "github-platform-${each.key}"
  user_assigned_identity_id = each.value.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_repository}:environment:platform-${each.key}"
}

locals {
  pipeline_roles = {
    # Plans see everything and change nothing in Azure. They do need to write to the
    # state container: for a brand-new landing zone the backend creates an empty state file.
    plan-reader = { identity = "plan", scope = local.platform_root_scope, role = "Reader" }
    plan-state  = { identity = "plan", scope = local.state_container, role = "Storage Blob Data Contributor" }
    # Applies build management groups, policies, networks and new landing zones.
    # Demo shortcut: Owner on the platform root. Production: split into narrower roles.
    apply-owner = { identity = "apply", scope = local.platform_root_scope, role = "Owner" }
    apply-state = { identity = "apply", scope = local.state_container, role = "Storage Blob Data Contributor" }
  }
}

resource "azurerm_role_assignment" "pipeline" {
  for_each                         = local.pipeline_roles
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.pipeline[each.value.identity].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
