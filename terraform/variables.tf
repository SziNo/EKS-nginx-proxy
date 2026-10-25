variable "region" {
  description = "AWS régió"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Az EKS cluster neve"
  type        = string
  default     = "nginx-proxy-demo"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes verzió (ellenőrizd, hogy az EKS még támogatja-e)"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
