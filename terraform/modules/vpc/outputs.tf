output "vpc_id" {
  description = "A VPC azonosítója"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "A VPC címtartománya"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "A publikus subnetek azonosítói (AZ név szerint rendezve)"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "A privát subnetek azonosítói (AZ név szerint rendezve)"
  value       = [for s in aws_subnet.private : s.id]
}

output "nat_public_ip" {
  description = "A NAT gateway publikus IP-je (ezzel az IP-vel mennek ki a node-ok)"
  value       = aws_eip.nat.public_ip
}
