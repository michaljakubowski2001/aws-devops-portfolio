# Runbook

Step-by-step operation of the project. The [README](../README.md) explains the design; this file is the procedure.

## 1. Local checks (no AWS credentials)

```bash
git clone --recurse-submodules https://github.com/michaljakubowski2001/aws-devops-portfolio.git
cd aws-devops-portfolio
# Install Terraform 1.16.4 and TFLint 0.64.0 first.
tflint --init
bash scripts/check-local.sh

python3 -m venv .venv
source .venv/bin/activate
pip install -r ansible/requirements.txt
ANSIBLE_HOME="$PWD/.ansible" ansible-galaxy collection install -r ansible/requirements.yml -p .ansible/collections
ansible-playbook -i ansible/inventory/example.yml ansible/site.yml --syntax-check
```

`terraform init -backend=false` downloads providers without contacting S3. Static validation does not prove that IAM permissions, quotas or services work at runtime; for IAM use step 3.

## 2. Authenticate locally

Use an IAM Identity Center (SSO) or IAM user profile with MFA, never root keys, and confirm the account with `aws sts get-caller-identity`. The operator needs EC2, IAM/OIDC, S3, CloudWatch and SSM rights for bootstrap. Nothing is pasted into Git.

## 3. Bootstrap (local, reviewed plan)

```bash
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
# Set github_oidc_subject_prefix from:
gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
# Set existing_github_oidc_provider_arn if the account already has GitHub OIDC.
terraform -chdir=bootstrap init
bash scripts/local-change.sh bootstrap apply   # prints the saved plan, applies only after typing ok
```

Migrate the bootstrap state into the new bucket under its own key:

```bash
terraform -chdir=bootstrap output -raw infra_backend > infra/backend.hcl
cp bootstrap/backend.tf.example bootstrap/backend.tf
sed 's#infra/terraform.tfstate#bootstrap/terraform.tfstate#' infra/backend.hcl > bootstrap/backend.hcl
terraform -chdir=bootstrap init -migrate-state -backend-config=backend.hcl
```

This moves state, not infrastructure. The CI roles cannot read or write the bootstrap key.

Check the deploy role before the first pipeline run. The simulation covers every call made by apply, Ansible over SSM and destroy, plus negative boundary tests:

```bash
python3 scripts/simulate-deploy-iam.py   # expects 63/63
```

## 4. GitHub settings

1. Environment `production`: required reviewer, admin bypass disabled, deployment branches restricted to `main`.
2. Environment `planning`: required reviewer before a same-repository PR receives read-only AWS credentials. Fork PRs never receive a role.
3. Publish the non-secret bootstrap outputs as repository variables and enable cloud jobs:

```bash
python3 scripts/configure-github.py
gh variable set AWS_READY --body true
```

Variables: `AWS_REGION`, `AWS_ACCOUNT_ID`, `STATE_BUCKET`, `TRANSFER_BUCKET`, `PLAN_ROLE_ARN`, `DEPLOY_ROLE_ARN`, `INSTANCE_PROFILE_NAME`, `AWS_READY`. No AWS credential is stored as a Secret or variable.

## 5. Deploy

- **Pull request:** static checks run; after `planning` approval the plan is posted as a PR comment (advisory).
- **Push to `main`:** CI saves a plan and publishes it as a job summary and artifact, then waits for `production` approval. The apply job verifies the commit and the plan's SHA-256 and applies that exact file.
- **After apply:** CI builds a one-host inventory from the Terraform output, waits for SSM and cloud-init, runs the Ansible roles twice (the second run must report `changed=0`), and checks the application APIs through SSM tunnels.

A failed configuration step leaves the infrastructure running (and billable); fix and re-run, or destroy.

## 6. Open the applications

Install AWS CLI and the Session Manager plugin (`brew install --cask session-manager-plugin`). One tunnel per terminal:

```bash
instance_id=$(terraform -chdir=infra output -raw instance_id)
aws ssm start-session --region eu-central-1 --target "$instance_id" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["20158"],"localPortNumber":["20158"]}'
# Repeat with 30157 (Uptime Kuma) and 20157 (Vaultwarden).
```

| Service | URL |
| --- | --- |
| Grafana | `http://localhost:20158/d/mikrus-infrastructure` (anonymous Viewer) |
| Uptime Kuma | `http://localhost:30157/status/portfolio` |
| Vaultwarden | `http://localhost:20157` (public signup disabled) |

Admin user for Grafana and Kuma is `admin`. The passwords were generated on the instance; read them privately with `aws ssm start-session --target "$instance_id"` and `sudo cat /opt/devops-portfolio/credentials.json`. For the Vaultwarden admin page (blocked by Nginx), forward port 18080 directly.

To refresh the screenshots while the tunnels are open, run `python3 scripts/capture-screenshots.py` (requires Playwright and a local Chrome).

## 7. Destroy

Destroy deletes the root disk, application data and generated credentials. Bootstrap is not touched.

**Preferred:** Actions → **Destroy infrastructure** → branch `main` → type `DESTROY`. CI saves a destroy plan and waits for `production` approval. After apply, `scripts/verify-destroy.py` checks with the AWS CLI that no tagged resource of the project remains. Typing `DESTROY` is not the approval; the environment review is.

**Local alternative:**

```bash
bash scripts/local-change.sh infra destroy   # saved plan, typed ok, then verify-destroy.py
```

`verify-destroy.py` runs read-only AWS CLI queries for non-terminated instances, volumes, VPCs, subnets, security groups, route tables, Internet Gateways, Elastic IPs and the project log group. It fails if anything remains. Bootstrap S3 and IAM are intentionally excluded.

Afterwards disable cloud jobs so a later push cannot plan a new deployment:

```bash
gh variable set AWS_READY --body false
```

## 8. Check the bill

Billing data lags by up to 24 hours. The end date is exclusive:

```bash
aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=YYYY-MM-DD,End=YYYY-MM-DD \
  --granularity DAILY --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

Without an activated cost allocation tag, account totals can include unrelated workloads.
