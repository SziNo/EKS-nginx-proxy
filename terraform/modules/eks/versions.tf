# Minimális provider verziók; a pontos rögzítés a rootban van. Provider blokk itt NINCS.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}
