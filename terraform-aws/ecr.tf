resource "aws_ecr_repository" "backend_ecr_repo" {
  name                 = "${var.project_name}-backend"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "frontend_ecr_repo" {
  name                 = "${var.project_name}-frontend"
  force_delete         = true
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Politica di lifecycle: tiene solo le ultime 5 immagini per repo, utile per non far crescere inutilmente lo storage
resource "aws_ecr_lifecycle_policy" "backend_lifecycle_policy" {
  repository = aws_ecr_repository.backend_ecr_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo le ultime 5 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "frontend_lifecycle_policy" {
  repository = aws_ecr_repository.frontend_ecr_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantieni solo le ultime 5 immagini"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}