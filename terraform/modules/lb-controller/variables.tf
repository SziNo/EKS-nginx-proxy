variable "cluster_name" {
  description = "Az EKS cluster neve (a controller ezzel tageli/keresi az erőforrásait)"
  type        = string
}

variable "region" {
  description = "AWS régió (megadjuk, hogy a controllernek ne kelljen az IMDS-ből kiolvasnia)"
  type        = string
}

variable "vpc_id" {
  description = "A VPC azonosítója (megadjuk, hogy a controllernek ne kelljen az IMDS-ből kiolvasnia)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "Az IAM OIDC provider ARN-je (az eks modul kimenete)"
  type        = string
}

variable "oidc_provider_url" {
  description = "Az OIDC kibocsátó címe https:// nélkül (az eks modul kimenete)"
  type        = string
}

variable "namespace" {
  description = "Ebbe a namespace-be települ a controller"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "A controller ServiceAccountjának neve; csak ez veheti fel az IAM szerepet"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "chart_version" {
  description = "Az aws-load-balancer-controller Helm chart verziója; az iam_policy.json ehhez illeszkedjen"
  type        = string
}
