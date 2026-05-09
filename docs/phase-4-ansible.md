# Phase 4 — Ansible Lab Configuration

Ansible connects to the VMs provisioned by Terraform and applies per-lab configuration. Reusable roles live in `ansible/roles/`; lab playbooks in `ansible/labs/<lab>/site.yml` compose them.

## Prerequisites

- Phase 3 complete — VMs running, `ansible/inventory/<lab>.ini` written by Terraform
- Ansible installed: `pip install ansible pywinrm`
- WinRM/SSH reachable from your Mac to the lab VMs

---

## Running a Lab

```bash
cd ansible

# Full run
ansible-playbook -i inventory/<lab>.ini labs/<lab>/site.yml

# Single role (for testing)
ansible-playbook -i inventory/<lab>.ini labs/<lab>/site.yml --tags <role>

# Dry run
ansible-playbook -i inventory/<lab>.ini labs/<lab>/site.yml --check
```

---

## Lab: ad-null-smb

Configures a Windows Server 2022 DC with:
- Active Directory domain `lab.local`
- Null SMB session access (anonymous enumeration enabled)
- Anonymous-readable `Public` SMB share containing a `credentials.txt` with the Administrator password
- `flag.txt` on the Administrator desktop (the lab objective)

### Pwn path

1. Anonymously enumerate SMB on the DC, find the `Public` share, and read `credentials.txt` to recover the Administrator password.
2. Authenticate over WinRM (or RDP) as `Administrator`, read `Desktop\flag.txt`.

### Run

```bash
ansible-playbook -i inventory/ad-null-smb.ini labs/ad-null-smb/site.yml
```

The playbook runs three roles in order:

| Role | What it does |
|------|-------------|
| `win_ad_dc` | Installs AD DS, promotes to DC for `lab.local`, reboots |
| `win_smb_null` | Sets `RestrictAnonymous=0`, enables null session pipes, creates anonymous `Public` share at `C:\Public` |
| `win_loot_file` | Drops `C:\Public\credentials.txt` (creds for stage 1) and `C:\Users\Administrator\Desktop\flag.txt` (objective for stage 2) |

### Verify the pwn path from your Mac

Stage 1 — anonymous SMB:

```bash
# Anonymous share enumeration: nxc should report `Public READ` for the empty user
nxc smb <dc-ip> -u '' -p '' --shares

# Read the creds file from the anonymous share
smbclient //<dc-ip>/Public -N -c 'get credentials.txt -'
```

Stage 2 — authenticated WinRM with the recovered creds:

```bash
# One-liner with nxc (already installed alongside the SMB tools above)
nxc winrm <dc-ip> -u Administrator -p '<password-from-stage-1>' \
    -X 'type C:\Users\Administrator\Desktop\flag.txt'

# Or interactive with evil-winrm:
#   evil-winrm -i <dc-ip> -u Administrator -p '<password-from-stage-1>'
#   PS> type C:\Users\Administrator\Desktop\flag.txt
```

End-to-end verified output (stage 2 should print something like `PG{null_smb_gives_you_wings}`).

---

## Roles Reference

### win_ad_dc

Installs `AD-Domain-Services` and promotes the host to a domain controller.

Variables (set in playbook `vars` or inventory):

| Variable | Default | Description |
|----------|---------|-------------|
| `ad_domain` | — | DNS domain name, e.g. `lab.local` |
| `ad_safe_mode_password` | — | DSRM password |

Reboots the VM after promotion and waits for ADWS to come up before continuing.

### win_smb_null

Applies registry keys, creates an anonymous-readable file share, and restarts the `LanmanServer` service:

- `LSA\RestrictAnonymous = 0` — allow anonymous SAM enumeration
- `LSA\RestrictNullSessAccess = 0` — disable null session restrictions
- `LSA\EveryoneIncludesAnonymous = 1` — anonymous users inherit `Everyone` ACLs
- `LanmanServer\NullSessionPipes` — exposes `netlogon`, `samr`, `lsarpc`, `srvsvc`
- `LanmanServer\NullSessionShares` — exposes `IPC$` and `Public`
- Creates `C:\Public`, grants NTFS `ReadAndExecute` to both `Everyone` and `ANONYMOUS LOGON` (inherited), and shares it as `Public` with share-level read for both principals
- Disables the SMB server signing requirement (`RequireSecuritySignature = 0`) and modifies the Default Domain Controllers Policy `GptTmpl.inf` so the change persists across `gpupdate`

`ANONYMOUS LOGON` is granted explicitly on both the share ACL and NTFS ACL rather than relying on `EveryoneIncludesAnonymous`. The signing requirement has to be disabled because null sessions cannot sign SMB messages (no session key), and a DC's default GPO requires signing — so tree connect to any non-`IPC$` share fails with `NT_STATUS_ACCESS_DENIED` regardless of share/NTFS ACLs. Flipping the registry alone gets reverted on the next `gpupdate`; the role bumps the GPO version in `GPT.INI` so DCs re-process the (now modified) Security Settings INF.

### win_loot_file

Writes two files:

- `C:\Public\credentials.txt` — domain name + Administrator password (readable anonymously via the `Public` share). Uses `ansible_password` from the inventory.
- `C:\Users\Administrator\Desktop\flag.txt` — the lab flag, retrieved after authenticating with the recovered creds.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `unreachable` on first task | VM still booting / OOBE not finished | Wait 2–3 min and retry; check Proxmox console |
| AD promotion fails with reboot loop | Insufficient RAM | Increase `memory_mb` in Terraform to at least 4096 |
| `win_feature` module not found | Missing `ansible.windows` collection | `ansible-galaxy collection install ansible.windows microsoft.ad` |
| SMB still requires auth after role | Server service needs full restart | Reboot the VM and retest |
| Null auth works but `tree connect failed: NT_STATUS_ACCESS_DENIED` on `Public` | DC requires SMB signing; null sessions can't sign, so tree connect to any non-`IPC$` share is denied regardless of ACLs. Default DC Policy enforces this and reverts plain registry edits | Re-run `win_smb_null` (it disables the signing requirement and persists it via the Default DC Policy `GptTmpl.inf`). After re-run, `nxc smb <dc-ip> -u '' -p '' --shares` should list `Public  READ`, and `smbclient //<dc-ip>/Public -N -c ls` should succeed. The role's final task also prints `Get-SmbServerConfiguration` showing `RequireSecuritySignature: False`. (Note: `nxc smb`'s `signing:True` banner is the *capability* flag and stays True even after the requirement is disabled — don't use it as your indicator) |
