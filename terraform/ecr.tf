# One ECR repository per shopNow service: <ecr_namespace>/frontend, /backend, /admin
locals {
  ecr_services = ["frontend", "backend", "admin"]
}

resource "aws_ecr_repository" "svc" {
  for_each             = toset(local.ecr_services)
  name                 = "${var.ecr_namespace}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lets `terraform destroy` clean up in a lab setting

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Cost optimisation: keep only the 10 most recent images per repository
resource "aws_ecr_lifecycle_policy" "svc" {
  for_each   = aws_ecr_repository.svc
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
