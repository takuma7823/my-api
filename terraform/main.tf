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
  project = var.project_id
  region  = var.region
}

resource "google_storage_bucket" "tfstate" {
  name     = "my-api-tfstate-494215"
  location = var.region

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
}

resource "google_artifact_registry_repository" "my_api" {
  repository_id = "my-api"
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "my_api" {
  name     = "my-api"
  location = var.region

  template {
    service_account = google_service_account.cloud_run.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/my-api/my-api:latest"
      ports {
        container_port = 8080
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "BQ_PROJECT_ID"
        value = var.project_id
      }
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.my_api.connection_name]
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_iam_member.cloud_run_database_url,
    google_project_iam_member.cloud_run_sql_client,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.my_api.name
  location = var.region
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
  region           = var.region

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

# ─────────────────────────────
# Cloud Run のサービスアカウント
# ─────────────────────────────
resource "google_service_account" "cloud_run" {
  account_id   = "my-api-cloud-run"
  display_name = "Service Account for Cloud Run my-api"
}

# Cloud SQL に接続する権限
resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ─────────────────────────────
# DATABASE_URL を組み立てて Secret Manager に保管
# ─────────────────────────────
locals {
  database_url = "postgresql+psycopg://app:${urlencode(random_password.db.result)}@/todos?host=/cloudsql/${google_sql_database_instance.my_api.connection_name}"
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = "my-api-database-url"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = local.database_url
}

# Cloud Run の SA にこの Secret への読み取り権限を付与
resource "google_secret_manager_secret_iam_member" "cloud_run_database_url" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_bigquery_dataset" "analytics" {
  dataset_id  = "analytics"
  location    = var.region
  description = "Analytics dataset for my-api events"

  # 学習用なのでデータセット削除時にテーブルごと消せるように
  delete_contents_on_destroy = true
}

resource "google_bigquery_table" "todo_events" {
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  table_id   = "todo_events"

  deletion_protection = false  # 学習用。本番では true

  time_partitioning {
    type  = "DAY"
    field = "event_time"
  }

  schema = jsonencode([
    {
      name = "event_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique event identifier (UUID)"
    },
    {
      name = "todo_id"
      type = "INT64"
      mode = "REQUIRED"
      description = "Reference to Cloud SQL todos.id"
    },
    {
      name = "action"
      type = "STRING"
      mode = "REQUIRED"
      description = "created or deleted"
    },
    {
      name = "title"
      type = "STRING"
      mode = "NULLABLE"
      description = "Todo title at event time"
    },
    {
      name = "event_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Event occurrence time"
    },
  ])
}

resource "google_project_iam_member" "cloud_run_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}