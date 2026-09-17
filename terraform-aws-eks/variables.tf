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