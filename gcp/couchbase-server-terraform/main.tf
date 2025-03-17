terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
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
    network_interfaces = [ for i, n in var.networks : {
        network = n
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

resource "google_compute_instance_template" "couchbase-server" {
  name        = "couchbase-server-template-${random_string.random-suffix.result}"
  description = "Couchbase Server Template for Couchbase Server Instances"
  tags        = ["couchbase-server"]

  instance_description = "Couchbase Server Node"
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

  disk {
    device_name  = "cb-server-data"
    disk_size_gb = var.data_disk_size
    disk_type    = var.data_disk_type
    auto_delete  = false
    boot         = false
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
        network = network_interface.value.network
        subnetwork = network_interface.value.subnetwork
        access_config {
        }
    }
  }

  metadata = {
    couchbase-server-version      = var.server_version
    couchbase-server-make-cluster = true
    couchbase-server-services = join(",", compact([
      "${var.data_service ? "data" : ""}",
      "${var.query_service ? "query" : ""}",
      "${var.index_service ? "index" : ""}",
      "${var.eventing_service ? "eventing" : ""}",
      "${var.fts_service ? "fts" : ""}",
      "${var.analytics_service ? "analytics" : ""}",
      "${var.backup_service ? "backup" : ""}",
      ])
    )
    couchbase-server-disk      = "cb-server-data"
    couchbase-server-secret    = "couchbase-server-secret-${random_string.random-suffix.result}"
    couchbase-server-rally-url = var.existing_rally_url
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

  depends_on = [google_secret_manager_secret_version.couchbase-server-secret-version]
}

resource "google_secret_manager_secret" "couchbase-server-secret" {
  secret_id = "couchbase-server-secret-${random_string.random-suffix.result}"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "couchbase-server-secret-version" {
  secret      = google_secret_manager_secret.couchbase-server-secret.id
  secret_data = jsonencode({ username = "${var.server_username}", password = "${var.server_password}" })
}

resource "google_compute_instance_group_manager" "couchbase-server-cluster" {
  name               = "couchbase-server-cluster-${random_string.random-suffix.result}"
  base_instance_name = "couchbase-server-${random_string.random-suffix.result}"
  zone               = var.zone
  version {
    instance_template = google_compute_instance_template.couchbase-server.self_link
  }
  target_size = var.server_node_count

  named_port {
    name = "admin-ui"
    port = 8091
  }
}

resource "google_compute_firewall" "couchbase-server-firewall" {
  name    = "couchbase-server-firewall-${random_string.random-suffix.result}"
  network = element(var.networks, 0)
  allow {
    protocol = "tcp"
    ports = [22, 4369, "8091-8096", "9100-9105", "9110-9118", "9120-9124", 9130, 9140, 9999, 11207,
    "11209-11211", 11207, 21100, "11206-11207", "18091-18096", 19130, 21150]
  }

  source_ranges = compact([for range in split(",", var.access_cidr) : trimspace(range)])

  target_tags = ["couchbase-server"]
}

