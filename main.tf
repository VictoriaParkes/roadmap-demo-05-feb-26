/*VPC module creates a complete network infrastructure
using a community Terraform module from the registry */
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  # VPC with specified name and CIDR block
  name = var.vpc_name
  cidr = var.vpc_cidr

  # Deploy both private and public subnets across multiple availability zones
  azs             = var.availability_zones
  private_subnets = var.private_subnets_cidr
  public_subnets  = var.public_subnets_cidr

  # Enable private subnets to access the internet for updates/downloads
  enable_nat_gateway = true
  # Provision a virtual private gateway for VPN connections
  enable_vpn_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

  # Automatically configures route tables for public/private subnet traffic flow
}

# Empty security group container to be attached to Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "load-balancer-security-group"
  description = "Allow HTTP traffic to load balancer"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "load-balancer-security-group"
  }
}

/* Security group ingress rule for load balancer security group
allows inbound HTTP traffic on port 80 from IPs in prefix list */
resource "aws_vpc_security_group_ingress_rule" "prefix_ingress_rule" {
  security_group_id = aws_security_group.alb_sg.id

  prefix_list_id = var.prefix_list_id
  from_port      = 80
  ip_protocol    = "tcp"
  to_port        = 80
}

/* Security group egress rule for load balancer security group
allows outbound traffic to any IP address */
resource "aws_vpc_security_group_egress_rule" "preffix_egress_rule" {
  security_group_id = aws_security_group.alb_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# Empty security group container to be attached to bastion host instance
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-security-group"
  description = "Allow SSH from prefix list"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "bastion-security-group"
  }
}

/* Security group ingress rule for bastion host security group
allows inbound SSH traffic on port 22 from IPs in prefix list */
resource "aws_vpc_security_group_ingress_rule" "bastion_ingress_rule" {
  security_group_id = aws_security_group.bastion_sg.id

  prefix_list_id = var.prefix_list_id
  from_port      = 22
  ip_protocol    = "tcp"
  to_port        = 22
}

/* Security group egress rule for bastion host security group
allows outbound traffic to any IP address */
resource "aws_vpc_security_group_egress_rule" "bastion_egress_rule" {
  security_group_id = aws_security_group.bastion_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# Empty security group container to be attached to web-server instances
resource "aws_security_group" "instance_sg" {
  name        = "instance-security-group"
  description = "Allow traffic from load balancer security group to instances"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "instance-security-group"
  }
}

/* Security group ingress rule for instance security group
allows inbound HTTP traffic on port 80 from load balancer security group */
resource "aws_vpc_security_group_ingress_rule" "instance_ingress_rule" {
  security_group_id = aws_security_group.instance_sg.id

  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

/* Security group ingress rule for instance security group
allows inbound SSH traffic on port 22 from bastion host security group */
resource "aws_vpc_security_group_ingress_rule" "instance_ingress_rule_ssh" {
  security_group_id = aws_security_group.instance_sg.id

  referenced_security_group_id = aws_security_group.bastion_sg.id
  from_port                    = 22
  ip_protocol                  = "tcp"
  to_port                      = 22
}

/* Security group egress rule for instance security group
allows outbound traffic to any IP address */
resource "aws_vpc_security_group_egress_rule" "instance_egress_rule" {
  security_group_id = aws_security_group.instance_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

/* RSA key of size 4096 bits
This generates a new 4096-bit RSA key pair (public and private keys) during
the Terraform plan and apply phases, storing the private key locally in the
Terraform state file and the public key is used to create the AWS key pair.
The private key is then written to a local file for use in 

Terraform execution for SSH authentication to your EC2 instances. */
# resource "tls_private_key" "rsa-4096-example" {
#   algorithm = "RSA"
#   rsa_bits  = 4096

#   lifecycle {
#     create_before_destroy = true
#   }
# }

/* Key pair for SSH access to bastion host and web server instances.
This registers the SSH public key with AWS EC2, making it available to
attach to instances for authentication. It takes the public key from the
Terraform-generated RSA key pair (created below) and uploads it to
AWS with specified name, so both the bastion host and web servers can use
it for SSH access. */
# resource "aws_key_pair" "demo_key_pair" {
#   key_name   = var.key_pair_name
#   public_key = tls_private_key.rsa-4096-example.public_key_openssh
# }

/* This saves the private SSH key to a file locally at the path specified in
var.file_name, so it can used to SSH into the bastion host and web servers for
management and debugging purposes (e.g., ssh -i <file_name> ec2-user@<instance-ip>) */
# resource "local_file" "demo_key" {
#   content  = tls_private_key.rsa-4096-example.private_key_pem
#   filename = var.file_name
#   file_permission = "0400"
# }

# resource "aws_secretsmanager_secret" "ssh_private_key" {
#   name        = "ssh-private-key"
#   description = "SSH private key"
# }

# resource "aws_secretsmanager_secret_version" "ssh_private_key" {
#   secret_id = aws_secretsmanager_secret.ssh_private_key.id
#   secret_string = jsonencode({
#     private_key = tls_private_key.rsa-4096-example.private_key_pem
#     public_key  = tls_private_key.rsa-4096-example.public_key_openssh
#     key_name    = aws_key_pair.demo_key_pair.key_name
#   })
# }

/* Bastion host (jump box) - a single t3.micro EC2 instance in the first public
subnet with public IP address, allowing SSH access into private web servers */
# resource "aws_instance" "bastion" {
#   ami                         = data.aws_ami.amazon_linux_2023.id
#   instance_type               = "t3.micro"
#   key_name                    = aws_key_pair.demo_key_pair.key_name
#   subnet_id                   = module.vpc.public_subnets[0]
#   vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
#   associate_public_ip_address = true

#   lifecycle {
#     replace_triggered_by = [aws_key_pair.demo_key_pair]
#   }

#   tags = {
#     Name = "bastion-host"
#   }
# }

/* Define template for launching web server instances, specifying ami, instance
type, security group, SSH key and a start up script to install and configure
nginx to serve a simple HTML page showing the server's hostname. The autoscaling
group uses this template to create identical web servers on demand. */
resource "aws_launch_template" "web_server" {
  name_prefix   = "web-server-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  # key_name      = aws_key_pair.demo_key_pair.key_name

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<html><h1>Server $(hostname)</h1></html>" > /usr/share/nginx/html/index.html

    # CPU cycling script for autoscaling demo
    cat > /usr/local/bin/cpu-cycle.sh << 'SCRIPT'
    #!/bin/bash
    while true; do
      # High CPU for 3 minutes (trigger scale up)
      yes > /dev/null & yes > /dev/null & yes > /dev/null &
      PIDS="$!"
      sleep 180
      killall yes
      
      # Low CPU for 3 minutes (trigger scale down)
      sleep 180
    done
    SCRIPT
    
    chmod +x /usr/local/bin/cpu-cycle.sh
    nohup /usr/local/bin/cpu-cycle.sh > /var/log/cpu-cycle.log 2>&1 &
  EOF
  )
}

resource "aws_lb" "load_balancer" {
  load_balancer_type = "application"
  name               = "load-balancer"
  internal           = false

  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.alb_sg.id]

  tags = {
    Name = "load-balancer"
  }
}

resource "aws_lb_target_group" "alb_target_group" {
  name     = "instance-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn = aws_lb_target_group.alb_target_group.arn
      }
    }
  }
}

resource "aws_autoscaling_group" "web_server_asg" {
  name                = "web-server-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  target_group_arns   = [aws_lb_target_group.alb_target_group.arn]
  health_check_type   = "ELB"

  min_size         = 3
  max_size         = 6
  desired_capacity = 3

  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-server"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 60
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name                = "web-server-high-cpu"
  alarm_description         = "This metric monitors for high ec2 cpu utilization"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 60
  statistic                 = "Average"
  threshold                 = 70
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name                = "web-server-low-cpu"
  alarm_description         = "This metric monitors for low ec2 cpu utilization"
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = 2
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 60
  statistic                 = "Average"
  threshold                 = 30
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server_asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down.arn]
}
