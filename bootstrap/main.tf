provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "Terraform"
      Environment = "bootstrap"
      Repository  = var.github_repository
    }
  }
}
data "aws_caller_identity" "current" {}
locals {
  account_id = data.aws_caller_identity.current.account_id
  prefix     = "${var.project}-${local.account_id}-${var.region}"
  ec2_arn    = "arn:aws:ec2:${var.region}:${local.account_id}"
  log_arn    = "arn:aws:logs:${var.region}:${local.account_id}:log-group:/aws/${var.project}/*"
}
resource "aws_s3_bucket" "state" {
  bucket        = "${local.prefix}-state"
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket" "transfer" {
  bucket        = "${local.prefix}-transfer"
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
# Deliberately unversioned: Ansible removes transfer objects, including module arguments.
resource "aws_s3_bucket_lifecycle_configuration" "transfer" {
  bucket = aws_s3_bucket.transfer.id
  rule {
    id     = "expire-abandoned-transfers"
    status = "Enabled"
    filter {}
    expiration { days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_s3_bucket_public_access_block" "private" {
  for_each                = { state = aws_s3_bucket.state.id, transfer = aws_s3_bucket.transfer.id }
  bucket                  = each.value
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "encrypted" {
  for_each = { state = aws_s3_bucket.state.id, transfer = aws_s3_bucket.transfer.id }
  bucket   = each.value
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_ownership_controls" "owned" {
  for_each = { state = aws_s3_bucket.state.id, transfer = aws_s3_bucket.transfer.id }
  bucket   = each.value
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_policy" "tls" {
  for_each = { state = aws_s3_bucket.state.id, transfer = aws_s3_bucket.transfer.id }
  bucket   = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = ["arn:aws:s3:::${each.value}", "arn:aws:s3:::${each.value}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  oidc_arn = var.existing_github_oidc_provider_arn != null ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}
resource "aws_iam_role" "github" {
  for_each             = toset(["plan", "deploy"])
  name                 = "${var.project}-${each.key}"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "sts:AssumeRoleWithWebIdentity", Principal = { Federated = local.oidc_arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = each.key == "deploy" ? [
          "${var.github_oidc_subject_prefix}:environment:production"
          ] : [
          "${var.github_oidc_subject_prefix}:environment:planning",
          "${var.github_oidc_subject_prefix}:ref:refs/heads/main"
        ]
      } }
    }]
  })
}
# Bootstrap owns IAM. The infrastructure deploy role cannot create or edit roles.
resource "aws_iam_role" "instance" {
  name = "${var.project}-instance"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "instance_logs" {
  role = aws_iam_role.instance.id
  name = "project-log-streams"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = [local.log_arn, "${local.log_arn}:*"]
    }]
  })
}
resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-instance"
  role = aws_iam_role.instance.name
}
