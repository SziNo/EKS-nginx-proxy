# ECR repók: ide tölti fel a scripts/build-push.sh a két alkalmazás image-ét, és innen
# húzzák le a node-ok (a node szerep AmazonEC2ContainerRegistryReadOnly policyjával).
# for_each a repó nevével: stabil kulcs, egy repó törlése nem tolja el a többit (a count-tal ellentétben).
resource "aws_ecr_repository" "this" {
  for_each = var.repository_names

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
