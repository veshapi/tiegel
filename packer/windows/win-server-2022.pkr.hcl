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

variable "windows_iso_file" {
  type    = string
  default = "local:iso/SERVER_EVAL_x64FRE_en-us.iso"
}
variable "virtio_iso_file" {
  type    = string
  default = "local:iso/virtio-win.iso"
}

variable "vm_id" {
  type    = number
  default = 9000
}
variable "vm_name" {
  type    = string
  default = "windows-server-2022-base"
}
variable "disk_size" {
  type    = string
  default = "60G"
}
variable "memory_mb" {
  type    = number
  default = 4096
}
variable "cpu_cores" {
  type    = number
  default = 2
}
variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "ssh_username" {
  type    = string
  default = "Administrator"
}
variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "Pr0vingGr0und!"
}

# ── Source ───────────────────────────────────────────────────────────────────

source "proxmox-iso" "windows" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  node                     = var.proxmox_node
  insecure_skip_tls_verify = var.proxmox_insecure

  vm_id   = var.vm_id
  vm_name = var.vm_name

  # Primary boot ISO (Windows Server)
  boot_iso {
    iso_file = var.windows_iso_file
    unmount  = true
  }

  # VirtIO drivers ISO
  additional_iso_files {
    type     = "sata"
    index    = 1
    iso_file = var.virtio_iso_file
    unmount  = true
  }

  # Autounattend.xml + helper scripts — packaged into a small ISO by Packer
  additional_iso_files {
    type             = "sata"
    index            = 2
    cd_files         = ["./answer-files/Autounattend.xml", "./answer-files/diskpart.txt", "./answer-files/install-guest-agent.bat"]
    cd_label         = "SETUP"
    iso_storage_pool = "local"
    unmount          = true
  }

  # Hardware
  cpu_type = "host"
  cores    = var.cpu_cores
  memory   = var.memory_mb

  os = "win11"

  # sata disk uses the Intel AHCI controller (8086:2922) which WinPE supports
  # natively. LSI SCSI (1000:0012) was dropped from WinPE in Server 2022.
  disks {
    disk_size    = var.disk_size
    format       = "raw"
    storage_pool = var.storage
    type         = "sata"
  }

  # e1000 has native Windows drivers — no VirtIO NIC driver needed during build.
  network_adapters {
    bridge = "vmbr0"
    model  = "e1000"
  }

  # BIOS boot — avoids EFI disk shifting disk IDs during WinPE setup.
  # Adequate for a lab template; clones inherit this setting.

  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "60m"

  template_name        = var.vm_name
  template_description = "Windows Server 2022 base template — built by Packer"
}

# ── Build ────────────────────────────────────────────────────────────────────

build {
  sources = ["source.proxmox-iso.windows"]

  provisioner "powershell" {
    scripts = ["./scripts/post-install.ps1"]
  }

  # Generalize with sysprep so clones get unique SIDs
  provisioner "powershell" {
    inline = [
      "Write-Host 'Running sysprep...'",
      "& $env:SystemRoot\\System32\\Sysprep\\sysprep.exe /generalize /oobe /shutdown /quiet"
    ]
  }
}
