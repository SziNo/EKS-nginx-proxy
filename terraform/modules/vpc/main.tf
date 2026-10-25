locals {
  # AZ név => CIDR térképek; a for_each ezeken megy végig, a kulcs az AZ neve (stabil, nem index).
  # 10.0.0.0/16 esetén:
  #   privát:   cidrsubnet(/16, 4, 0..2)  -> 10.0.0.0/20, 10.0.16.0/20, 10.0.32.0/20
  #             (nagyok, mert a VPC CNI miatt a podok is innen kapnak IP-t)
  #   publikus: cidrsubnet(/16, 8, 48..50) -> 10.0.48.0/24, 10.0.49.0/24, 10.0.50.0/24
  #             (csak az NLB és a NAT gateway van itt, kicsi is elég)
  private_subnets = { for i, az in var.azs : az => cidrsubnet(var.vpc_cidr, 4, i) }
  public_subnets  = { for i, az in var.azs : az => cidrsubnet(var.vpc_cidr, 8, 48 + i) }
}

# A VPC maga. A DNS támogatás és a DNS hostnevek kellenek az EKS-hez
# (a node-ok és a privát API endpoint névfeloldása miatt).
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# Internet gateway: ezen keresztül éri el a publikus subnet az internetet (és az internet az NLB-t).
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# Publikus subnetek AZ-nként: ide kerül az internet felé néző NLB és a NAT gateway.
# A kubernetes.io/role/elb tag alapján választja ezeket az AWS Load Balancer Controller
# internet-facing load balancerhez.
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Privát subnetek AZ-nként: itt futnak a node-ok és a podok, kívülről közvetlenül nem érhetők el.
# A kubernetes.io/role/internal-elb tag a belső load balancerekhez jelöli ki őket.
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = {
    Name                              = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Elastic IP a NAT gatewaynek: ez lesz a privát subnetekből kimenő forgalom publikus IP-je.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# NAT gateway: a privát subnetben lévő node-ok ezen keresztül érik el az internetet
# (ECR, EKS API, image-ek letöltése), miközben kívülről nem érhetők el.
#
# Gyakorláshoz EGY NAT gateway van, az első AZ publikus subnetjében: olcsóbb, de ha ez az AZ
# kiesik, a többi AZ privát subnetje sem jut ki az internetre. Élesben AZ-nként egy kellene
# a magas rendelkezésre állás miatt. for_each-csel így lehetne megoldani:
#   - aws_eip.nat:              for_each = local.public_subnets
#   - aws_nat_gateway.this:     for_each = aws_subnet.public
#                               allocation_id = aws_eip.nat[each.key].id, subnet_id = each.value.id
#   - aws_route_table.private:  for_each = local.private_subnets (AZ-nként saját route tábla)
#   - aws_route.private_nat:    for_each = aws_route_table.private
#                               nat_gateway_id = aws_nat_gateway.this[each.key].id (azonos AZ!)
#   - aws_route_table_association.private: route_table_id = aws_route_table.private[each.key].id
# Mivel minden kulcs az AZ neve, minden privát subnet a saját AZ-jában lévő NAT-ot használná.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.azs[0]].id

  tags = {
    Name = "${var.name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# Publikus route tábla: mindhárom publikus subnet ezt használja.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-public"
  }
}

# Alapértelmezett útvonal a publikus route táblában: minden nem VPC-n belüli forgalom az internet gatewayre megy.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# A publikus subnetek társítása a publikus route táblához (subnetenként egy társítás).
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Privát route tábla: mindhárom privát subnet ezt használja (egy NAT gateway esetén egy is elég).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-private"
  }
}

# Alapértelmezett útvonal a privát route táblában: a kimenő forgalom a NAT gatewayen át megy ki.
resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

# A privát subnetek társítása a privát route táblához (subnetenként egy társítás).
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
