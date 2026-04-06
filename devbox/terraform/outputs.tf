output "instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.devbox.name
}

output "external_ip" {
  description = "Current ephemeral external IP (only valid when running)"
  value       = google_compute_instance.devbox.network_interface[0].access_config[0].nat_ip
}
