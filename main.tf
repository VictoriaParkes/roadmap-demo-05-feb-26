/* VPC module creates a complete network infrastructure
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
  enable_vpn_gateway = false

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

/* Security group egress rule for instance security group
allows outbound traffic to any IP address */
resource "aws_vpc_security_group_egress_rule" "instance_egress_rule" {
  security_group_id = aws_security_group.instance_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-instance-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

# IAM role for EC2 to pull from ECR
resource "aws_iam_role" "ec2_ecr_role" {
  name = "ec2-ecr-access-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

# IAM policy to allow ec2 to pull from ecr
resource "aws_iam_role_policy_attachment" "ec2_ecr_pull" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

/* Define template for launching web server instances, specifying ami, instance
type, security group, SSH key and a start up script to install and configure
nginx to serve a simple HTML page showing the server's hostname. The autoscaling
group uses this template to create identical web servers on demand. */
resource "aws_launch_template" "web_server" {
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  # key_name      = aws_key_pair.demo_key_pair.key_name

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  # The user data script runs when the instance starts and installs Docker,
  # pulls the web app image from ECR, and runs it.
  # The base64encode function encodes the script so it can be passed as a string
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y jq
    dnf install -y docker
    systemctl start docker
    systemctl enable docker

    # Authenticate and pull from ECR
    aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${aws_ecr_repository.app.repository_url}
    docker pull ${aws_ecr_repository.app.repository_url}:latest
    
    SECRET=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.cloudinary.name} --region ${var.region} --query SecretString --output text)
    
    # run container
    docker run -d -p 80:8080 \
      -e cloudinary_cloud_name=$(echo $SECRET | jq -r .cloud_name) \
      -e cloudinary_api_key=$(echo $SECRET | jq -r .api_key) \
      -e cloudinary_api_secret=$(echo $SECRET | jq -r .api_secret) \
      --name web-server ${aws_ecr_repository.app.repository_url}:latest


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
    healthy_threshold   = 2         # Instance becomes healthy after 2 consecutive successful checks (60 seconds)
    interval            = 30        # Checks every 30 seconds
    matcher             = "200"     # Expects HTTP 200 status code for healthy response
    path                = "/health" # ALB sends HTTP GET requests to the root path
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
  port              = 80                       # Listens for incoming HTTP traffic on port 80
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
  name = "web-server-asg"
  # Launch instances in private subnets across multiple availability zones
  vpc_zone_identifier = module.vpc.private_subnets
  #v Automatically register new instances with the load balancer's target group
  target_group_arns = [aws_lb_target_group.alb_target_group.arn]
  # Use load balancer health checks (not just EC2 status checks) to determine instance health
  health_check_type = "ELB"

  min_size         = 3
  max_size         = 6
  desired_capacity = 3

  launch_template {
    # Use web server template to create identical instances
    id = aws_launch_template.web_server.id
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
  adjustment_type = "ChangeInCapacity"
  # Number of instances to add when triggered
  scaling_adjustment = 1
  # Wait 60 seconds after scaling before allowing another scale-up action
  cooldown = 60
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
  evaluation_periods        = 1                      # Must exceed threshold for x num consecutive periods
  metric_name               = "CPUUtilization"       # Monitors CPU percentage
  namespace                 = "AWS/EC2"              # Uses EC2 metrics from CloudWatch
  period                    = 60                     # Checks CPU every 60 seconds
  statistic                 = "Average"              # Calculates average CPU across all instances
  threshold                 = 50                     # Alarm triggers when average CPU > 50%
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
  evaluation_periods        = 1
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = 60
  statistic                 = "Average"
  threshold                 = 20
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

/* Create an ECR repository to store Docker images for application */
resource "aws_ecr_repository" "app" {
  name                 = "roadmap-demo-app"
  image_tag_mutability = "MUTABLE"
  /* Allows image tags to be overwritten. For example,
  you can push a new image with the same tag (like latest)
  and it will replace the old one. Setting this to IMMUTABLE
  would prevent tag overwrites, forcing unique tags for each
  image. */

  image_scanning_configuration {
    scan_on_push = true
  }
  /* Automatically scans images for security vulnerabilities (CVEs)
  whenever a new image is pushed to the repository. AWS ECR will
  check for known security issues in container image layers */

  tags = {
    Name = "roadmap-demo-app"
  }
}

/* ECR lifecycle policy that automatically manages and cleans up old
Docker images in your repository to save storage costs */
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1                     # Execution order (lower numbers run first if you have multiple rules)
      description  = "Keep last 10 images" # Human-readable explanation of what the rule does
      selection = {
        tagStatus   = "any"                # Applies to all images, tagged or untagged
        countType   = "imageCountMoreThan" # Triggers when the total image count exceeds a threshold
        countNumber = 10                   # Keeps only the 10 most recent images
      }
      action = {
        type = "expire" # Deletes images that exceed the limit
      }
    }]
  })

  /* ALTERNATIVE FORMAT
  policy = <<EOF
{
  "rules": [
  {
    "rulePriority": 1,
    "description": "Keep last 10 images",
    "selection": {
      "tagStatus": "any",
      "countType": "imageCountMoreThan",
      "countNumber": 10
    },
    "action": {
      "type": "expire"
    }
  }
  ]
}
EOF
*/
}

# AWS Secrets Manager secret container to securely store sensitive data
resource "aws_secretsmanager_secret" "cloudinary" {
  name = "cloudinary-credentials"
}

/* Store Cloudinary credentials in the secret, using JSON format for easy parsing
by applications. These values are sourced from variables defined in terraform.tfvars */
resource "aws_secretsmanager_secret_version" "cloudinary" {
  secret_id = aws_secretsmanager_secret.cloudinary.id
  secret_string = jsonencode({
    cloud_name = var.cloudinary_cloud_name
    api_key    = var.cloudinary_api_key
    api_secret = var.cloudinary_api_secret
  })
}

/* IAM policy to grant EC2 instances permission to read the Cloudinary secrets from AWS Secrets Manager */
resource "aws_iam_role_policy" "secrets_access" {
  role = aws_iam_role.ec2_ecr_role.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.cloudinary.arn
    }]
  })
}
