# ==============================================================================
# 测试代码 2: ESP32-S3 最简 LVGL 8.3 SPI 屏幕 Demo (对齐 sim.lvgl.io 规范)
# 适用驱动: 固件内置 ili9XXX 驱动 (支持 st7789, gc9a01, ili9341 等)
# ==============================================================================
import lvgl as lv
from ili9XXX import st7789  # 如使用其他屏幕可直接替换为: from ili9XXX import gc9a01 或 ili9341

# 1. 初始化 LVGL 引擎内核
lv.init()

# 2. 初始化 SPI 硬件总线与内置屏幕驱动 (引脚请根据你的开发板或屏幕模块实际接线修改)
disp = st7789(
    miso=-1,
    mosi=11,        # SPI MOSI 引脚
    clk=12,         # SPI SCLK 时钟引脚
    cs=10,          # 片选 CS
    dc=13,          # 数据/命令 DC 引脚
    rst=14,         # 复位 RST 引脚 (-1 表示不使用)
    backlight=15,   # 背光引脚 (-1 表示不使用)
    width=240,
    height=240,     # 若为 240x320 屏幕请修改为 320
    start_x=0,
    start_y=0,
    rot=st7789.ROTATION_0,
    colormode=st7789.COLOR_MODE_BGR,
    spihost=1       # 默认 SPI2 (FSPI)
)

# 3. 创建界面元素 (完全兼容 sim.lvgl.io 语法)
scr = lv.scr_act()
scr.set_style_bg_color(lv.color_hex(0x1E1E2E), 0)

# 顶部标题文本
title = lv.label(scr)
title.set_text("ESP32-S3 LVGL 8.3")
title.set_style_text_color(lv.color_hex(0x89B4FA), 0)
title.align(lv.ALIGN.TOP_MID, 0, 20)

# 状态指示标签
status = lv.label(scr)
status.set_text("GPIO19 & 20 Freed OK")
status.set_style_text_color(lv.color_hex(0xA6E3A1), 0)
status.align(lv.ALIGN.TOP_MID, 0, 45)

# 居中交互按钮
btn = lv.btn(scr)
btn.set_size(150, 48)
btn.align(lv.ALIGN.CENTER, 0, 20)
btn.set_style_bg_color(lv.color_hex(0xF38BA8), 0)

# 按钮内部文字
btn_label = lv.label(btn)
btn_label.set_text("Click: 0")
btn_label.center()

# 按钮点击事件处理
click_count = 0
def button_event_cb(event):
    global click_count
    click_count += 1
    btn_label.set_text(f"Click: {click_count}")
    print(f"屏幕按钮被点击，当前计数: {click_count}")

btn.add_event_cb(button_event_cb, lv.EVENT.CLICKED, None)
print("=== LVGL 8.3 UI 初始化完成，主循环持续运行中 ===")
