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

    # To synchronize all instances, use time-based alignment so they all start their
    # CPU cycles at the same clock time:

    # Synchronized CPU cycling script
    cat > /usr/local/bin/cpu-cycle.sh << 'SCRIPT'
    #!/bin/bash
    while true; do
      # Wait until next 6-minute boundary (00, 06, 12, 18, etc.)
      CURRENT_MIN=$(date +%M | sed 's/^0//')
      WAIT_MIN=$((6 - CURRENT_MIN % 6))
      WAIT_SEC=$((WAIT_MIN * 60 - $(date +%S)))
      sleep $WAIT_SEC
      
      # High CPU for 3 minutes
      yes > /dev/null & yes > /dev/null & yes > /dev/null &
      sleep 180
      killall yes
      
      # Low CPU for 3 minutes
      sleep 180
    done
    SCRIPT

    # This synchronizes all instances to start high CPU at the same time
    # (every 6 minutes: XX:00, XX:06, XX:12, etc.), making the aggregate
    # CPU spike uniform across the ASG.
    
    chmod +x /usr/local/bin/cpu-cycle.sh
    nohup /usr/local/bin/cpu-cycle.sh > /var/log/cpu-cycle.log 2>&1 &
  EOF
  )
}

/* Create an Application Load Balancer (ALB) that distributes incoming HTTP
traffic across your web server instances. */
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

/* Create This code creates a target group that defines where the load balancer
should send traffic and how to check if those targets are healthy. */
resource "aws_lb_target_group" "alb_target_group" {
  name     = "instance-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2 # Instance becomes healthy after 2 consecutive successful checks (60 seconds)
    interval            = 30 # Checks every 30 seconds
    matcher             = "200" # Expects HTTP 200 status code for healthy response
    path                = "/" # ALB sends HTTP GET requests to the root path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5 # Waits 5 seconds for a response before considering it failed
    unhealthy_threshold = 2 # Instance becomes unhealthy after 2 consecutive failed checks (60 seconds)
  }
}
/* How it works:
 - Auto Scaling Group automatically registers new instances to this target group
 - ALB continuously checks each instance's health by requesting http://instance-ip/
 - Only healthy instances receive traffic from the ALB
 - If an instance fails 2 checks, ALB stops sending it traffic until it passes 2 checks again
 - This ensures users only reach working instances.
*/

/* Create a listener for the ALB that forwards HTTP traffic (port 80) to the
target group, which contains your web server instances. */
resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn # Attaches this listener to your load balancer
  port              = 80 # Listens for incoming HTTP traffic on port 80
  protocol          = "HTTP"

  default_action {
    type = "forward" # Forwards all incoming requests to the target group

    forward {
      target_group {
        arn = aws_lb_target_group.alb_target_group.arn # Specifies which target group receives the traffic
      }
    }
  }
}

/* Create an Auto Scaling Group (ASG) that maintains a specified number of web
server instances (3) in the private subnets, using the launch template defined
above. The ASG automatically registers instances with the ALB's target group
and handles scaling based on CloudWatch alarms. */

/* Auto Scaling Group (ASG) that automatically manages the number of EC2
instances based on demand. */
resource "aws_autoscaling_group" "web_server_asg" {
  name                = "web-server-asg"
  # Launch instances in private subnets across multiple availability zones
  vpc_zone_identifier = module.vpc.private_subnets
  #v Automatically register new instances with the load balancer's target group
  target_group_arns   = [aws_lb_target_group.alb_target_group.arn]
  # Use load balancer health checks (not just EC2 status checks) to determine instance health
  health_check_type   = "ELB"

  min_size         = 3
  max_size         = 6
  desired_capacity = 3

  launch_template {
    # Use web server template to create identical instances
    id      = aws_launch_template.web_server.id
    # Always use the latest version of the template
    version = "$Latest"
  }

  tag {
    # Applies the "web-server" name tag to all launched instances
    key                 = "Name"
    value               = "web-server"
    propagate_at_launch = true
  }
}
/* How it works:
 - ASG maintains 3 instances initially
 - When CloudWatch alarms trigger, scaling policies adjust the desired capacity
 - ASG automatically launches/terminates instances to match desired capacity
 - New instances are automatically registered with the load balancer
 - Unhealthy instances are terminated and replaced
 - This provides automatic high availability and scalability for your web application.
*/

# Scaling policy that tells the Auto Scaling Group how to scale up when triggered.
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  # Change the number of instances by a fixed amount (not percentage or exact number)
  adjustment_type        = "ChangeInCapacity"
  # Number of instances to add when triggered
  scaling_adjustment     = 1
  # Wait 60 seconds after scaling before allowing another scale-up action
  cooldown               = 60
}
/* How it works:
 - CloudWatch alarm detects high CPU (>70% for 2 minutes)
 - Alarm triggers this scale-up policy
 - ASG increases desired capacity by 1 (e.g., 3 → 4 instances)
 - ASG launches 1 new instance using the launch template
 - 60-second cooldown prevents immediate additional scaling
 - New instance registers with load balancer and starts receiving traffic
 
Example scenario:
 - Current: 3 instances
 - High CPU alarm triggers → Policy adds 1 → Now 4 instances
 - If CPU still high after cooldown → Policy adds 1 more → Now 5 instances
 - Continues until max_size (6) is reached or CPU drops below threshold

This provides gradual, controlled scaling rather than adding all instances at once.
*/

# scaling policy that tells the Auto Scaling Group how to scale down when triggered.
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 60
}
/* This reduces costs by removing unnecessary instances during low demand while
ensuring you never go below the minimum of 3 instances. */


/* CloudWatch alarm that monitors CPU usage and triggers the scale-up policy
when CPU is too high. */
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name                = "web-server-high-cpu"
  alarm_description         = "This metric monitors for high ec2 cpu utilization"
  comparison_operator       = "GreaterThanThreshold" # Triggers when CPU exceeds threshold
  evaluation_periods        = 2 # Must exceed threshold for 2 consecutive periods (2 minutes total)
  metric_name               = "CPUUtilization" # Monitors CPU percentage
  namespace                 = "AWS/EC2" # Uses EC2 metrics from CloudWatch
  period                    = 60 # Checks CPU every 60 seconds
  statistic                 = "Average" # Calculates average CPU across all instances
  threshold                 = 70 # Alarm triggers when average CPU > 70%
  insufficient_data_actions = []

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_server_asg.name
  } # Monitors only instances in your specific ASG

  # Executes the scale-up policy when alarm triggers
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}
/* How it works:
 - CloudWatch checks average CPU every 60 seconds
 - If CPU > 70% for first period → waits
 - If CPU > 70% for second consecutive period → alarm state changes to ALARM
 - Alarm triggers scale-up policy
 - ASG adds 1 instance
 - Process repeats if CPU remains high
The 2-period requirement prevents scaling from temporary CPU spikes, ensuring
sustained high load before adding capacity.
*/

/* CloudWatch alarm that monitors CPU usage and triggers the scale-down policy
when CPU is too low. */
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
/* How it works:
 - CloudWatch checks average CPU every 60 seconds
 - If CPU < 30% for first period → waits
 - If CPU < 30% for second consecutive period → alarm state changes to ALARM
 - Alarm triggers scale-down policy
 - ASG removes 1 instance
 - Process repeats if CPU remains low (until min_size of 3)
This saves costs by removing excess capacity during low demand, while the 2-period requirement prevents scaling down from temporary CPU drops.
*/
