variable "cluster_name" {
  description = "Az EKS cluster neve"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes verzió (a node group és az addonok is ehhez igazodnak)"
  type        = string
}

variable "vpc_id" {
  description = "A VPC, amelyben a security groupok létrejönnek"
  type        = string
}

variable "subnet_ids" {
  description = "Privát subnetek: ide kerülnek a control plane ENI-k és a node-ok"
  type        = list(string)
}

variable "node_instance_types" {
  description = "A managed node group EC2 instance típusai"
  type        = list(string)
}

variable "node_ami_type" {
  description = "A node-ok AMI típusa (kategória, a konkrét AMI-t az EKS választja és frissíti). Illeszkednie kell az instance típus architektúrájához (x86 vagy ARM)."
  type        = string
}

variable "node_desired_size" {
  description = "A node-ok kívánt száma"
  type        = number
}

variable "node_min_size" {
  description = "A node-ok minimális száma"
  type        = number
}

variable "node_max_size" {
  description = "A node-ok maximális száma"
  type        = number
}

variable "endpoint_public_access_cidrs" {
  description = "Mely IP-tartományokból érhető el a publikus API endpoint"
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "IAM user/role ARN-ek, amelyek cluster admin jogot kapnak (access entry)"
  type        = set(string)
}

variable "nlb_ingress_cidrs" {
  description = "Honnan érhető el az NLB a 80-as porton"
  type        = list(string)
}