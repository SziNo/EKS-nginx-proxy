variable "name" {
  description = "Névelőtag az erőforrások Name tagjéhez (a cluster neve)"
  type        = string
}

variable "vpc_cidr" {
  description = "A VPC címtartománya"
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
}