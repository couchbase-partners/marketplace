terraform {
  required_version = ">= 1.2"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "random_string" "random-suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  network_interfaces = [for i, n in var.networks : {
    network    = n
    subnetwork = length(var.sub_networks) > i ? element(var.sub_networks, i) : null
  }]
}

resource "google_project_iam_member" "member-role" {
  for_each = toset([
    "roles/secretmanager.secretAccessor",
    "roles/editor"
  ])
  role    = each.key
  member  = "serviceAccount:${google_service_account.couchbase-service-account.email}"
  project = var.project_id
}

resource "google_service_account" "couchbase-service-account" {
  account_id   = "${var.svc_account}-${random_string.random-suffix.result}"
  display_name = "Couchbase Server Service Account"
}

resource "google_compute_instance_template" "couchbase-sync-gateway" {
  name        = "couchbase-sync-gateway-template-${random_string.random-suffix.result}"
  description = "Couchbase Sync Gateway Template for Couchbase Sync Gateway Instances"
  tags        = ["couchbase-gateway"]

  instance_description = "Couchbase Sync Gateway Node"
  machine_type         = var.machine_type
  can_ip_forward       = false
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  disk {
    disk_size_gb = var.boot_disk_size
    source_image = var.source_image
    disk_type    = var.boot_disk_type
    device_name  = "boot-disk"
    auto_delete  = true
    boot         = true
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network    = network_interface.value.network
      subnetwork = network_interface.value.subnetwork
      access_config {
      }
    }
  }

  metadata = {
    couchbase-gateway-version           = var.gateway_version
    couchbase-gateway-secret            = "couchbase-gateway-secret-${random_string.random-suffix.result}"
    couchbase-gateway-connection-string = var.connection_string
    couchbase-gateway-bucket            = var.bucket
  }

  service_account {
    email = google_service_account.couchbase-service-account.email
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/cloud.useraccounts.readonly",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/cloudruntimeconfig"
    ]
  }

  depends_on = [google_secret_manager_secret_version.couchbase-gateway-secret-version]
}

resource "google_secret_manager_secret" "couchbase-gateway-secret" {
  secret_id = "couchbase-gateway-secret-${random_string.random-suffix.result}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "couchbase-gateway-secret-version" {
  secret      = google_secret_manager_secret.couchbase-gateway-secret.id
  secret_data = jsonencode({ username = var.server_username, password = var.server_password })
}

resource "google_compute_instance_group_manager" "couchbase-gateway-cluster" {
  name               = "couchbase-gateway-cluster-${random_string.random-suffix.result}"
  base_instance_name = "couchbase-gateway-${random_string.random-suffix.result}"
  zone               = var.zone
  version {
    instance_template = google_compute_instance_template.couchbase-sync-gateway.self_link
  }
  target_size = var.gateway_node_count

  named_port {
    name = "admin-ui"
    port = 8091
  }
}

resource "google_compute_firewall" "couchbase-server-firewall" {
  name    = "couchbase-gateway-firewall-${random_string.random-suffix.result}"
  network = element(var.networks, 0)
  allow {
    protocol = "tcp"
    ports    = [4984, 4985, 4986]
  }

  source_ranges = compact([for range in split(",", var.access_cidr) : trimspace(range)])

  target_tags = ["couchbase-gateway"]
}

