# Phase 1 — Prerequisites & Toolchain Setup

This guide sets up the control machine (your Mac) to provision and configure VMs on a dedicated Proxmox host.

## Architecture

```
Mac (control machine)
  ├── Packer    ──► Proxmox API (build base templates)
  ├── Terraform ──► Proxmox API (clone & provision VMs)
  └── Ansible   ──► SSH / WinRM into VMs (configure lab scenarios)

Proxmox host: 192.168.0.245:8006
```

---

## 1. Install Toolchain (macOS)

### Homebrew (prerequisite)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Packer

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/packer
packer version
```

### Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

### Ansible

```bash
brew install ansible
ansible --version
```

### Install required Ansible collections

```bash
ansible-galaxy collection install ansible.windows community.windows
```

---

## 2. Create a Proxmox API Token

Packer and Terraform authenticate to Proxmox using an API token — no username/password in scripts.

1. Log into Proxmox web UI at `https://<proxmox-ip>:8006`
2. Go to **Datacenter → Permissions → API Tokens**
3. Click **Add**
   - User: `root@pam` (or create a dedicated user)
   - Token ID: `automation`
   - Uncheck **Privilege Separation** (simplest to start; tighten later)
4. Copy the token secret — it is shown **only once**

You'll end up with values like:
```
Token ID:     root@pam!automation
Token Secret: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

5. Grant the token sufficient permissions:
   - **Datacenter → Permissions → Add → API Token Permission**
   - Path: `/`
   - Token: `root@pam!automation`
   - Role: `Administrator` (or a custom role — see below)

> **Minimal role** (create under Datacenter → Roles) with permissions:
> `Datastore.AllocateSpace`, `Datastore.Audit`, `Pool.Audit`,
> `Sys.Audit`, `Sys.Modify`, `VM.Allocate`, `VM.Audit`,
> `VM.Clone`, `VM.Config.CDROM`, `VM.Config.CPU`,
> `VM.Config.Disk`, `VM.Config.HWType`, `VM.Config.Memory`,
> `VM.Config.Network`, `VM.Config.Options`, `VM.Monitor`,
> `VM.PowerMgmt`, `VM.Snapshot`

---

## 3. Store Credentials Locally

Create a `.env` file at the repo root (gitignored):

```bash
# .env — never commit this
export PROXMOX_URL="https://192.168.0.245:8006/api2/json"
export PROXMOX_TOKEN_ID="root@pam!automation"
export PROXMOX_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_NODE="pve"
```

Source it before running any tooling:

```bash
source .env
```

---

## 4. Verify API Access

```bash
source .env
curl -sk -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
  "${PROXMOX_URL}/version" | python3 -m json.tool
```

Expected output:

```json
{
    "data": {
        "version": "8.x.x",
        "release": "8.x",
        "repoid": "..."
    }
}
```

---

## 5. Verify SSH to Proxmox Host

Ansible and some Packer steps require SSH to the Proxmox host itself (for ISO uploads).

```bash
ssh root@192.168.0.245
```

If you haven't set up key-based auth:

```bash
ssh-keygen -t ed25519 -C "proving-ground" -f ~/.ssh/proving_ground
ssh-copy-id -i ~/.ssh/proving_ground.pub root@192.168.0.245
ssh -i ~/.ssh/proving_ground root@192.168.0.245 "pveversion"
```

---

## 6. Phase 1 Checklist

```
[ ] packer version        → Packer v1.x.x
[ ] terraform version     → Terraform v1.x.x
[ ] ansible --version     → ansible [core 2.x.x]
[ ] API token created in Proxmox web UI
[ ] .env populated with token credentials
[ ] curl verify command returns Proxmox version JSON
[ ] SSH key-based login to 192.168.0.245 works
```

Once all boxes are checked, proceed to [Phase 2 — Packer Base Images](./phase-2-packer.md).
