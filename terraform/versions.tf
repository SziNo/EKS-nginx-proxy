# A Terraform és a providerek verzióinak rögzítése.
# A "~>" operátor a főverzión belül engedi a frissítést (pl. ~> 6.0 = 6.x, de 7.0 már nem),
# a pontos verziót a "terraform init" után a .terraform.lock.hcl rögzíti (ezt commitold!).
terraform {
  # 1.6: a README is ezt írja elő; az itt használt nyelvi elemek (for_each, optional, precondition) ezzel mind működnek
  required_version = ">= 1.6"

  required_providers {
    # AWS provider: a VPC, EKS, IAM, ECR erőforrások.
    # 6.x: az aktuális főverzió. Az 5.x-hez képest törő változások vannak (pl. az aws_eip-nél
    # csak a domain = "vpc" működik, a régi vpc = true már nem), a kód ehhez igazodik.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # Helm provider: az AWS Load Balancer Controller telepítése.
    # 3.x: ehhez kell az új szintaxis (kubernetes = { ... }, set = [ ... ]); a 2.x nem ismeri,
    # a régi blokk szintaxist pedig a 3.x nem fogadja el.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }

    # TLS provider: csak egy data source-hoz kell, amely kiolvassa az EKS OIDC végpontjának
    # tanúsítványát, hogy az IAM OIDC provider ujjlenyomatát (thumbprint) ne kelljen kézzel beírni.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
