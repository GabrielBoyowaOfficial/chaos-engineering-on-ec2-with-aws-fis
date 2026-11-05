# -----------------------------------------------------------------------------
# AWS Fault Injection Service: IAM role, experiment logs, stop-condition alarm, experiment template
# -----------------------------------------------------------------------------

# ---- IAM: the identity FIS acts as during an experiment ---------------------

# Trust policy: only the FIS service can assume this role, and only for experiments
# that belong to THIS account and Region (AWS's recommended confused-deputy protection).
data "aws_iam_policy_document" "fis_trust" {
  statement {
    sid     = "FisAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:fis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:experiment/*"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "${var.project_name}-fis-role"
  description        = "Assumed by AWS FIS for the ${var.project_name} EC2 instance-failure experiment"
  assume_role_policy = data.aws_iam_policy_document.fis_trust.json
}

# Permissions: what the aws:ec2:terminate-instances action needs, and nothing more.
# Modelled on AWS's AWSFaultInjectionSimulatorEC2Access managed policy, but narrower.
data "aws_iam_policy_document" "fis_permissions" {
  # Read-only lookups FIS uses to resolve the target list. Describe actions cannot be
  # limited to specific resources, hence "*".
  statement {
    sid       = "ResolveTargets"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }

  # The only destructive permission: terminate instances in this account and Region
  # that carry the FIS target tag. An instance without the tag cannot be terminated
  # through this role, even if someone points an experiment at it by mistake. The
  # Project tag adds a second independent boundary around this demo's instances.
  statement {
    sid       = "TerminateTaggedInstancesOnly"
    actions   = ["ec2:TerminateInstances"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.fis_target_tag_key}"
      values   = [var.fis_target_tag_value]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }
}

resource "aws_iam_role_policy" "fis" {
  name   = "terminate-tagged-instances"
  role   = aws_iam_role.fis.id
  policy = data.aws_iam_policy_document.fis_permissions.json
}

# ---- Observability: FIS experiment logs -------------------------------------

# FIS writes detailed experiment events (target resolution, action start/end,
# experiment state changes, etc.) to this CloudWatch Logs group. The /aws/vendedlogs/
# prefix is friendly to AWS service log-delivery resource policies.
resource "aws_cloudwatch_log_group" "fis_experiments" {
  name              = "/aws/vendedlogs/fis/${var.project_name}"
  retention_in_days = 30
}

# ---- Guardrail: stop condition ----------------------------------------------

# FIS halts a running experiment if this alarm goes into ALARM. It fires when the load
# balancer has no healthy target left. Terminating instances is instant and cannot be
# undone, so this mainly protects any follow-up actions you add to the experiment later;
# it is a useful safety guardrail for any additional duration-based actions you add later.
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  alarm_name        = "${var.project_name}-no-healthy-targets"
  alarm_description = "FIS stop condition: the ALB has no healthy targets."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HealthyHostCount"
  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }

  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching" # no data means no healthy targets
}

# ---- The experiment ---------------------------------------------------------

resource "aws_fis_experiment_template" "terminate_instances" {
  description = "Instance-failure HA test: terminate ${var.fis_percent_to_terminate}% of the running ${var.project_name} web instances and verify ALB routing plus ASG self-healing"
  role_arn    = aws_iam_role.fis.arn

  # Detailed FIS experiment events are delivered to CloudWatch Logs. The FIS
  # API requires the log-group ARN to end in :*. Schema version 2 is current.
  log_configuration {
    log_schema_version = 2

    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis_experiments.arn}:*"
    }
  }

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.no_healthy_targets.arn
  }

  action {
    name        = "terminate-instances"
    action_id   = "aws:ec2:terminate-instances"
    description = "Terminate the selected instances; the Auto Scaling group should replace them"

    target {
      key   = "Instances"
      value = "tagged-web-instances"
    }
  }

  target {
    name          = "tagged-web-instances"
    resource_type = "aws:ec2:instance"

    # PERCENT(50) picks half of the matching instances at random. FIS rounds down and
    # cannot select less than one instance, so with only one instance running the
    # experiment fails instead of taking down the last server.
    selection_mode = "PERCENT(${var.fis_percent_to_terminate})"

    # Both tags must match. Purpose marks an instance as intentionally eligible for FIS;
    # Project confines the blast radius to this Terraform deployment.
    resource_tag {
      key   = var.fis_target_tag_key
      value = var.fis_target_tag_value
    }

    resource_tag {
      key   = "Project"
      value = var.project_name
    }

    # Filters are ANDed with the tags. A terminated instance keeps its tag and stays
    # visible for a while, so only running instances count; and the VPC filter keeps
    # the experiment away from any similarly tagged instance elsewhere in the account.
    filter {
      path   = "State.Name"
      values = ["running"]
    }

    filter {
      path   = "VpcId"
      values = [aws_vpc.main.id]
    }
  }

  tags = { Name = "${var.project_name}-instance-failure-${var.fis_percent_to_terminate}pct" }

  # Attach the permissions before FIS validates the template.
  depends_on = [aws_iam_role_policy.fis]
}
