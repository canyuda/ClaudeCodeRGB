# ClaudeCodeRGB

基于 ESP32C3 Super Mini + RGB 灯模块(共阴) 实现的Claude Code指示灯系统。

## 成果展示

<table>
  <tr>
    <td align="center">
      <b>🟢 绿灯 — idle / done</b><br><br>
      <img src="./result/绿灯.jpg" width="300" />
    </td>
    <td align="center">
      <b>🔴 红灯 — error</b><br><br>
      <img src="./result/红灯.gif" width="300" />
    </td>
  </tr>
  <tr>
    <td align="center">
      <b>🟡 黄灯 — ask</b><br><br>
      <img src="./result/黄灯.gif" width="300" />
    </td>
    <td align="center">
      <b>🔵➡️🟣➡️🔵 蓝转紫转蓝 — running → tool → running</b><br><br>
      <img src="./result/蓝转紫转蓝灯.gif" width="300" />
    </td>
  </tr>
</table>

---

## 软硬件环境

### 电脑

| 项目 | 说明 |
|------|------|
| 系统 | macOS / Linux / Windows |

### 软件

| 名称 | 作用 | 版本 | 收费 | 下载地址 |
|------|------|------|------|----------|
| Arduino IDE | 烧录程序 | 2.3.9 | 免费 | [官网下载](https://www.arduino.cc/en/software/) |
| Python 3 | Hook 脚本运行环境 | ≥ 3.8 | 免费 | [官网下载](https://www.python.org/downloads/) |

<details>
<summary>📷 查看截图</summary>

![下载烧录程序](./images/下载烧录程序.png)

</details>

### 硬件

| # | 名称 | 价格 | 购买地址 | 备注 |
|---|------|------|----------|------|
| 1 | Type-C 数据线 | 2.13 元 | [淘宝链接](https://item.taobao.com/item.htm?id=734206474044&mi_id=0000z-VobxuyIgyOhcNoR8ovWlwF-aQOBVOH6uVJRoKuDAI&skuId=5247366846668&spm=tbpc.boughtlist.suborder_itemtitle.1.599f2e8dgGGenX) | 已有 Type-C 线可不买 |
| 2 | ESP32C3 SuperMini 模块 | 10 元 | [天猫链接](https://detail.tmall.com/item.htm?id=792938098209&mi_id=0000tlEOX1sNYD7-LX3Et2qIvKGHNW8g_uO0WJHa-kg8uhA&skuId=5584672027421&spm=tbpc.boughtlist.suborder_itemtitle.1.599f2e8dgGGenX) | 动手能力强可买不焊接版，便宜 5 毛钱 |
| 3 | 电子积木全彩 RGB 模块(共阴配4P线) | 11.87 元 | [天猫链接](https://detail.tmall.com/item.htm?id=610156877546&mi_id=0000UlnE1-fWWXJaWEfJdVGbDJ5KWKxlMBt6mbrLw2hD78&skuId=5924593772549&spm=tbpc.boughtlist.suborder_itemtitle.1.599f2e8dgGGenX) | 可买不带壳版；自带杜邦线最低 2.07 元 |
| 4 | 杜邦线 × 4 | — | — | 购买带线版 RGB 模块则无需准备 |

#### 硬件图片

<details>
<summary>📷 Type-C 数据线</summary>

![烧录线](./images/烧录线.jpg)

</details>

<details>
<summary>📷 ESP32C3 SuperMini 模块</summary>

![ESP32-C3开发板SuperMini](./images/ESP32-C3开发板SuperMini.jpg)

</details>

<details>
<summary>📷 RGB 灯模块</summary>

![RGB灯模块](./images/RGB灯模块.jpg)

</details>

## 具体实现

### 接线

![接线图.png](./images/接线图.png)

#### 接线表

| RGB 模块 | ESP32-C3 SuperMini |
| ------ | ------------------ |
| R      | GPIO2              |
| G      | GPIO3              |
| B      | GPIO4              |
| GND    | GND                |

#### 最终接线

```txt
电脑  --> USB线 --> 开发板 --> RGB灯模块
```

### Arduino IDE烧录

#### 烧录前的准备

1. 通过USB Type-C数据线将ESP32C3SuperMini连接到计算机
2. 启动 Arduino 应用程序
3. 将 ESP32 板包添加到 Arduino IDE
   1. 导航到File > Preferences ，然后使用以下 url 填写"Additional Boards Manager URL" ：`https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   2. 等待下载
   3. 导航到 Tools > Board > Boards Manager...，在搜索框中输入关键字 "esp32"，选择最新版本的 ESP32 并安装。![esp32c3烧录准备](./images/esp32c3烧录准备.png)
   4. 等待安装
   5. 选择开发板: ![选择开发板](./images/烧录准备-2.png)
   6. 选择开发板: ![选择esp32c3 dev module](./images/烧录准备-3.png)

#### 编码

此部分由 Claude Code 实现

| 状态名       | 指令          | 灯效       |
| --------- | ----------- | -------- |
| `idle`    | 空闲          | 绿色常亮       |
| `running` | Claude 正在运行 | 蓝色慢闪     |
| `tool`    | 正在调用工具      | 紫色快闪     |
| `ask`     | 等待用户输入 / 权限 | 黄色快闪     |
| `done`    | 运行完成        | 绿色常亮  |
| `error`   | 出错          | 红色快闪     |

完整源码见 [`claude_rgb.ino`](./claude_rgb.ino)

#### 烧录与调试

> Q1 Arduino上无法识别Com口 进入下载模式：
> 方式1：按住BOOT上电。
> 方式2：按住ESP32C3的BOOT按键，然后按下RESET按键，松开RESET按键，再松开BOOT按键，此时ESP32C3会进入下载模式。（每次连接都需要重新进入下载模式，有时按一遍，端口不稳定会断开，可以通过端口识别声音来判断）
>
> Q2：上传之后程序无法运行。上传成功后需要按一下 Reset 按键，程序才会执行。
>
> Q3：ESP32-C3 SuperMini Arduino 串口无法打印。需要将工具栏中 "USB CDC On Boot" 设置成 "Enabled"。

##### 验证

![验证](./images/验证.png)

##### 写入

![写入](./images/写入.png)

##### Arduino IDE 中测试

> 确保写入完成

按下 Reset 键（程序内置上电自检逻辑：红灯闪烁一次 → 绿灯闪烁一次 → 蓝灯闪烁一次 → 绿灯常亮）

| 问题          | 处理                             |
| ----------- | ------------------------------ |
| RGB 完全不亮    | 检查 GND 是否接到共阴极公共脚              |
| 颜色错乱        | R/G/B 线接反，换线或改代码 pin           |
| 上传后串口消失     | 确认 `USB CDC On Boot = Enabled` |
| 一运行就 USB 断开 | 电源、USB 线、外设短路优先排查              |

打开 Arduino IDE 的 Serial Monitor：

输入：
```
PING
```

正常返回：
```
PONG STATE:idle
```

测试状态：
```
STATE:running
```

预期：蓝灯慢闪。

继续测试：
```
STATE:tool
STATE:ask
STATE:error
STATE:done
STATE:idle
```

对应：

|输入|预期灯效|
|---|---|
|`STATE:running`|蓝灯慢闪|
|`STATE:tool`|紫灯快闪|
|`STATE:ask`|黄灯快闪|
|`STATE:error`|红灯快闪|
|`STATE:done`|绿灯常亮|
|`STATE:idle`|绿灯常亮|

##### 终端中测试

> 测试前先关闭 Arduino IDE 的串口监视器，否则 Python 或 shell 可能无法占用串口。

**macOS / Linux** — 查询串口：

```bash
find /dev \
  \( -name 'cu.usbmodem*' \
  -o -name 'cu.usbserial*' \
  -o -name 'cu.wchusbserial*' \
  -o -name 'cu.SLAB_USBtoUART*' \) \
  -maxdepth 1
```

返回(这里你的电脑可能会不一样):

```bash
/dev/cu.usbmodem1201
```

执行命令：

```bash
printf 'STATE:running\n' > /dev/cu.usbmodem1201
```

分别执行命令：

```bash
printf 'STATE:tool\n' > /dev/cu.usbmodem1201
printf 'STATE:ask\n' > /dev/cu.usbmodem1201
printf 'STATE:error\n' > /dev/cu.usbmodem1201
printf 'STATE:done\n' > /dev/cu.usbmodem1201
```

**Windows (PowerShell)** — 查询串口：

```powershell
# Method 1: WMI query
Get-CimInstance Win32_SerialPort | Select-Object DeviceID, Description

# Method 2: .NET API
[System.IO.Ports.SerialPort]::GetPortNames()
```

返回（你的电脑可能会不一样）：

```
COM3
```

执行命令（需要安装 Python）：

```powershell
# Install Python first, then use the hook script to test
python claude_rgb_hook.py --port COM3 running
```

### Python脚本

#### 编码

> 在`~/.claude/hooks/`目录创建 `claude_rgb_hook.py` 文件

> 此部分也由 Claude Code 实现，以下是示例

完整源码见 [`claude_rgb_hook.py`](./claude_rgb_hook.py)

> **跨平台支持**：Python 脚本同时支持 macOS / Linux / Windows，无需安装任何 pip 依赖。
> - macOS / Linux 使用 `termios` 进行串口通信
> - Windows 使用 `ctypes`（调用 kernel32.dll）进行串口通信

#### 测试

##### 赋权（仅 macOS / Linux）

```bash
chmod +x ~/.claude/hooks/claude_rgb_hook.py
```

##### 扫描串口

**macOS / Linux：**

```bash
~/.claude/hooks/claude_rgb_hook.py --scan
```

**Windows (PowerShell)：**

```powershell
python $HOME\.claude\hooks\claude_rgb_hook.py --scan
```

返回
> 这里可能返回其他串口, 请注意：

```bash
/dev/cu.usbmodem1201   # macOS / Linux
COM3                    # Windows
```

设置环境变量

**macOS / Linux：**

```bash
export CLAUDE_RGB_PORT=/dev/cu.usbmodem1201
```

**Windows (PowerShell)：**

```powershell
$env:CLAUDE_RGB_PORT = "COM3"
```

可选：打开日志。

**macOS / Linux：**

```bash
export CLAUDE_RGB_LOG=$HOME/.claude/logs/rgb-hook.log
```

**Windows (PowerShell)：**

```powershell
$env:CLAUDE_RGB_LOG = "$HOME\.claude\logs\rgb-hook.log"
```

手动测试状态

**macOS / Linux：**

```bash
~/.claude/hooks/claude_rgb_hook.py running
```

**Windows (PowerShell)：**

```powershell
python $HOME\.claude\hooks\claude_rgb_hook.py running
```

预期：蓝灯慢闪。

继续测试：

```bash
# macOS / Linux
~/.claude/hooks/claude_rgb_hook.py tool
~/.claude/hooks/claude_rgb_hook.py ask
~/.claude/hooks/claude_rgb_hook.py error
~/.claude/hooks/claude_rgb_hook.py done
~/.claude/hooks/claude_rgb_hook.py idle
```

```powershell
# Windows (PowerShell)
python $HOME\.claude\hooks\claude_rgb_hook.py tool
python $HOME\.claude\hooks\claude_rgb_hook.py ask
python $HOME\.claude\hooks\claude_rgb_hook.py error
python $HOME\.claude\hooks\claude_rgb_hook.py done
python $HOME\.claude\hooks\claude_rgb_hook.py idle
```

###### 测试 Hook JSON 输入

> 模拟 Claude Code 的 UserPromptSubmit：

**macOS / Linux：**

```bash
echo '{"hook_event_name":"UserPromptSubmit","prompt":"test"}' \
  | ~/.claude/hooks/claude_rgb_hook.py
```

**Windows (PowerShell)：**

```powershell
'{"hook_event_name":"UserPromptSubmit","prompt":"test"}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

预期：蓝灯慢闪。

> 模拟工具调用：

**macOS / Linux：**

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | ~/.claude/hooks/claude_rgb_hook.py
```

**Windows (PowerShell)：**

```powershell
'{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

预期：紫灯快闪。

> 模拟等待权限：

**macOS / Linux：**

```bash
echo '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}' \
  | ~/.claude/hooks/claude_rgb_hook.py
```

**Windows (PowerShell)：**

```powershell
'{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission"}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

预期：黄灯快闪。

> 模拟任务完成：

**macOS / Linux：**

```bash
echo '{"hook_event_name":"Stop","last_assistant_message":"done"}' \
  | ~/.claude/hooks/claude_rgb_hook.py
```

**Windows (PowerShell)：**

```powershell
'{"hook_event_name":"Stop","last_assistant_message":"done"}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

预期：绿灯常亮。

> 模拟错误：

**macOS / Linux：**

```bash
echo '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"failed"}' \
  | ~/.claude/hooks/claude_rgb_hook.py
```

**Windows (PowerShell)：**

```powershell
'{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"failed"}' | python $HOME\.claude\hooks\claude_rgb_hook.py
```

预期：红灯快闪。

##### 查看日志

如果你设置了 CLAUDE_RGB_LOG：

**macOS / Linux：**

```bash
cat ~/.claude/logs/rgb-hook.log
```

**Windows (PowerShell)：**

```powershell
Get-Content $HOME\.claude\logs\rgb-hook.log
```

如果没有日志，确认目录位置：

```bash
# macOS / Linux
echo $CLAUDE_RGB_LOG
```

```powershell
# Windows (PowerShell)
echo $env:CLAUDE_RGB_LOG
```

### 一键部署

项目提供了一键部署脚本，自动完成 hook 脚本下载、环境变量配置、Claude Code settings 合并。

**前置条件**：已安装 `curl`（macOS/Linux 自带）和 `python3`。

```bash
# macOS / Linux / WSL2 — 部署到当前项目
curl -fsSL https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/install.sh | bash

# 部署到用户级（所有项目生效）
curl -fsSL https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/install.sh | bash -s -- --user
```

```powershell
# Windows (PowerShell) — 部署到当前项目
iwr -useb https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/install.ps1 | iex

# 部署到用户级（所有项目生效）
iwr -useb https://raw.githubusercontent.com/canyuda/ClaudeCodeRGB/main/install.ps1 -OutFile $env:TEMP\install_rgb.ps1; & $env:TEMP\install_rgb.ps1 -User
```

> Windows 如遇执行策略限制，先运行：
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

#### 脚本执行流程

1. **系统检测** — 检查操作系统及 Python 环境
2. **下载 hook 脚本** — 从 GitHub 仓库下载 `claude_rgb_hook.py` 到目标目录
3. **配置串口** — 自动扫描可用串口，交互式设置 `CLAUDE_RGB_PORT`（必填）
4. **配置日志** — 交互式设置 `CLAUDE_RGB_LOG`（可选，留空关闭日志）
5. **合并配置** — 将 hooks 和 env 写入 settings 文件，**不影响已有配置**

两种模式对比：

| | `./install.sh` 或 `.\install.ps1` | `--user` / `-User` |
|---|---|---|
| 配置文件 | `.claude/settings.local.json` | `~/.claude/settings.json` |
| hook 脚本 | `.claude/hooks/claude_rgb_hook.py` | `~/.claude/hooks/claude_rgb_hook.py` |
| 生效范围 | 当前项目 | 所有项目 |
| 是否进 git | ❌ 不提交 | — |

---

### 配置 Claude Code Hooks

> 如果你使用了一键部署脚本，可以跳过本节，脚本已自动完成配置。

Claude Code 的 user 级配置文件是：

**macOS / Linux：**

```bash
~/.claude/settings.json
```

**Windows：**

```powershell
$HOME\.claude\settings.json
```

官方文档说明：

- user settings 作用于所有项目
- project settings 放在项目里的 `.claude/settings.json`
- local settings 放在 `.claude/settings.local.json`

如果你希望所有项目都用这个 RGB 状态灯，编辑：

```bash
# macOS / Linux
nano ~/.claude/settings.json
```

```powershell
# Windows
notepad $HOME\.claude\settings.json
```

完整配置见 [`claude_settings.json`](./claude_settings.json)

> **Windows 注意事项**：`claude_settings.json` 中的 hook command 需要加 `python` 前缀：
> ```json
> "command": "python $HOME/.claude/hooks/claude_rgb_hook.py"
> ```

#### 测试Claude Code

##### 测试 `running`

在 Claude Code 输入一个简单任务：

```text
帮我列出当前目录下的文件
```

你应该看到：

```text
绿灯常亮 → 蓝灯慢闪
```

##### 测试 `tool`

让 Claude 执行工具，例如：

```text
运行 pwd
```

当 Claude 调用 Bash 前，应该短暂进入：

```text
紫灯快闪
```

工具完成后回到：

```text
蓝灯慢闪
```

##### 测试 `ask`

让 Claude 执行一个需要权限确认的命令，例如：

```text
运行 ls -la
```

如果 Claude Code 弹出权限确认，灯应该变成：

```text
黄灯快闪
```

官方文档说明 `PermissionRequest` 会在权限对话框即将展示时触发；`Notification` 的 `permission_prompt` 也用于 Claude 需要权限时通知。([Claude Code][1])

##### 测试 `done`

Claude 回复结束后，`Stop` 触发，灯应该变成：

```text
绿灯常亮
```

官方文档说明 `Stop` 在主 Claude Code agent 完成响应时运行。([Claude Code][1])

---

## 常见故障定位

### 问题 A：Arduino 串口监视器能控制灯，但 Python 不行

**macOS / Linux** — 检查 Python 是否可执行：

```bash
ls -l ~/.claude/hooks/claude_rgb_hook.py
```

应该看到有 `x` 权限。

没有就执行：

```bash
chmod +x ~/.claude/hooks/claude_rgb_hook.py
```

然后手动测试：

```bash
CLAUDE_RGB_PORT=/dev/cu.usbmodem1201 ~/.claude/hooks/claude_rgb_hook.py ask
```

**Windows** — 确认 Python 在 PATH 中：

```powershell
python --version
python $HOME\.claude\hooks\claude_rgb_hook.py --port COM3 ask
```

### 问题 B：Python 手动测试可以，但 Claude Code 不触发

检查配置：

```bash
# macOS / Linux
python3 -m json.tool ~/.claude/settings.json >/dev/null && echo "JSON OK"
```

```powershell
# Windows
python -m json.tool $HOME\.claude\settings.json
```

再进入 Claude Code：

```text
/hooks
```

确认相关事件确实显示了 hook。

### 问题 C：日志没有生成

先创建目录：

```bash
# macOS / Linux
mkdir -p ~/.claude/logs
```

```powershell
# Windows
New-Item -ItemType Directory -Path "$HOME\.claude\logs" -Force
```

然后手动运行：

```bash
# macOS / Linux
CLAUDE_RGB_PORT=/dev/cu.usbmodem1201 \
CLAUDE_RGB_LOG=$HOME/.claude/logs/rgb-hook.log \
~/.claude/hooks/claude_rgb_hook.py running
```

```powershell
# Windows
$env:CLAUDE_RGB_PORT = "COM3"
$env:CLAUDE_RGB_LOG = "$HOME\.claude\logs\rgb-hook.log"
python $HOME\.claude\hooks\claude_rgb_hook.py running
```

查看：

```bash
# macOS / Linux
cat ~/.claude/logs/rgb-hook.log
```

```powershell
# Windows
Get-Content $HOME\.claude\logs\rgb-hook.log
```

### 问题 D：串口被占用

关闭：

* Arduino IDE Serial Monitor
* 其他串口调试工具
* macOS / Linux：任何正在连接 `/dev/cu.usbmodem1201` 的程序
* Windows：任何正在连接 `COM3` 的程序

再测试：

```bash
# macOS / Linux
~/.claude/hooks/claude_rgb_hook.py done
```

```powershell
# Windows
python $HOME\.claude\hooks\claude_rgb_hook.py done
```

### 问题 E：灯效颜色不对

直接在 Arduino 串口监视器输入：

```text
STATE:error
```

如果不是红灯，说明 R/G/B 线接错。处理方式二选一：

1. 重新接线；
2. 修改代码里的 GPIO 定义：

```cpp
#define RED_PIN    2
#define GREEN_PIN  3
#define BLUE_PIN   4
```

### 问题 F：Windows 下 Python 提示 ModuleNotFoundError

确认 Python 版本 ≥ 3.8：

```powershell
python --version
```

脚本仅使用 Python 标准库，不需要安装任何 pip 包。如果仍有问题，请检查 Python 安装是否完整。

---

## 你最终应该得到的行为

```text
Claude Code 未运行 / 已完成
  → 绿灯常亮

你提交 prompt
  → 蓝灯慢闪

Claude 调用 Read / Bash / Edit / Write 等工具
  → 紫灯快闪

Claude 等你确认权限 / 等你输入
  → 黄灯快闪

Claude 工具执行失败 / StopFailure
  → 红灯快闪
```

配置里使用了 `"async": true`，官方文档说明异步 command hook 会在后台运行，Claude Code 不会等待 hook 完成；这正适合 RGB 状态灯这种副作用型集成。

---

## 功能列表

### ✅ 已实现

- [x] 点灯
- [x] 烧录程序
- [x] 对接 Claude Code，实现 CC 不同状态下的灯光变化（idle / running / tool / ask / done / error）
- [x] 跨平台支持（macOS / Linux / Windows）

### 🚧 暂未实现

- [ ] 3D 打印外壳（急需懂 3D 打印的同学帮助）
- [ ] 基于 WiFi 或蓝牙实现无线状态灯（使用充电宝供电）
- [ ] 焊接电池模块实现真正意义上的无线状态灯（产品化）

### 💡 可能的优化方案

1. **更轻量的硬件方案**：找一款更轻量级、更便宜的开发板，或者自己定制（本人不擅长硬件，急需懂硬件的同学帮助）
2. **产品分级**：
   - **A 档**：仅三色灯（有线）
   - **B 档**：三色灯 + 蜂鸣器（有线）
   - **C 档**：三色灯（WiFi 无线）
   - ...
