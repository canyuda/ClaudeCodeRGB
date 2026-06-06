#!/usr/bin/env python3
"""
Claude Code BLE RGB Hook — calls the daemon's HTTP API.

Zero external dependencies (stdlib only). The daemon handles BLE.

Usage:
  echo '{"hook_event_name":"UserPromptSubmit"}' | python3 claude_rgb_ble_hook.py
  python3 claude_rgb_ble_hook.py running          # manual test
  python3 claude_rgb_ble_hook.py --scan           # scan BLE devices
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from typing import Any, Dict, Optional

DEFAULT_HTTP_PORT = 19740
VALID_STATES = {"idle", "done", "running", "tool", "ask", "error"}

# ---------------------------------------------------------------------------
# Hook event → LED state mapping (identical to serial version)
# ---------------------------------------------------------------------------


def state_from_hook(data: Dict[str, Any]) -> Optional[str]:
    event = data.get("hook_event_name", "")
    tool_name = data.get("tool_name", "")
    notification_type = data.get("notification_type", "")

    if event == "SessionStart":
        return "idle"
    if event == "SessionEnd":
        return "idle"
    if event == "UserPromptSubmit":
        return "running"
    if event == "PreToolUse":
        if tool_name in {"AskUserQuestion", "ExitPlanMode"}:
            return "ask"
        return "tool"
    if event == "PostToolUse":
        return "running"
    if event == "PostToolUseFailure":
        return "error"
    if event == "PermissionRequest":
        return "ask"
    if event == "PermissionDenied":
        return "error"
    if event == "Notification":
        if notification_type in ("permission_prompt", "elicitation_dialog"):
            return "ask"
        return None
    if event == "Stop":
        return "done"
    if event == "StopFailure":
        return "error"

    return None


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def _base_url() -> str:
    port = os.environ.get("CLAUDE_RGB_BLE_PORT", str(DEFAULT_HTTP_PORT))
    return f"http://127.0.0.1:{port}"


def http_get(path: str, timeout: float = 1.0) -> Optional[dict]:
    """GET request to daemon, return parsed JSON or None."""
    url = _base_url() + path
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def send_state(state: str) -> bool:
    """Send state to daemon via HTTP."""
    result = http_get(f"/state/{state}", timeout=1.0)
    return result is not None and result.get("ok", False)


def read_hook_input() -> Dict[str, Any]:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return {}
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Claude Code BLE RGB Hook")
    parser.add_argument(
        "state", nargs="?",
        help="Manual test: idle, done, running, tool, ask, error",
    )
    parser.add_argument(
        "--scan", action="store_true",
        help="Scan BLE devices via daemon",
    )
    parser.add_argument(
        "--print-input", action="store_true",
        help="Debug: print parsed hook JSON",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    # --scan: forward scan request to daemon
    if args.scan:
        # Ping daemon first
        status = http_get("/status", timeout=2.0)
        if status is None:
            print("Daemon not running. Start it first:", file=sys.stderr)
            print("  python3 claude_rgb_ble_daemon.py --scan", file=sys.stderr)
            return 1
        print(f"Daemon status: connected={status.get('connected')}, "
              f"state={status.get('state')}, device={status.get('device')}")
        return 0

    # Manual test mode
    if args.state:
        state = args.state.strip().lower()
        if state not in VALID_STATES:
            print(f"Invalid state: {state}", file=sys.stderr)
            print(f"Valid: {', '.join(sorted(VALID_STATES))}", file=sys.stderr)
            return 1

        ok = send_state(state)
        if not ok:
            print("Failed to send state. Is the daemon running?", file=sys.stderr)
            return 1
        print(f"OK: {state}")
        return 0

    # Claude Code hook mode — read JSON from stdin
    data = read_hook_input()

    if args.print_input:
        print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)

    state = state_from_hook(data)
    if state:
        send_state(state)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
