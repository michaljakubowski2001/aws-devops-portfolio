# Validation evidence

## Static checks (every push and PR, no AWS credentials)

- `terraform fmt -check -recursive bootstrap infra`
- `terraform init -backend=false -lockfile=readonly` and `terraform validate` in both roots
- TFLint 0.64.0 with the AWS ruleset 0.49.0 in both roots
- Ansible syntax check against the example inventory

Provider lock files cover macOS ARM64 and Linux AMD64. The upstream Ansible roles are unchanged in a pinned submodule.

## IAM simulation (before the first successful run)

`scripts/simulate-deploy-iam.py` evaluates the live deploy role with `iam:SimulatePrincipalPolicy`: 63/63 checks match. 52 calls are allowed:

- apply of every infra resource;
- Ansible over SSM and the S3 transfer bucket;
- smoke-test tunnels;
- destroy.

11 calls are denied:

- a non-t3.small instance (explicit deny);
- an untagged launch;
- a foreign VPC or instance;
- an ingress rule;
- an Elastic IP or NAT Gateway;
- `iam:CreateRole`, or passing the deploy role;
- writing the bootstrap state;
- an SSM session to a foreign instance.

## Live deployment (27 September 2026)

| Run | Commit | Result |
| --- | --- | --- |
| [36345922174](https://github.com/michaljakubowski2001/aws-devops-portfolio/actions/runs/36345922174) | `0407d78` | Plan failed: OIDC trust expected the name-based subject; nothing created |
| [36346314989](https://github.com/michaljakubowski2001/aws-devops-portfolio/actions/runs/36346314989) | `b1ce781` | Apply created VPC, IGW and log group, then 403 on subnet, route table and SG creation (recorded in state) |
| [36347354637](https://github.com/michaljakubowski2001/aws-devops-portfolio/actions/runs/36347354637) | `833a492` | Success in 14m22s: apply 7 added; Ansible `ok=22 changed=8`, then `ok=22 changed=0`; three APIs checked through SSM tunnels |
| [36348971073](https://github.com/michaljakubowski2001/aws-devops-portfolio/actions/runs/36348971073) | `833a492` | Destroy success: 10 resources destroyed. `verify-destroy.py` reported zero tagged instances, volumes, VPCs, subnets, security groups, route tables, Internet Gateways, Elastic IPs and log groups, and a local re-run gave the same result |

Every apply and destroy used a saved plan approved in the `production` environment.

The smoke test (`scripts/smoke-ssm.sh`) checked the following through SSM port-forwarding tunnels:

- Vaultwarden `/alive` returns an ISO timestamp;
- Grafana `/api/health` returns `database: ok`;
- the Kuma status page reports 4 monitors.
