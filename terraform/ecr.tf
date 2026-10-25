# ECR repók a két alkalmazás image-ének (for_each a szolgáltatás nevével).
module "ecr" {
  source = "./modules/ecr"

  repository_names     = local.services
  image_tag_mutability = "MUTABLE" # gyakorlás közben ugyanaz a tag felülírható; élesben IMMUTABLE ajánlott
  force_delete         = true      # a destroy akkor is lefut, ha van image a repóban
}
