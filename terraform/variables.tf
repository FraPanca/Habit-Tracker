# --- General ---
variable "project_name" {
  description = "Nome del progetto, usato come prefisso per le risorse"
  type        = string
  default     = "habit-tracker"
}

variable "github_user" {
  description = "Username account GitHub che fornisce le image Docker"
  type        = string
  default     = "frapanca"
}


# --- Backend ---
variable "backend" {
  description = "Nome del backend, usato come prefisso per le risorse"
  type        = string
  default     = "backend"
}

variable "github_image_tag_backend" {
  description = "Tag dell'immagine backend da usare"
  type        = string
  default     = "v0.1.1"
}

variable "backend_port" {
  description = "Porta esposta dal backend"
  type        = string
  default     = "5000"
}


# --- Frontend ---
variable "frontend" {
  description = "Nome del frontend, usato come prefisso per le risorse"
  type        = string
  default     = "frontend"
}

variable "github_image_tag_frontend" {
  description = "Tag dell'immagine frontend da usare"
  type        = string
  default     = "v0.1.1"
}

variable "frontend_port" {
  description = "Porta esposta sull'host, mappata sulla porta 80 del container"
  type        = number
  default     = 8080

  validation {
    condition     = var.frontend_port > 1024 && var.frontend_port < 65535
    error_message = "La porta host deve essere compresa tra 1025 e 65534."
  }
}


# --- DataBase ---
variable "db_name" {
  description = "Nome del DB da usare"
  type        = string
  default     = "mongodb"
}

variable "mongo_image_name" {
  description = "Nome del DB da usare"
  type        = string
  default     = "mongo"
}

variable "mongodb_version" {
  description = "Tag dell'immagine MongoDB da usare"
  type        = string
  default     = "7"
}


variable "mongo_root_username" {
  description = "Utente MongoDB"
  type        = string
  default     = "admin"
}

variable "mongo_root_password" {
  description = "Utente MongoDB"
  type        = string
  default     = "CHANGE_ME"
  sensitive   = true
}

variable "mongo_root_database" {
  description = "Nome DB MongoDB"
  type        = string
  default     = "habittracker"
}