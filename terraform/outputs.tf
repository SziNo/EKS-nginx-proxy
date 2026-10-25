# A scripts/ és a README ezekre a nevekre hivatkozik, ezért a nevek nem változtak.

output "region" {
  value = var.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "nlb_security_group_id" {
  value = module.eks.nlb_security_group_id
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
