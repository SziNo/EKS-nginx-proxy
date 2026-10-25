# EKS cluster: IAM szerepek, security groupok (az NLB-é is), cluster, addonok,
# managed node group, OIDC provider és admin access entry.
module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids # a control plane ENI-k és a node-ok is a privát subnetekben

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Aki a Terraformot futtatja (IAM user), cluster admin lesz
  cluster_admin_principal_arns = [data.aws_caller_identity.current.arn]
}
