# ECR repók: ide tölti fel a scripts/build-push.sh a két alkalmazás image-ét, és innen
# húzzák le a node-ok (a node szerep AmazonEC2ContainerRegistryReadOnly policyjával).
# for_each a szolgáltatás nevével: stabil kulcs, egy repó törlése nem tolja el a többit (a count-tal ellentétben).
# A repó neve "<előtag>/<szolgáltatás>" (pl. szino-nginx-proxy-demo/service-a): az ECR nevek fiókon belül
# régiónként egyediek, az előtag miatt több projekt vagy ember sem ütközik, és a konzolban egy "mappába" kerülnek.
resource "aws_ecr_repository" "this" {
  for_each = var.repository_names

  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}