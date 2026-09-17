resource "random_password" "mongo_root_password" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "mongo_credentials" {
  name                    = "${var.project_name}/mongo-credentials"
  recovery_window_in_days = 0
  description             = "Credenziali root MongoDB per la istanza EC2 di ${var.project_name}"
}

resource "aws_secretsmanager_secret_version" "mongo_credentials" {
  secret_id = aws_secretsmanager_secret.mongo_credentials.id

  secret_string = jsonencode({
    MONGO_ROOT_USER     = "admin"
    MONGO_ROOT_PASSWORD = random_password.mongo_root_password.result
    MONGO_DB_NAME       = "habittracker"
  })
}