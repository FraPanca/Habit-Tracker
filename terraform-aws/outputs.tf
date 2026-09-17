output "ecr_backend_repository_url" {
  value = aws_ecr_repository.backend_ecr_repo.repository_url
}

output "ecr_frontend_repository_url" {
  value = aws_ecr_repository.frontend_ecr_repo.repository_url
}

output "mongo_secret_arn" {
  description = "ARN del secret Mongo, servirà per la policy IAM dell'EC2"
  value       = aws_secretsmanager_secret.mongo_credentials.arn
}

output "app_security_group_id" {
  value = aws_security_group.app_sg.id
}

output "ec2_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}

output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}"
}

output "mongo_backups_bucket_name" {
  value = aws_s3_bucket.mongo_backups.bucket
}

output "github_actions_ecr_role_arn" {
  value = aws_iam_role.github_actions_ecr_push.arn
}