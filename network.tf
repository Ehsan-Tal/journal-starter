module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.16"

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"
  azs  = local.azs

  # Private subnets hold only the database (and the EKS control-plane ENIs).
  # They need no internet access, so no NAT gateway is created.
  private_subnets = [for k, az in local.azs : cidrsubnet("10.0.0.0/16", 4, k)]

  # Worker nodes live in the public subnets and get public IPs, so they can pull
  # images (ECR, Docker Hub) through the free internet gateway instead of a NAT.
  public_subnets = [for k, az in local.azs : cidrsubnet("10.0.0.0/16", 4, k + 8)]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
  enable_dns_hostnames    = true
  enable_dns_support      = true

  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
