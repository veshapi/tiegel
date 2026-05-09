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

variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "admin_password" {
  type      = string
  sensitive = true
  default   = "Pr0vingGr0und!"
}
