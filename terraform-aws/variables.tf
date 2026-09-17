variable "aws_region" {
  description = "Regione AWS in cui creare le risorse"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefisso usato per nominare le risorse"
  type        = string
  default     = "habit-tracker"
}

variable "allowed_ssh_cidr" {
  description = "CIDR (formato IP/32) autorizzato a connettersi via SSH alla porta 22"
  type        = string
  # nessun default: obbligatorio impostarlo esplicitamente
}

variable "instance_type" {
  description = "Tipo di istanza EC2 free-tier"
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key_path" {
  description = "Percorso locale della tua chiave pubblica SSH"
  type        = string
}

variable "app_repo_url" {
  description = "URL del repository Git dell'app da clonare sull'EC2"
  type        = string
  default     = "https://github.com/FraPanca/Habit-Tracker.git"
}

variable "backend_image_tag" {
  description = "Tag dell'immagine backend in ECR da deployare"
  type        = string
}

variable "frontend_image_tag" {
  description = "Tag dell'immagine frontend in ECR da deployare"
  type        = string
}

variable "backup_retention_days" {
  description = "Giorni di retention dei backup MongoDB su S3 prima della cancellazione automatica"
  type        = number
  default     = 7
}

variable "github_repo" {
  description = "Repository GitHub nel formato owner/repo, per la condizione di trust OIDC"
  type        = string
  default     = "FraPanca/Habit-Tracker"
}

variable "github_owner_id" {
  description = "ID numerico immutabile dell'account GitHub, usato nel claim OIDC 'sub'"
  type        = string
  default     = "195170957"
}

variable "github_repository_id" {
  description = "ID numerico immutabile del repository GitHub, usato nel claim OIDC 'sub'"
  type        = string
  default     = "1340543158"
}