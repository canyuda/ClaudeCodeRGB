#!/usr/bin/env bash
# Claude Code RGB WiFi Status Light - One-click Deployment
# Deploys WiFi hook to Claude Code settings (project-level or user-level)
# Supports macOS, Linux, and Windows (Git Bash / MSYS)
#
# Usage:
#   ./install.sh           # Deploy to current project
#   ./install.sh --user    # Deploy to user-level (~/.claude/settings.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IS_WINDOWS=false
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=true ;;
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
        echo -e -n "${CYAN}${prompt_text}${NC}: " >&2
        read -r value </dev/tty
        if [ -z "$value" ]; then
            warn "${varname} cannot be empty" >&2
        fi
    done
    echo "$value"
}

prompt_optional() {
    local prompt_text="$1"
    local default="${2:-}"
    local value=""
    if [ -n "$default" ]; then
        echo -e -n "${CYAN}${prompt_text}${NC} [${default}]: " >&2
    else
        echo -e -n "${CYAN}${prompt_text}${NC} (leave empty to skip): " >&2
    fi
    read -r value </dev/tty
    echo "${value:-$default}"
}

# ============================================================
# Step 1: Determine target paths
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
        HOOK_TARGET="$HOOK_TARGET_DIR/claude_rgb_wifi_hook.py"
        if [ "$IS_WINDOWS" = true ]; then
            HOOK_CMD='python $HOME/.claude/hooks/claude_rgb_wifi_hook.py'
        else
            HOOK_CMD='$HOME/.claude/hooks/claude_rgb_wifi_hook.py'
        fi
        info "Target: user-level ($TARGET_SETTINGS)"
    else
        TARGET_SETTINGS="$(pwd)/.claude/settings.local.json"
        SCOPE="project"
        HOOK_TARGET_DIR="$(pwd)/.claude/hooks"
        HOOK_TARGET="$HOOK_TARGET_DIR/claude_rgb_wifi_hook.py"
        if [ "$IS_WINDOWS" = true ]; then
            HOOK_CMD='python .claude/hooks/claude_rgb_wifi_hook.py'
        else
            HOOK_CMD='.claude/hooks/claude_rgb_wifi_hook.py'
        fi
        info "Target: project-level ($TARGET_SETTINGS)"
    fi
}

# ============================================================
# Step 2: Download hook script (HTTP with local fallback)
# ============================================================

HOOK_SCRIPT_URL="https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/wifiClaudeCodeRGB/claude_rgb_wifi_hook.py"

install_hook_script() {
    mkdir -p "$HOOK_TARGET_DIR"

    local local_source="$SCRIPT_DIR/claude_rgb_wifi_hook.py"

    if [ -f "$local_source" ]; then
        cp "$local_source" "$HOOK_TARGET"
        ok "Hook script copied from local: $local_source"
    elif command -v curl >/dev/null 2>&1; then
        info "Downloading hook script from GitHub..."
        if curl -fsSL "$HOOK_SCRIPT_URL" -o "$HOOK_TARGET"; then
            ok "Hook script downloaded from GitHub"
        else
            err "Failed to download hook script"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        info "Downloading hook script from GitHub (wget)..."
        if wget -q "$HOOK_SCRIPT_URL" -O "$HOOK_TARGET"; then
            ok "Hook script downloaded from GitHub"
        else
            err "Failed to download hook script"
            exit 1
        fi
    else
        err "No curl or wget found, and no local claude_rgb_wifi_hook.py"
        err "Install curl or place the script alongside install.sh"
        exit 1
    fi

    if [ "$IS_WINDOWS" = false ]; then
        chmod +x "$HOOK_TARGET"
    fi
    ok "Hook script installed to $HOOK_TARGET"
}

# ============================================================
# Step 3: Auto-discover ESP32 via mDNS
# ============================================================

ESP_HOST=""
MODE_VALUE=""
LOG_VALUE=""
PYTHON_BIN=""

discover_esp32() {
    echo ""
    info "========== Device Discovery =========="
    echo ""
    info "Searching for ESP32 via mDNS (claude-rgb.local)..."

    # Use the hook script's --discover to find the device
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
    else
        PYTHON_BIN=""
    fi

    if [ -z "$PYTHON_BIN" ]; then
        warn "Python not found, skipping mDNS discovery"
        fallback_manual_ip
        return
    fi

    DISCOVER_OUTPUT=$("$PYTHON_BIN" "$HOOK_TARGET" --discover 2>&1) || true

    if echo "$DISCOVER_OUTPUT" | grep -q "Found ESP32"; then
        # Extract IP from "Found ESP32 at 192.168.x.x (claude-rgb.local)"
        ESP_HOST=$(echo "$DISCOVER_OUTPUT" | grep "Found ESP32 at" | sed 's/.*at \([0-9.]*\).*/\1/')
        ok "ESP32 found via mDNS: $ESP_HOST (claude-rgb.local)"
        echo ""
        info "No need to set CLAUDE_RGB_HOST — the hook will auto-discover via mDNS"
    else
        warn "mDNS discovery failed — ESP32 not found on local network"
        echo ""
        info "Possible reasons:"
        info "  - ESP32 is not powered on or not connected to WiFi"
        info "  - Firmware not yet updated with mDNS support"
        info "  - Linux: avahi-daemon not installed (sudo apt install avahi-daemon)"
        echo ""
        fallback_manual_ip
    fi
}

fallback_manual_ip() {
    info "You can manually enter the ESP32 IP address instead."
    info "Check the serial monitor or your router for the IP."
    echo ""
    ESP_HOST="$(prompt_optional "ESP32 IP address" "")"

    if [ -z "$ESP_HOST" ]; then
        info "No IP set — hook will use mDNS auto-discovery at runtime"
    fi
}

configure_mode() {
    MODE_VALUE="$(prompt_optional "Communication mode (auto/http/serial)" "auto")"
    echo ""

    LOG_VALUE="$(prompt_optional "Log path" "")"
}

# ============================================================
# Step 4: Merge into settings.json using python3
# ============================================================

merge_settings() {
    local settings_file="$1"
    local host_value="$2"
    local mode_value="$3"
    local log_value="$4"
    local hook_cmd="$5"

    mkdir -p "$(dirname "$settings_file")"
    [ -f "$settings_file" ] || echo '{}' > "$settings_file"

    # Use detected python binary (python3 or python)
    local py_bin="${PYTHON_BIN:-python3}"

    "$py_bin" - "$settings_file" "$host_value" "$mode_value" "$log_value" "$hook_cmd" <<'PYEOF'
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

# Only set CLAUDE_RGB_HOST when explicitly provided (mDNS auto-discovery if empty)
if host_value:
    settings["env"]["CLAUDE_RGB_HOST"] = host_value
elif "CLAUDE_RGB_HOST" in settings["env"]:
    del settings["env"]["CLAUDE_RGB_HOST"]

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
PYEOF

    if [ $? -eq 0 ]; then
        ok "Config updated: $settings_file"
    else
        err "Config merge failed"
        exit 1
    fi
}

# ============================================================
# Step 5: Summary
# ============================================================

print_summary() {
    echo ""
    echo "=========================================="
    ok "WiFi RGB Hook Deployed!"
    echo "=========================================="
    echo ""
    echo "  Hook script:  $HOOK_TARGET"
    echo "  Config:       $TARGET_SETTINGS ($SCOPE)"
    if [ -n "$ESP_HOST" ]; then
        echo "  ESP32 IP:     $ESP_HOST"
    else
        echo "  ESP32 IP:     auto (mDNS: claude-rgb.local)"
    fi
    echo "  Mode:         $MODE_VALUE"
    if [ -n "$LOG_VALUE" ]; then
        echo "  Log:          $LOG_VALUE"
    else
        echo "  Log:          disabled"
    fi
    echo ""
    info "Test:"
    echo "  python3 $HOOK_TARGET --discover"
    echo "  python3 $HOOK_TARGET --status"
    echo "  python3 $HOOK_TARGET running"
    echo ""
    info "Restart Claude Code for changes to take effect"
    echo "=========================================="
}

# ============================================================
# Main
# ============================================================

main() {
    echo ""
    info "Claude Code RGB WiFi Status Light - Deployment"
    echo ""

    parse_args "$@"
    install_hook_script
    discover_esp32
    configure_mode
    merge_settings "$TARGET_SETTINGS" "$ESP_HOST" "$MODE_VALUE" "$LOG_VALUE" "$HOOK_CMD"
    print_summary
}

main "$@"
