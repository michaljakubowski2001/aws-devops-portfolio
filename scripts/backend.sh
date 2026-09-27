#!/usr/bin/env bash
set -euo pipefail
: "${STATE_BUCKET:?Set STATE_BUCKET after local bootstrap}"
: "${AWS_REGION:?Set AWS_REGION}"
[[ "$STATE_BUCKET" =~ ^[a-z0-9.-]+$ ]]
[[ "$AWS_REGION" == eu-central-1 ]]
cat > infra/backend.hcl <<EOF_BACKEND
bucket       = "$STATE_BUCKET"
key          = "infra/terraform.tfstate"
region       = "$AWS_REGION"
encrypt      = true
use_lockfile = true
EOF_BACKEND
terraform -chdir=infra init -input=false -lockfile=readonly -backend-config=backend.hcl
