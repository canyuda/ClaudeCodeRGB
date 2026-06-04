#Requires -Version 5.1
# Claude Code RGB WiFi Status Light - Windows Deployment
# Usage:
#   .\install.ps1              # Deploy to current project
#   .\install.ps1 -User        # Deploy to user-level config

param(
    [switch]$User
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
# Helpers
# ============================================================

function Write-Info($msg)  { Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $msg }
function Write-Ok($msg)    { Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn($msg)  { Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err($msg)   { Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $msg }

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
        if (-not $homeDir) { $homeDir = (Resolve-Path "~").Path }

        $script:TargetSettings = Join-Path $homeDir ".claude\settings.json"
        $script:Scope = "user"
        $script:HookTargetDir = Join-Path $homeDir ".claude\hooks"
        $script:HookTarget = Join-Path $script:HookTargetDir "claude_rgb_wifi_hook.py"
        $script:HookCmd = "python `$HOME/.claude/hooks/claude_rgb_wifi_hook.py"
        Write-Info "Target: user-level ($script:TargetSettings)"
    }
    else {
        $script:TargetSettings = Join-Path (Get-Location) ".claude\settings.local.json"
        $script:Scope = "project"
        $script:HookTargetDir = Join-Path (Get-Location) ".claude\hooks"
        $script:HookTarget = Join-Path $script:HookTargetDir "claude_rgb_wifi_hook.py"
        $script:HookCmd = "python .claude/hooks/claude_rgb_wifi_hook.py"
        Write-Info "Target: project-level ($script:TargetSettings)"
    }
}

# ============================================================
# Step 3: Copy hook script
# ============================================================

function Install-HookScript {
    New-Item -ItemType Directory -Path $script:HookTargetDir -Force | Out-Null

    $sourceScript = Join-Path $ScriptDir "claude_rgb_wifi_hook.py"
    if (-not (Test-Path $sourceScript)) {
        Write-Err "Hook script not found: $sourceScript"
        Write-Err "Make sure claude_rgb_wifi_hook.py is in the same directory as install.ps1"
        exit 1
    }

    Copy-Item $sourceScript $script:HookTarget -Force
    Write-Ok "Hook script installed to $($script:HookTarget)"
}

# ============================================================
# Step 4: Configure ESP32 IP and mode
# ============================================================

$script:EspHost = ""
$script:ModeValue = ""
$script:LogValue = ""

function Configure-Env {
    Write-Host ""
    Write-Info "========== WiFi Configuration =========="
    Write-Host ""
    Write-Info "ESP32 should already be connected to your home WiFi."
    Write-Info "Check the serial monitor for its IP address."
    Write-Host ""

    $script:EspHost = Read-Host "Enter ESP32 IP address (e.g. 192.168.1.100)"
    if (-not $script:EspHost) {
        Write-Err "ESP32 IP address cannot be empty"
        exit 1
    }

    Write-Host ""
    $modeInput = Read-Host "Communication mode (auto/http/serial) [auto]"
    $script:ModeValue = if ($modeInput) { $modeInput } else { "auto" }

    Write-Host ""
    $script:LogValue = Read-Host "Log path (leave empty to disable)"
}

# ============================================================
# Step 5: Merge into settings.json using Python
# ============================================================

function Merge-Settings {
    $settingsFile = $script:TargetSettings
    $hostValue = $script:EspHost
    $modeValue = $script:ModeValue
    $logValue = $script:LogValue
    $hookCmd = $script:HookCmd

    $settingsDir = Split-Path $settingsFile -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    if (-not (Test-Path $settingsFile)) {
        Set-Content -Path $settingsFile -Value "{}" -Encoding UTF8
    }

    $pythonScript = @"
import json, sys

settings_path = sys.argv[1]
host_value = sys.argv[2]
mode_value = sys.argv[3]
log_value = sys.argv[4]
hook_command = sys.argv[5]

with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

if "env" not in settings or not isinstance(settings["env"], dict):
    settings["env"] = {}
if "hooks" not in settings or not isinstance(settings["hooks"], dict):
    settings["hooks"] = {}

settings["env"]["CLAUDE_RGB_HOST"] = host_value
settings["env"]["CLAUDE_RGB_MODE"] = mode_value
if log_value:
    settings["env"]["CLAUDE_RGB_LOG"] = log_value
elif "CLAUDE_RGB_LOG" in settings["env"]:
    del settings["env"]["CLAUDE_RGB_LOG"]

RGB_HOOKS = {
    "SessionStart": "startup|resume|clear|compact",
    "UserPromptSubmit": "",
    "PreToolUse": "*",
    "PostToolUse": "*",
    "PostToolUseFailure": "*",
    "PermissionRequest": "",
    "PermissionDenied": "",
    "Notification": "*",
    "Stop": "",
    "StopFailure": "*",
}

def make_hook():
    return {"type": "command", "command": hook_command, "async": True, "timeout": 2}

def is_rgb_hook(h):
    return "claude_rgb_wifi_hook" in h.get("command", "")

for event, matcher in RGB_HOOKS.items():
    hook_entry = make_hook()
    if event not in settings["hooks"]:
        settings["hooks"][event] = [{"matcher": matcher, "hooks": [hook_entry]}]
    else:
        existing = settings["hooks"][event]
        if not isinstance(existing, list):
            existing = []
            settings["hooks"][event] = existing
        found = None
        for g in existing:
            if g.get("matcher", "") == matcher:
                found = g
                break
        if found is None:
            existing.append({"matcher": matcher, "hooks": [hook_entry]})
        else:
            hooks_list = found.get("hooks", [])
            if not any(is_rgb_hook(h) for h in hooks_list):
                hooks_list.append(hook_entry)
                found["hooks"] = hooks_list

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("OK")
"@

    $tmpPy = Join-Path $env:TEMP "claude_rgb_wifi_merge_$PID.py"
    try {
        Set-Content -Path $tmpPy -Value $pythonScript -Encoding UTF8
        $result = python $tmpPy $settingsFile $hostValue $modeValue $logValue $hookCmd 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Config merge failed: $result"
            exit 1
        }
        Write-Ok "Config updated: $settingsFile"
    }
    finally {
        if (Test-Path $tmpPy) { Remove-Item $tmpPy -Force }
    }
}

# ============================================================
# Step 6: Summary
# ============================================================

function Print-Summary {
    Write-Host ""
    Write-Host "=========================================="
    Write-Ok "WiFi RGB Hook Deployed!"
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "  Hook script:  $($script:HookTarget)"
    Write-Host "  Config:       $($script:TargetSettings) ($($script:Scope))"
    Write-Host "  ESP32 IP:     $($script:EspHost)"
    Write-Host "  Mode:         $($script:ModeValue)"
    if ($script:LogValue) {
        Write-Host "  Log:          $($script:LogValue)"
    }
    else {
        Write-Host "  Log:          disabled"
    }
    Write-Host ""
    Write-Info "Test:"
    Write-Host "  python $($script:HookTarget) --host $($script:EspHost) --status"
    Write-Host "  python $($script:HookTarget) --host $($script:EspHost) running"
    Write-Host ""
    Write-Info "Restart Claude Code for changes to take effect"
    Write-Host "=========================================="
}

# ============================================================
# Main
# ============================================================

Write-Host ""
Write-Info "Claude Code RGB WiFi Status Light - Windows Deployment"
Write-Host ""

Check-Python
Resolve-TargetPaths
Install-HookScript
Configure-Env
Merge-Settings
Print-Summary
