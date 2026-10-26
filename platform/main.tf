# Airstrip level 2, "Regional airfield": the shared foundation and its guardrails.
# The modules come straight from the open-source Airstrip repository, pinned to a
# commit. This repository only holds configuration.

import {
  to = module.foundation.azurerm_management_group.root
  id = "/providers/Microsoft.Management/managementGroups/${var.root_id}"
}

module "foundation" {
  source = "github.com/florianlenz96/azure-airstrip-landing-zone//terraform/modules/foundation?ref=ee735616c07ad179c7d9d2a61c493a62a6407976"

  stage              = "regional_airfield"
  root_id            = var.root_id
  root_display_name  = var.root_display_name
  workloads          = var.workloads
  subscriptions      = var.subscriptions
  allowed_locations  = var.allowed_locations
  logging_location   = var.logging_location
  log_retention_days = var.log_retention_days
  defender_plans     = var.defender_plans
}

module "governance" {
  source = "github.com/florianlenz96/azure-airstrip-landing-zone//terraform/modules/governance?ref=ee735616c07ad179c7d9d2a61c493a62a6407976"

  stage                            = "regional_airfield"
  landingzones_management_group_id = module.foundation.management_group_ids.landingzones
  corp_management_group_id         = module.foundation.management_group_ids.corp
  location                         = var.logging_location
  allowed_envs                     = var.allowed_envs
  exemptions                       = var.exemptions
}
