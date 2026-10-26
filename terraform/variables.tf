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
  description = "A VPC címtartománya; a subnets CIDR-jeinek ebbe kell esniük"
  type        = string
}

variable "subnets" {
  description = "Subnetek AZ-nként: a kulcs az AZ neve, az érték a privát és a publikus subnet CIDR-je"
  type = map(object({
    private_cidr = string
    public_cidr  = string
  }))

  validation {
    condition     = length(var.subnets) >= 2
    error_message = "Az EKS-hez legalább 2 AZ kell."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [can(cidrhost(s.private_cidr, 0)), can(cidrhost(s.public_cidr, 0))]
    ]))
    error_message = "Minden private_cidr és public_cidr érvényes CIDR legyen (pl. 10.0.0.0/20)."
  }
}

variable "node_instance_types" {
  description = "A managed node group EC2 instance típusai"
  type        = list(string)
}

variable "node_ami_type" {
  description = "A node-ok AMI típusa; illeszkednie kell a node_instance_types architektúrájához (t3 = x86)"
  type        = string
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

variable "nlb_ingress_cidrs" {
  description = "Honnan érhető el az NLB a 80-as porton"
  type        = list(string)
}

variable "ecr_image_tag_mutability" {
  description = "MUTABLE: ugyanaz a tag felülírható (gyakorláshoz); IMMUTABLE: egy tag csak egyszer tölthető fel (élesben ajánlott)"
  type        = string
}

variable "ecr_force_delete" {
  description = "true: a repó akkor is törölhető, ha van benne image (gyakorláshoz, hogy a destroy lefusson); élesben false"
  type        = bool
}