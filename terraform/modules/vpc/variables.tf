variable "name" {
  description = "Névelőtag az erőforrások Name tagjéhez (a cluster neve)"
  type        = string
}

variable "vpc_cidr" {
  description = "A VPC címtartománya (legalább /16, hogy a /20-as privát subnetek beleférjenek)"
  type        = string
}

variable "azs" {
  description = "Availability zone-ok listája; mindegyikbe 1 publikus és 1 privát subnet kerül"
  type        = list(string)

  # A subnet-kiosztás (lásd main.tf locals) legfeljebb 3 AZ-ra van méretezve:
  # 4 AZ esetén a 4. privát /20 átfedne a publikus /24-ekkel.
  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Az EKS-hez legalább 2, ehhez a subnet-kiosztáshoz legfeljebb 3 AZ kell."
  }
}
