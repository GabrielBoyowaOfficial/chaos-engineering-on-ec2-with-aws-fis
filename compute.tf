# -----------------------------------------------------------------------------
# Compute: instance security group, launch template, Auto Scaling group
# -----------------------------------------------------------------------------

# Instance firewall. The ONLY inbound rule references the ALB's security group, so the
# instances accept HTTP from the load balancer and from nothing else, even though they
# sit in public subnets and have public IPs. There is no SSH rule.
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web instances: HTTP from the ALB only"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-web-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "web_http_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from the ALB security group only"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Outbound is limited to web ports: user-data.sh needs them to reach the Amazon Linux
# package repositories (dnf install nginx). DNS and the instance metadata service are
# not filtered by security groups, so they need no rules.
resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS to the package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "web_http_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP, for mirrors that redirect"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_launch_template" "web" {
  name_prefix            = "${var.project_name}-web-"
  description            = "Amazon Linux 2023 web server running the page from user-data.sh"
  image_id               = local.resolved_ami_id
  instance_type          = var.instance_type
  update_default_version = true
  user_data              = local.user_data_b64

  # IMDSv2 only. user-data.sh already uses session tokens, and requiring them blocks
  # the credential-theft tricks that work against the older IMDSv1.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # The subnets are public and there is no NAT gateway, so each instance needs its own
  # public IP to reach the package repositories. Inbound access is still limited to the
  # ALB by the security group.
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/xvda" # root volume of Amazon Linux

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # CRUCIAL for FIS: every instance the Auto Scaling group launches gets this tag
  # (Purpose = FIS-Target by default). The FIS experiment in fis.tf selects on it, and
  # the FIS role may only terminate instances that carry it.
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      local.fis_target_tag,
      { Name = "${var.project_name}-web" },
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${var.project_name}-web" })
  }

  tags = { Name = "${var.project_name}-web-lt" }

  lifecycle {
    create_before_destroy = true

    # A Windows editor can silently save CRLF line endings, which break the #! line of
    # the script and leave instances without a web server. Fail early instead.
    precondition {
      condition     = !strcontains(local.user_data_raw, "\r")
      error_message = "user-data.sh has Windows (CRLF) line endings. Convert it to LF (in VS Code, click CRLF in the status bar and choose LF) and run again."
    }

    # EC2 rejects user data larger than 16 KB.
    precondition {
      condition     = length(local.user_data_b64) * 3 / 4 <= 16384
      error_message = "user-data.sh is larger than EC2's 16 KB user-data limit."
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  min_size            = var.asg_min_size
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  vpc_zone_identifier = aws_subnet.public[*].id # both public subnets, so instances spread over two AZs

  # Register instances with the ALB target group, and let the ALB's health check decide
  # whether an instance is healthy ("ELB"), not just whether EC2 says it is running.
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 180 # time for user-data.sh to install nginx before checks count

  # On create, wait until the instances are healthy in the target group, so a broken
  # user-data script fails `terraform apply` instead of passing silently.
  min_elb_capacity          = var.asg_desired_capacity
  wait_for_capacity_timeout = "10m"

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  # A change to the launch template (including a newly resolved or explicitly pinned AMI,
  # or new user data) replaces instances one by one while keeping at least half in service.
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }

  # The listener must exist before instances register with the target group.
  depends_on = [aws_lb_listener.http]

  lifecycle {
    precondition {
      condition     = var.asg_min_size <= var.asg_desired_capacity && var.asg_desired_capacity <= var.asg_max_size
      error_message = "Capacity must satisfy asg_min_size <= asg_desired_capacity <= asg_max_size."
    }
  }
}
