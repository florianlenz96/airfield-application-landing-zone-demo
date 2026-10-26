# Run the printed commands once to wire the repository to Azure.
output "github_setup_commands" {
  value = <<-EOT
    REPO=${var.github_repository}

    gh variable set AZURE_TENANT_ID         --repo $REPO --body ${data.azurerm_client_config.current.tenant_id}
    gh variable set TFSTATE_SUBSCRIPTION_ID --repo $REPO --body ${var.management_subscription_id}
    gh variable set TFSTATE_RESOURCE_GROUP  --repo $REPO --body ${azurerm_resource_group.state.name}
    gh variable set TFSTATE_STORAGE_ACCOUNT --repo $REPO --body ${azurerm_storage_account.state.name}
    gh variable set TFSTATE_CONTAINER       --repo $REPO --body ${azurerm_storage_container.state.name}

    gh api --method PUT repos/$REPO/environments/platform-plan  >/dev/null
    gh api --method PUT repos/$REPO/environments/platform-apply >/dev/null
    gh variable set AZURE_CLIENT_ID --repo $REPO --env platform-plan  --body ${azurerm_user_assigned_identity.pipeline["plan"].client_id}
    gh variable set AZURE_CLIENT_ID --repo $REPO --env platform-apply --body ${azurerm_user_assigned_identity.pipeline["apply"].client_id}

    # Fine-grained token that may create environments and variables in app repositories:
    gh secret set LZ_GITHUB_TOKEN --repo $REPO
  EOT
}
