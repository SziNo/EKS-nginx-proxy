# Lekérdezések: már létező dolgok adatai, ezeket a Terraform nem hozza létre és nem törli.

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