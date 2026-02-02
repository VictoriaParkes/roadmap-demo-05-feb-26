module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets_cidr
  public_subnets  = var.public_subnets_cidr

  enable_nat_gateway = true
  enable_vpn_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "alb_sg" {
  name        = "load-balancer-security-group"
  description = "Allow HTTP traffic to load balancer"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "load-balancer-SG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "prefix_ingress_rule" {
  security_group_id = aws_security_group.alb_sg.id

  prefix_list_id = var.prefix_list_id
  from_port      = 80
  ip_protocol    = "tcp"
  to_port        = 80
}

resource "aws_vpc_security_group_egress_rule" "preffix_egress_rule" {
  security_group_id = aws_security_group.alb_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_security_group" "instance_sg" {
  name        = "instance-security-group"
  description = "Allow traffic from load balancer security group to instances"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "instance-SG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "instance_ingress_rule" {
  security_group_id = aws_security_group.instance_sg.id

  referenced_security_group_id = aws_security_group.alb_sg.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "instance_egress_rule" {
  security_group_id = aws_security_group.instance_sg.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# resource "aws_instance" "web_server_instance" {
#   count                  = length(module.vpc.private_subnets)
#   subnet_id              = module.vpc.private_subnets[count.index]
#   ami                    = data.aws_ami.amazon_linux_2023.id
#   instance_type          = "t3.micro"
#   vpc_security_group_ids = [aws_security_group.instance_sg.id]

#   user_data_base64 = base64encode(<<-EOF
#     #!/bin/bash
#     dnf update -y
#     dnf install -y nginx
#     systemctl start nginx
#     systemctl enable nginx
#     echo "<html><h1>Server ${count.index + 1}</h1></html>" > /usr/share/nginx/html/index.html
#   EOF
#   )

#   tags = {
#     Name = "web-server ${count.index + 1}"
#   }
# }

resource "aws_launch_template" "web_server" {
  name_prefix   = "web-server-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y nginx
    systemctl start nginx
    systemctl enable nginx
    echo "<html><h1>Server $(hostname)</h1></html>" > /usr/share/nginx/html/index.html
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

# resource "aws_lb_target_group_attachment" "alb_target_group_attachment" {
#   count            = length(aws_instance.web_server_instance)
#   target_group_arn = aws_lb_target_group.alb_target_group.arn
#   target_id        = aws_instance.web_server_instance[count.index].id
#   port             = 80
# }

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
  
  min_size         = 2
  max_size         = 6
  desired_capacity = 3

  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-server-asg"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale-down"
  autoscaling_group_name = aws_autoscaling_group.web_server_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 300
}
