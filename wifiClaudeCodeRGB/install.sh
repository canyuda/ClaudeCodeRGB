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
        echo -e -n "${CYAN}${prompt_text}${NC}: "
        read -r value </dev/tty
        if [ -z "$value" ]; then
            warn "${varname} cannot be empty"
        fi
    done
    echo "$value"
}

prompt_optional() {
    local prompt_text="$1"
    local default="${2:-}"
    local value=""
    if [ -n "$default" ]; then
        echo -e -n "${CYAN}${prompt_text}${NC} [${default}]: "
    else
        echo -e -n "${CYAN}${prompt_text}${NC} (leave empty to skip): "
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
# Step 2: Copy hook script
# ============================================================

install_hook_script() {
    mkdir -p "$HOOK_TARGET_DIR"
    cp "$SCRIPT_DIR/claude_rgb_wifi_hook.py" "$HOOK_TARGET"
    if [ "$IS_WINDOWS" = false ]; then
        chmod +x "$HOOK_TARGET"
    fi
    ok "Hook script installed to $HOOK_TARGET"
}

# ============================================================
# Step 3: Configure ESP32 IP and mode
# ============================================================

ESP_HOST=""
MODE_VALUE=""
LOG_VALUE=""

configure_env() {
    echo ""
    info "========== WiFi Configuration =========="
    echo ""
    info "ESP32 should already be connected to your home WiFi."
    info "Check the serial monitor for its IP address."
    echo ""

    ESP_HOST="$(prompt_required "ESP32 IP" "Enter ESP32 IP address (e.g. 192.168.1.100)")"
    echo ""

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

    python3 - "$settings_file" "$host_value" "$mode_value" "$log_value" "$hook_cmd" <<'PYEOF'
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
    echo "  ESP32 IP:     $ESP_HOST"
    echo "  Mode:         $MODE_VALUE"
    if [ -n "$LOG_VALUE" ]; then
        echo "  Log:          $LOG_VALUE"
    else
        echo "  Log:          disabled"
    fi
    echo ""
    info "Test:"
    echo "  python3 $HOOK_TARGET --host $ESP_HOST --status"
    echo "  python3 $HOOK_TARGET --host $ESP_HOST running"
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
    configure_env
    merge_settings "$TARGET_SETTINGS" "$ESP_HOST" "$MODE_VALUE" "$LOG_VALUE" "$HOOK_CMD"
    print_summary
}

main "$@"
