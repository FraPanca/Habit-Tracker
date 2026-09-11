#!/bin/bash
set -euxo pipefail

AWS_REGION="${aws_region}"
MONGO_SECRET_NAME="${mongo_secret_name}"
ECR_BACKEND_IMAGE="${ecr_backend_image}"
ECR_FRONTEND_IMAGE="${ecr_frontend_image}"
GIT_REPO_URL="${git_repo_url}"

dnf update -y
dnf install -y docker git jq

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

systemctl enable --now docker

git clone "$GIT_REPO_URL" /opt/app
cd /opt/app

# Login ECR usando le credenziali temporanee del ruolo IAM dell'istanza (nessuna chiave statica)
REGISTRY_HOST=$(echo "$ECR_BACKEND_IMAGE" | cut -d/ -f1)
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$REGISTRY_HOST"

# Recupera le credenziali Mongo da Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$MONGO_SECRET_NAME" \
  --query SecretString --output text)

cat > /opt/app/.env <<EOF
MONGO_ROOT_USER=$(echo "$SECRET_JSON" | jq -r .MONGO_ROOT_USER)
MONGO_ROOT_PASSWORD=$(echo "$SECRET_JSON" | jq -r .MONGO_ROOT_PASSWORD)
MONGO_DB_NAME=$(echo "$SECRET_JSON" | jq -r .MONGO_DB_NAME)
ECR_BACKEND_IMAGE=$ECR_BACKEND_IMAGE
ECR_FRONTEND_IMAGE=$ECR_FRONTEND_IMAGE
EOF
chmod 600 /opt/app/.env

docker compose -f docker-compose.aws.yml pull
docker compose -f docker-compose.aws.yml up -d