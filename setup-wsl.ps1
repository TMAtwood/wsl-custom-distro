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

# Wait for systemd to finish booting before issuing per-user `sudo` commands so
# they run against a fully-booted system manager (avoids racing daemon-reexec /
# service restarts below). NOTE: the one-time "Failed to start the systemd user
# session for 'dev'" printed on the very first cold-boot entry is a benign WSL
# artifact -- the journal confirms user@1001 opens cleanly and it does not recur
# on subsequent boots.
Write-Host "Waiting for systemd to finish booting."
$booted = $false
for ($i = 0; $i -lt 30; $i++) {
    $state = (wsl -d tmatwood-ubuntu-26.04 -u root --cd / -- systemctl is-system-running 2>$null)
    if ($state -match 'running|degraded') { $booted = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $booted) { Write-Host "systemd not fully ready after 30s; continuing anyway." }

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
