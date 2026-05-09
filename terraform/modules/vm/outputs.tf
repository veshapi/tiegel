output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_address" {
  description = "First non-loopback IPv4 reported by the QEMU guest agent"
  value = try(
    flatten([
      for idx, name in proxmox_virtual_environment_vm.this.network_interface_names :
      proxmox_virtual_environment_vm.this.ipv4_addresses[idx]
      if name != "lo" && length(proxmox_virtual_environment_vm.this.ipv4_addresses[idx]) > 0
    ])[0],
    null
  )
}
