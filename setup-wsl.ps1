Write-Host "Starting Podman."
podman machine start

Write-Host "Unregistering old WSL distro if it exists."
wsl --unregister tmatwood-ubuntu-26.04

Write-Host "Cleaning up old installation directory."
Remove-Item -Path "c:/temp/tmatwood-ubuntu-26.04" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Creating fresh directory."
New-Item -ItemType Directory -Force -Path c:/temp/tmatwood-ubuntu-26.04

Write-Host "Removing old container if present."
podman rm -f tmatwood-ubuntu-26.04 2>$null
podman run -it -d --name tmatwood-ubuntu-26.04 localhost/tmatwood/ubuntu-26.04:latest
podman export --output=c:/temp/tmatwood-ubuntu-26.04/tmatwood-ubuntu-26.04.tar tmatwood-ubuntu-26.04
podman stop tmatwood-ubuntu-26.04
wsl.exe --import tmatwood-ubuntu-26.04 "c:/temp/tmatwood-ubuntu-26.04/" "c:/temp/tmatwood-ubuntu-26.04/tmatwood-ubuntu-26.04.tar" --version 2
wsl --set-default tmatwood-ubuntu-26.04
# Backup wsl.conf
wsl -d tmatwood-ubuntu-26.04 --cd / sudo cp /etc/wsl.conf /etc/wsl.conf.bak

# Restart systemd services (use -d to specify distro name)
wsl -d tmatwood-ubuntu-26.04 --cd / sudo systemctl daemon-reexec
wsl -d tmatwood-ubuntu-26.04 --cd / sudo systemctl restart systemd-resolved.service
wsl -d tmatwood-ubuntu-26.04 --cd / sudo systemctl unmask systemd-binfmt.service
wsl -d tmatwood-ubuntu-26.04 --cd / sudo systemctl restart systemd-binfmt.service
wsl -d tmatwood-ubuntu-26.04 --cd / sudo systemctl mask systemd-binfmt.service
Copy-Item .wslgconfig "$env:USERPROFILE\.wslgconfig"
wsl --shutdown
