packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ── Variables ────────────────────────────────────────────────────────────────

variable "proxmox_url" {
  type = string
}
variable "proxmox_token_id" {
  type = string
}
variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}
variable "proxmox_node" {
  type    = string
  default = "pve"
}
variable "proxmox_insecure" {
  type    = bool
  default = true
}

variable "debian_iso_file" {
  type    = string
  # Upload the ISO to Proxmox local storage first:
  # wget -O /var/lib/vz/template/iso/debian-13.4.0-amd64-netinst.iso \
  #   https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.4.0-amd64-netinst.iso
  default = "local:iso/debian-13.4.0-amd64-netinst.iso"
}

variable "vm_id" {
  type    = number
  default = 9001
}
variable "vm_name" {
  type    = string
  default = "debian-13-base"
}
variable "disk_size" {
  type    = string
  default = "20G"
}
variable "memory_mb" {
  type    = number
  default = 1024
}
variable "cpu_cores" {
  type    = number
  default = 1
}
variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}
variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "packer"
}

# ── Source ───────────────────────────────────────────────────────────────────

source "proxmox-iso" "debian" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_insecure

  vm_id   = var.vm_id
  vm_name = var.vm_name

  boot_iso {
    iso_file = var.debian_iso_file
    unmount  = true
  }

  # Preseed file served via Packer's built-in HTTP server
  http_directory = "./http"
  http_port_min  = 8100
  http_port_max  = 8200

  # Boot: interrupt grub and pass preseed URL
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "debian-installer=en_US.UTF-8 auto locale=en_US.UTF-8 kbd-chooser/method=us ",
    "keyboard-configuration/xkb-keymap=us netcfg/get_hostname=debian-base ",
    "netcfg/get_domain=local fb=false debconf/frontend=noninteractive ",
    "console-setup/ask_detect=false console-keymaps-at/keymap=us ",
    "<enter>"
  ]

  # Hardware
  cpu_type = "host"
  cores    = var.cpu_cores
  memory   = var.memory_mb
  os       = "l26"

  disks {
    disk_size    = var.disk_size
    format       = "raw"
    storage_pool = var.storage
    type         = "virtio"
  }

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "30m"
  ssh_handshake_attempts = 20

  template_name        = var.vm_name
  template_description = "Debian 12 base template — built by Packer"
}

# ── Build ────────────────────────────────────────────────────────────────────

build {
  sources = ["source.proxmox-iso.debian"]

  provisioner "shell" {
    scripts = ["./scripts/post-install.sh"]
  }
}
