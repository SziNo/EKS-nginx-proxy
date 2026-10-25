# Hálózat: VPC, publikus és privát subnetek 3 AZ-ban, internet és NAT gateway, route táblák.
module "vpc" {
  source = "./modules/vpc"

  name     = var.cluster_name
  vpc_cidr = var.vpc_cidr
  azs      = local.azs
}
