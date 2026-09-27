variable "region" {
  description = "Deployment region."
  type        = string
  default     = "eu-central-1"
  validation {
    condition     = var.region == "eu-central-1"
    error_message = "The IAM policy is scoped to eu-central-1."
  }
}
variable "project" {
  description = "Must match the bootstrap IAM resource-tag boundary."
  type        = string
  default     = "aws-devops-portfolio"
  validation {
    condition     = var.project == "aws-devops-portfolio"
    error_message = "The fixed project tag is also the IAM and teardown boundary."
  }
}
variable "instance_profile_name" {
  description = "Existing instance profile created by bootstrap. Required for live plans."
  type        = string
}
variable "ami_id" {
  description = "Optional reviewed Ubuntu 24.04 amd64 AMI override; null resolves Canonical's latest image at plan time."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.ami_id == null || can(regex("^ami-[a-f0-9]+$", var.ami_id))
    error_message = "Use a valid AMI ID or null."
  }
}
