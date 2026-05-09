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
