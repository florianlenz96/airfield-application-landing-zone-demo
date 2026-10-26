# Read by connectivity/ and landing-zones/ through terraform_remote_state.

output "root_id" {
  value = var.root_id
}

output "subscriptions" {
  value = var.subscriptions
}

output "management_group_ids" {
  value = module.foundation.management_group_ids
}

output "workload_management_group_ids" {
  value = module.foundation.workload_management_group_ids
}

output "log_analytics_workspace_id" {
  value = module.foundation.log_analytics_workspace_id
}
