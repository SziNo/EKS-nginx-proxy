data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # Privát subnetek a node-oknak ÉS a podoknak (VPC CNI!) -> legyenek nagyok (/20 = ~4000 IP)
  private_subnets = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  # Publikus subnetek az NLB-nek és a NAT gateway-nek
  public_subnets = ["10.0.48.0/24", "10.0.49.0/24", "10.0.50.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # gyakorláshoz olcsóbb; élesben AZ-nként egy
  enable_dns_hostnames = true

  # Ezekből a tagekből tudja az AWS Load Balancer Controller, hová tegye a load balancert
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
