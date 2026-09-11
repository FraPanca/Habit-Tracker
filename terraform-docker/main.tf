terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}


# --- Provider ---
provider "docker" {
  # Si connette al Docker daemon locale via socket di default: /var/run/docker.sock
}


# --- Variabili composte ---
locals {
  mongo_uri = "mongodb://${var.mongo_root_username}:${var.mongo_root_password}@${docker_container.mongodb.name}:27017/${var.mongo_root_database}?authSource=admin"
}


# --- Reti ---
resource "docker_network" "backend_network" {
  name   = "${var.backend}-network"
  driver = "bridge"
}

resource "docker_network" "frontend_network" {
  name   = "${var.frontend}-network"
  driver = "bridge"
}


# --- Volumi ---
resource "docker_volume" "mongo_volume" {
  name = "mongo-data"
}


# --- Immagini ---
resource "docker_image" "mongodb-image" {
  name         = "${var.mongo_image_name}:${var.mongodb_version}"
  keep_locally = true
}

resource "docker_image" "backend-image" {
  name         = "ghcr.io/${var.github_user}/${var.project_name}-backend:${var.github_image_tag_backend}"
  keep_locally = true
}

resource "docker_image" "frontend-image" {
  name         = "ghcr.io/${var.github_user}/${var.project_name}-frontend:${var.github_image_tag_frontend}"
  keep_locally = true
}


# --- Container applicativi ---
resource "docker_container" "mongodb" {
  name  = var.db_name
  image = docker_image.mongodb-image.image_id

  networks_advanced {
    name = docker_network.backend_network.name
  }

  volumes {
    volume_name    = docker_volume.mongo_volume.name
    container_path = "/data/db"
  }

  env = [
    "MONGO_INITDB_ROOT_USERNAME=${var.mongo_root_username}",
    "MONGO_INITDB_ROOT_PASSWORD=${var.mongo_root_password}",
    "MONGO_INITDB_DATABASE=${var.mongo_root_database}"
  ]

  restart = "unless-stopped"

  memory                = 512
  cpus                  = "1.0"
  destroy_grace_seconds = 10

  wait         = true
  wait_timeout = 70 # start_period (20s) + retries*interval (5*10s) + margine

  healthcheck {
    test         = ["CMD-SHELL", "mongosh --quiet -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval \"db.adminCommand('ping')\" || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "20s"
  }
}

resource "docker_container" "backend" {
  name  = var.backend
  image = docker_image.backend-image.image_id

  networks_advanced {
    name = docker_network.backend_network.name
  }

  networks_advanced {
    name = docker_network.frontend_network.name
  }

  env = [
    "PORT=${var.backend_port}",
    "MONGO_URI=${local.mongo_uri}"
  ]

  restart    = "unless-stopped"
  depends_on = [docker_container.mongodb]

  memory = 256
  cpus   = "0.5"

  wait         = true
  wait_timeout = 180 # start_period (10s) + retries*interval (5*30s) + margine

  healthcheck {
    test         = ["CMD-SHELL", "wget -qO- http://localhost:${var.backend_port}/api/health || exit 1"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 5
    start_period = "10s"
  }
}

resource "docker_container" "frontend" {
  name  = var.frontend
  image = docker_image.frontend-image.image_id

  networks_advanced {
    name = docker_network.frontend_network.name
  }

  ports {
    internal = 80
    external = var.frontend_port
  }

  restart    = "unless-stopped"
  depends_on = [docker_container.backend]

  memory = 128
  cpus   = "0.3"

  wait         = true
  wait_timeout = 180

  healthcheck {
    test         = ["CMD-SHELL", "wget -qO- http://127.0.0.1:80 || exit 1"]
    interval     = "30s"
    timeout      = "5s"
    retries      = 5
    start_period = "10s"
  }
}