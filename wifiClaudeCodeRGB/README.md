# WiFi 版 Claude Code RGB 状态灯

ESP32-C3 SuperMini + RGB LED 无线版本。ESP32 通过 WiFi HTTP API 接收灯光状态指令，支持 WiFi Manager 配网门户，充电宝供电。

## 架构

```
Claude Code Hooks → Python hook (HTTP) → WiFi → ESP32-C3 (HTTP Server) → RGB LED
```

## 与串口版的区别

| 特性 | 串口版 | WiFi 版 |
|------|--------|---------|
| 连接方式 | USB 串口 | WiFi (HTTP API) |
| 供电 | 电脑 USB | 充电宝 / 任意 USB 电源 |
| 通信距离 | USB 线长度 | WiFi 覆盖范围（约 10-20m 室内） |
| 配网 | 无需 | WiFi Manager（手机浏览器配网） |
| 依赖 | 零（纯 stdlib） | 零（纯 stdlib，http.client） |
| 串口兼容 | — | auto 模式自动回退串口 |

## 快速开始

### 1. 烧录固件

Arduino IDE 打开 `claude_rgb_wifi.ino`，烧录到 ESP32-C3 SuperMini。

接线：R → GPIO2, G → GPIO3, B → GPIO4, GND → GND

### 2. 首次配网

1. ESP32 上电（充电宝 USB）
2. 手机 WiFi 搜索 **"ClaudeRGB"** 热点并连接（密码：`12345678`）
3. 浏览器自动弹出配网页面（或手动访问 `http://192.168.4.1`）
4. 选择你家 WiFi，输入密码，点击 Connect
5. ESP32 自动重启并连接家庭 WiFi
6. 串口监视器打印分配的 IP 地址

### 3. 部署 Hook

```bash
# macOS / Linux / Git Bash
./install.sh              # 部署到当前项目
./install.sh --user       # 部署到用户级配置

# Windows PowerShell
.\install.ps1             # 部署到当前项目
.\install.ps1 -User       # 部署到用户级配置
```

部署脚本会：
- 复制 `claude_rgb_wifi_hook.py` 到 `.claude/hooks/`
- 交互式输入 ESP32 IP 地址
- 自动合并 hooks 配置到 settings.json

### 4. 验证

```bash
# 查询 ESP32 状态
python3 claude_rgb_wifi_hook.py --host <ESP32_IP> --status

# 手动设置状态
python3 claude_rgb_wifi_hook.py --host <ESP32_IP> running
python3 claude_rgb_wifi_hook.py --host <ESP32_IP> error

# 模拟 hook 输入
echo '{"hook_event_name":"UserPromptSubmit"}' | python3 claude_rgb_wifi_hook.py
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `claude_rgb_wifi.ino` | ESP32 固件（Arduino），WiFi AP/STA + HTTP Server |
| `claude_rgb_wifi_hook.py` | Python hook 脚本，HTTP 优先 + 串口回退 |
| `claude_wifi_settings.json` | Hooks 配置参考（部署脚本自动生成） |
| `install.sh` | 一键部署脚本（macOS / Linux / Git Bash） |
| `install.ps1` | 一键部署脚本（Windows PowerShell） |
| `README.md` | 本文件 |

## HTTP API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/state/{state}` | 设置灯光状态 |
| GET | `/status` | 查询当前状态、IP、工作模式 |
| GET | `/ping` | 心跳检测 |
| GET | `/wifiscan` | 扫描周围 WiFi |
| POST | `/wificfg` | 配置 WiFi（JSON body） |
| GET | `/` | AP 模式返回配网页面，STA 模式返回控制页面 |
| GET | `/wifisetup` | 始终返回配网页面 |

### 示例

```bash
# 设置状态
curl http://192.168.1.100/state/running    # 蓝灯慢闪
curl http://192.168.1.100/state/tool       # 紫灯快闪
curl http://192.168.1.100/state/error      # 红灯快闪
curl http://192.168.1.100/state/idle       # 绿灯常亮

# 查询状态
curl http://192.168.1.100/status
# {"state":"idle","ip":"192.168.1.100","mode":"STA"}

# 配网（AP 模式下）
curl -X POST http://192.168.4.1/wificfg \
  -H 'Content-Type: application/json' \
  -d '{"ssid":"MyWiFi","pass":"MyPassword"}'
```

## 串口命令

WiFi 版保留全部串口命令，并新增 WiFi 管理命令：

```
STATE:idle|done|running|tool|ask|error   # 设置灯光状态
WIFICONFIG:SSID:PASSWORD                 # 通过串口配网
WIFICLEAR                                 # 清除 WiFi 配置，重启后进入配网模式
WIFIDIAG                                  # WiFi 诊断（扫描周围网络）
PING                                      # 心跳
HELP                                      # 帮助
```

## LED 状态

| 状态 | 颜色 | 闪烁 | 含义 |
|------|------|------|------|
| idle | 绿 | 常亮 | 空闲 / 完成 |
| running | 蓝 | 慢闪 500ms | Claude 正在思考 |
| tool | 紫 | 快闪 150ms | 工具调用中 |
| ask | 黄 | 快闪 250ms | 等待用户确认 |
| error | 红 | 快闪 100ms | 出错 |
| wifi_config | 蓝 | 慢闪 1s | AP 配网模式 |
| wifi_connecting | 蓝 | 快闪 200ms | 正在连接 WiFi |

## Python Hook

```bash
# auto 模式（HTTP 优先，失败回退串口）
python3 claude_rgb_wifi_hook.py running

# 仅 HTTP
python3 claude_rgb_wifi_hook.py --mode http running

# 仅串口（与原版完全兼容）
python3 claude_rgb_wifi_hook.py --mode serial running

# 指定 ESP32 IP
python3 claude_rgb_wifi_hook.py --host 192.168.1.100 running

# 查询状态
python3 claude_rgb_wifi_hook.py --status
```

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CLAUDE_RGB_HOST` | `192.168.4.1` | ESP32 IP 地址 |
| `CLAUDE_RGB_MODE` | `auto` | 通信模式：auto / http / serial |
| `CLAUDE_RGB_PORT` | (自动检测) | 串口回退端口 |
| `CLAUDE_RGB_LOG` | (空) | 日志文件路径 |

## 重新配网

1. 串口发送 `WIFICLEAR`，ESP32 重启后进入配网模式
2. STA 模式下浏览器访问 ESP32 IP，点击 "WiFi Settings"
3. 烧录固件时擦除 Flash

## Web 控制页面

STA 模式下浏览器访问 ESP32 IP 可看到控制页面，提供 6 个状态按钮和 WiFi 设置入口。

## 硬件

- ESP32-C3 SuperMini
- 共阴极 4P RGB 模块：R → GPIO2, G → GPIO3, B → GPIO4, GND → GND
- 供电：充电宝 USB 或任意 5V USB 电源
- 串口波特率：115200
