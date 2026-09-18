output "ecr_backend_repository_url" {
  value = aws_ecr_repository.backend_ecr_repo.repository_url
}

output "ecr_frontend_repository_url" {
  value = aws_ecr_repository.frontend_ecr_repo.repository_url
}

output "github_actions_ecr_role_arn" {
  value = aws_iam_role.github_actions_ecr_push.arn
}