# Provider blokkok CSAK itt, a root modulban vannak; a saját modulok ezeket öröklik.

# AWS provider: a régiót változóból kapja. A default_tags minden AWS erőforrásra
# rákerül, így a konzolban és a számlán is látszik, mi tartozik a projekthez.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.cluster_name
      ManagedBy = "terraform"
    }
  }
}

# Helm provider (3.x szintaxis): az EKS clusterhez ugyanúgy csatlakozik, mint a kubectl.
# A kubernetes és az exec itt attribútum (= { ... }), nem blokk.
# Az exec az AWS CLI-vel kér rövid életű tokent (aws eks get-token), így nem kell
# statikus jelszót tárolni; a token az access entryben megadott admin jogot kapja.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
