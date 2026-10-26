output "landing_zone" {
  value = local.landing_zone
}

output "deploy_identity_client_id" {
  value = azurerm_user_assigned_identity.deploy.client_id
}

# Printed into the workflow summary after the apply.
output "summary" {
  value = <<-EOT
    ### Landing zone `${var.name}` is ready

    | | |
    |---|---|
    | Subscription | `${var.subscription_id}` |
    | Network | `${module.spoke.network.vnet_id}` |
    | Subnets | ${join(", ", [for k, v in module.spoke.network.subnet_ids : "`${k}`"])} |
    | Deploy identity | `${azurerm_user_assigned_identity.deploy.client_id}` |
    | Terraform state | container `${azurerm_storage_container.state.name}` |
    | GitHub | ${var.github_repository == null ? "not connected" : "environment `${var.github_environment}` in `${var.github_repository}`"} |
  EOT
}
