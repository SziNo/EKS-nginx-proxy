# Számított és közös értékek, amelyeket a modulhívások használnak.
locals {
  # Az első 3 AZ: ide kerül 1-1 publikus és privát subnet
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # A két alkalmazás neve: ebből lesznek az ECR repók.
  # A scripts/build-push.sh ugyanezeket a neveket használja (külön, a saját ciklusában).
  services = ["service-a", "service-b"]
}