# Lekérdezések: már létező dolgok adatai, ezeket a Terraform nem hozza létre és nem törli.

# Ki futtatja a Terraformot? IAM usernél az ARN közvetlenül megadható az EKS access entrynek.
data "aws_caller_identity" "current" {}