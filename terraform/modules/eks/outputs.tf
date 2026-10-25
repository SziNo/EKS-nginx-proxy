output "cluster_name" {
  description = "Az EKS cluster neve"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "A Kubernetes API címe (a Helm provider használja)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "A cluster CA tanúsítványa base64-ben (a Helm provider használja)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "Az IAM OIDC provider ARN-je (IRSA trust policyhoz)"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "Az OIDC kibocsátó címe https:// nélkül (IRSA trust policy feltételeihez)"
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

output "cluster_security_group_id" {
  description = "A control plane kiegészítő security groupja"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "A node-ok security groupja"
  value       = aws_security_group.node.id
}

output "nlb_security_group_id" {
  description = "Az NLB security groupja (a k8s/nginx-service.yaml annotációjába kerül)"
  value       = aws_security_group.nlb.id
}

output "node_role_arn" {
  description = "A node IAM szerep ARN-je"
  value       = aws_iam_role.node.arn
}
