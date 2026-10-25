# A modul csak a provider minimális verzióját köti ki (>=); a pontos rögzítés a root
# versions.tf dolga. Provider blokk itt NINCS, a root adja.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
