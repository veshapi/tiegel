terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.46.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = var.proxmox_insecure
}

module "dc" {
  source = "../../modules/vm"

  name        = "ad-dc01"
  vm_id       = 100
  template_id = 9000
  node_name   = var.proxmox_node

  cores     = 2
  memory_mb = 4096
  disk_size = 60
  storage   = var.storage
  os_type   = "win11"
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    dc_ip          = module.dc.ipv4_address
    admin_password = var.admin_password
  })
  filename        = "${path.root}/../../../ansible/inventory/ad-null-smb.ini"
  file_permission = "0600"
}
