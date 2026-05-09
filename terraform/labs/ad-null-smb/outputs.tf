output "dc_ip" {
  description = "Domain controller IP — use this to connect or check Ansible inventory"
  value       = module.dc.ipv4_address
}
