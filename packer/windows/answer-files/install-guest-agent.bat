@echo off
for %%d in (C D E F G H I J K) do (
    if exist "%%d:\guest-agent\qemu-ga-x86_64.msi" (
        msiexec /i "%%d:\guest-agent\qemu-ga-x86_64.msi" /quiet /norestart
        net start QEMU-GA
        exit /b 0
    )
)
