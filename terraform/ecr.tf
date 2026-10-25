locals {
  services = ["service-a", "service-b"]
}

resource "aws_ecr_repository" "app" {
  for_each = toset(local.services) # stabil kulcsok: a szolgáltatás neve, nem index!

  name                 = each.value
  image_tag_mutability = "MUTABLE" # élesben IMMUTABLE ajánlott
  force_delete         = true      # gyakorláshoz: destroy akkor is menjen, ha van benne image

  image_scanning_configuration {
    scan_on_push = true
  }
}
