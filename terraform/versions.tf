# A Terraform és a providerek verzióinak rögzítése.
# A "~>" operátor a főverzión belül engedi a frissítést (pl. ~> 6.0 = 6.x, de 7.0 már nem),
# a pontos verziót a "terraform init" után a .terraform.lock.hcl rögzíti (ezt commitold!).
terraform {
  # 1.6: a README is ezt írja elő; az itt használt nyelvi elemek (for_each, optional, precondition) ezzel mind működnek
  required_version = ">= 1.6"

  # Remote state S3-ban (most NINCS bekapcsolva, a state helyben van: terraform/terraform.tfstate).

  # A bucketet ELŐRE, kézzel kell létrehozni, mert az "init" már keresi, mielőtt bármit létrehozna:
  #   aws s3 mb s3://nginx-proxy-demo-tfstate-362099375729 --region eu-west-1
  #   aws s3api put-bucket-versioning --bucket nginx-proxy-demo-tfstate-362099375729 \
  #     --versioning-configuration Status=Enabled     # ajánlott: egy elrontott state visszaállítható
  # (A nyilvános hozzáférés tiltása és a titkosítás az új bucketeken alapból be van kapcsolva.)

  # Bekapcsolás: vedd ki a kommentet a blokk elől, majd "terraform init -migrate-state"
  # (átköltözteti a helyi state-et a bucketbe).
  # A backend blokkban NEM használhatók változók: az init minden más előtt olvassa be, ezért szó szerinti értékek.
  # A use_lockfile egy .tflock fájllal zárol az S3-ban, így két egyidejű apply nem írhatja felül egymást
  # (régebben ehhez DynamoDB tábla kellett).

  # backend "s3" {
  #   bucket       = "nginx-proxy-demo-tfstate-362099375729"
  #   key          = "eks-nginx-proxy/terraform.tfstate"
  #   region       = "eu-west-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }

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
