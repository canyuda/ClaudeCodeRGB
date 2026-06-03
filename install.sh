#!/usr/bin/env bash
# Claude Code RGB Status Light - One-click Deployment Script
# Modifies Claude Code settings.json to integrate RGB hook
# Supports macOS, Linux, and Windows (Git Bash / MSYS)

set -euo pipefail

# ============================================================
# Constants
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect platform
IS_WINDOWS=false
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        IS_WINDOWS=true
        ;;
esac

# ============================================================
# Helpers
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

prompt_required() {
    local varname="$1"
    local prompt_text="$2"
    local value=""
    while [ -z "$value" ]; do
        read -rp "$(echo -e "${CYAN}${prompt_text}${NC}: ")" value
        if [ -z "$value" ]; then
            warn "${varname} cannot be empty"
        fi
    done
    echo "$value"
}

prompt_optional() {
    local prompt_text="$1"
    local value=""
    read -rp "$(echo -e "${CYAN}${prompt_text}${NC} (leave empty to skip): ")" value
    echo "$value"
}

prompt_yesno() {
    local prompt_text="$1"
    local default="${2:-n}"
    local answer=""
    while true; do
        read -rp "$(echo -e "${CYAN}${prompt_text}${NC} [y/N]: ")" answer
        answer="${answer:-$default}"
        case "$answer" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) warn "Please enter y or n" ;;
        esac
    done
}

# ============================================================
# Step 1: OS check
# ============================================================

check_os() {
    local os="$(uname -s)"
    case "$os" in
        Darwin)
            ok "Detected system: macOS"
            ;;
        Linux)
            ok "Detected system: Linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            ok "Detected system: Windows ($os)"
            ;;
        *)
            err "Unsupported system: $os"
            exit 1
            ;;
    esac
}

# ============================================================
# Step 2: Determine target settings file
# ============================================================

TARGET_SETTINGS=""
SCOPE=""
HOOK_TARGET_DIR=""
HOOK_TARGET=""
HOOK_CMD=""

parse_args() {
    if [ "${1:-}" = "--user" ]; then
        TARGET_SETTINGS="$HOME/.claude/settings.json"
        SCOPE="user"
        HOOK_TARGET_DIR="$HOME/.claude/hooks"
        HOOK_TARGET="$HOOK_TARGET_DIR/claude_rgb_hook.py"

        if [ "$IS_WINDOWS" = true ]; then
            HOOK_CMD='python $HOME/.claude/hooks/claude_rgb_hook.py'
        else
            HOOK_CMD='$HOME/.claude/hooks/claude_rgb_hook.py'
        fi
        info "Target: user-level config ($TARGET_SETTINGS)"
    else
        TARGET_SETTINGS="$(pwd)/.claude/settings.local.json"
        SCOPE="project"
        HOOK_TARGET_DIR="$(pwd)/.claude/hooks"
        HOOK_TARGET="$HOOK_TARGET_DIR/claude_rgb_hook.py"

        if [ "$IS_WINDOWS" = true ]; then
            HOOK_CMD='python .claude/hooks/claude_rgb_hook.py'
        else
            HOOK_CMD='.claude/hooks/claude_rgb_hook.py'
        fi
        info "Target: project-level config ($TARGET_SETTINGS)"
    fi
}

# ============================================================
# Step 3: Copy hook script
# ============================================================

HOOK_REMOTE_URL="https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/claude_rgb_hook.py"

install_hook_script() {
    mkdir -p "$HOOK_TARGET_DIR"

    info "Downloading hook script: $HOOK_REMOTE_URL"

    local http_code
    http_code=$(curl -fsSL -o "$HOOK_TARGET" -w "%{http_code}" "$HOOK_REMOTE_URL" 2>/dev/null) || true

    if [ "$http_code" != "200" ]; then
        err "Download failed (HTTP $http_code)"
        err "Please check your network connection, or manually copy claude_rgb_hook.py to $HOOK_TARGET"
        exit 1
    fi

    if [ "$IS_WINDOWS" = false ]; then
        chmod +x "$HOOK_TARGET"
    fi
    ok "Hook script installed to $HOOK_TARGET"
}

# ============================================================
# Step 4: Scan serial port
# ============================================================

scan_serial_port() {
    local candidates=""
    local os="$(uname -s)"

    case "$os" in
        Darwin)
            candidates="$(ls /dev/cu.usbmodem* /dev/cu.usbserial* /dev/cu.wchusbserial* /dev/cu.SLAB_USBtoUART* 2>/dev/null || true)"
            ;;
        Linux)
            candidates="$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true)"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Windows COM ports: use PowerShell or mode command to scan
            candidates="$(
                powershell.exe -NoProfile -Command \
                    'Get-CimInstance Win32_SerialPort | Select-Object -ExpandProperty DeviceID' 2>/dev/null \
                | tr -d '\r' | grep -i '^COM' || true
            )"
            if [ -z "$candidates" ]; then
                # Fallback: try mode command
                candidates="$(mode 2>/dev/null | grep -oE 'COM[0-9]+' | sort -u || true)"
            fi
            ;;
    esac

    if [ -n "$candidates" ]; then
        echo "$candidates" | tr ' ' '\n' | sort -u
    fi
}

# ============================================================
# Step 5: Interactive env var configuration
# ============================================================

configure_env() {
    local serial_ports
    serial_ports="$(scan_serial_port)"

    echo ""
    info "========== Environment Variable Configuration =========="

    # --- CLAUDE_RGB_PORT ---
    local current_port="${CLAUDE_RGB_PORT:-}"

    if [ -z "$current_port" ]; then
        if [ -n "$serial_ports" ]; then
            echo ""
            info "Detected serial ports:"
            echo "$serial_ports" | nl -w2 -s'. '
            echo ""
        fi
        warn "CLAUDE_RGB_PORT is not configured (required)"
        local port_hint="/dev/cu.usbmodem1201"
        if [ "$IS_WINDOWS" = true ]; then
            port_hint="COM3"
        fi
        CLAUDE_RGB_PORT_VALUE="$(prompt_required "CLAUDE_RGB_PORT" "Enter serial port path (e.g. $port_hint)")"
    else
        ok "CLAUDE_RGB_PORT already configured: $current_port"
        if prompt_yesno "Overwrite?"; then
            if [ -n "$serial_ports" ]; then
                echo ""
                info "Detected serial ports:"
                echo "$serial_ports" | nl -w2 -s'. '
                echo ""
            fi
            CLAUDE_RGB_PORT_VALUE="$(prompt_required "CLAUDE_RGB_PORT" "Enter new serial port path")"
        else
            CLAUDE_RGB_PORT_VALUE="$current_port"
        fi
    fi

    # --- CLAUDE_RGB_LOG ---
    local current_log="${CLAUDE_RGB_LOG:-}"
    echo ""

    if [ -z "$current_log" ]; then
        info "CLAUDE_RGB_LOG not configured (leave empty to disable logging)"
        CLAUDE_RGB_LOG_VALUE="$(prompt_optional "CLAUDE_RGB_LOG" "Enter log path (e.g. ~/.claude/logs/rgb-hook.log)")"
    else
        ok "CLAUDE_RGB_LOG already configured: $current_log"
        if prompt_yesno "Modify?"; then
            CLAUDE_RGB_LOG_VALUE="$(prompt_optional "CLAUDE_RGB_LOG" "Enter log path (leave empty to disable logging)")"
        else
            CLAUDE_RGB_LOG_VALUE="$current_log"
        fi
    fi
}

# ============================================================
# Step 6: Merge into settings.json using python3
# ============================================================

merge_settings() {
    local settings_file="$1"
    local port_value="$2"
    local log_value="$3"
    local hook_cmd="$4"

    mkdir -p "$(dirname "$settings_file")"
    [ -f "$settings_file" ] || echo '{}' > "$settings_file"

    # Normalize path separators for Windows (Python handles forward slashes fine)
    python3 - "$settings_file" "$port_value" "$log_value" "$hook_cmd" <<'PYEOF'
import json
import sys

settings_path = sys.argv[1]
port_value = sys.argv[2]
log_value = sys.argv[3]
hook_command = sys.argv[4]

# Read existing settings
with open(settings_path, "r", encoding="utf-8") as f:
    settings = json.load(f)

# Ensure top-level keys exist
if "env" not in settings or not isinstance(settings["env"], dict):
    settings["env"] = {}
if "hooks" not in settings or not isinstance(settings["hooks"], dict):
    settings["hooks"] = {}

# Update env
settings["env"]["CLAUDE_RGB_PORT"] = port_value
if log_value:
    settings["env"]["CLAUDE_RGB_LOG"] = log_value
elif "CLAUDE_RGB_LOG" in settings["env"]:
    del settings["env"]["CLAUDE_RGB_LOG"]

# Hook definitions to merge
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

# Merge each hook event
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

# Write back
with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("OK")
PYEOF

    if [ $? -eq 0 ]; then
        ok "Config updated: $settings_file"
    else
        err "Config merge failed"
        exit 1
    fi
}

# ============================================================
# Step 7: Summary
# ============================================================

print_summary() {
    echo ""
    echo "=========================================="
    ok "Deployment complete!"
    echo "=========================================="
    echo ""
    echo "  Hook script:  $HOOK_TARGET"
    echo "  Config file:  $TARGET_SETTINGS ($SCOPE level)"
    echo "  Serial port:  $CLAUDE_RGB_PORT_VALUE"
    if [ -n "$CLAUDE_RGB_LOG_VALUE" ]; then
        echo "  Log:          $CLAUDE_RGB_LOG_VALUE"
    else
        echo "  Log:          disabled"
    fi
    echo ""
    info "Test commands:"
    if [ "$IS_WINDOWS" = true ]; then
        echo "  python $HOOK_TARGET --scan"
        echo "  python $HOOK_TARGET running"
    else
        echo "  $HOOK_TARGET --scan"
        echo "  $HOOK_TARGET running"
    fi
    echo ""
    info "Restart Claude Code for changes to take effect"
    echo "=========================================="
}

# ============================================================
# Main
# ============================================================

main() {
    echo ""
    info "Claude Code RGB Status Light - One-click Deployment"
    echo ""

    check_os

    parse_args "$@"
    install_hook_script
    configure_env
    merge_settings "$TARGET_SETTINGS" "$CLAUDE_RGB_PORT_VALUE" "$CLAUDE_RGB_LOG_VALUE" "$HOOK_CMD"
    print_summary
}

main "$@"
