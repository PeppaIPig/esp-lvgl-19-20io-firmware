#!/usr/bin/env bash
# ==============================================================================
# ESP32-S3 LVGL8.3 固件一键烧录工具 (Mac 用户双击可用)
# 适用平台: macOS (Apple Silicon M系列 / Intel)
# ==============================================================================
cd "$(dirname "$0")"

clear
echo "=============================================================================="
echo "                 ESP32-S3 LVGL8.3 固件一键烧录工具 (Mac 专享版)"
echo "          (已关闭USB-JTAG控制台，GPIO19与GPIO20已释放为普通IO)"
echo "=============================================================================="
echo ""
echo "[硬件连接提醒]:"
echo "1. 请务必连接【第二个独立UART接口】(带有 CH340 / CP2102 芯片对应的Type-C口)！"
echo "2. 原来绑定GPIO19/20的原生USB口已关闭虚拟串口功能，无法用于烧录和REPL调试。"
echo "------------------------------------------------------------------------------"

# 1. 检查待烧录固件
if [ ! -f "firmware.bin" ]; then
    echo "【错误】当前目录下未找到固件文件 firmware.bin！"
    echo "请确认 firmware.bin 与本脚本位于同一文件夹下。"
    echo ""
    read -n 1 -s -r -p "按任意键退出..."
    exit 1
fi

# 2. 检测/配置烧录工具 esptool
echo "正在检测烧录环境..."
ESPTOOL_BIN=""

if command -v esptool.py >/dev/null 2>&1; then
    ESPTOOL_BIN="esptool.py"
elif command -v esptool >/dev/null 2>&1; then
    ESPTOOL_BIN="esptool"
elif [ -f "$HOME/.local/bin/esptool" ]; then
    ESPTOOL_BIN="$HOME/.local/bin/esptool"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import esptool" >/dev/null 2>&1; then
    ESPTOOL_BIN="python3 -m esptool"
fi

# 如果未安装 esptool，尝试自动轻量安装
if [ -z "$ESPTOOL_BIN" ]; then
    if command -v python3 >/dev/null 2>&1; then
        echo "首次运行，正在自动准备烧录依赖 (esptool)..."
        python3 -m pip install --user --quiet esptool -i https://pypi.tuna.tsinghua.edu.cn/simple >/dev/null 2>&1 || \
        python3 -m pip install --quiet esptool >/dev/null 2>&1 || true
        
        if python3 -c "import esptool" >/dev/null 2>&1; then
            ESPTOOL_BIN="python3 -m esptool"
        elif [ -f "$HOME/.local/bin/esptool" ]; then
            ESPTOOL_BIN="$HOME/.local/bin/esptool"
        fi
    fi
fi

if [ -z "$ESPTOOL_BIN" ]; then
    echo "【错误】未能找到或自动安装 esptool 烧录工具！"
    echo "请在终端中执行以下命令安装后重试："
    echo "pip3 install esptool"
    echo ""
    read -n 1 -s -r -p "按任意键退出..."
    exit 1
fi

echo "烧录工具就绪: $ESPTOOL_BIN"
echo ""

# 3. 自动扫描可用 USB 串口
echo "正在扫描连接的开发板串口..."
PORTS=($(ls /dev/cu.wchusbserial* /dev/cu.usbserial* /dev/cu.SLAB_USBtoUART* /dev/cu.usbmodem* 2>/dev/null || true))

SELECTED_PORT=""
if [ ${#PORTS[@]} -eq 0 ]; then
    echo "【警告】未自动检测到开发板串口！"
    echo "请排查："
    echo "1. 数据线是否已插入【带有CH340/CP2102芯片的独立UART口】？"
    echo "2. 数据线是否为纯充电线？（请更换为支持数据传输的线缆）"
    echo "3. 若为 CH340 芯片，是否已安装 Mac 版 CH34xVCPDriver 驱动？"
    echo ""
    read -r -p "请手动输入端口路径 (例如 /dev/cu.wchusbserial5AE60279341): " MANUAL_PORT
    SELECTED_PORT="$MANUAL_PORT"
elif [ ${#PORTS[@]} -eq 1 ]; then
    SELECTED_PORT="${PORTS[0]}"
    echo "检测到开发板端口: $SELECTED_PORT"
    read -r -p "按回车键直接使用此端口烧录，或输入其他端口后回车: " USER_INPUT
    if [ -n "$USER_INPUT" ]; then
        SELECTED_PORT="$USER_INPUT"
    fi
else
    echo "检测到多个可用串口设备:"
    for i in "${!PORTS[@]}"; do
        echo "  $((i+1))) ${PORTS[$i]}"
    done
    read -r -p "请输入序号选择对应端口 (默认 1): " PORT_INDEX
    if [ -z "$PORT_INDEX" ]; then
        PORT_INDEX=1
    fi
    SELECTED_PORT="${PORTS[$((PORT_INDEX-1))]}"
fi

if [ -z "$SELECTED_PORT" ]; then
    echo "【错误】未指定串口，操作取消。"
    exit 1
fi

echo ""
echo "=============================================================================="
echo "目标串口: $SELECTED_PORT"
echo "待刷固件: firmware.bin (约 2.1MB)"
echo "即将开始: 全片擦除旧数据 -> 烧录全新固件 -> 自动复位"
echo "=============================================================================="
read -r -p "请按回车键开始烧录..."

echo ""
echo ">>> [1/2] 正在全片擦除旧数据 (耗时约 3~5 秒，防止旧文件系统残留)..."
$ESPTOOL_BIN --chip esp32s3 --port "$SELECTED_PORT" --baud 921600 erase_flash || {
    echo "全片擦除返回警告，继续尝试直接写入..."
}

echo ""
echo ">>> [2/2] 正在向 ESP32-S3 写入全新固件..."
$ESPTOOL_BIN --chip esp32s3 --port "$SELECTED_PORT" --baud 921600 \
    --before default_reset --after hard_reset \
    write_flash -z --flash_mode dio --flash_freq 80m --flash_size 8MB 0x0 firmware.bin

if [ $? -eq 0 ]; then
    echo ""
    echo "=============================================================================="
    echo "   [√ 烧录成功！] 固件已顺利写入 ESP32-S3！"
    echo "   开发板已自动复位重启。"
    echo "   您现在可以在 Thonny IDE 中选择 $SELECTED_PORT 开始 MicroPython 编程。"
    echo "=============================================================================="
else
    echo ""
    echo "=============================================================================="
    echo "   [X 烧录失败！] 未能成功写入开发板。"
    echo "   排查建议："
    echo "   1. 确认数据线是否插入到了【带有CH340芯片的串口口】。"
    echo "   2. 确认端口是否被 Thonny、串口助手或终端占用（请先退出它们）。"
    echo "   3. 手动进入下载模式：按住板上 [BOOT] 键不放，点按一下 [RST] 键，"
    echo "      松开 [BOOT] 键后，重新运行本脚本。"
    echo "=============================================================================="
fi

echo ""
read -n 1 -s -r -p "按任意键退出窗口..."
echo ""
