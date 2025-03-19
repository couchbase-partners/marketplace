variable "project_id" {
    type = string
}
#Required for Marketplace Deployments
#tflint-ignore: terraform_unused_declarations
variable "goog_cm_deployment_name" {
  type    = string
  default = "ja-test-value"
}

variable "region" {
  type    = string
  default = "us-central1"

}

variable "zone" {
  type    = string
  default = "us-central1-c"
}

variable "networks" {
  description = "The network name to attach the VM instance."
  type        = list(string)
  default     = ["default"]
}

variable "sub_networks" {
  description = "The sub network name to attach the VM instance."
  type        = list(string)
  default     = []
}

variable "server_node_count" {
  default     = 3
  type        = number
  description = "The number of Couchbase Server nodes to deploy"
  validation {
    condition     = var.server_node_count > 1 && var.server_node_count < 100
    error_message = "The number of nodes cannot be less than 1 or greater than 100"
  }
}

variable "machine_type" {
  type    = string
  default = "n1-standard-4"
}

variable "boot_disk_type" {
  type    = string
  default = "pd-ssd"
}

variable "boot_disk_size" {
  type    = string
  default = "20"
}

variable "data_disk_type" {
  type    = string
  default = "pd-ssd"
}

variable "data_disk_size" {
  type    = number
  default = 100
  validation {
    condition     = var.data_disk_size <= 100
    error_message = "Disk sizes under 100gb are not recommended."
  }
}

variable "server_version" {
  type    = string
  default = "7.6.5"
  validation {
    condition = contains([
      "7.6.5",
      "7.6.4",
      "7.6.3",
      "7.6.2",
      "7.6.1",
      "7.6.0",
      "7.2.5",
      "7.2.4",
      "7.2.3",
      "7.2.2",
      "7.2.1",
      "7.2.0",
      "7.1.4",
      "7.1.3",
      "7.1.2",
      "7.1.1",
      "7.1.0",
      "7.0.5",
      "7.0.4",
      "7.0.3",
    "7.0.2", ], var.server_version)
    error_message = "Valid values for server version are: 7.0.5, 7.1.4, 7.2.5, 7.6.5"
  }
}

variable "server_username" {
  type    = string
  default = "couchbase"
}

variable "server_password" {
  type      = string
  sensitive = true
}

variable "source_image" {
  type    = string
  default = "projects/couchbase-public/global/images/couchbase-server-byol-v20250316"
}

variable "existing_rally_url" {
  type     = string
  nullable = true
}


variable "data_service" {
  type    = bool
  default = true
}

variable "index_service" {
  type    = bool
  default = true
}

variable "query_service" {
  type    = bool
  default = true
}

variable "eventing_service" {
  type    = bool
  default = false
}

variable "fts_service" {
  type    = bool
  default = false
}

variable "analytics_service" {
  type    = bool
  default = false
}

variable "backup_service" {
  type    = bool
  default = false
}

variable "svc_account" {
  type    = string
  default = "couchbase-sa"
}

variable "access_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
