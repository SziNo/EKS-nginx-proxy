output "repository_urls" {
  description = "Repó név => repó URL (pl. service-a => 123456789012.dkr.ecr.eu-west-1.amazonaws.com/service-a)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Repó név => repó ARN"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
