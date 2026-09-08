# --- ID Container ---
output "container_mongodb_id" {
  description = "ID del container mongodb creato"
  value       = docker_container.mongodb.id
}

output "container_backend_id" {
  description = "ID del container backend creato"
  value       = docker_container.backend.id
}

output "container_frontend_id" {
  description = "ID del container frontend creato"
  value       = docker_container.frontend.id
}


# --- Nomi Container ---
output "container_mongodb_name" {
  description = "Nome del container mongodb creato"
  value       = docker_container.mongodb.name
}

output "container_backend_name" {
  description = "Nome del container backend creato"
  value       = docker_container.backend.name
}

output "container_frontend_name" {
  description = "Nome del container frontend creato"
  value       = docker_container.frontend.name
}


# --- Reti ---
output "network_backend_name" {
  description = "Nome della rete backend Docker creata"
  value       = docker_network.backend_network.name
}

output "network_frontend_name" {
  description = "Nome della rete frontend Docker creata"
  value       = docker_network.frontend_network.name
}


# --- Volume ---
output "volume_name" {
  description = "Nome del volume Docker creata"
  value       = docker_volume.mongo_volume.name
}

output "volume_path" {
  description = "Mountpoint del volume Docker creata"
  value       = docker_volume.mongo_volume.mountpoint
}


# --- URL di accesso ---
output "access_url" {
  description = "URL per raggiungere il servizio dall'host"
  value       = "http://localhost:${var.frontend_port}"
}