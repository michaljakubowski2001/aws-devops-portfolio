#!/usr/bin/env bash
# Human-operated helper. An automated agent must additionally obtain a fresh chat "ok".
set -euo pipefail
root=${1:?Usage: local-change.sh bootstrap|infra apply|destroy}
action=${2:?Usage: local-change.sh bootstrap|infra apply|destroy}
[[ "$root" == bootstrap || "$root" == infra ]]
[[ "$action" == apply || "$action" == destroy ]]
if [[ "$root" == bootstrap && "$action" == destroy ]]; then
  echo 'Bootstrap teardown is intentionally outside this lab workflow.' >&2
  exit 1
fi
mkdir -p .artifacts
args=()
if [[ "$action" == destroy ]]; then args+=(-destroy); fi
plan="$PWD/.artifacts/local-$root.tfplan"
terraform -chdir="$root" plan -input=false "${args[@]}" -out="$plan"
terraform -chdir="$root" show -no-color "$plan"
printf '\nReview the complete plan above. Type ok to apply precisely this saved plan: '
read -r approval
[[ "$approval" == ok ]] || { echo 'Cancelled.'; exit 1; }
terraform -chdir="$root" apply -input=false "$plan"
if [[ "$root" == infra && "$action" == destroy ]]; then python3 scripts/verify-destroy.py; fi
