# Validation and deployment boundary

## Credential-free checks

The prepared code is checked with:

- `terraform fmt -check -recursive bootstrap infra`
- `terraform init -backend=false -input=false -lockfile=readonly` in both roots
- `terraform validate` in both roots
- TFLint 0.64.0 with AWS ruleset 0.49.0 in both roots
- Ansible syntax check against the example inventory, without a connection
- Shell and workflow syntax checks

Provider lock files cover macOS ARM64 and Linux AMD64. Upstream Ansible roles remain byte-for-byte unchanged in a pinned Git submodule.

## Not yet verified

No AWS credentials have been configured or used. No cloud plan, apply, destroy, Cost Explorer query or teardown-verification command has run.

After account activation, live verification must cover IAM authorization, S3 lock contention, OIDC trust and approval gates, account quotas, cloud-init, SSM/S3 transfer, complete service startup on t3.small, browser login/URL behavior, Ansible idempotence, tunnel-based availability checks, and final destruction confirmed by AWS CLI. Static validation is not evidence that these have passed.

Do not enable `AWS_READY` until the account, local CLI identity, bootstrap and GitHub environment protections have been reviewed.
