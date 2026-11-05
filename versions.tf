# Terraform and provider pins, plus the AWS provider configuration.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # For a team or production setup, keep state remote and locked, for example an
  # S3 backend with state locking. This demo uses local state.
  # backend "s3" {
  #   bucket = "<your-state-bucket>"
  #   key    = "fis-ha-demo/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  # Tags every taggable resource Terraform creates. Instances launched by the
  # Auto Scaling group are NOT covered by this: the launch template tags them
  # (see compute.tf), and that is where the FIS target tag comes from.
  default_tags {
    tags = local.common_tags
  }
}
