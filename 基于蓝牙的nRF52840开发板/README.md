# Claude Code RGB Status Light — nRF52840 BLE 版

基于 **Seeed Studio XIAO nRF52840** 开发板，通过 BLE（蓝牙低功耗）无线控制内置 RGB LED，实时显示 Claude Code 工作状态。

## 硬件

只需要：
- **Seeed Studio XIAO nRF52840**（或 Sense 版本）× 1
- USB Type-C 数据线 × 1

无需外接 RGB LED 模块，开发板自带 3-in-1 RGB LED。

### 内置 LED 规格

| LED | Arduino 名称 | 逻辑 |
|---|---|---|
| Red | `LED_RED` (Pin 11) | LOW = 亮, HIGH = 灭 |
| Green | `LED_GREEN` (Pin 13) | LOW = 亮, HIGH = 灭 |
| Blue | `LED_BLUE` (Pin 12) | LOW = 亮, HIGH = 灭 |

共阳极，与 ESP32-C3 外接模块的共阴极逻辑相反。

## 架构

```
Claude Code Hooks → Hook 脚本 (HTTP, ~5ms) → 守护进程 (BLE 长连接) → nRF52840 内置 RGB
```

三层设计：

1. **Arduino 固件** (`claude_rgb_ble.ino`) — 运行在 nRF52840 上，通过 BLE UART (NUS) 接收 `STATE:xxx` 命令
2. **BLE 守护进程** (`claude_rgb_ble_daemon.py`) — 后台维持 BLE 长连接，提供 HTTP 接口，50ms 防抖
3. **Hook 脚本** (`claude_rgb_ble_hook.py`) — Claude Code 调用，HTTP 请求守护进程，零依赖

### 为什么需要守护进程？

BLE 连接建立需要 1-3 秒，而 Claude Code hook 超时只有 2 秒。守护进程维持 BLE 长连接后，hook 只需 HTTP 调用（~5ms），不会超时。

### 状态映射

| Claude Code 状态 | LED 效果 |
|---|---|
| idle / done | 🟢 绿色常亮 |
| running | 🔵 蓝色慢闪 (500ms) |
| tool use | 🟣 紫色快闪 (150ms) |
| ask / permission | 🟡 黄色快闪 (250ms) |
| error | 🔴 红色快闪 (100ms) |

## 快速开始

### Step 1: 烧录固件

1. 打开 Arduino IDE
2. **File → Preferences** → Additional Boards Manager URLs 添加：
   ```
   https://files.seeedstudio.com/arduino/package_seeeduino_boards_index.json
   ```
3. **Tools → Board → Boards Manager** → 搜索 `seeed nrf52` → 安装 **Seeed nRF52 Boards**
4. **Tools → Board** → 选择 `Seeed XIAO nRF52840`（或 Sense 版本）
5. 打开 `claude_rgb_ble.ino`，点击 Upload
6. 烧录成功后，开发板上电自检（红→绿→蓝闪烁），然后绿灯常亮

### Step 2: 安装依赖

```bash
pip3 install bleak
```

### Step 3: 运行安装脚本

```bash
cd 基于蓝牙的nRF52840开发板
chmod +x install.sh
./install.sh           # 部署到当前项目
# 或
./install.sh --user    # 部署到用户级别
```

安装脚本会：
- 部署守护进程和 hook 脚本到 `~/.claude/hooks/`
- 配置 macOS launchd 开机自启动
- 写入 Claude Code hooks 配置

### Step 4: 验证

```bash
# 扫描 BLE 设备（确认开发板在广播）
python3 ~/.claude/hooks/claude_rgb_ble_daemon.py --scan

# 检查守护进程状态
curl http://localhost:19740/status

# 手动测试
python3 ~/.claude/hooks/claude_rgb_ble_hook.py running
```

## 手动操作

### 启动守护进程

```bash
# 前台运行（可看日志）
python3 ~/.claude/hooks/claude_rgb_ble_daemon.py

# 后台运行
nohup python3 ~/.claude/hooks/claude_rgb_ble_daemon.py &

# 通过 launchd（macOS 开机自启）
launchctl load ~/Library/LaunchAgents/com.claude.rgb-ble-daemon.plist
```

### 停止守护进程

```bash
# 如果用 launchd
launchctl unload ~/Library/LaunchAgents/com.claude.rgb-ble-daemon.plist

# 如果后台运行
pkill -f claude_rgb_ble_daemon
```

### 查看日志

```bash
# launchd 日志
cat /tmp/claude_rgb_ble_daemon.log
cat /tmp/claude_rgb_ble_daemon.err

# 自定义日志路径
CLAUDE_RGB_BLE_LOG=/tmp/rgb_daemon.log python3 claude_rgb_ble_daemon.py
```

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `CLAUDE_RGB_BLE_NAME` | `ClaudeRGB-nRF52840` | BLE 设备名 |
| `CLAUDE_RGB_BLE_PORT` | `19740` | 守护进程 HTTP 端口 |
| `CLAUDE_RGB_BLE_LOG` | (空) | 守护进程日志文件路径 |

## BLE 连接说明

BLE 不需要 macOS 系统蓝牙配对。守护进程通过 bleak 库直接建立应用层连接。

**首次运行注意：**
- macOS 可能弹窗"允许访问蓝牙" → 点击**允许**
- 如果没弹窗但扫描不到：系统设置 → 隐私与安全 → 蓝牙 → 给终端/Python 勾选

**连接流程：**
1. nRF52840 通电 → 自动 BLE 广播
2. 守护进程启动 → 扫描 → 发现设备 → 自动连接
3. 连接成功 → LED 可以被控制
4. 断连后 → 守护进程自动重连（最多 30 次）

## 用手机调试

可以用 **nRF Connect** 手机 App 验证固件：

1. 打开 nRF Connect → Scan
2. 找到 `ClaudeRGB-nRF52840` → Connect
3. 找到 Nordic UART Service (UUID `6E400001-...`)
4. 向 RX Characteristic 写入 `STATE:running`
5. 观察 LED 变蓝色闪烁

## 故障排查

| 问题 | 解决 |
|---|---|
| 守护进程扫描不到设备 | 检查开发板是否通电、固件是否烧录成功 |
| HTTP 请求失败 | 检查守护进程是否运行：`curl localhost:19740/ping` |
| BLE 连接断开 | 守护进程自动重连，无需手动干预 |
| LED 不亮但连接成功 | 检查是否选对了板卡包（Seeed nRF52 Boards） |
| launchd 不自启 | `launchctl list \| grep claude` 查看状态 |

## 文件说明

```
基于蓝牙的nRF52840开发板/
├── claude_rgb_ble.ino              # Arduino 固件（烧录到 nRF52840）
├── claude_rgb_ble_daemon.py        # BLE 守护进程（后台运行）
├── claude_rgb_ble_hook.py          # Claude Code hook 脚本
├── com.claude.rgb-ble-daemon.plist # macOS launchd 自启动配置
├── install.sh                      # 一键安装脚本
├── README.md                       # 本文件
├── XIAO_nRF52840.md               # 开发板参考资料
└── XIAO_nRF52840_back_pinout.png  # 引脚图
```
