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
  description = "Numero di nodi worker desiderati (2 necessari: 1 solo t3.small non regge app + ingress + metrics-server + EBS CSI + ArgoCD)"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Numero minimo di nodi worker"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Numero massimo di nodi worker"
  type        = number
  default     = 2
}