output "alb_url" {
  description = "Open this in a browser. It serves the page from user-data.sh."
  value       = "http://${aws_lb.web.dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = aws_lb.web.dns_name
}

output "aws_region" {
  description = "Region everything was deployed into (handy for CLI commands)."
  value       = var.aws_region
}


output "resolved_ami_id" {
  description = "AMI ID used by the launch template. This is either ami_id or the current value resolved from the AL2023 SSM parameter."
  value       = local.resolved_ami_id
}

output "asg_name" {
  description = "Name of the Auto Scaling group."
  value       = aws_autoscaling_group.web.name
}

output "target_group_arn" {
  description = "ARN of the ALB target group (use it to watch target health)."
  value       = aws_lb_target_group.web.arn
}

output "fis_experiment_template_id" {
  description = "ID of the FIS experiment template."
  value       = aws_fis_experiment_template.terminate_instances.id
}

output "fis_role_arn" {
  description = "ARN of the IAM role FIS assumes during the experiment."
  value       = aws_iam_role.fis.arn
}

output "fis_log_group_name" {
  description = "CloudWatch Logs group that receives detailed FIS experiment events."
  value       = aws_cloudwatch_log_group.fis_experiments.name
}

output "preview_targets_command" {
  description = "Safe target preview: resolves the FIS targets but skips every fault action."
  value       = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.terminate_instances.id} --experiment-options actionsMode=skip-all --region ${var.aws_region}"
}

output "start_experiment_command" {
  description = "Destructive command: starts the EC2 instance-termination experiment."
  value       = "aws fis start-experiment --experiment-template-id ${aws_fis_experiment_template.terminate_instances.id} --region ${var.aws_region}"
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets."
  value       = aws_subnet.public[*].id
}
