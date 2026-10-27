# --- Set in landing-zones/<name>.tfvars, one file per application --------------

variable "subscription_id" {
  description = "The application's subscription. Create it by hand and add it to platform/terraform.tfvars."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a lowercase GUID."
  }
}

variable "address_space" {
  description = "One /24 (or /23, /22) from the IP plan. Must not overlap the hub or any other spoke."
  type        = list(string)
  validation {
    condition     = length(var.address_space) == 1 && contains([22, 23, 24], tonumber(split("/", var.address_space[0])[1]))
    error_message = "Use exactly one range with a /22, /23 or /24 prefix."
  }
}

variable "tags" {
  description = "Airstrip's tag policy denies resource groups without owner, cost-center and an allowed env."
  type        = map(string)
  validation {
    condition     = alltrue([for k in ["owner", "cost-center", "env"] : try(length(trimspace(var.tags[k])) > 0, false)]) && contains(["dev", "test", "prod"], try(var.tags["env"], ""))
    error_message = "tags need owner, cost-center and env (dev, test or prod)."
  }
}

variable "github_repository" {
  description = "owner/repo that deploys into this landing zone. Gets an OIDC-trusted identity and a ready GitHub environment."
  type        = string
  default     = null
}

variable "github_environment" {
  type    = string
  default = "prod"
}

variable "github_oidc_repository" {
  description = "Repository portion of the GitHub OIDC subject, e.g. owner@123/repo@456. Null uses github_repository for subjects without numeric IDs."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_repository == null ? true : can(regex("^[^/:[:space:]]+/[^/:[:space:]]+$", var.github_oidc_repository))
    error_message = "github_oidc_repository must contain exactly an owner/repository pair from the OIDC subject, without the repo: prefix or environment suffix."
  }
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "other_spoke_prefixes" {
  description = "Address spaces of the other spokes, routed through the firewall. Keep current in every spoke."
  type        = set(string)
  default     = []
}

variable "private_dns_zones" {
  description = "Hub DNS zones the team may register private endpoints in."
  type        = list(string)
  default     = ["privatelink.blob.core.windows.net"]
}

variable "assignable_roles" {
  description = "Roles the team may hand out inside its own subscription (to its app identities). Owner and friends are never on this list."
  type        = list(string)
  default = [
    "AcrPull",
    "AcrPush",
    "Storage Blob Data Contributor",
    "Storage Blob Data Reader",
    "Storage Queue Data Contributor",
    "Key Vault Secrets User",
    "Monitoring Metrics Publisher",
  ]
}

# --- Set by scripts/platform.sh -------------------------------------------------

variable "name" {
  description = "The landing zone's name. scripts/platform.sh passes the file name, e.g. meter-readings."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.name))
    error_message = "name: 3-24 lowercase letters, digits and hyphens."
  }
}

variable "state_backend" {
  description = "Where the platform states live. Also hosts one state container per landing zone."
  type = object({
    subscription_id      = string
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
  })
}
