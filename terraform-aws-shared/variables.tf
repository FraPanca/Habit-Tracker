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

variable "github_repo" {
  description = "Repository GitHub nel formato owner/repo"
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