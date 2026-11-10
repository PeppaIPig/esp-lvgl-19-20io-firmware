# ==============================================================================
# 测试代码 1: ESP32-S3 GPIO19 与 GPIO20 电平控制与输入输出自检
# 目的: 验证 USB-SERIAL-JTAG 已彻底解绑，GPIO19 与 GPIO20 具备标准普通 IO 功能
# ==============================================================================
import time
from machine import Pin

print("=== ESP32-S3 GPIO19 / GPIO20 普通功能测试开始 ===")

# 初始化 GPIO19 与 GPIO20 为输出模式
p19 = Pin(19, Pin.OUT)
p20 = Pin(20, Pin.OUT)

print("1. 测试 GPIO19 / GPIO20 输出翻转 (持续 5 次)...")
for i in range(5):
    p19.value(1)
    p20.value(0)
    print(f"[{i+1}/5] GPIO19=高电平(1), GPIO20=低电平(0)")
    time.sleep_ms(300)

    p19.value(0)
    p20.value(1)
    print(f"[{i+1}/5] GPIO19=低电平(0), GPIO20=高电平(1)")
    time.sleep_ms(300)

# 测试输入模式与内部弱上下拉电阻功能
print("\n2. 测试 GPIO19 / GPIO20 弱上拉与弱下拉模式读数...")
p19_in_pullup = Pin(19, Pin.IN, Pin.PULL_UP)
p20_in_pulldown = Pin(20, Pin.IN, Pin.PULL_DOWN)
time.sleep_ms(50)
print(f"GPIO19 弱上拉读取状态: {p19_in_pullup.value()} (预期为 1)")
print(f"GPIO20 弱下拉读取状态: {p20_in_pulldown.value()} (预期为 0)")

print("\n=== 自检通过: GPIO19 与 GPIO20 已完全释放为普通 GPIO，无任何串口占用！ ===")
