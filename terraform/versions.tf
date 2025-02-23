terraform {
  required_version = ">= 0.13.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.45.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
  }
}
