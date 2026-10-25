# Minimális provider verziók; a pontos rögzítés a rootban van. Provider blokk itt NINCS
# (a Helm provider is a rootban van konfigurálva, a modul azt örökli).
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}
