# Trust policy: chi può assumere questo ruolo (solo il servizio EC2)
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Permesso: leggere SOLO il secret Mongo di questo progetto
data "aws_iam_policy_document" "read_mongo_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.mongo_credentials.arn]
  }
}

resource "aws_iam_policy" "read_mongo_secret" {
  name   = "${var.project_name}-read-mongo-secret"
  policy = data.aws_iam_policy_document.read_mongo_secret.json
}

resource "aws_iam_role_policy_attachment" "read_mongo_secret" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.read_mongo_secret.arn
}

# Permesso: pull di sole immagini da ECR
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# L'instance profile è il "contenitore" che collega un IAM role a un'istanza EC2
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}