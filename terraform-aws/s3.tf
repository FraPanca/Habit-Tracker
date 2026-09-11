data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "${var.project_name}-mongo-backups-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket                  = aws_s3_bucket.mongo_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    filter {}

    expiration {
      days = var.backup_retention_days
    }
  }
}