# Közös adatok, amelyeket a root ad át a moduloknak. A modulhívások témánként külön
# fájlban vannak: vpc.tf, eks.tf, ecr.tf, lb-controller.tf.

# A régióban elérhető availability zone-ok listája (az opt-in zónák, pl. Local Zone-ok nélkül).
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Ki futtatja a Terraformot? IAM usernél az ARN közvetlenül megadható az EKS access entrynek.
data "aws_caller_identity" "current" {}

locals {
  # Az első 3 AZ: ide kerül 1-1 publikus és privát subnet
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # A két alkalmazás neve: ebből lesznek az ECR repók (a scripts/build-push.sh is ezeket használja)
  services = ["service-a", "service-b"]
}
