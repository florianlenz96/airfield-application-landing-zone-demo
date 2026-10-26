variable "root_id" {
  description = "Prefix of every management group. Must be unique in the tenant."
  type        = string
}

variable "root_display_name" {
  type = string
}

variable "workloads" {
  description = "One management group per application, below Corp or Online."
  type = object({
    corp   = optional(map(string), {})
    online = optional(map(string), {})
  })
  default = {}
}

variable "subscriptions" {
  description = "Which subscription goes into which management group (management, connectivity, corp, online or <corp|online>-<workload>)."
  type        = map(list(string))

  validation {
    condition     = contains(keys(var.subscriptions), "management") && contains(keys(var.subscriptions), "connectivity")
    error_message = "subscriptions needs a management and a connectivity subscription."
  }

  validation {
    condition = alltrue([
      for id in flatten(values(var.subscriptions)) :
      can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))
    ])
    error_message = "Every subscription ID must be a lowercase GUID. Replace the placeholders."
  }
}

variable "allowed_locations" {
  type = list(string)
}

variable "logging_location" {
  type    = string
  default = "westeurope"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "defender_plans" {
  type = object({
    servers   = optional(bool, false)
    storage   = optional(bool, false)
    key_vault = optional(bool, false)
    arm       = optional(bool, false)
  })
  default = {}
}

variable "allowed_envs" {
  type    = list(string)
  default = ["dev", "test", "prod"]
}

variable "exemptions" {
  description = "Explicit, expiring exceptions from the Corp 'No public endpoints' policy."
  type = map(object({
    scope         = string
    description   = string
    category      = optional(string, "Waiver")
    expires_on    = string
    reference_ids = optional(list(string), [])
  }))
  default = {}
}
