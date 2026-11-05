# Shared data sources and locals.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Availability Zones that are enabled by default (this skips Local Zones).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# The current Amazon Linux 2023 AMI published by AWS as a public SSM parameter.
# It is used when ami_id is null. Set ami_id to pin a specific image for reproducible runs.
# user-data.sh relies on dnf and systemd, which is what AL2023 provides.
data "aws_ssm_parameter" "al2023" {
  count = var.ami_id == null ? 1 : 0
  name  = var.ami_ssm_parameter
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # The first two AZs of the Region. One public subnet goes into each.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Default behavior follows AWS's current AL2023 image. Set var.ami_id to a concrete
  # AMI ID when you want identical deployments across runs.
  resolved_ami_id = var.ami_id != null ? var.ami_id : data.aws_ssm_parameter.al2023[0].insecure_value

  # The ONE definition of the tag that marks an instance as fair game for FIS.
  # The launch template applies it (compute.tf); the FIS target selects on it (fis.tf).
  fis_target_tag = { (var.fis_target_tag_key) = var.fis_target_tag_value }

  # The page and web server setup, passed to every instance as user data.
  user_data_raw = file("${path.module}/user-data.sh")
  user_data_b64 = base64encode(local.user_data_raw)
}
