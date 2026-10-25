module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # a node-ok privát subnetben

  # Gyakorláshoz publikus API endpoint; élesben szűkítsd (cluster_endpoint_public_access_cidrs)
  cluster_endpoint_public_access = true

  # Aki a Terraformot futtatja, admin access entryt kap a clusterhez
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent    = true
      before_compute = true # a CNI legyen kész, mielőtt a node-ok elindulnak
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = 2
      max_size     = 4
      desired_size = 3 # az ábrán 3 node van

      # A modul alapból hozzáadja a node szerephez:
      #   AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy,
      #   AmazonEC2ContainerRegistryReadOnly (ECR pull!)
    }
  }
}
