resource "aws_ecr_repository" "app" {
  name = "aws-deployment-demo"

  # MUTABLE is required because CI also pushes a convenience ":latest" tag.
  # Deployments never depend on "latest" — they always reference the exact
  # commit SHA tag, so image versions stay reproducible.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "aws-deployment-demo" }
}
