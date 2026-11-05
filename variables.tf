# Inputs. Every default below gives the setup described in the brief, so
# `terraform apply` works with no tfvars file.

variable "aws_region" {
  description = "AWS Region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix for resource names and a tag value (2-20 characters: lowercase letters, digits and hyphens)."
  type        = string
  default     = "fis-ha-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 2-20 characters: lowercase letters, digits and hyphens, starting with a letter and not ending with a hyphen."
  }
}

variable "environment" {
  description = "Environment label used in tags."
  type        = string
  default     = "demo"
}

# ---- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, for example 10.0.0.0/16."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets, one per Availability Zone. They must sit inside vpc_cidr."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Provide exactly two valid CIDR blocks, one for each Availability Zone."
  }
}

variable "alb_ingress_cidrs" {
  description = "Source CIDR blocks allowed to reach the ALB on port 80. The default is the whole internet; narrow it to your own IP while testing."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0 && alltrue([for c in var.alb_ingress_cidrs : can(cidrhost(c, 0))])
    error_message = "alb_ingress_cidrs must contain at least one valid CIDR block."
  }
}

# ---- Load balancer ----------------------------------------------------------

variable "health_check_path" {
  description = "Path the ALB requests to decide whether a target is healthy. user-data.sh serves 200 on /healthz."
  type        = string
  default     = "/healthz"
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion. Leave false for a demo so `terraform destroy` works; set true in production."
  type        = bool
  default     = false
}

# ---- Compute ----------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the web servers."
  type        = string
  default     = "t3.micro"
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that resolves to the latest Amazon Linux 2023 AMI. Use the arm64 parameter if you switch to a Graviton (t4g) instance type."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "ami_id" {
  description = "Optional compatible Amazon Linux 2023 AMI ID to pin for reproducible runs. Leave null to resolve the current AL2023 AMI from ami_ssm_parameter."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-fA-F]+$", var.ami_id))
    error_message = "ami_id must be null or a valid-looking EC2 AMI ID such as ami-0123456789abcdef0."
  }
}

variable "asg_min_size" {
  description = "Minimum number of instances. Keep at least 1 so the site is never fully down."
  type        = number
  default     = 1

  validation {
    condition     = var.asg_min_size >= 1
    error_message = "asg_min_size must be at least 1."
  }
}

variable "asg_desired_capacity" {
  description = "Number of instances the Auto Scaling group tries to keep running."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum number of instances."
  type        = number
  default     = 4
}

# ---- Fault Injection Service ------------------------------------------------

variable "fis_target_tag_key" {
  description = "Tag key that marks instances as eligible targets for FIS. The launch template applies it and the experiment selects on it."
  type        = string
  default     = "Purpose"
}

variable "fis_target_tag_value" {
  description = "Tag value that marks instances as eligible targets for FIS."
  type        = string
  default     = "FIS-Target"
}

variable "fis_percent_to_terminate" {
  description = "Percentage of the targeted, running instances the experiment terminates. FIS rounds down."
  type        = number
  default     = 50

  validation {
    condition     = var.fis_percent_to_terminate >= 1 && var.fis_percent_to_terminate <= 100
    error_message = "fis_percent_to_terminate must be between 1 and 100."
  }
}
