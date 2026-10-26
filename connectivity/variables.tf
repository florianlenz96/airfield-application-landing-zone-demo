variable "state_backend" {
  description = "Where the platform states live. scripts/platform.sh sets this from the pipeline variables."
  type = object({
    subscription_id      = string
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
  })
}

variable "location" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "address_space" {
  type = list(string)
}

variable "firewall_subnet" {
  type = string
}

variable "private_dns_zones" {
  type = set(string)
}

variable "network_rules" {
  type = map(object({
    protocols             = list(string)
    source_addresses      = list(string)
    destination_addresses = list(string)
    destination_ports     = list(string)
  }))
  default = {}
}

variable "application_rules" {
  description = "Explicit outbound FQDNs per source range. Airstrip allows no wildcards."
  type = map(object({
    source_addresses  = list(string)
    destination_fqdns = list(string)
    protocols = list(object({
      type = string
      port = number
    }))
  }))
  default = {}
}
