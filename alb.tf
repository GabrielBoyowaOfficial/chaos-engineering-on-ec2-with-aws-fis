# -----------------------------------------------------------------------------
# Load balancing: security group, Application Load Balancer, target group, listener
#
# Traffic path:  internet --80--> ALB --80--> web instances
# Both hops are controlled by security-group rules (see also compute.tf).
# -----------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB: HTTP in from the internet, HTTP out to the web instances only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-alb-sg" }
}

# Inbound: HTTP from the internet (or whichever CIDRs you allow in var.alb_ingress_cidrs).
resource "aws_vpc_security_group_ingress_rule" "alb_http_in" {
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# Outbound: only to the web instances' security group, on port 80.
resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP to the web instances"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false # internet-facing
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id # one ALB node per AZ

  idle_timeout               = 60 # nginx keepalive (75 s in user-data.sh) is deliberately longer
  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "web" {
  name_prefix = "web-" # unique name, so a replacement can be created before the old one is destroyed
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # Stop sending traffic to a terminating instance quickly (default is 300 s).
  deregistration_delay = 30

  # A target is healthy after 2 consecutive 200s from /healthz and unhealthy after 2
  # failures. At a 10 s interval an instance that disappears leaves rotation in about
  # 20 s, which bounds how long clients can see errors during the FIS experiment.
  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${var.project_name}-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Port 80 listener: everything is forwarded to the target group.
# (For HTTPS, add an ACM certificate and a 443 listener; see README "Next steps".)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
