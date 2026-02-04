data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:Name"
    values = ["web-server"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

output "asg_instance_private_ips" {
  description = "Private IPs of ASG instances"
  value       = data.aws_instances.asg_instances.private_ips
}

output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = "HTTP://${aws_lb.load_balancer.dns_name}"
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.app.repository_url
}

# output "ssh_command_template" {
#   description = "SSH command template"
#   value       = "ssh -A -i ${var.file_name} -J ec2-user@${aws_instance.bastion.public_ip} ec2-user@<INSTANCE_PRIVATE_IP>"
# }


# output "ssh_access" {
#   description = "BASH command for SSH access"
#   value = "ssh -A -i ${var.file_name} -J ec2-user@${aws_instance.bastion.public_ip} ec2-user@${data.aws_instances.asg_instances.private_ips[0]}"
# }

# # Output public key (safe to display)
# output "public_key_openshh" {
#   description = "Public key in OpenSSH format"
#   value       = tls_private_key.rsa-4096-example.public_key_openssh
# }

# # Output private key (sensitive)
# output "private_key_pem" {
#   description = "Private key in PEM format"
#   value       = tls_private_key.rsa-4096-example.private_key_pem
#   sensitive   = true
# }