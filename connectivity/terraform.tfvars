location        = "westeurope"
tags            = { owner = "platform-team", cost-center = "cc-platform", env = "prod" }
address_space   = ["10.100.0.0/22"]
firewall_subnet = "10.100.0.0/26"

# Landing zones get records in these zones for their private endpoints.
private_dns_zones = [
  "privatelink.blob.core.windows.net",
  "privatelink.vaultcore.azure.net",
  "privatelink.database.windows.net",
  "privatelink.azurewebsites.net",
]

# No allow rules = no workload egress through the firewall.
application_rules = {}
network_rules     = {}
