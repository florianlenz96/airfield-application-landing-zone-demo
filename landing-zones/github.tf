# 5. GitHub: the team's repository gets a ready-to-use environment.
# No ticket, no copy and paste of IDs: the first push can deploy.

resource "github_repository_environment" "app" {
  count       = var.github_repository == null ? 0 : 1
  repository  = local.github_repo
  environment = var.github_environment
}

resource "github_actions_environment_variable" "app" {
  for_each      = var.github_repository == null ? {} : local.github_variables
  repository    = local.github_repo
  environment   = github_repository_environment.app[0].environment
  variable_name = each.key
  value         = each.value
}
