#Requires -Version 5.1
# Claude Code RGB Status Light - Windows Deployment Script
# Modifies Claude Code settings.json to integrate RGB hook
# Usage:
#   .\install.ps1              # Deploy to current project
#   .\install.ps1 -User        # Deploy to user-level config

param(
    [switch]$User
)

$ErrorActionPreference = "Stop"

# ============================================================
# Constants
# ============================================================

$HookRemoteUrl = "https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/claude_rgb_hook.py"

# ============================================================
# Helpers
# ============================================================

function Write-Info($msg)    { Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $msg }
function Write-Ok($msg)      { Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn($msg)    { Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err($msg)     { Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $msg }

# ============================================================
# Step 1: Check Python
# ============================================================

function Check-Python {
    try {
        $pyVersion = python --version 2>&1
        Write-Ok "Python found: $pyVersion"
    }
    catch {
        Write-Err "Python not found. Please install Python 3 and add it to PATH."
        exit 1
    }
}

# ============================================================
# Step 2: Determine target paths
# ============================================================

$script:TargetSettings = ""
$script:Scope = ""
$script:HookTargetDir = ""
$script:HookTarget = ""
$script:HookCmd = ""

function Resolve-TargetPaths {
    if ($User) {
        $homeDir = $env:USERPROFILE
        if (-not $homeDir) { $homeDir = $env:HOME }
        if (-not $homeDir) {
            # Fallback for Git Bash / MSYS environment
            $homeDir = (Resolve-Path "~").Path
        }

        $script:TargetSettings = Join-Path $homeDir ".claude\settings.json"
        $script:Scope = "user"
        $script:HookTargetDir = Join-Path $homeDir ".claude\hooks"
        $script:HookTarget = Join-Path $script:HookTargetDir "claude_rgb_hook.py"
        $script:HookCmd = "python `$HOME/.claude/hooks/claude_rgb_hook.py"
        Write-Info "Target: user-level config ($script:TargetSettings)"
    }
    else {
        $script:TargetSettings = Join-Path (Get-Location) ".claude\settings.local.json"
        $script:Scope = "project"
        $script:HookTargetDir = Join-Path (Get-Location) ".claude\hooks"
        $script:HookTarget = Join-Path $script:HookTargetDir "claude_rgb_hook.py"
        $script:HookCmd = "python .claude/hooks/claude_rgb_hook.py"
        Write-Info "Target: project-level config ($script:TargetSettings)"
    }
}

# ============================================================
# Step 3: Download hook script
# ============================================================

function Install-HookScript {
    New-Item -ItemType Directory -Path $script:HookTargetDir -Force | Out-Null

    Write-Info "Downloading hook script: $HookRemoteUrl"

    try {
        Invoke-WebRequest -Uri $HookRemoteUrl -OutFile $script:HookTarget -UseBasicParsing
        Write-Ok "Hook script installed to $($script:HookTarget)"
    }
    catch {
        Write-Err "Download failed: $_"
        Write-Err "Please check your network connection, or manually copy claude_rgb_hook.py to $($script:HookTarget)"
        exit 1
    }
}

# ============================================================
# Step 4: Scan serial ports
# ============================================================

function Get-SerialPorts {
    $ports = @()

    try {
        $ports = Get-CimInstance Win32_SerialPort |
            Where-Object { $_.DeviceID -match '^COM\d+$' } |
            Select-Object -ExpandProperty DeviceID |
            Sort-Object { [int]($_ -replace '\D', '') }
    }
    catch {
        # Fallback: try [System.IO.Ports.SerialPort]::GetPortNames()
        try {
            $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
        }
        catch {
            Write-Warn "Cannot scan serial ports automatically"
        }
    }

    return $ports
}

# ============================================================
# Step 5: Interactive env var configuration
# ============================================================

$script:ClaudeRgbPort = ""
$script:ClaudeRgbLog = ""

function Configure-Env {
    $serialPorts = Get-SerialPorts
    $currentPort = $env:CLAUDE_RGB_PORT

    Write-Host ""
    Write-Info "========== Environment Variable Configuration =========="

    # --- CLAUDE_RGB_PORT ---
    if (-not $currentPort) {
        if ($serialPorts.Count -gt 0) {
            Write-Host ""
            Write-Info "Detected serial ports:"
            for ($i = 0; $i -lt $serialPorts.Count; $i++) {
                Write-Host "  $($i+1). $($serialPorts[$i])"
            }
            Write-Host ""
        }
        Write-Warn "CLAUDE_RGB_PORT is not configured (required)"
        $script:ClaudeRgbPort = Read-Host "Enter CLAUDE_RGB_PORT (e.g. COM3)"
        if (-not $script:ClaudeRgbPort) {
            Write-Err "CLAUDE_RGB_PORT cannot be empty"
            exit 1
        }
    }
    else {
        Write-Ok "CLAUDE_RGB_PORT already configured: $currentPort"
        $answer = Read-Host "Overwrite? [y/N]"
        if ($answer -eq 'y' -or $answer -eq 'Y') {
            if ($serialPorts.Count -gt 0) {
                Write-Host ""
                Write-Info "Detected serial ports:"
                for ($i = 0; $i -lt $serialPorts.Count; $i++) {
                    Write-Host "  $($i+1). $($serialPorts[$i])"
                }
                Write-Host ""
            }
            $script:ClaudeRgbPort = Read-Host "Enter new serial port path"
            if (-not $script:ClaudeRgbPort) {
                Write-Err "CLAUDE_RGB_PORT cannot be empty"
                exit 1
            }
        }
        else {
            $script:ClaudeRgbPort = $currentPort
        }
    }

    # --- CLAUDE_RGB_LOG ---
    $currentLog = $env:CLAUDE_RGB_LOG
    Write-Host ""

    if (-not $currentLog) {
        Write-Info "CLAUDE_RGB_LOG not configured (leave empty to disable logging)"
        $script:ClaudeRgbLog = Read-Host "Enter CLAUDE_RGB_LOG (leave empty to skip)"
    }
    else {
        Write-Ok "CLAUDE_RGB_LOG already configured: $currentLog"
        $answer = Read-Host "Modify? [y/N]"
        if ($answer -eq 'y' -or $answer -eq 'Y') {
            $script:ClaudeRgbLog = Read-Host "Enter log path (leave empty to disable logging)"
        }
        else {
            $script:ClaudeRgbLog = $currentLog
        }
    }
}

# ============================================================
# Step 6: Merge into settings.json using Python
# ============================================================

function Merge-Settings {
    $settingsFile = $script:TargetSettings
    $portValue = $script:ClaudeRgbPort
    $logValue = $script:ClaudeRgbLog
    $hookCmd = $script:HookCmd

    $settingsDir = Split-Path $settingsFile -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }

    if (-not (Test-Path $settingsFile)) {
        Set-Content -Path $settingsFile -Value "{}" -Encoding UTF8
    }

    # Use Python to merge JSON (same logic as install.sh)
    $pythonScript = @"
import json
import sys

settings_path = sys.argv[1]
port_value = sys.argv[2]
log_value = sys.argv[3]
hook_command = sys.argv[4]

with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

if "env" not in settings or not isinstance(settings["env"], dict):
    settings["env"] = {}
if "hooks" not in settings or not isinstance(settings["hooks"], dict):
    settings["hooks"] = {}

settings["env"]["CLAUDE_RGB_PORT"] = port_value
if log_value:
    settings["env"]["CLAUDE_RGB_LOG"] = log_value
elif "CLAUDE_RGB_LOG" in settings["env"]:
    del settings["env"]["CLAUDE_RGB_LOG"]

RGB_HOOKS = {
    "SessionStart": "startup|resume|clear|compact",
    "SessionEnd": "",
    "UserPromptSubmit": "",
    "PreToolUse": "*",
    "PostToolUse": "*",
    "PostToolUseFailure": "*",
    "PermissionRequest": "*",
    "PermissionDenied": "*",
    "Notification": "permission_prompt|elicitation_dialog",
    "Stop": "",
    "StopFailure": "*",
}

def make_hook_entry():
    return {
        "type": "command",
        "command": hook_command,
        "async": True,
        "timeout": 2,
    }

def is_rgb_hook(hook_entry):
    cmd = hook_entry.get("command", "")
    return "claude_rgb_hook.py" in cmd

for event_name, matcher in RGB_HOOKS.items():
    hook_entry = make_hook_entry()

    if event_name not in settings["hooks"]:
        settings["hooks"][event_name] = [
            {
                "matcher": matcher,
                "hooks": [hook_entry],
            }
        ]
    else:
        existing = settings["hooks"][event_name]
        if not isinstance(existing, list):
            existing = []
            settings["hooks"][event_name] = existing

        found_group = None
        for group in existing:
            if group.get("matcher", "") == matcher:
                found_group = group
                break

        if found_group is None:
            existing.append({
                "matcher": matcher,
                "hooks": [hook_entry],
            })
        else:
            hooks_list = found_group.get("hooks", [])
            already_exists = any(is_rgb_hook(h) for h in hooks_list)

            if not already_exists:
                hooks_list.append(hook_entry)
                found_group["hooks"] = hooks_list

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("OK")
"@

    $tmpPy = Join-Path $env:TEMP "claude_rgb_merge_$PID.py"
    try {
        Set-Content -Path $tmpPy -Value $pythonScript -Encoding UTF8

        $result = python $tmpPy $settingsFile $portValue $logValue $hookCmd 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Err "Config merge failed: $result"
            exit 1
        }

        Write-Ok "Config updated: $settingsFile"
    }
    finally {
        if (Test-Path $tmpPy) {
            Remove-Item $tmpPy -Force
        }
    }
}

# ============================================================
# Step 7: Summary
# ============================================================

function Print-Summary {
    Write-Host ""
    Write-Host "=========================================="
    Write-Ok "Deployment complete!"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "  Hook script:  $($script:HookTarget)"
    Write-Host "  Config file:  $($script:TargetSettings) ($($script:Scope) level)"
    Write-Host "  Serial port:  $($script:ClaudeRgbPort)"
    if ($script:ClaudeRgbLog) {
        Write-Host "  Log:          $($script:ClaudeRgbLog)"
    }
    else {
        Write-Host "  Log:          disabled"
    }
    Write-Host ""
    Write-Info "Test commands:"
    Write-Host "  python $($script:HookTarget) --scan"
    Write-Host "  python $($script:HookTarget) running"
    Write-Host ""
    Write-Info "Restart Claude Code for changes to take effect"
    Write-Host "=========================================="
}

# ============================================================
# Main
# ============================================================

Write-Host ""
Write-Info "Claude Code RGB Status Light - Windows Deployment"
Write-Host ""

Check-Python
Resolve-TargetPaths
Install-HookScript
Configure-Env
Merge-Settings
Print-Summary
