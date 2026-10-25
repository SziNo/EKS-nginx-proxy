output "iam_role_arn" {
  description = "A controller IRSA szerepének ARN-je"
  value       = aws_iam_role.this.arn
}

output "helm_release_version" {
  description = "A telepített chart verziója"
  value       = helm_release.this.version
}
