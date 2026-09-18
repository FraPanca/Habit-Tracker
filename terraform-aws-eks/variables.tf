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

variable "node_instance_type" {
  description = "Tipo di istanza EC2 per i nodi worker EKS"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 2
}