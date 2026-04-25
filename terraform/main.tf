terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  backend "gcs" {
    bucket = "my-api-tfstate-494215"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = "terraform-practice-494215"
  region  = "asia-northeast1"
}

resource "google_storage_bucket" "tfstate" {
  name     = "my-api-tfstate-494215"
  location = "asia-northeast1"

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
}

resource "google_artifact_registry_repository" "my_api" {
  repository_id = "my-api"
  format        = "DOCKER"
  location      = "asia-northeast1"
}

resource "google_cloud_run_v2_service" "my_api" {
  name     = "my-api"
  location = "asia-northeast1"
  template {
    containers {
      image = "asia-northeast1-docker.pkg.dev/terraform-practice-494215/my-api/my-api:latest"
      ports {
        container_port = 8080
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.my_api.name
  location = "asia-northeast1"
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ─────────────────────────────
# Cloud SQL: パスワード生成 & Secret Manager 保管
# ─────────────────────────────
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "my-api-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

# ─────────────────────────────
# Cloud SQL: PostgreSQL インスタンス
# ─────────────────────────────
resource "google_sql_database_instance" "my_api" {
  name             = "my-api-db"
  database_version = "POSTGRES_15"
  region           = "asia-northeast1"

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_HDD"

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  deletion_protection = false
}

resource "google_sql_database" "todos" {
  name     = "todos"
  instance = google_sql_database_instance.my_api.name
}

resource "google_sql_user" "app" {
  name     = "app"
  instance = google_sql_database_instance.my_api.name
  password = random_password.db.result
}