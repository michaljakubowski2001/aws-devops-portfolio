output "configuration" {
  description = "Non-secret values to set as GitHub repository variables after bootstrap approval."
  value = {
    AWS_REGION            = var.region
    AWS_ACCOUNT_ID        = local.account_id
    STATE_BUCKET          = aws_s3_bucket.state.id
    TRANSFER_BUCKET       = aws_s3_bucket.transfer.id
    PLAN_ROLE_ARN         = aws_iam_role.github["plan"].arn
    DEPLOY_ROLE_ARN       = aws_iam_role.github["deploy"].arn
    INSTANCE_PROFILE_NAME = aws_iam_instance_profile.app.name
  }
}
output "infra_backend" {
  description = "Save to infra/backend.hcl (ignored by Git)."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "infra/terraform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
