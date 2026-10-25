variable "region" {
  description = "AWS régió"
  type        = string
}

variable "cluster_name" {
  description = "Az EKS cluster neve (a legtöbb erőforrás neve is ebből képződik)"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes verzió (ellenőrizd, hogy standard támogatásban van-e: aws eks describe-cluster-versions)"
  type        = string
}

variable "vpc_cidr" {
  description = "A VPC címtartománya; a subnetek ebből számolódnak (cidrsubnet)"
  type        = string
}

variable "node_instance_types" {
  description = "A managed node group EC2 instance típusai"
  type        = list(string)
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "Mely IP-tartományokból érhető el a publikus EKS API endpoint (gyakorláshoz mindenhonnan; élesben szűkítsd a saját IP-dre)"
  type        = list(string)
}

variable "node_desired_size" {
  description = "A node group kívánt node száma"
  type        = number
}

variable "node_min_size" {
  description = "A node group minimális node száma"
  type        = number
}

variable "node_max_size" {
  description = "A node group maximális node száma"
  type        = number
}

variable "lb_controller_chart_version" {
  description = "Az aws-load-balancer-controller Helm chart verziója; a 3.x óta megegyezik a controller verziójával, és a modules/lb-controller/iam_policy.json-nak ehhez kell illeszkednie. Ennek marad alapértéke, mert a policy JSON-hoz kötődik, vagyis a kód része."
  type        = string
  default     = "3.6.2"
}
