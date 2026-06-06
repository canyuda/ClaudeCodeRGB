#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Claude RGB BLE — one-click installer for macOS / Linux
# Installs: daemon + hook script + launchd (macOS) autostart
#
# Usage:
#   ./install.sh              # deploy to current project
#   ./install.sh --user       # deploy to user-level (~/.claude/settings.json)
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_SRC="$SCRIPT_DIR/claude_rgb_ble_daemon.py"
HOOK_SRC="$SCRIPT_DIR/claude_rgb_ble_hook.py"
PLIST_SRC="$SCRIPT_DIR/com.claude.rgb-ble-daemon.plist"

# Resolve deploy target
if [ "${1:-}" = "--user" ]; then
    DEPLOY_DIR="$HOME/.claude/hooks"
    SETTINGS_FILE="$HOME/.claude/settings.json"
    HOOK_CMD="python3 $HOME/.claude/hooks/claude_rgb_ble_hook.py"
else
    DEPLOY_DIR=".claude/hooks"
    SETTINGS_FILE=".claude/settings.local.json"
    HOOK_CMD="python3 .claude/hooks/claude_rgb_ble_hook.py"
fi

echo "=== Claude RGB BLE Installer ==="
echo ""

# Step 1: Check Python3
if ! command -v python3 &>/dev/null; then
    echo "Error: python3 not found" >&2
    exit 1
fi
echo "[OK] python3: $(python3 --version)"

# Step 2: Check / Install bleak
echo ""
echo "Checking bleak..."
if python3 -c "import bleak" 2>/dev/null; then
    echo "[OK] bleak installed"
else
    echo "Installing bleak..."
    pip3 install bleak
    if python3 -c "import bleak" 2>/dev/null; then
        echo "[OK] bleak installed"
    else
        echo "Error: failed to install bleak" >&2
        exit 1
    fi
fi

# Step 3: Deploy scripts
echo ""
echo "Deploying scripts to $DEPLOY_DIR/..."
mkdir -p "$DEPLOY_DIR"

cp "$DAEMON_SRC" "$DEPLOY_DIR/claude_rgb_ble_daemon.py"
cp "$HOOK_SRC"   "$DEPLOY_DIR/claude_rgb_ble_hook.py"
chmod +x "$DEPLOY_DIR/claude_rgb_ble_daemon.py"
chmod +x "$DEPLOY_DIR/claude_rgb_ble_hook.py"

echo "[OK] Deployed:"
echo "     $DEPLOY_DIR/claude_rgb_ble_daemon.py"
echo "     $DEPLOY_DIR/claude_rgb_ble_hook.py"

# Step 4: macOS launchd autostart
if [ "$(uname)" = "Darwin" ] && [ -f "$PLIST_SRC" ]; then
    echo ""
    echo "Setting up launchd autostart..."

    LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
    mkdir -p "$LAUNCH_AGENTS_DIR"
    PLIST_DEST="$LAUNCH_AGENTS_DIR/com.claude.rgb-ble-daemon.plist"

    # Update path in plist to match actual user home
    sed "s|/Users/yiqi|$HOME|g" "$PLIST_SRC" > "$PLIST_DEST"

    # Unload old version if exists
    if launchctl list | grep -q "com.claude.rgb-ble-daemon" 2>/dev/null; then
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
    fi

    launchctl load "$PLIST_DEST"
    echo "[OK] launchd: $PLIST_DEST"
fi

# Step 5: Configure Claude Code hooks
echo ""
echo "Configuring Claude Code hooks..."

# Build hook events JSON
HOOK_EVENTS='[
  {"hook_event_name":"SessionStart",        "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"SessionEnd",          "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"UserPromptSubmit",    "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"PreToolUse",          "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"PostToolUse",         "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"PostToolUseFailure",  "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"PermissionRequest",   "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"PermissionDenied",    "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"Notification",        "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"Stop",                "command":"'"$HOOK_CMD"'"},
  {"hook_event_name":"StopFailure",         "command":"'"$HOOK_CMD"'"}
]'

# Use Python to merge JSON settings
python3 - "$SETTINGS_FILE" "$HOOK_EVENTS" <<'PYEOF'
import json, sys, os

settings_path = sys.argv[1]
new_hooks_str = sys.argv[2]
new_hooks = json.loads(new_hooks_str)

# Read existing settings or start fresh
settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path, "r") as f:
            settings = json.load(f)
    except (json.JSONDecodeError, IOError):
        settings = {}

# Get existing hooks
existing = settings.get("hooks", [])

# Remove old claude_rgb hooks (match by command substring)
existing = [h for h in existing if "claude_rgb_ble_hook" not in h.get("command", "")]

# Add new hooks
existing.extend(new_hooks)
settings["hooks"] = existing

# Write back
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print(f"[OK] {settings_path}")
PYEOF

# Step 6: Summary
echo ""
echo "=== Install Complete ==="
echo ""
echo "Test commands:"
echo ""
echo "  # 1. Start daemon (if not using launchd)"
echo "  python3 $DEPLOY_DIR/claude_rgb_ble_daemon.py"
echo ""
echo "  # 2. Test hook manually"
echo "  python3 $DEPLOY_DIR/claude_rgb_ble_hook.py running"
echo ""
echo "  # 3. Check daemon status"
echo "  curl http://localhost:19740/status"
echo ""
echo "  # 4. Scan BLE devices"
echo "  python3 $DEPLOY_DIR/claude_rgb_ble_daemon.py --scan"
echo ""
echo "Settings written to: $SETTINGS_FILE"
echo ""
echo "Make sure your XIAO nRF52840 is powered on with the firmware flashed!"
