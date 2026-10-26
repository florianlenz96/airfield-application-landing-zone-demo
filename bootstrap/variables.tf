variable "management_subscription_id" {
  description = "Holds the state, the logging workspace and the pipeline identities."
  type        = string
}

variable "github_repository" {
  description = "owner/repo of this platform repository, e.g. florianlenz96/kestrel-platform."
  type        = string
}

variable "state_storage_account_name" {
  description = "Globally unique, 3-24 lowercase letters and digits."
  type        = string
}

variable "root_id" {
  description = "ID of the existing platform root management group. Same root_id as in platform/terraform.tfvars."
  type        = string
  default     = "kestrel"
}

variable "location" {
  type    = string
  default = "westeurope"
}
