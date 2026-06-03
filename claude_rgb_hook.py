#!/usr/bin/env python3
import argparse
import glob
import json
import os
import sys
import time
import termios
from typing import Any, Dict, Optional


DEFAULT_PORT = "/dev/cu.usbmodem1201"
DEFAULT_BAUD = 115200

VALID_STATES = {
    "idle",
    "done",
    "running",
    "tool",
    "ask",
    "error",
}

PORT_PATTERNS = [
    # macOS
    "/dev/cu.usbmodem*",
    "/dev/cu.usbserial*",
    "/dev/cu.wchusbserial*",
    "/dev/cu.SLAB_USBtoUART*",

    # Linux
    "/dev/ttyACM*",
    "/dev/ttyUSB*",
]


def log(message: str) -> None:
    log_path = os.environ.get("CLAUDE_RGB_LOG", "")
    if not log_path:
        return

    log_path = os.path.expanduser(log_path)

    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except Exception:
        # 日志失败不能影响 Claude Code
        pass


def scan_ports() -> list[str]:
    ports: list[str] = []

    for pattern in PORT_PATTERNS:
        ports.extend(glob.glob(pattern))

    return sorted(set(ports))


def pick_serial_port(cli_port: Optional[str] = None) -> Optional[str]:
    if cli_port:
        return cli_port

    env_port = os.environ.get("CLAUDE_RGB_PORT")
    if env_port:
        return env_port

    if os.path.exists(DEFAULT_PORT):
        return DEFAULT_PORT

    ports = scan_ports()
    if ports:
        return ports[0]

    return None


def baud_to_termios(baud: int) -> int:
    if baud == 9600:
        return termios.B9600
    if baud == 19200:
        return termios.B19200
    if baud == 38400:
        return termios.B38400
    if baud == 57600:
        return termios.B57600
    if baud == 115200:
        return termios.B115200

    # 默认 115200
    return termios.B115200


def configure_serial(fd: int, baud: int) -> None:
    attrs = termios.tcgetattr(fd)

    # Input flags
    attrs[0] &= ~(
        termios.IGNBRK
        | termios.BRKINT
        | termios.PARMRK
        | termios.ISTRIP
        | termios.INLCR
        | termios.IGNCR
        | termios.ICRNL
        | termios.IXON
    )

    # Output flags
    attrs[1] &= ~termios.OPOST

    # Control flags: 8N1
    attrs[2] &= ~termios.CSIZE
    attrs[2] |= termios.CS8
    attrs[2] &= ~termios.PARENB
    attrs[2] &= ~termios.CSTOPB

    if hasattr(termios, "CREAD"):
        attrs[2] |= termios.CREAD
    if hasattr(termios, "CLOCAL"):
        attrs[2] |= termios.CLOCAL

    # Local flags
    attrs[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG)

    if hasattr(termios, "IEXTEN"):
        attrs[3] &= ~termios.IEXTEN

    speed = baud_to_termios(baud)
    attrs[4] = speed
    attrs[5] = speed

    # VMIN / VTIME
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 5

    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def write_state_to_serial(state: str, port: Optional[str] = None, baud: int = DEFAULT_BAUD) -> bool:
    state = state.strip().lower()

    if state not in VALID_STATES:
        log(f"Invalid state: {state}")
        return False

    picked_port = pick_serial_port(port)

    if not picked_port:
        log("No serial port found")
        return False

    payload = f"STATE:{state}\n".encode("utf-8")

    try:
        fd = os.open(picked_port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)

        try:
            configure_serial(fd, baud)

            # 连续发送两次，降低偶发丢包概率
            os.write(fd, payload)
            time.sleep(0.04)
            os.write(fd, payload)

            try:
                termios.tcdrain(fd)
            except Exception:
                pass

            log(f"sent STATE:{state} to {picked_port}")
            return True

        finally:
            os.close(fd)

    except Exception as e:
        log(f"serial write failed: port={picked_port}, error={repr(e)}")
        return False


def read_hook_input() -> Dict[str, Any]:
    try:
        raw = sys.stdin.read()

        if not raw.strip():
            return {}

        data = json.loads(raw)

        if isinstance(data, dict):
            return data

        return {}

    except Exception as e:
        log(f"failed to read hook input: {repr(e)}")
        return {}


def state_from_hook(data: Dict[str, Any]) -> Optional[str]:
    event = data.get("hook_event_name", "")
    tool_name = data.get("tool_name", "")
    notification_type = data.get("notification_type", "")

    # 当 Claude Code 启动新会话或恢复会话时，会触发 SessionStart
    if event == "SessionStart":
        return "idle"

    if event == "SessionEnd":
        return "idle"

    # 用户提交 prompt 后，Claude 开始处理
    if event == "UserPromptSubmit":
        return "running"

    # 工具调用前：显示 tool
    # AskUserQuestion / ExitPlanMode 本质上是等用户介入，显示 ask
    if event == "PreToolUse":
        if tool_name in {"AskUserQuestion", "ExitPlanMode"}:
            return "ask"
        return "tool"

    # 工具成功后：回到 running
    if event == "PostToolUse":
        return "running"

    # 工具失败：错误
    if event == "PostToolUseFailure":
        return "error"

    # 即将弹权限确认框：等待用户
    if event == "PermissionRequest":
        return "ask"

    # 用户拒绝权限：错误/中断态
    if event == "PermissionDenied":
        return "error"

    # Claude 等待输入或权限时会触发 Notification
    if event == "Notification":
        if notification_type == "permission_prompt":
            return "ask"

        if notification_type == "elicitation_dialog":
            return "ask"

        # 关键修复：idle_prompt 不再映射为 ask
        if notification_type == "idle_prompt":
            return None

        return None
    # 主 agent 完成本轮响应
    if event == "Stop":
        return "done"

    # API / 鉴权 / 模型等异常
    if event == "StopFailure":
        return "error"

    return None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Claude Code RGB hook for ESP32-C3"
    )

    parser.add_argument(
        "state",
        nargs="?",
        help="Manual test state: idle, done, running, tool, ask, error"
    )

    parser.add_argument(
        "--port",
        default=None,
        help=f"Serial port, default from CLAUDE_RGB_PORT or {DEFAULT_PORT}"
    )

    parser.add_argument(
        "--baud",
        type=int,
        default=DEFAULT_BAUD,
        help="Serial baud rate, default 115200"
    )

    parser.add_argument(
        "--scan",
        action="store_true",
        help="List candidate serial ports"
    )

    parser.add_argument(
        "--print-input",
        action="store_true",
        help="Debug: print stdin JSON parsed from Claude Code hook"
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.scan:
        ports = scan_ports()
        for port in ports:
            print(port)
        return 0

    # 手动测试模式：
    # ~/.claude/hooks/claude_rgb_hook.py running
    if args.state:
        state = args.state.strip().lower()

        if state not in VALID_STATES:
            print(f"Invalid state: {state}", file=sys.stderr)
            print(f"Valid states: {', '.join(sorted(VALID_STATES))}", file=sys.stderr)
            return 1

        ok = write_state_to_serial(state, port=args.port, baud=args.baud)

        if not ok:
            print("Failed to write serial.", file=sys.stderr)
            print("Check ESP32 connection and CLAUDE_RGB_PORT.", file=sys.stderr)
            return 1

        return 0

    # Claude Code hook 模式
    data = read_hook_input()

    if args.print_input:
        print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)

    state = state_from_hook(data)

    if state:
        write_state_to_serial(state, port=args.port, baud=args.baud)

    # 关键：RGB hook 不应阻断 Claude Code
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
