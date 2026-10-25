# Access entry: felveszi az IAM principalt (itt: a Terraformot futtató IAM usert) a cluster
# hozzáférési listájára. Enélkül a kubectl és a Helm provider "Unauthorized" hibát kapna.
# A node group szerepéhez az EKS magától létrehozza a saját access entryt.
resource "aws_eks_access_entry" "admin" {
  for_each = var.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

# Jogosultság az access entryhez: AmazonEKSClusterAdminPolicy (cluster-admin) az egész clusterre.
resource "aws_eks_access_policy_association" "admin" {
  for_each = var.cluster_admin_principal_arns

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
