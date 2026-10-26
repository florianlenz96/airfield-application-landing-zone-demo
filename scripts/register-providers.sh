#!/usr/bin/env bash
# Airstrip registers no resource providers on its own. Run this once per new subscription.
# Usage: scripts/register-providers.sh management|connectivity|landing-zone <subscription-id>
set -euo pipefail

kind="${1:?usage: register-providers.sh management|connectivity|landing-zone <subscription-id>}"
subscription="${2:?subscription id missing}"

case "$kind" in
  management)
    namespaces=(Microsoft.Management Microsoft.Security Microsoft.OperationalInsights Microsoft.PolicyInsights
      Microsoft.Insights Microsoft.Storage Microsoft.ManagedIdentity) ;;
  connectivity)
    namespaces=(Microsoft.Network Microsoft.Insights Microsoft.PolicyInsights) ;;
  landing-zone)
    # Platform (network, policies) + what the .NET demo app uses.
    namespaces=(Microsoft.Network Microsoft.Insights Microsoft.PolicyInsights Microsoft.Web
      Microsoft.Storage Microsoft.ContainerRegistry Microsoft.ManagedIdentity Microsoft.OperationalInsights) ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

for ns in "${namespaces[@]}"; do
  echo "Registering $ns in $subscription"
  az provider register --namespace "$ns" --subscription "$subscription" --wait --only-show-errors
done
