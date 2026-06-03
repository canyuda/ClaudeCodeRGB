#!/usr/bin/env python3
import argparse
import glob
import json
import os
import sys
import time

IS_WINDOWS = sys.platform == "win32"

if IS_WINDOWS:
    import ctypes
    import ctypes.wintypes as wt

    try:
        import winreg
    except ImportError:
        winreg = None
else:
    import termios

from typing import Any, Dict, Optional


# Default port differs by platform
if IS_WINDOWS:
    DEFAULT_PORT = "COM3"
else:
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

PORT_PATTERNS_POSIX = [
    # macOS
    "/dev/cu.usbmodem*",
    "/dev/cu.usbserial*",
    "/dev/cu.wchusbserial*",
    "/dev/cu.SLAB_USBtoUART*",
    # Linux
    "/dev/ttyACM*",
    "/dev/ttyUSB*",
]


# ============================================================
# Windows serial via ctypes (kernel32.dll)
# ============================================================

if IS_WINDOWS:
    kernel32 = ctypes.windll.kernel32

    _GENERIC_READ = 0x80000000
    _GENERIC_WRITE = 0x40000000
    _OPEN_EXISTING = 3
    _INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    # DCB structure for serial port configuration
    class _DCB(ctypes.Structure):
        _fields_ = [
            ("DCBlength", wt.DWORD),
            ("BaudRate", wt.DWORD),
            ("fFlags", wt.DWORD),
            ("wReserved", wt.WORD),
            ("XonLim", wt.WORD),
            ("XoffLim", wt.WORD),
            ("ByteSize", wt.BYTE),
            ("Parity", wt.BYTE),
            ("StopBits", wt.BYTE),
            ("XonChar", ctypes.c_char),
            ("XoffChar", ctypes.c_char),
            ("ErrorChar", ctypes.c_char),
            ("EofChar", ctypes.c_char),
            ("EvtChar", ctypes.c_char),
            ("wReserved1", wt.WORD),
        ]

    class _COMMTIMEOUTS(ctypes.Structure):
        _fields_ = [
            ("ReadIntervalTimeout", wt.DWORD),
            ("ReadTotalTimeoutMultiplier", wt.DWORD),
            ("ReadTotalTimeoutConstant", wt.DWORD),
            ("WriteTotalTimeoutMultiplier", wt.DWORD),
            ("WriteTotalTimeoutConstant", wt.DWORD),
        ]

    def _win_open_port(port: str):
        """Open a Windows COM port, return handle or None."""
        # On Windows, COM ports >= 10 need \\.\ prefix
        if port.startswith("COM") and len(port) > 4:
            win_port = f"\\\\.\\{port}"
        else:
            win_port = port

        handle = kernel32.CreateFileW(
            win_port,
            _GENERIC_READ | _GENERIC_WRITE,
            0,
            None,
            _OPEN_EXISTING,
            0,
            None,
        )
        if handle == _INVALID_HANDLE_VALUE or handle is None:
            return None
        return handle

    def _win_close_port(handle) -> None:
        kernel32.CloseHandle(handle)

    def _win_configure_port(handle, baud: int) -> bool:
        """Configure DCB and timeouts on an open handle."""
        dcb = _DCB()
        dcb.DCBlength = ctypes.sizeof(_DCB)

        if not kernel32.GetCommState(handle, ctypes.byref(dcb)):
            return False

        dcb.BaudRate = baud
        dcb.ByteSize = 8
        dcb.Parity = 0   # NOPARITY
        dcb.StopBits = 0  # ONESTOPBIT
        dcb.fFlags = 0x01  # fBinary only

        if not kernel32.SetCommState(handle, ctypes.byref(dcb)):
            return False

        timeouts = _COMMTIMEOUTS()
        timeouts.ReadIntervalTimeout = 50
        timeouts.ReadTotalTimeoutMultiplier = 0
        timeouts.ReadTotalTimeoutConstant = 50
        timeouts.WriteTotalTimeoutMultiplier = 0
        timeouts.WriteTotalTimeoutConstant = 1000

        if not kernel32.SetCommTimeouts(handle, ctypes.byref(timeouts)):
            return False

        return True

    def _win_write_serial(state: str, port: str, baud: int) -> bool:
        """Write state to serial on Windows using ctypes."""
        handle = _win_open_port(port)
        if handle is None:
            log(f"failed to open port {port}")
            return False

        try:
            if not _win_configure_port(handle, baud):
                log(f"failed to configure port {port}")
                return False

            payload = f"STATE:{state}\n".encode("utf-8")
            written = wt.DWORD()

            # Send twice to reduce packet loss (same as POSIX)
            kernel32.WriteFile(
                handle, payload, len(payload), ctypes.byref(written), None
            )
            time.sleep(0.04)
            kernel32.WriteFile(
                handle, payload, len(payload), ctypes.byref(written), None
            )

            log(f"sent STATE:{state} to {port}")
            return True

        finally:
            _win_close_port(handle)


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
        # Log failure must not affect Claude Code
        pass


def scan_ports() -> list[str]:
    if IS_WINDOWS:
        return _scan_ports_windows()
    return _scan_ports_posix()


def _scan_ports_posix() -> list[str]:
    ports: list[str] = []
    for pattern in PORT_PATTERNS_POSIX:
        ports.extend(glob.glob(pattern))
    return sorted(set(ports))


def _scan_ports_windows() -> list[str]:
    """Scan COM ports via Windows registry (HARDWARE\\DEVICEMAP\\SERIALCOMM)."""
    ports: list[str] = []

    if winreg is not None:
        try:
            key = winreg.OpenKey(
                winreg.HKEY_LOCAL_MACHINE,
                r"HARDWARE\DEVICEMAP\SERIALCOMM",
            )
            i = 0
            while True:
                try:
                    _, value, _ = winreg.EnumValue(key, i)
                    if isinstance(value, str) and value.startswith("COM"):
                        ports.append(value)
                    i += 1
                except OSError:
                    break
            winreg.CloseKey(key)
        except Exception:
            pass

    return sorted(ports)


def pick_serial_port(cli_port: Optional[str] = None) -> Optional[str]:
    if cli_port:
        return cli_port

    env_port = os.environ.get("CLAUDE_RGB_PORT")
    if env_port:
        return env_port

    # On Windows, skip the file-existence check (COM ports aren't files)
    if not IS_WINDOWS and os.path.exists(DEFAULT_PORT):
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


def _write_serial_posix(state: str, port: str, baud: int) -> bool:
    """Write state to serial on POSIX systems using termios."""
    payload = f"STATE:{state}\n".encode("utf-8")

    try:
        fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)

        try:
            configure_serial(fd, baud)

            # Send twice to reduce packet loss
            os.write(fd, payload)
            time.sleep(0.04)
            os.write(fd, payload)

            try:
                termios.tcdrain(fd)
            except Exception:
                pass

            log(f"sent STATE:{state} to {port}")
            return True

        finally:
            os.close(fd)

    except Exception as e:
        log(f"serial write failed: port={port}, error={repr(e)}")
        return False


def write_state_to_serial(
    state: str, port: Optional[str] = None, baud: int = DEFAULT_BAUD
) -> bool:
    state = state.strip().lower()

    if state not in VALID_STATES:
        log(f"Invalid state: {state}")
        return False

    picked_port = pick_serial_port(port)

    if not picked_port:
        log("No serial port found")
        return False

    if IS_WINDOWS:
        return _win_write_serial(state, picked_port, baud)
    else:
        return _write_serial_posix(state, picked_port, baud)


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
        if notification_type == "permission_prompt":
            return "ask"

        if notification_type == "elicitation_dialog":
            return "ask"

        if notification_type == "idle_prompt":
            return None

        return None

    if event == "Stop":
        return "done"

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
        help="Manual test state: idle, done, running, tool, ask, error",
    )

    parser.add_argument(
        "--port",
        default=None,
        help=f"Serial port, default from CLAUDE_RGB_PORT or {DEFAULT_PORT}",
    )

    parser.add_argument(
        "--baud",
        type=int,
        default=DEFAULT_BAUD,
        help="Serial baud rate, default 115200",
    )

    parser.add_argument(
        "--scan",
        action="store_true",
        help="List candidate serial ports",
    )

    parser.add_argument(
        "--print-input",
        action="store_true",
        help="Debug: print stdin JSON parsed from Claude Code hook",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.scan:
        ports = scan_ports()
        for port in ports:
            print(port)
        if not ports:
            print("No serial ports found.", file=sys.stderr)
        return 0

    # Manual test mode
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

    # Claude Code hook mode
    data = read_hook_input()

    if args.print_input:
        print(json.dumps(data, ensure_ascii=False, indent=2), file=sys.stderr)

    state = state_from_hook(data)

    if state:
        write_state_to_serial(state, port=args.port, baud=args.baud)

    # RGB hook must not block Claude Code
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
