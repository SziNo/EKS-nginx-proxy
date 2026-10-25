locals {
  # A cluster szerephez csatolt AWS managed policyk (név => ARN); for_each megy rajta végig
  cluster_policies = {
    AmazonEKSClusterPolicy = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  }

  # A node szerephez csatolt AWS managed policyk
  node_policies = {
    # A kubelet regisztrálhatja a node-ot és lekérdezheti az EKS/EC2 adatokat
    AmazonEKSWorkerNodePolicy = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    # A VPC CNI (aws-node) ENI-ket és másodlagos IP-ket kezelhet a podoknak
    AmazonEKS_CNI_Policy = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    # A node-ok le tudják húzni az image-eket az ECR-ből (Hints: "ECR authentication")
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
}

# Trust policy a cluster szerephez: csak az EKS szolgáltatás veheti fel a szerepet.
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

# Cluster IAM szerep: ezzel kezeli az EKS control plane az AWS erőforrásokat (pl. ENI-k a VPC-ben).
resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
}

# A cluster policyk csatolása a cluster szerephez.
resource "aws_iam_role_policy_attachment" "cluster" {
  for_each = local.cluster_policies

  role       = aws_iam_role.cluster.name
  policy_arn = each.value
}

# Trust policy a node szerephez: az EC2 instance-ok (a node-ok) vehetik fel.
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Node IAM szerep: ezzel futnak a node-ok (kubelet, VPC CNI, image letöltés az ECR-ből).
resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
}

# A három node policy csatolása a node szerephez.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = local.node_policies

  role       = aws_iam_role.node.name
  policy_arn = each.value
}
