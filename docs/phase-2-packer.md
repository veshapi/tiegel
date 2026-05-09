# Phase 2 — Packer Base Images

Packer builds golden VM templates in Proxmox. These templates are cloned (never modified) by Terraform in later phases. You build them once and only rebuild when you want a fresher base.

## What Gets Built

| Template | VM ID | Purpose |
|----------|-------|---------|
| `windows-server-2022-base` | 9000 | Windows Server 2022 Std, WinRM enabled, sysprep'd |
| `debian-13-base` | 9001 | Debian 13 minimal, SSH + Python3, QEMU agent |

---

## Prerequisites

Complete [Phase 1](./phase-1-prerequisites.md) first. Then:

### 1. Download and upload ISOs to Proxmox

In the Proxmox web UI: **pve → local → ISO Images → Upload**

**Windows Server 2022 Evaluation:**
- Download from: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022
- Select: ISO, 64-bit, English — file will be named `SERVER_EVAL_x64FRE_en-us.iso`

**VirtIO Drivers (required for Windows):**
- Download latest stable ISO from: https://fedoraproject.org/wiki/Windows_Virtio_Drivers
  - Direct: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso

> Debian ISO is downloaded automatically by Packer — no manual upload needed.

### 2. Install the Proxmox Packer plugin

```bash
cd packer/windows && packer init .
cd packer/linux   && packer init .
```

### 3. Create var files from examples

```bash
cp packer/windows/win-server-2022.pkrvars.hcl.example packer/windows/win-server-2022.pkrvars.hcl
cp packer/linux/debian-base.pkrvars.hcl.example    packer/linux/debian-base.pkrvars.hcl
```

Edit both files with your actual Proxmox token credentials.

---

## Build the Windows Template

```bash
cd packer/windows

# Validate the config first
packer validate -var-file=win-server-2022.pkrvars.hcl .

# Build (takes ~30–45 min on first run)
packer build -var-file=win-server-2022.pkrvars.hcl .
```

**What happens:**
1. Packer creates a VM in Proxmox and boots the Windows Server ISO
2. `Autounattend.xml` is attached as a small CD — the installer reads it automatically
3. VirtIO drivers are loaded from the secondary ISO during setup
4. VirtIO serial driver loaded during setup — required for QEMU guest agent communication
5. On first logon, OpenSSH Server is installed and QEMU guest agent is started
6. Packer discovers the VM IP via the guest agent and connects over SSH (port 22)
7. `post-install.ps1` runs: registry hardening, writes sysprep answer file for clones
8. Sysprep generalizes the image (unique SID on each clone)
7. Proxmox converts the VM to a template (VM ID 9000)

**Watch the build in Proxmox:** Open the VM console in the web UI during the build to see the installer progress.

---

## Build the Debian Template

### 1. Download the ISO directly on Proxmox

Uploading via the API is unreliable for large files. Download directly on the host:

```bash
ssh -i ~/.ssh/proving_ground root@192.168.0.245 \
  "wget -O /var/lib/vz/template/iso/debian-13.4.0-amd64-netinst.iso \
  https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.4.0-amd64-netinst.iso"
```

### 2. Build

```bash
cd packer/linux

packer validate -var-file=debian-base.pkrvars.hcl .

# Build (takes ~10–15 min)
packer build -var-file=debian-base.pkrvars.hcl .
```

**What happens:**
1. Packer references the pre-existing ISO from Proxmox local storage
2. Packer starts an HTTP server and serves `http/preseed.cfg`
3. The boot command passes the preseed URL to the Debian installer
4. Minimal OS installs: SSH, Python3, qemu-guest-agent
5. Packer connects over SSH and runs `post-install.sh`
6. Template registered as VM ID 9001

> **Important:** Packer's HTTP server must be reachable from the VM during install.
> If your Proxmox VMs are on a different VLAN from your local machine, the preseed URL won't be
> accessible. In that case, convert the preseed to a CD file using `additional_iso_files`
> with `cd_files = ["./http/preseed.cfg"]` and adjust the boot command to use `file:///...`.

---

## Verify

After both builds, check Proxmox:

```
pve → Datacenter → pve → 9000 (windows-server-2022-base) → (Template icon)
pve → Datacenter → pve → 9001 (debian-13-base)           → (Template icon)
```

Both should show as templates (lock icon in the VM list).

You can also verify via the Proxmox API:

```bash
source .env
curl -sk -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
  "${PROXMOX_URL}/nodes/${PROXMOX_NODE}/qemu" | python3 -m json.tool | grep -E '"vmid"|"name"|"template"'
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| SSH timeout / `Waiting for SSH` | Guest agent not reporting IP | VirtIO serial driver must load during setup — check `Microsoft-Windows-PnpCustomizationsWinPE` DriverPaths in `Autounattend.xml` |
| VirtIO disk not detected | Wrong driver path in Autounattend.xml | Verify `vioserial\2k22\amd64` path exists on the VirtIO ISO |
| Preseed not fetched (Debian) | HTTP server unreachable from VM | Check firewall on the host running Packer; try `additional_iso_files` approach instead |
| `packer init` fails | No internet access | Proxy or download the plugin manually |
| Template already exists | Previous failed build left VM | Delete the VM manually in Proxmox, then rebuild |

---

## Customising the Images

- **Different Windows edition:** Change `<Value>2</Value>` in `Autounattend.xml` (1=Core, 2=Desktop Experience)
- **Different password:** Change `winrm_password` in pkrvars and the matching value in `Autounattend.xml`
- **Add baseline tools:** Edit `scripts/post-install.ps1` or `scripts/post-install.sh`
- **Different VM IDs:** Change `vm_id` in pkrvars — must not conflict with existing VMs

---

Once both templates exist in Proxmox, proceed to [Phase 3 — Terraform](./phase-3-terraform.md).
