# Read by landing-zones/ through terraform_remote_state.
output "hub" {
  value = module.connectivity.hub
}
