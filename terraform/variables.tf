variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone. If empty, a zone is selected automatically from the available zones in the region."
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name of the Compute Engine VM instance"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type (e.g. e2-standard-2, e2-standard-4)"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "ssh_public_keys" {
  description = "SSH public keys for VM access — one entry per machine (contents of ~/.ssh/zaeem_devbox.pub)"
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "At least one SSH public key is required."
  }
}

variable "idle_timer_enabled" {
  description = "Whether to install the idle shutdown timer (powers off VM after 20min idle)"
  type        = bool
  default     = true
}

variable "profile_name" {
  description = "Profile name — used in instance metadata and Terraform state path"
  type        = string
}

variable "repos" {
  description = "Git repo URLs to clone into ~/workspace on first login"
  type        = list(string)
  default     = []
}

variable "secrets" {
  description = "GCP Secret Manager secret names to fetch on bootstrap (also used as env var names)"
  type        = list(string)
  default     = []
}
