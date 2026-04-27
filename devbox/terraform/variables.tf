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
  description = "SSH public keys for VM access — one entry per machine (contents of ~/.ssh/zaeem.pub)"
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

variable "static_ip" {
  description = "Reserve a static external IP address for the VM. When false, an ephemeral IP is assigned (changes on every reset)."
  type        = bool
  default     = false
}

variable "firewall_allow_ports" {
  description = "Additional TCP ports to open on the VM firewall beyond SSH (22). Source range is 0.0.0.0/0. E.g. [\"3000\", \"8080\", \"443\"]"
  type        = list(string)
  default     = []
}

variable "enable_display" {
  description = "Expose a VirtIO GPU virtual display device to the VM. Required for GUI/desktop sessions (rigging gui). Applies on next stop/start — no VM recreation needed."
  type        = bool
  default     = false
}

