variable "region" {
  description = "AWS region for state storage and the deployment."
  type        = string
  default     = "eu-central-1"
  validation {
    condition     = var.region == "eu-central-1"
    error_message = "This portfolio is scoped to eu-central-1."
  }
}
variable "project" {
  description = "Stable prefix and IAM tag boundary. Keep consistent with infra."
  type        = string
  default     = "aws-devops-portfolio"
  validation {
    condition     = var.project == "aws-devops-portfolio"
    error_message = "The fixed project tag is also the IAM and teardown boundary."
  }
}
variable "github_repository" {
  description = "Only this exact GitHub owner/repository may assume OIDC roles."
  type        = string
  default     = "michaljakubowski2001/aws-devops-portfolio"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/repository, without wildcards."
  }
}
variable "existing_github_oidc_provider_arn" {
  description = "Reuse an existing account-wide GitHub OIDC provider when present."
  type        = string
  default     = null
  nullable    = true
}
