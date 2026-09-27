output "instance_id" {
  description = "SSM target used by Ansible and port-forwarding sessions."
  value       = aws_instance.app.id
}
output "public_ip" {
  description = "Ephemeral IPv4 for outbound connectivity; security group allows no ingress."
  value       = aws_instance.app.public_ip
}
output "vpc_id" {
  description = "VPC identifier for teardown verification."
  value       = aws_vpc.app.id
}
output "region" {
  description = "AWS region for SSM sessions."
  value       = var.region
}
