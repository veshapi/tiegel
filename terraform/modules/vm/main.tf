resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.template_id
    full  = true
  }

  # Agent was disabled during Packer build (IP discovery bypass).
  # Re-enable here — the agent binary is already in the image.
  agent { enabled = true }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory { dedicated = var.memory_mb }

  network_device {
    bridge = "vmbr0"
    model  = "e1000"
  }

  disk {
    datastore_id = var.storage
    interface    = "sata0"
    size         = var.disk_size
  }

  operating_system { type = var.os_type }
}
