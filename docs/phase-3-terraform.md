# Phase 3 — Terraform Lab Provisioning

Terraform clones the templates built in Phase 2 and turns them into running lab VMs. Each lab lives under `terraform/labs/<lab>/` as an isolated workspace with its own state, variables, and outputs.

This phase walks through **building the `ad-null-smb` lab from scratch** — every file you need to write, what each block does, and why. Once you've done it once, adding new labs is just copy-and-modify.

## What you'll end up with

| Resource | Why |
|----------|-----|
| `terraform/labs/ad-null-smb/` | Lab workspace with its own state file |
| `ad-dc01` (VM ID 100) on Proxmox | The future domain controller, cloned from template `9000` |
| `ansible/inventory/ad-null-smb.ini` | Inventory file pointing Ansible at `ad-dc01`'s discovered IP, written automatically by Terraform on every `apply` |

---

## Prerequisites

- Phase 2 complete — templates `9000` (Windows Server 2022) and `9001` (Debian 13) registered in Proxmox
- Terraform installed (`brew install hashicorp/tap/terraform` or via tfenv)
- Proxmox API token with `VM.Clone`, `VM.Allocate`, `VM.Config.*`, `VM.PowerMgmt`, `Datastore.AllocateSpace` (same token Phase 2 uses)
- `.env` populated and sourced

---

## The shared VM module

Before writing the lab, look at `terraform/modules/vm/`. It's a thin wrapper around `proxmox_virtual_environment_vm` that every lab calls — saves repeating clone/cpu/memory/disk/network blocks per VM.

[terraform/modules/vm/main.tf](../terraform/modules/vm/main.tf) takes these inputs (defaults shown):

| Variable | Default | Notes |
|----------|---------|-------|
| `name` | — | VM display name in Proxmox |
| `vm_id` | — | Proxmox VM ID (use 100–899 for lab VMs; 9000+ are reserved for templates) |
| `template_id` | — | Template to clone — `9000` for Windows, `9001` for Debian |
| `node_name` | `pve` | Proxmox node |
| `cores` | `2` | |
| `memory_mb` | `2048` | Override for AD DCs (need ≥ 4096 to promote cleanly) |
| `disk_size` | `60` | GB |
| `storage` | `local-lvm` | |
| `os_type` | `win11` | bpg/proxmox uses `win11` for Server 2022; use `l26` for Linux |

The module exposes one important output, `ipv4_address` — the first non-loopback IPv4 reported by the QEMU guest agent. This is how the lab gets the DC's IP without hardcoding it.

> **Why agent gets re-enabled in the module:** The Packer build disables the QEMU agent flag (Packer uses an SSH-based IP discovery instead). The `agent { enabled = true }` block in `modules/vm/main.tf` flips it back on at clone time so Terraform's IP discovery works. The agent binary is already baked into the template — only the Proxmox-side flag needs flipping.

---

## Build `ad-null-smb` from scratch

### 1. Create the lab directory

```bash
mkdir -p terraform/labs/ad-null-smb
cd terraform/labs/ad-null-smb
```

### 2. `main.tf` — provider, VM clone, inventory rendering

This is the lab's entry point. Three things happen here:

1. Declare the providers we need (`bpg/proxmox` for Proxmox, `hashicorp/local` for writing the inventory file).
2. Configure the Proxmox provider with token credentials (passed in via variables, never hardcoded).
3. Call `modules/vm` to clone template `9000` into a VM named `ad-dc01`, then render the Ansible inventory once we know the VM's IP.

```hcl
# terraform/labs/ad-null-smb/main.tf
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
  template_id = 9000          # windows-server-2022-base
  node_name   = var.proxmox_node

  cores     = 2
  memory_mb = 4096            # AD promotion needs ≥ 4 GB
  disk_size = 60
  storage   = var.storage
  os_type   = "win11"         # Proxmox treats Server 2022 as win11
}

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    dc_ip          = module.dc.ipv4_address
    admin_password = var.admin_password
  })
  filename        = "${path.root}/../../../ansible/inventory/ad-null-smb.ini"
  file_permission = "0600"
}
```

Things worth knowing:

- `module.dc.ipv4_address` is `null` until the QEMU agent inside the VM boots and reports an IP. Terraform waits for the agent automatically — you don't need a separate "wait" resource.
- The inventory file is written to a relative path **outside** this lab dir (`../../../ansible/inventory/`). That's intentional — it lives where Ansible expects it in Phase 4. `file_permission = "0600"` keeps the password from being world-readable.
- Don't put credentials in `main.tf`. Everything secret comes through variables → `terraform.tfvars` (which is gitignored).

### 3. `variables.tf` — input declarations

Tells Terraform which inputs the lab accepts. `sensitive = true` on the password fields keeps them out of `terraform plan` / `apply` output.

```hcl
# terraform/labs/ad-null-smb/variables.tf
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
  default = true              # Proxmox uses self-signed TLS by default
}

variable "storage" {
  type    = string
  default = "local-lvm"
}

variable "admin_password" {
  type      = string
  sensitive = true
  default   = "Pr0vingGr0und!"  # baked into the Packer template; change in both places if you change it
}
```

> **Why `admin_password` has a default**: it must match the password set by `Autounattend.xml` in the Packer build. If you change one without the other, Ansible can't WinRM/SSH into the VM.

### 4. `outputs.tf` — surface the DC IP

Lets `terraform output dc_ip` print the discovered IP. Useful for sanity-checking and for any external automation that needs to know where the DC ended up.

```hcl
# terraform/labs/ad-null-smb/outputs.tf
output "dc_ip" {
  description = "Domain controller IP — use this to connect or check Ansible inventory"
  value       = module.dc.ipv4_address
}
```

### 5. `inventory.tpl` — Ansible inventory template

Terraform's `templatefile()` substitutes `${dc_ip}` and `${admin_password}` and writes the result to `ansible/inventory/ad-null-smb.ini`.

```ini
# terraform/labs/ad-null-smb/inventory.tpl
[dc]
ad-dc01 ansible_host=${dc_ip}

[windows:children]
dc

[windows:vars]
ansible_user=Administrator
ansible_password=${admin_password}
ansible_connection=ssh
ansible_shell_type=powershell
ansible_ssh_common_args=-o StrictHostKeyChecking=no
```

> **Why `ansible_connection=ssh` for Windows**: the Phase 2 Packer build installs OpenSSH Server on the Windows template and sets PowerShell as the default shell. Ansible connects over SSH (port 22) instead of WinRM — simpler auth, same capabilities. `StrictHostKeyChecking=no` skips the host-key prompt; the IP is throwaway lab IP space anyway.

### 6. `terraform.tfvars.example` — credential template

A non-sensitive template that gets copied to `terraform.tfvars` (gitignored) and filled in.

```hcl
# terraform/labs/ad-null-smb/terraform.tfvars.example
proxmox_url          = "https://192.168.0.245:8006/api2/json"
proxmox_token_id     = "root@pam!automation"
proxmox_token_secret = "your-token-secret-here"
proxmox_node         = "pve"
proxmox_insecure     = true
storage              = "local-lvm"
```

The repo's `.gitignore` is set so that `*.tfvars` is ignored but `*.tfvars.example` is not — the example tracks the schema, the real file holds your secrets.

---

## Initialise and apply

```bash
cd terraform/labs/ad-null-smb

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — paste in your real Proxmox token secret.

terraform init    # downloads bpg/proxmox + hashicorp/local providers
terraform apply   # type "yes" when prompted, or pass -auto-approve
```

Expected output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

dc_ip = "192.168.0.x"
```

The two resources are the VM (`module.dc.proxmox_virtual_environment_vm.this`) and the inventory file (`local_file.ansible_inventory`).

If `dc_ip` shows as `null`, the QEMU agent never reported an IP — see Troubleshooting.

## Verify

```bash
# 1. Inventory was written and looks right
cat ../../../ansible/inventory/ad-null-smb.ini

# 2. The VM is reachable on SSH (Windows OpenSSH, set up by Packer)
ssh -o StrictHostKeyChecking=no Administrator@$(terraform output -raw dc_ip)
# Type "exit" once you've confirmed login works. Default password: Pr0vingGr0und!
```

If both work, you're ready for Phase 4.

## Tear down

```bash
terraform destroy
```

This stops and deletes the lab VM. The Phase 2 templates (`9000`, `9001`) and the lab files you wrote are untouched. To re-run, just `terraform apply` again — you'll get a fresh VM, fresh IP, fresh inventory.

---

## Adding more VMs to the same lab

Multi-VM labs (e.g. DC + workstation, attacker + victim) just call `modules/vm` again with a different `name` / `vm_id` and add the new host to `inventory.tpl`. Example skeleton for a workstation joined to the same lab:

```hcl
module "ws" {
  source      = "../../modules/vm"
  name        = "ws01"
  vm_id       = 101
  template_id = 9000
  node_name   = var.proxmox_node
  cores       = 2
  memory_mb   = 2048
  disk_size   = 40
  storage     = var.storage
  os_type     = "win11"
}
```

Then extend `inventory.tpl` with a `[workstations]` group, and pass the new VM's IP via `templatefile()`. The shared module handles the rest.

---

## Adding a new lab

To author a brand-new lab `my-lab`:

```bash
cp -r terraform/labs/ad-null-smb terraform/labs/my-lab
cd terraform/labs/my-lab
rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
```

Then in `main.tf`:
- Change `vm_id` (must be globally unique on the Proxmox node)
- Change `template_id` if you need Linux (`9001`) or different sizing
- Update the inventory output filename: `ansible/inventory/my-lab.ini`

In `inventory.tpl`, adjust group names if your lab isn't a single Windows DC. Then proceed to Phase 4 with the new lab name.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `provider registry does not have a provider named hashicorp/proxmox` | Missing `required_providers` block, or wrong source | Use `bpg/proxmox` (not the older `Telmate/proxmox`); verify both `terraform/labs/<lab>/main.tf` and `terraform/modules/vm/versions.tf` declare it |
| `dc_ip = null` after apply | QEMU guest agent isn't reporting an IP | Clone is probably stuck at OOBE wizard — Packer template needs the sysprep answer file. Rebuild the template; verify `C:\Windows\System32\Sysprep\unattend.xml` exists in the Packer image |
| Clone stuck at OOBE wizard | Sysprep answer file missing from template | Rebuild the Packer template — `post-install.ps1` writes `unattend.xml` before sysprep |
| `Error: 500 Internal Server Error` on clone | Token lacks permissions | Grant token `VM.Clone`, `VM.Allocate` on the Proxmox node (Phase 1 §2) |
| `local_file` writes to wrong path | Running `terraform apply` from somewhere other than the lab dir | Always `cd terraform/labs/<lab>` first — the inventory path is relative to `path.root`, which is the working directory at apply time |
| `vm_id 100 already exists` | Stale VM from a previous run | `terraform destroy` from this lab dir, or delete VM 100 manually in Proxmox |

---

Once `dc_ip` is populated and the inventory file exists, proceed to [Phase 4 — Ansible](./phase-4-ansible.md).
