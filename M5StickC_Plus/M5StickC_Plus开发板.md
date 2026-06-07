# M5StickC Plus 开发板

**M5StickC Plus** 是一款基于 ESP32-PICO 的小型化 IoT 开发板，由 M5 Stack 出品。它将 ESP32 无线模块、显示屏、电池、IMU 传感器、按键、红外、麦克风、蜂鸣器等集成在一块火柴盒大小的 PCB 上，非常适合穿戴设备、便携终端、IoT 节点等场景。

## 核心规格

### SoC

| 参数 | 规格 |
|---|---|
| 芯片 | ESP32-PICO-D4（集成 ESP32 + 4MB PSRAM） |
| 处理器 | 双核 32-bit LX6 |
| 主频 | 240 MHz |
| Flash | 4MB（ESP32-PICO-D4 集成） |
| PSRAM | 4MB Octal SPI |
| 无线 | Wi-Fi 802.11 b/g/n（2.4 GHz）、Bluetooth 4.2（BR/EDR + BLE） |

### 存储

| 参数 | 规格 |
|---|---|
| 程序存储 | 4MB Flash |
| 数据/帧缓存 | 4MB PSRAM |

### 电源

| 参数 | 规格 |
|---|---|
| USB 供电 | 5V / Type-C |
| 内置电池 | 120 mAh 锂聚合物电池 |
| 工作电压 | 3.3V |
| 3.3V 引脚输出 | 最大 1000 mA |

## 板载外设

### 显示屏

| 参数 | 规格 |
|---|---|
| 类型 | ST7789v2 IPS LCD |
| 尺寸 | 1.14 英寸 |
| 分辨率 | 135 × 240 |
| 颜色 | 18-bit color（65K） |
| 接口 | SPI |
| 控制引脚 | CLK: GPIO18, MOSI: GPIO23, CS: GPIO5, RS(A0): GPIO22, RST: GPIO16, BL: GPIO15 |

### LED 与红外

| 外设 | 规格 |
|---|---|
| 红色 LED | GPIO2，共阳极（HIGH = 亮） |
| 红外发射器 | GPIO10，支持 NEC 协议 |

### 按键

| 按键 | 引脚 | 逻辑 |
|---|---|---|
| Power / Back | GPIO37 (IOX_P) | LOW = 按下 |
| Button A | GPIO37 (IOX_P) | LOW = 按下 |
| Button B | GPIO39 (IOX_N) | LOW = 按下 |

> **注意：** M5StickC Plus 使用 MCP23017 GPIO 扩展器（IOX）来控制 Power/Back、Button A 和 Button B，因此需要通过 M5Stack 库或 I2C 直接访问这些引脚。

### IMU 传感器

| 参数 | 规格 |
|---|---|
| 型号 | MPU-6886 |
| 功能 | 3 轴加速度计 + 3 轴陀螺仪（6 轴 IMU） |
| 接口 | I2C (默认地址: 0x68) |
| 默认 I2C 引脚 | SDA: GPIO32, SCL: GPIO33 |

### 其他

| 外设 | 规格 |
|---|---|
| 蜂鸣器 | 无源蜂鸣器（Buzzer），引脚 GPIO13（通过 M5 库控制） |
| 红外 | IR 发射器，支持 NEC 协议（通过 M5 库） |
| 麦克风 | 数字 MEMS 麦克风（通过 M5 库） |
| I2C 扩展口 | GROVE 接口（支持 I2C / UART） |
| 充电管理 | AXP192 PMU 芯片，支持 USB 充电和电池电量检测 |

## 物理尺寸与引脚

### 尺寸

- PCB 尺寸：约 48.7 mm × 52.6 mm × 16.2 mm（不含 protrusions）
- 重量：约 25 g（含电池）

### Grove 接口（4-pin JST 2.54mm）

| 引脚 | 信号 | 说明 |
|---|---|---|
| 1 | 3.3V | 3.3V 电源输出 |
| 2 | GND | 地 |
| 3 | RX2 / GPIO15 | UART TX（默认）或 PWM 背光 |
| 4 | TX2 / GPIO22 | UART RX（默认）或 I2C SDA |

> GROVE 接口支持 UART（默认）、I2C、GPIO 等模式，可通过代码重新配置。

### 底部金手指（Pogo Pin）

M5StickC Plus 底部提供 6 个 Pogo Pin 连接器，支持与 Base 模块堆叠：

| 引脚 | 默认功能 |
|---|---|
| V | 3.3V |
| A | GPIO34（ADC1_CH0） |
| B | GPIO32 |
| C | GPIO33（I2C SCL 默认） |
| D | GPIO25（I2C SDA 默认，或 PWM 输出） |
| E | GND |

## 开发环境

### Arduino IDE

1. 打开 **File → Preferences**，在 Additional Boards Manager URLs 添加：
   ```
   https://raw.githubusercontent.com/m5stack/M5Stack/master/package_m5stack_index.json
   ```
2. 打开 **Tools → Board → Boards Manager**，搜索 `m5stack`，安装 **M5Stack library package**
3. 选择 Board：`M5Stack-Camera` 或 `M5Stack-Pico`（ESP32 系列即可）
4. 配置参数：
   - Flash Mode: QIO
   - Flash Frequency: 80MHz
   - PSRAM: Enabled
   - Partition Scheme: Default 4MB with spiffs (1.2MB APP/1.5MB FS)

### PlatformIO

在 `platformio.ini` 中添加：

```ini
[env:m5stack-stick-c]
platform = espressif32
board = m5stack-stick-c
framework = arduino
```

## 快速示例：Arduino 点亮屏幕

```cpp
#include <M5StickCPlus.h>

void setup() {
    M5.begin();
    M5.Lcd.setRotation(3);
    M5.Lcd.fillScreen(BLACK);
    M5.Lcd.setTextColor(YELLOW);
    M5.Lcd.setTextSize(2);
    M5.Lcd.setCursor(20, 50);
    M5.Lcd.println("Hello, M5StickC Plus!");
}

void loop() {
    M5.update();
    if (M5.BtnA.wasPressed()) {
        M5.Lcd.fillScreen(RED);
    }
    if (M5.BtnB.wasPressed()) {
        M5.Lcd.fillScreen(BLUE);
    }
    delay(100);
}
```

## 典型应用场景

- **可穿戴设备** — 尺寸小巧，可固定在手臂、腕部
- **便携 IoT 终端** — 内置电池 + Wi-Fi/BLE，独立工作
- **遥控器 / 控制面板** — 屏幕 + 按键，本地交互
- **数据采集器** — IMU + Grove 接口，环境监测
- **开发板学习** — 低成本的 ESP32 入门平台

## 与 ESP32-C3 / nRF52840 对比

| 特性 | M5StickC Plus | ESP32-C3 SuperMini | XIAO nRF52840 |
|---|---|---|---|
| SoC | ESP32-PICO-D4 | ESP32-C3 | nRF52840 |
| CPU | Dual-core LX6 @ 240MHz | Single-core RISC-V @ 160MHz | ARM Cortex-M4 @ 64MHz |
| 无线 | Wi-Fi + BLE 4.2 | Wi-Fi + BLE 5.0 | BLE 5.0 |
| 内存 | 4MB Flash + 4MB PSRAM | 无内置 Flash* | 1MB Flash + 256KB RAM |
| 显示屏 | 1.14" 135×240 IPS | 无 | 无 |
| 电池 | 120 mAh 内置 | 无外接 | 无外接 |
| 尺寸 | 48.7 × 52.6 × 16.2 mm | 18 × 37 mm | 21 × 18 mm |
| IMU | MPU-6886（板载） | 无 | 无 |
| 按键 | 3 个（含 Power） | 1 个 BOOT | 1 个 RESET/USER |
| 开发难度 | 低（M5 库封装完善） | 低 | 低 |
| 价格 | ~¥60-80 | ~¥20-30 | ~¥60-90 |

> *ESP32-C3 外接 Flash 需自行焊接，SuperMini 模块自带 8MB SPI Flash。

## 购买渠道

- [M5Stack 官网](https://docs.m5stack.com/en/core/M5Stick_C_Plus)
- 淘宝 / 京东
- AliExpress（M5Stack 官方商店）

## 参考资源

- [M5StickC Plus 官方文档](https://docs.m5stack.com/en/core/M5Stick_C_Plus)
- [M5StickC Plus Pinout 图示](https://docs.m5stack.com/en/core/m5stickc_plus)
- [ESP32-PICO-D4 Datasheet](https://www.espressif.com/sites/default/files/documentation/esp32-pico-d4_datasheet_en.pdf)
- [MPU-6886 Datasheet](https://www.invensense.com/products/motionfusion/6-axis/mpu-6886/)
