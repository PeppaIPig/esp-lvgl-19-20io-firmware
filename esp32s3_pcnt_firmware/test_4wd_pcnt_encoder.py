# -*- coding: utf-8 -*-
"""
ESP32-S3 4WD 麦克纳姆轮底盘 硬件 PCNT 编码器及全外设验证脚本
=============================================================
验证目标：
1. 验证 4 路底层硬件 PCNT 正交编码器 (machine.Encoder) 驱动及 4x 倍频计数：
   - M1: Unit 0, Phase A=GPIO 12, Phase B=GPIO 13
   - M2: Unit 1, Phase A=GPIO 46, Phase B=GPIO 9  (重点验证 GPIO 46 纯输入硬件计数)
   - M3: Unit 2, Phase A=GPIO 17, Phase B=GPIO 18
   - M4: Unit 3, Phase A=GPIO 6,  Phase B=GPIO 7
2. 验证 GPIO 0~48 (SOC_GPIO_PIN_COUNT=49) 软中断安全性（杜绝 >=40 越界崩溃 Bug）：
   - Pin(45), Pin(46), Pin(47), Pin(48) 注册中断无崩溃、无 VFS 踩踏
3. 验证 GPIO 39~42 释放脱离 JTAG：可作为标准 GPIO 输出
4. 验证常用组件：
   - 基础硬件: WS2812 RGB (GPIO 48), 无源蜂鸣器 PWM (GPIO 14)
   - 系统并发: _thread 多线程
   - 网络组件: network (WLAN / SoftAP / Socket)
"""

import time
import machine
from machine import Pin, Encoder
import _thread
import network

print("=" * 65)
print("  ESP32-S3 4WD 底盘 硬件 PCNT 编码器与全外设测试程序")
print("=" * 65)

# -------------------------------------------------------------
# 1. 验证 4 路硬件 PCNT 编码器 (Unit 0 ~ 3)
# -------------------------------------------------------------
print("\n[Step 1] 初始化 4 路硬件 PCNT 编码器 (phases=4, filter_ns=1000)...")

# 电机编码器引脚映射 (M1~M4)
ENCODER_CONFIGS = [
    {"name": "M1 (左前轮)", "unit": 0, "pin_a": 12, "pin_b": 13},
    {"name": "M2 (右前轮)", "unit": 1, "pin_a": 46, "pin_b": 9},   # GPIO 46 input-only strapping pin
    {"name": "M3 (左后轮)", "unit": 2, "pin_a": 17, "pin_b": 18},
    {"name": "M4 (右后轮)", "unit": 3, "pin_a": 6,  "pin_b": 7},
]

encoders = {}

for cfg in ENCODER_CONFIGS:
    unit_id = cfg["unit"]
    try:
        # machine.Encoder(unit, phase_a, phase_b, phases=4, filter_ns=1000)
        enc = Encoder(unit_id, cfg["pin_a"], cfg["pin_b"], phases=4, filter_ns=1000)
        enc.value(0) # 计数值清零
        encoders[unit_id] = enc
        print("  ✅ {} Unit {}: Pin A={}, Pin B={} -> 初始化成功 (当前计数: {})".format(
            cfg["name"], unit_id, cfg["pin_a"], cfg["pin_b"], enc.value()
        ))
    except Exception as e:
        print("  ❌ {} Unit {} 初始化失败: {}".format(cfg["name"], unit_id, e))

print("\n>> 4 路 PCNT 初始化完毕，请用手轻轻转动 4 个车轮观察硬件脉冲实时计数 (测试 5 秒)...")
for t in range(5):
    counts = [encoders[i].value() if i in encoders else "N/A" for i in range(4)]
    print("   [T+{}s] M1(U0): {:6} | M2(U1): {:6} | M3(U2): {:6} | M4(U3): {:6}".format(
        t + 1, counts[0], counts[1], counts[2], counts[3]
    ))
    time.sleep(1)

# 测试清零功能
print(">> 测试编码器计数原子清零 (enc.value(0))...")
for i in range(4):
    if i in encoders:
        encoders[i].value(0)
counts = [encoders[i].value() if i in encoders else "N/A" for i in range(4)]
print("   清零后数值: M1={}, M2={}, M3={}, M4={} (全部应为 0)".format(*counts))

# -------------------------------------------------------------
# 2. 验证高位 GPIO >= 40 软中断越界安全性 (彻底杜绝 VFS 踩踏)
# -------------------------------------------------------------
print("\n[Step 2] 验证 GPIO 0~48 中断数组边界安全性 (GPIO 45, 46, 47, 48)...")
test_irq_pins = [45, 46, 47, 48]
irq_triggered_count = 0

def dummy_irq_handler(pin):
    global irq_triggered_count
    irq_triggered_count += 1

try:
    for pin_id in test_irq_pins:
        p = Pin(pin_id, Pin.IN)
        # 注册双边沿中断，验证底层 MP_STATE_PORT(machine_pin_irq_handler)[pin_id] 索引安全
        p.irq(handler=dummy_irq_handler, trigger=Pin.IRQ_RISING | Pin.IRQ_FALLING)
        print("  ✅ Pin({}).irq() 成功挂载，无数组越界，无系统 Panic".format(pin_id))
        p.irq(handler=None) # 测试完成后注销
    print("  🎉 恭喜！高位 GPIO >= 40 软中断测试全部安全通过！")
except Exception as e:
    print("  ❌ Pin.irq() 越界测试异常: {}".format(e))

# -------------------------------------------------------------
# 3. 验证 GPIO 39~42 脱离传统 JTAG 占用
# -------------------------------------------------------------
print("\n[Step 3] 验证 GPIO 39~42 脱离 JTAG 占用，作为普通 GPIO 输出...")
jtag_pins = [39, 40, 41, 42]
for pin_id in jtag_pins:
    try:
        p = Pin(pin_id, Pin.OUT)
        p.value(0)
        p.value(1)
        p.value(0)
        print("  ✅ Pin({}) 成功配置为普通数字输出".format(pin_id))
    except Exception as e:
        print("  ❌ Pin({}) JTAG 释放失败: {}".format(pin_id, e))

# -------------------------------------------------------------
# 4. 验证常用组件 (NeoPixel, 蜂鸣器, _thread, WLAN)
# -------------------------------------------------------------
print("\n[Step 4] 验证系统常用组件...")

# (1) NeoPixel WS2812 on GPIO 48
try:
    import neopixel
    np = neopixel.NeoPixel(Pin(48), 1)
    np[0] = (0, 30, 0) # 绿色微光
    np.write()
    time.sleep(0.3)
    np[0] = (0, 0, 0) # 熄灭
    np.write()
    print("  ✅ WS2812 RGB (GPIO 48) 驱动正常")
except Exception as e:
    print("  ⚠️ WS2812 RGB 测试: {}".format(e))

# (2) 无源蜂鸣器 PWM on GPIO 14
try:
    from machine import PWM
    buzzer = PWM(Pin(14), freq=2000, duty_u16=32768)
    time.sleep(0.1)
    buzzer.deinit()
    print("  ✅ 无源蜂鸣器 PWM (GPIO 14) 驱动正常")
except Exception as e:
    print("  ⚠️ 蜂鸣器测试: {}".format(e))

# (3) 多线程支持 _thread
thread_running = False
def thread_entry():
    global thread_running
    thread_running = True

try:
    _thread.start_new_thread(thread_entry, ())
    time.sleep(0.1)
    if thread_running:
        print("  ✅ 多线程 (_thread) 后台任务运行正常")
    else:
        print("  ⚠️ 多线程启动未置位")
except Exception as e:
    print("  ❌ 多线程测试失败: {}".format(e))

# (4) 网络组件 WLAN
try:
    wlan_sta = network.WLAN(network.STA_IF)
    wlan_sta.active(True)
    mac = wlan_sta.config('mac')
    mac_str = ':'.join(['{:02X}'.format(b) for b in mac])
    print("  ✅ WLAN STA 初始化正常 (MAC: {})".format(mac_str))
    wlan_sta.active(False)
except Exception as e:
    print("  ❌ WLAN 测试失败: {}".format(e))

print("\n" + "=" * 65)
print("  🎉 全部外设与硬件 PCNT 编码器测试完毕！系统运行平稳！")
print("=" * 65)
