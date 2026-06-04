# Pro Micro ATmega32U4 开发板

## 简介

Pro Micro 是一款基于 ATmega32U4 微控制器的紧凑型开发板，尺寸仅 33×18mm。由于芯片内置 USB 收发器，无需额外的 USB 转串口芯片（如 CH340、CP2102），可以直接通过 USB 接口进行编程和串口通信。它常用于键盘 DIY、HID 设备模拟等场景。

### 引脚图

![Pro Micro 引脚图](ProMicro引脚图.avif)

## 引脚标注含义

开发板引脚图上标注了不同的功能分区，各含义如下：

### PWM（脉冲宽度调制）

PWM 是一种通过快速开关数字信号来模拟模拟输出的技术。通过调节高电平占整个周期的比例（占空比），可以控制 LED 亮度、电机转速等。Pro Micro 提供了 5 个 PWM 引脚（3、5、6、9、10），使用 `analogWrite()` 函数即可输出 PWM 信号。

### Analog（模拟输入）

模拟输入引脚可以读取连续变化的电压值（0-5V），通过 ADC（模数转换器）转换为 0-1023 的数字值。适用于读取传感器数据，如电位器、光敏电阻、温度传感器等。Pro Micro 提供 9 个模拟输入引脚（A0-A8），部分与数字引脚复用。

### SPI（串行外设接口）

SPI 是一种高速同步串行通信协议，采用主从架构，需要 4 根线：SCLK（时钟）、MOSI（主出从入）、MISO（主入从出）、SS（片选）。常用于驱动 OLED/LCD 显示屏、SD 卡模块、SPI 传感器等。Pro Micro 的 SPI 引脚为 15（SCLK）、16（MOSI）、14（MISO）。

### I2C（集成电路间通信）

I2C 是一种双线制串行通信协议，仅需 SDA（数据线）和 SCL（时钟线）两根线即可连接多个设备。每个设备有唯一的地址，适合连接传感器、EEPROM、OLED 显示屏等外设。Pro Micro 的 I2C 引脚为 2（SDA）和 3（SCL）。

### Serial（串口通信）

Serial 指的是 UART 串口通信，用于设备间的数据传输。ATmega32U4 内置 USB 收发器，因此有两个串口：一个是通过 USB 虚拟的串口（`Serial`），用于与电脑通信；另一个是硬件串口（`Serial1`），通过引脚 0（RX）和 1（TX）与其他设备通信。

### Arduino（数字 I/O）

标注为 Arduino 的引脚是通用数字输入/输出引脚，可以通过 `pinMode()` 设置为输入或输出模式，使用 `digitalRead()` / `digitalWrite()` 读取或输出高低电平。Pro Micro 提供 18 个数字 I/O 引脚，支持 5V 逻辑电平。

### Power（电源）

电源引脚包括：
- **VCC**：5V 输出，为外设供电
- **RAW**：电源输入引脚，可接入 5-12V 外部电源（通过板载稳压器降压至 5V）
- **GND**：接地引脚
- **RST**：复位引脚，拉低可复位芯片

## 为什么不选择 Pro Micro 作为本项目的开发板

尽管 Pro Micro 体积小巧、价格低廉且 USB 支持完善，但它 **不适合** 作为 Claude Code RGB 状态灯的开发板，原因如下：

### 1. 不支持 WiFi

Pro Micro 基于 ATmega32U4，这是一颗纯 MCU，没有内置 WiFi/蓝牙无线模块。本项目需要实现 **无线状态灯**，Claude Code 的 Hook 脚本需要通过 HTTP API 或串口向 ESP32 发送灯光状态指令。没有 WiFi 意味着：

- 无法通过 HTTP API 远程控制灯光
- 必须通过 USB 线缆连接电脑，失去无线部署的灵活性
- 无法使用充电宝独立供电，必须依赖电脑 USB 口

### 2. 扩展性差

ATmega32U4 的资源非常有限：

- **Flash**：32KB（其中 4KB 被 bootloader 占用）
- **SRAM**：2.5KB
- **时钟频率**：16MHz

如果需要外接 WiFi 模块（如 ESP8266），还需要通过 SPI 或串口通信，不仅占用宝贵的引脚和内存资源，还会增加硬件复杂度和成本。而 ESP32-C3 SuperMini 本身就集成了 WiFi，一颗芯片搞定所有需求。

### 结论

对于需要 **WiFi 无线通信** 和 **HTTP 服务** 的场景，ESP32-C3 SuperMini 是更合适的选择：内置 WiFi + 蓝牙、足够的 Flash/SRAM、原生 USB 支持、价格同样亲民。Pro Micro 更适合做键盘控制器、HID 设备等对 USB 有强需求的纯有线项目。
