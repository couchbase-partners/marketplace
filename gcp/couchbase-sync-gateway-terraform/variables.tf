variable "project_id" {
  type=string
}
#Required for Marketplace Deployments
#tflint-ignore: terraform_unused_declarations
variable "goog_cm_deployment_name" {
  type    = string
  default = "ja-test-value"
}

variable "region" {
  default = "us-central1"
  type = string
}

variable "zone" {
  default = "us-central1-c"
  type = string
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

variable "gateway_node_count" {
  default     = 3
  type        = number
  description = "The number of Couchbase Sync Gateway nodes to deploy"
  validation {
    condition     = var.gateway_node_count >= 1 && var.gateway_node_count <= 100
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

variable "gateway_version" {
  type    = string
  default = "3.2.3"
  validation {
    condition = contains([
      "3.2.3",
      "3.2.2",
      "3.2.1",
      "3.2.0",
      "3.1.11",
      "3.0.8",
      "2.8.3"
    ], var.gateway_version)
    error_message = "Valid values for sync gateway version are: 3.2.3, 3.1.11, and 3.0.8"
  }
}

variable "server_username" {
  type = string
}

variable "server_password" {
  type      = string
  sensitive = true
}

variable "source_image" {
  type    = string
  default = "projects/couchbase-public/global/images/couchbase-sync-gateway-hourly-pricing-v20250318"
}

variable "connection_string" {
  type = string
}

variable "svc_account" {
  type    = string
  default = "couchbase-sa"
}

variable "access_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "bucket" {
  type = string
}
