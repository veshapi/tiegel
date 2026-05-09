variable "name" {
  type        = string
  description = "VM name in Proxmox"
}

variable "vm_id" {
  type        = number
  description = "Proxmox VM ID (100–899 range for lab VMs)"
}

variable "template_id" {
  type        = number
  description = "VM ID of the Proxmox template to clone"
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type        = number
  description = "Disk size in GB"
  default     = 60
}

variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "os_type" {
  type    = string
  default = "win11"
}
