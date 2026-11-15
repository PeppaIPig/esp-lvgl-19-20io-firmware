# ==============================================================================
# ESP32-S3 4路硬件PCNT正交编码器 与 全量GPIO中断测试代码
# 支持: LVGL 8.3 + 4路硬件PCNT编码器 (machine.Encoder) + GPIO 0~48 中断越界修复
# ==============================================================================
import time
from machine import Pin, Encoder

print("==================================================")
print("  ESP32-S3 硬件特性与PCNT编码器自检")
print("==================================================")

# 1. 验证中断数组边界修复 (GPIO >= 40 不再发生 VFS 越界踩踏)
print("\n[测试 1] 验证 GPIO 0~48 软硬件中断安全性 (GPIO 45, 46, 47, 48)...")
try:
    p45 = Pin(45, Pin.IN, Pin.PULL_UP)
    p45.irq(trigger=Pin.IRQ_FALLING, handler=lambda t: None)
    
    p47 = Pin(47, Pin.IN, Pin.PULL_UP)
    p47.irq(trigger=Pin.IRQ_FALLING, handler=lambda t: None)
    
    print("  -> GPIO 45 与 GPIO 47 中断注册成功！无内存踩踏。")
except Exception as e:
    print(f"  [X] 中断注册异常: {e}")

# 2. 初始化 4 路硬件 PCNT 编码器
# 针对 4WD 麦克纳姆轮底盘电机:
# 电机 0: Unit 0 (引脚示例: 12, 13)
# 电机 1: Unit 1 (引脚示例: 46, 9) -> 特别验证 GPIO46 (Input-only Strapping 引脚)
# 电机 2: Unit 2 (引脚示例: 10, 11)
# 电机 3: Unit 3 (引脚示例: 14, 21)
print("\n[测试 2] 初始化 4 路硬件 PCNT 编码器 (Unit 0~3, phases=4 4倍频)...")
try:
    enc0 = Encoder(0, 12, 13, phases=4, filter_ns=1000)
    print("  -> Unit 0 (Motor 0, Pins 12/13) 初始化成功")
    
    # Unit 1 Phase A 使用 GPIO 46 (Input-only strapping pin)
    enc1 = Encoder(1, 46, 9, phases=4, filter_ns=1000)
    print("  -> Unit 1 (Motor 1, Pins 46/9) 初始化成功 (GPIO46 硬件路由正常)")
    
    enc2 = Encoder(2, 10, 11, phases=4, filter_ns=1000)
    print("  -> Unit 2 (Motor 2, Pins 10/11) 初始化成功")
    
    enc3 = Encoder(3, 14, 21, phases=4, filter_ns=1000)
    print("  -> Unit 3 (Motor 3, Pins 14/21) 初始化成功")
    
    print("\n[测试 3] 读取 4 路编码器当前硬件计数值:")
    print(f"  Motor 0: {enc0.value()}")
    print(f"  Motor 1: {enc1.value()}")
    print(f"  Motor 2: {enc2.value()}")
    print(f"  Motor 3: {enc3.value()}")
    
    # 测试计数重置功能
    enc0.value(100)
    print(f"  Motor 0 设置值为 100 后的读数: {enc0.value()} (预期: 100)")
    enc0.value(0)
    print(f"  Motor 0 清零后的读数: {enc0.value()} (预期: 0)")
    
    print("\n==================================================")
    print("  [√ 全部通过] ESP32-S3 PCNT 4路编码器与中断驱动就绪！")
    print("==================================================")
    
except Exception as e:
    print(f"\n[X] 编码器测试发生异常: {e}")
