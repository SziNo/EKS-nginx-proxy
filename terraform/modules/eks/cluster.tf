# Az EKS cluster (control plane). Az AWS üzemelteti, mi csak a hálózatát és a hozzáférést adjuk meg.
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    # A control plane ENI-k a privát subnetekbe kerülnek
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.cluster.id]

    # Privát endpoint: a node-ok a VPC-n belül érik el az API-t
    endpoint_private_access = true
    # Publikus endpoint: a Terraform és a kubectl a saját gépről éri el
    endpoint_public_access = true
    public_access_cidrs    = var.endpoint_public_access_cidrs
  }

  access_config {
    # Csak access entry alapú hozzáférés (a régi aws-auth ConfigMap nélkül)
    authentication_mode = "API"
    # A létrehozó automatikus admin jogát kikapcsoljuk, mert explicit access entryt adunk neki
    # (access.tf). Ha mindkettő be lenne kapcsolva, a második entry létrehozása ütközne.
    bootstrap_cluster_creator_admin_permissions = false
  }

  # A szerep policyjai legyenek csatolva, mielőtt a cluster létrejön (és csak a cluster
  # törlése után kerüljenek le), különben az EKS nem tudná kezelni az ENI-ket.
  depends_on = [aws_iam_role_policy_attachment.cluster]
}
