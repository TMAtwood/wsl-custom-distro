# ============================================================================
# runner/host/30-autostart.ps1
# ============================================================================
# Registers a Windows Scheduled Task that starts the fcg-runner-host WSL2
# distro at logon AND at system startup, so that systemd brings up
# podman.socket and supervisor.service without manual intervention.
#
# WHY THIS IS NEEDED:
#   WSL2 distros do not start automatically on Windows boot.  When the host
#   machine restarts, fcg-runner-host would remain stopped until a user
#   manually ran 'wsl -d fcg-runner-host'.  This task solves that by firing
#   a brief wsl.exe invocation at two trigger points:
#     - At system startup (runs as SYSTEM, available even before logon)
#     - At user logon (belt-and-suspenders; catches cases where startup fires
#       before WSL is fully initialized)
#   Both triggers wake the distro; systemd then initialises all units.
#
# IDEMPOTENT: unregisters any existing task with the same name before
# re-registering, so this script can be re-run after changes.
#
# USAGE (from an elevated PowerShell prompt on Windows):
#   .\30-autostart.ps1
#
# VALIDATION after reboot:
#   wsl --list --running
#   wsl -d fcg-runner-host -- systemctl is-active podman.socket
#   wsl -d fcg-runner-host -- systemctl is-active supervisor.service
# ============================================================================

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ─── Constants ───────────────────────────────────────────────────────────────
$DistroName       = "fcg-runner-host"
$TaskName         = "FCG-Runner-HostStart"
$TaskDescription  = "Starts the $DistroName WSL2 distro at boot/logon so " +
                    "systemd brings up podman.socket and supervisor.service."

# ─── Helpers ─────────────────────────────────────────────────────────────────
function Write-Info    { param([string]$M); Write-Host "[INFO]    $M" -ForegroundColor Cyan }
function Write-Success { param([string]$M); Write-Host "[SUCCESS] $M" -ForegroundColor Green }
function Write-Warn    { param([string]$M); Write-Host "[WARN]    $M" -ForegroundColor Yellow }
function Write-Err     { param([string]$M); Write-Host "[ERROR]   $M" -ForegroundColor Red }

# ─── Guard: Administrator ─────────────────────────────────────────────────────
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "This script must be run as Administrator."
    Write-Err "Right-click PowerShell -> 'Run as administrator', then retry."
    exit 1
}

# ─── Guard: wsl.exe ───────────────────────────────────────────────────────────
$wslExe = (Get-Command wsl.exe -ErrorAction SilentlyContinue)?.Source
if (-not $wslExe) {
    Write-Err "wsl.exe not found in PATH.  Is WSL2 installed?"
    exit 1
}
Write-Info "wsl.exe found at: $wslExe"

# ─── Guard: distro exists ─────────────────────────────────────────────────────
$existingNames = (wsl.exe --list --quiet 2>$null) -split "`n" |
    ForEach-Object { $_.Trim().TrimEnd([char]0) } |
    Where-Object { $_ -ne "" }

if ($existingNames -notcontains $DistroName) {
    Write-Err "Distro '$DistroName' not found.  Run 00-create-host-distro.ps1 first."
    exit 1
}
Write-Info "Distro '$DistroName' confirmed present."

# ─── Idempotency: remove existing task if present ─────────────────────────────
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warn "Task '$TaskName' already registered — removing before re-registering."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Info "Existing task removed."
}

# ─── Build the scheduled task ─────────────────────────────────────────────────
# Action: invoke wsl.exe -d fcg-runner-host -- true
#   - "-d <distro>" selects the distro
#   - "-- true" runs the shell built-in 'true' and exits immediately
#   - The distro's systemd keeps running in the background (it is PID 1)
#   - Subsequent wsl.exe sessions attach to the already-running distro
#
# Note on "-WindowStyle Hidden": wsl.exe does not have a GUI window, but
# the hidden style suppresses any console window flicker at logon.
$action = New-ScheduledTaskAction `
    -Execute    $wslExe `
    -Argument   "-d $DistroName -- true"

# Triggers: startup fires immediately on Windows boot (before any user logs in);
# logon fires when any user signs in (belt-and-suspenders in case startup
# races ahead of WSL initialization during fast-startup scenarios).
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerLogon   = New-ScheduledTaskTrigger -AtLogOn

# Principal: run as SYSTEM with highest privileges.
# SYSTEM can invoke wsl.exe for distros registered on the machine; this avoids
# tying the task to a specific user account while still starting the distro.
# Note: the distro itself is per-user — if you see issues, change to run as
# the specific user who imported the distro.
$principal = New-ScheduledTaskPrincipal `
    -UserId    "SYSTEM" `
    -RunLevel  Highest `
    -LogonType ServiceAccount

# Settings: start if missed, do not stop on idle, no execution time limit
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable            `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 60) `
    -MultipleInstances IgnoreNew

$task = Register-ScheduledTask `
    -TaskName   $TaskName `
    -Description $TaskDescription `
    -Action     $action `
    -Trigger    @($triggerStartup, $triggerLogon) `
    -Principal  $principal `
    -Settings   $settings `
    -Force

if (-not $task) {
    Write-Err "Failed to register scheduled task '$TaskName'."
    exit 1
}

Write-Success "Scheduled task '$TaskName' registered."

# ─── Verify registration ──────────────────────────────────────────────────────
$registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($registered) {
    Write-Success "Task verified in Task Scheduler."
    Write-Info "  Task name  : $($registered.TaskName)"
    Write-Info "  State      : $($registered.State)"
    Write-Info "  Triggers   : $($registered.Triggers.Count) (startup + logon)"
} else {
    Write-Warn "Task registered but could not be read back immediately."
}

# ─── Done ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Success "=================================================================="
Write-Success " Autostart task '$TaskName' is active."
Write-Success "=================================================================="
Write-Host ""
Write-Info "The task will start '$DistroName' at next startup and logon."
Write-Host ""
Write-Info "VALIDATION HINTS (run after a reboot to confirm everything is up):"
Write-Info ""
Write-Info "  # Check the distro is running:"
Write-Info "    wsl --list --running"
Write-Info ""
Write-Info "  # Check systemd units inside the distro:"
Write-Info "    wsl -d $DistroName -- systemctl is-active podman.socket"
Write-Info "    wsl -d $DistroName -- systemctl is-active supervisor.service"
Write-Info ""
Write-Info "  # Check the Podman socket is present:"
Write-Info "    wsl -d $DistroName -- test -S /run/podman/podman.sock && echo OK"
Write-Info ""
Write-Info "To view or modify the task in the GUI:"
Write-Info "  taskschd.msc -> Task Scheduler Library -> $TaskName"
Write-Host ""
