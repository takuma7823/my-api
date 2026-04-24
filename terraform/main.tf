terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
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
