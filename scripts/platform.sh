#!/usr/bin/env bash
# Runs the platform in dependency order, the same way on a laptop and in CI:
#   1. platform       management groups, policies, subscription placement
#   2. connectivity   hub, firewall, private DNS zones
#   3. landing-zones  one state per file: landing-zones/<name>.tfvars
#
# Usage:
#   scripts/platform.sh plan              plan everything (read-only identity, no state lock)
#   scripts/platform.sh apply             plan, then apply every root that has changes
#   scripts/platform.sh destroy <name>    destroy one landing zone (rehearsal reset)
#
# Needs TFSTATE_SUBSCRIPTION_ID, TFSTATE_RESOURCE_GROUP, TFSTATE_STORAGE_ACCOUNT,
# TFSTATE_CONTAINER and an Azure login (az login locally, OIDC in GitHub Actions).
# Writes a Markdown summary to $SUMMARY_FILE (default: plan-summary.md).
set -euo pipefail

mode="${1:?usage: platform.sh plan|apply|destroy <landing-zone>}"
target="${2:-}"
cd "$(dirname "$0")/.."

summary="${SUMMARY_FILE:-$PWD/plan-summary.md}"
: >"$summary"
failed=0

: "${TFSTATE_SUBSCRIPTION_ID:?}" "${TFSTATE_RESOURCE_GROUP:?}" "${TFSTATE_STORAGE_ACCOUNT:?}" "${TFSTATE_CONTAINER:?}"
export TF_IN_AUTOMATION=1
TF_VAR_state_backend="$(printf '{"subscription_id":"%s","resource_group_name":"%s","storage_account_name":"%s","container_name":"%s"}' \
  "$TFSTATE_SUBSCRIPTION_ID" "$TFSTATE_RESOURCE_GROUP" "$TFSTATE_STORAGE_ACCOUNT" "$TFSTATE_CONTAINER")"
export TF_VAR_state_backend

# Plans run with a read-only identity, which can't take the state lock.
plan_flags=(-input=false -no-color -out=tfplan -detailed-exitcode)
case "$mode" in
  plan) plan_flags+=(-lock=false) ;;
  apply) ;;
  destroy) plan_flags+=(-destroy) ;;
  *) echo "unknown mode: $mode" >&2; exit 2 ;;
esac

note() { printf '%s\n' "$@" >>"$summary"; }

init() { # <dir> <state key>
  local log; log="$(mktemp)"
  if ! terraform -chdir="$1" init -input=false -reconfigure -no-color \
    -backend-config="subscription_id=${TFSTATE_SUBSCRIPTION_ID}" \
    -backend-config="resource_group_name=${TFSTATE_RESOURCE_GROUP}" \
    -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}" \
    -backend-config="container_name=${TFSTATE_CONTAINER}" \
    -backend-config="key=$2" \
    -backend-config="use_azuread_auth=true" >"$log" 2>&1; then
    cat "$log"
    return 1
  fi
}

fail() { # <label> <log>
  failed=1
  note "#### ❌ \`$1\`: failed" '```text' "$(tail -n 40 "$2")" '```' ''
  if [[ "$mode" != "plan" ]]; then
    echo "::error::$1 failed"
    exit 1
  fi
}

run_root() { # <label> <dir> <state key> [extra plan arguments]
  local label="$1" dir="$2" key="$3"
  shift 3
  local log="$dir/plan.log" rc=0
  echo "::group::$label ($mode)"

  if ! init "$dir" "$key" >"$log" 2>&1; then
    cat "$log"; fail "$label" "$log"; echo "::endgroup::"; return 0
  fi

  terraform -chdir="$dir" plan "${plan_flags[@]}" "$@" >"$log" 2>&1 || rc=$?
  cat "$log"
  case "$rc" in
    0)
      note "#### ✅ \`$label\`: no changes" ''
      ;;
    2)
      local headline
      headline="$(grep -E '^Plan:' "$log" || echo 'Output changes only.')"
      note "#### 📝 \`$label\`: $headline" '<details><summary>Show the plan</summary>' '' '```diff'
      # Move +, - and ~ to the start of the line so GitHub colours the diff.
      terraform -chdir="$dir" show -no-color tfplan >"$dir/plan.txt"
      # head stops reading early; ignore the resulting SIGPIPE.
      sed -E 's/^([[:space:]]+)([-+~])/\2\1/' "$dir/plan.txt" | head -c 20000 >>"$summary" || true
      note '' '```' '</details>' ''
      ;;
    *)
      fail "$label" "$log"; echo "::endgroup::"; return 0
      ;;
  esac

  if [[ "$mode" != "plan" && "$rc" -eq 2 ]]; then
    if ! terraform -chdir="$dir" apply -input=false -no-color tfplan 2>&1 | tee "$dir/apply.log"; then
      fail "$label" "$dir/apply.log"
    fi
    if [[ "$dir" == "landing-zones" && "$mode" == "apply" ]]; then
      note "$(terraform -chdir="$dir" output -raw summary)" ''
    fi
  fi
  echo "::endgroup::"
}

run_landing_zone() { # <name>
  # The file name is the landing zone name. One state per landing zone.
  run_root "landing-zones/$1" landing-zones "landing-zone-$1.tfstate" \
    -var-file="$1.tfvars" -var="name=$1"
}

if [[ "$mode" == "destroy" ]]; then
  if [[ ! "$target" =~ ^[a-z][a-z0-9-]{2,23}$ || ! -f "landing-zones/$target.tfvars" ]]; then
    echo "::error::landing-zones/$target.tfvars not found. Destroy it before deleting its file."
    exit 1
  fi
  run_landing_zone "$target"
  exit "$failed"
fi

run_root platform platform management-groups.tfstate
run_root connectivity connectivity connectivity.tfstate
for file in landing-zones/*.tfvars; do
  [[ -e "$file" ]] || continue
  name="$(basename "$file" .tfvars)"
  if [[ ! "$name" =~ ^[a-z][a-z0-9-]{2,23}$ ]]; then
    echo "::error file=$file::file name must be 3-24 lowercase letters, digits and hyphens"
    exit 1
  fi
  run_landing_zone "$name"
done

exit "$failed"
