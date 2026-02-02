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

output "ssh_command_template" {
  description = "SSH command template"
  value       = "ssh -A -i ${var.file_name} -J ec2-user@${aws_instance.bastion.public_ip} ec2-user@<INSTANCE_PRIVATE_IP>"
}


# output "ssh_access" {
#   description = "BASH command for SSH access"
#   value = "ssh -A -i ${var.file_name} -J ec2-user@${aws_instance.bastion.public_ip} ec2-user@${data.aws_instances.asg_instances.private_ips[0]}"
# }
