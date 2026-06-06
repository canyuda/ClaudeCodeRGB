#!/usr/bin/env python3
"""
Claude RGB BLE Daemon — maintains persistent BLE connection to XIAO nRF52840.

Architecture:
  - bleak for BLE long-connection (Nordic UART Service)
  - HTTP server on localhost for hook script to call (~5ms per request)
  - 50ms debounce: only sends the latest state, skips intermediates
  - Auto-reconnect on BLE disconnect

Usage:
  python3 claude_rgb_ble_daemon.py                 # start daemon
  python3 claude_rgb_ble_daemon.py --scan          # scan BLE devices
  python3 claude_rgb_ble_daemon.py --port 19740    # custom HTTP port
"""

import argparse
import asyncio
import json
import os
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    print("Error: bleak not installed. Run: pip install bleak", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_DEVICE_NAME = "ClaudeRGB-nRF52840"
DEFAULT_HTTP_PORT = 19740

NUS_SERVICE_UUID = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
NUS_RX_CHAR_UUID = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"  # Write
NUS_TX_CHAR_UUID = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"  # Notify

VALID_STATES = {"idle", "done", "running", "tool", "ask", "error"}

DEBOUNCE_MS = 0.050  # 50ms debounce window

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG_PATH = os.environ.get("CLAUDE_RGB_BLE_LOG", "")


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} {msg}"
    print(line, flush=True)
    if LOG_PATH:
        try:
            with open(os.path.expanduser(LOG_PATH), "a") as f:
                f.write(line + "\n")
        except Exception:
            pass


# ---------------------------------------------------------------------------
# BLE State Manager
# ---------------------------------------------------------------------------

class BLEManager:
    """Manages BLE connection, debounce, and state sending."""

    def __init__(self, device_name: str):
        self.device_name = device_name
        self.client: BleakClient | None = None
        self.connected = False
        self.current_state = "idle"
        self._pending_state: str | None = None
        self._debounce_timer: asyncio.TimerHandle | None = None
        self._lock = asyncio.Lock()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._device_address: str | None = None

    async def scan(self, timeout: float = 5.0) -> list[dict]:
        """Scan for BLE devices, return list of {name, address}."""
        devices = await BleakScanner.discover(timeout=timeout)
        results = []
        for d in devices:
            results.append({"name": d.name or "(unknown)", "address": d.address})
        return results

    async def find_device(self, timeout: float = 10.0) -> str | None:
        """Find target device by name, return its address."""
        log(f"Scanning for '{self.device_name}' (timeout={timeout}s)...")
        devices = await BleakScanner.discover(timeout=timeout)
        for d in devices:
            if d.name == self.device_name:
                log(f"Found device: {d.name} ({d.address})")
                self._device_address = d.address
                return d.address
        log(f"Device '{self.device_name}' not found")
        return None

    async def connect(self) -> bool:
        """Connect to the BLE device."""
        if self._device_address is None:
            addr = await self.find_device()
            if addr is None:
                return False
        else:
            addr = self._device_address

        try:
            self.client = BleakClient(
                addr,
                disconnected_callback=self._on_disconnect,
                timeout=15.0,
            )
            await self.client.connect()
            self.connected = True
            log(f"BLE connected to {addr}")
            return True
        except Exception as e:
            log(f"BLE connect failed: {e}")
            self.connected = False
            return False

    def _on_disconnect(self, client: BleakClient) -> None:
        """Called when BLE disconnects."""
        log("BLE disconnected")
        self.connected = False
        # Schedule reconnect in background
        if self._loop and not self._loop.is_closed():
            asyncio.run_coroutine_threadsafe(self._reconnect_loop(), self._loop)

    async def _reconnect_loop(self) -> None:
        """Keep trying to reconnect."""
        for attempt in range(1, 31):
            log(f"Reconnect attempt {attempt}/30...")
            if await self.connect():
                # Re-send current state after reconnection
                await self._send_ble(self.current_state)
                return
            await asyncio.sleep(2.0)
        log("Reconnect failed after 30 attempts, giving up")

    async def _send_ble(self, state: str) -> bool:
        """Write state command to BLE UART."""
        if not self.connected or self.client is None:
            log(f"Not connected, queuing state: {state}")
            return False

        payload = f"STATE:{state}\n".encode("utf-8")
        try:
            await self.client.write_gatt_char(NUS_RX_CHAR_UUID, payload)
            log(f"Sent STATE:{state} via BLE")
            return True
        except Exception as e:
            log(f"BLE write failed: {e}")
            self.connected = False
            return False

    async def set_state(self, state: str) -> bool:
        """Set LED state with 50ms debounce."""
        if state not in VALID_STATES:
            log(f"Invalid state: {state}")
            return False

        self.current_state = state

        async with self._lock:
            self._pending_state = state

            # Reset debounce timer
            if self._debounce_timer is not None:
                self._debounce_timer.cancel()

            self._debounce_timer = self._loop.call_later(
                DEBOUNCE_MS, lambda: asyncio.ensure_future(self._flush_pending())
            )

        return True

    async def _flush_pending(self) -> None:
        """Send the pending state after debounce window."""
        async with self._lock:
            state = self._pending_state
            self._pending_state = None

        if state is not None:
            await self._send_ble(state)

    def get_status(self) -> dict:
        """Return current status."""
        return {
            "connected": self.connected,
            "state": self.current_state,
            "device": self.device_name,
            "address": self._device_address,
        }


# ---------------------------------------------------------------------------
# HTTP Handler
# ---------------------------------------------------------------------------

class DaemonHandler(BaseHTTPRequestHandler):
    """HTTP request handler for hook scripts."""

    ble_manager: BLEManager  # set by main()

    def do_GET(self) -> None:
        path = self.path.rstrip("/")

        # GET /state/{state}
        if path.startswith("/state/"):
            state = path[7:].strip().lower()
            if state not in VALID_STATES:
                self._json_response(400, {"ok": False, "error": f"invalid state: {state}"})
                return

            # Schedule state change in the asyncio event loop
            future = asyncio.run_coroutine_threadsafe(
                self.ble_manager.set_state(state), self.ble_manager._loop
            )
            try:
                future.result(timeout=1.0)
            except Exception as e:
                self._json_response(500, {"ok": False, "error": str(e)})
                return

            self._json_response(200, {"ok": True, "state": state})
            return

        # GET /status
        if path == "/status":
            self._json_response(200, self.ble_manager.get_status())
            return

        # GET /ping
        if path == "/ping":
            self._json_response(200, {"ok": True})
            return

        # Unknown path
        self._json_response(404, {"ok": False, "error": "not found"})

    def log_message(self, format, *args) -> None:
        # Suppress default HTTP access logs (use our own log)
        pass

    def _json_response(self, code: int, data: dict) -> None:
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run_http_server(ble_manager: BLEManager, port: int) -> None:
    """Run HTTP server in a background thread."""
    DaemonHandler.ble_manager = ble_manager
    server = HTTPServer(("127.0.0.1", port), DaemonHandler)
    log(f"HTTP server listening on http://127.0.0.1:{port}")
    server.serve_forever()


async def async_main(args: argparse.Namespace) -> int:
    device_name = os.environ.get("CLAUDE_RGB_BLE_NAME", args.device)
    http_port = int(os.environ.get("CLAUDE_RGB_BLE_PORT", args.port))

    ble_manager = BLEManager(device_name)
    ble_manager._loop = asyncio.get_event_loop()

    # --scan mode
    if args.scan:
        print("Scanning BLE devices...")
        devices = await ble_manager.scan(timeout=10.0)
        if not devices:
            print("No BLE devices found.")
            return 0
        for d in devices:
            marker = " <-- target" if d["name"] == device_name else ""
            print(f"  {d['name']:30s} {d['address']}{marker}")
        return 0

    # Start HTTP server in background thread
    http_thread = threading.Thread(
        target=run_http_server, args=(ble_manager, http_port), daemon=True
    )
    http_thread.start()

    # Connect to BLE device
    log(f"Connecting to '{device_name}'...")
    if not await ble_manager.connect():
        log("Initial connection failed, will retry...")
        # Don't exit — HTTP server is up, reconnect will happen in background

    log(f"Daemon ready. Hook URL: http://127.0.0.1:{http_port}/state/<state>")
    log("Press Ctrl+C to stop")

    # Keep running
    try:
        while True:
            await asyncio.sleep(1.0)
    except (KeyboardInterrupt, SystemExit):
        log("Shutting down...")

    if ble_manager.client and ble_manager.connected:
        await ble_manager.client.disconnect()

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Claude RGB BLE Daemon")
    parser.add_argument(
        "--device", default=DEFAULT_DEVICE_NAME,
        help=f"BLE device name (default: {DEFAULT_DEVICE_NAME})",
    )
    parser.add_argument(
        "--port", type=int, default=DEFAULT_HTTP_PORT,
        help=f"HTTP server port (default: {DEFAULT_HTTP_PORT})",
    )
    parser.add_argument(
        "--scan", action="store_true",
        help="Scan for BLE devices and exit",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return asyncio.run(async_main(args))


if __name__ == "__main__":
    raise SystemExit(main())
