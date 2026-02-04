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
