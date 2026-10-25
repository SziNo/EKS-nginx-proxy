variable "region" {
  description = "AWS régió"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "Az EKS cluster neve (a legtöbb erőforrás neve is ebből képződik)"
  type        = string
  default     = "nginx-proxy-demo"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes verzió (ellenőrizd, hogy standard támogatásban van-e: aws eks describe-cluster-versions)"
  type        = string
  default     = "1.37"
}

variable "vpc_cidr" {
  description = "A VPC címtartománya; a subnetek ebből számolódnak (cidrsubnet)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "A managed node group EC2 instance típusai"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Mely IP-tartományokból érhető el a publikus EKS API endpoint (gyakorláshoz mindenhonnan; élesben szűkítsd a saját IP-dre)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "lb_controller_chart_version" {
  description = "Az aws-load-balancer-controller Helm chart verziója. A modules/lb-controller/iam_policy.json-nak a chart appVersion-jéhez kell illeszkednie (chart 1.N.x = controller v2.N.x)."
  type        = string
  default     = "3.6.2"
}
