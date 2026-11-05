# -----------------------------------------------------------------------------
# Networking: VPC, two public subnets (one per AZ), Internet Gateway, routing
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # lets instances resolve the package repository hostnames
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# Empties the VPC's default security group (no rules means no traffic). Nothing here
# uses it, and an empty default group is a CIS AWS Foundations recommendation.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-default-sg-locked" }
}

# The Internet Gateway is the VPC's door to the internet. Without it the ALB would be
# unreachable and the instances could not download nginx.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

# One public subnet per AZ. Spanning two AZs gives the ALB and Auto Scaling group
# cross-AZ placement for this instance-failure test; the FIS experiment itself does not
# simulate loss of an entire Availability Zone.
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # Public IPs are requested explicitly in the launch template, not subnet-wide.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

# A subnet is "public" because its route table sends internet-bound traffic to the IGW.
# Traffic to other addresses inside the VPC CIDR uses the implicit "local" route that
# AWS adds to every route table, so it needs no entry here.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

# Attach the route table to both public subnets.
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
