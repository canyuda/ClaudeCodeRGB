# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ESP32-C3 SuperMini + RGB LED module (common cathode) status light for Claude Code. The hardware displays different colors/blink patterns based on Claude Code's state (idle, running, tool use, ask, error, done).

## Architecture

```
Claude Code Hooks → Python script (serial) → ESP32-C3 → RGB LED
```

Three layers:

1. **Arduino firmware** (`claude_rgb.ino`) — Runs on ESP32-C3, listens on serial for `STATE:xxx` commands, controls RGB via GPIO2/3/4. Common cathode logic: HIGH = on, LOW = off.

2. **Python hook** (`claude_rgb_hook.py`) — Claude Code hook script. Reads JSON from stdin, maps hook events to LED states, writes to serial. Platform-specific implementations:
   - **POSIX** (macOS/Linux): Uses `termios` for serial communication
   - **Windows**: Uses `ctypes` (kernel32.dll) for serial communication — no pip dependencies on either platform

3. **Install scripts** — Platform-specific one-click deployment:
   - `install.sh` — Bash script for macOS, Linux, and Windows (Git Bash / MSYS)
   - `install.ps1` — PowerShell script for native Windows deployment

## Key Files

- `claude_rgb.ino` — Arduino firmware, burn via Arduino IDE
- `claude_rgb_hook.py` — Python hook script (cross-platform: macOS / Linux / Windows)
- `claude_settings.json` — Reference Claude Code hooks config
- `install.sh` — One-click deployment script for macOS / Linux / Git Bash
- `install.ps1` — One-click deployment script for Windows (PowerShell)
- `为什么选择ESP32-C3 SuperMini.md` — Hardware selection rationale

## LED State Mapping

| Hook Event | State | LED Effect |
|---|---|---|
| SessionStart / SessionEnd | idle | Green steady |
| UserPromptSubmit | running | Blue slow blink (500ms) |
| PreToolUse | tool | Purple fast blink (150ms) |
| PermissionRequest / Notification(ask) | ask | Yellow fast blink (250ms) |
| PostToolUseFailure / PermissionDenied | error | Red fast blink (100ms) |
| Stop | done | Green steady |

## Commands

### macOS / Linux / Git Bash

```bash
# Deploy to current project (writes .claude/settings.local.json)
./install.sh

# Deploy to user-level (writes ~/.claude/settings.json)
./install.sh --user

# Test hook manually
~/.claude/hooks/claude_rgb_hook.py running
~/.claude/hooks/claude_rgb_hook.py --scan

# Simulate hook JSON input
echo '{"hook_event_name":"UserPromptSubmit"}' | ~/.claude/hooks/claude_rgb_hook.py
```

### Windows (PowerShell)

```powershell
# Deploy to current project
.\install.ps1

# Deploy to user-level
.\install.ps1 -User

# Test hook manually
python $HOME\.claude\hooks\claude_rgb_hook.py running
python $HOME\.claude\hooks\claude_rgb_hook.py --scan

# Simulate hook JSON input
echo '{"hook_event_name":"UserPromptSubmit"}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

## Hardware

- ESP32-C3 SuperMini: R → GPIO2, G → GPIO3, B → GPIO4, GND → GND
- Serial baud: 115200
- Power: USB Type-C from computer

## Constraints

- `install.sh` must work with bash 3.2 (macOS default) — no `declare -A`, no associative arrays
- Python hook uses only stdlib on all platforms:
  - POSIX: `termios`, `json`, `argparse`, `glob`, `os`, `sys`, `time`
  - Windows: `ctypes`, `winreg`, `json`, `argparse`, `os`, `sys`, `time`
  - No pip dependencies on any platform
- `install.sh` is fully self-contained: the Python hook is embedded, no external file references needed at deploy time
- `install.ps1` uses Python for JSON merge (no external dependencies)
- Hook command path differs by platform and scope:
  - POSIX project: `.claude/hooks/claude_rgb_hook.py`
  - POSIX user: `$HOME/.claude/hooks/claude_rgb_hook.py`
  - Windows project: `python .claude/hooks/claude_rgb_hook.py`
  - Windows user: `python $HOME/.claude/hooks/claude_rgb_hook.py`
