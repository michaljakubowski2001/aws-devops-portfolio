#!/usr/bin/env bash
# Credential-free checks only: intentionally no plan, apply, destroy or AWS CLI call.
set -euo pipefail
export AWS_EC2_METADATA_DISABLED=true
terraform fmt -check -recursive bootstrap infra
for root in bootstrap infra; do
  terraform -chdir="$root" init -backend=false -input=false -lockfile=readonly
  terraform -chdir="$root" validate
  tflint --chdir="$root" --config="$PWD/.tflint.hcl"
done
