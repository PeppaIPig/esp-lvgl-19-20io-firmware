#!/bin/bash
# ==============================================================================
# ESP32-S3 MicroPython 4路硬件 PCNT 编码器固件 一键编译脚本
# 适用平台：macOS / Linux
# 目标芯片：ESP32-S3 (Xtensa Dual-Core LX7)
# 核心特性：
#   1. 硬件 PCNT (Unit 0~3) 四倍频编码器 (machine.Encoder)
#   2. 开放 GPIO 46 作为 PCNT 输入 (M2 轮 Phase A)
#   3. 修复 GPIO 0~48 (SOC_GPIO_PIN_COUNT=49) 软硬件中断越界隐患
#   4. 释放 GPIO 39~42 传统 JTAG 复用为通用 GPIO / PWM
#   5. 启用 GPIO 47 / 48 (I2C SCL 与 WS2812 RGB)
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPY_DIR="${SCRIPT_DIR}/micropython"
IDF_PATH_DEFAULT="${HOME}/esp/esp-idf-v5.3"

echo "=========================================================="
echo "  ESP32-S3 MicroPython PCNT 硬件编码器固件 编译流程启动"
echo "=========================================================="

# 1. 检查并加载 ESP-IDF v5.x 环境
if [ -z "${IDF_PATH}" ]; then
    if [ -d "${IDF_PATH_DEFAULT}" ]; then
        export IDF_PATH="${IDF_PATH_DEFAULT}"
    else
        echo "❌ 未检测到 ESP-IDF 路径，请指定 IDF_PATH 或安装至 ~/esp/esp-idf-v5.3"
        exit 1
    fi
fi

echo ">> [1/6] 激活 ESP-IDF 环境: ${IDF_PATH} ..."
source "${IDF_PATH}/export.sh"

# 2. 拉取 / 检查 MicroPython 源码
if [ ! -d "${MPY_DIR}" ]; then
    echo ">> [2/6] 克隆 MicroPython 官方仓库 (v1.24.1) ..."
    git clone -b v1.24.1 --depth 1 https://github.com/micropython/micropython.git "${MPY_DIR}"
else
    echo ">> [2/6] 检测到已有 MicroPython 源码目录: ${MPY_DIR}"
fi

cd "${MPY_DIR}"

# 3. 更新必要子模块
echo ">> [3/6] 同步 submodules ..."
git submodule update --init --recursive lib/micropython-lib lib/berkeley-db-1.xx

# 4. 注入 PCNT 驱动源码与配置补丁
echo ">> [4/6] 注入 machine.Encoder / machine.Counter C 驱动与硬件补丁 ..."
cp -f "${SCRIPT_DIR}/ports_esp32/machine_encoder.c" "${MPY_DIR}/ports/esp32/machine_encoder.c"
cp -f "${SCRIPT_DIR}/ports_esp32/machine_encoder.h" "${MPY_DIR}/ports/esp32/machine_encoder.h"

# 应用补丁 (如果尚未应用)
if ! grep -q "MICROPY_PY_MACHINE_PCNT" "${MPY_DIR}/ports/esp32/mpconfigport.h"; then
    echo ">> 应用 esp32s3_pcnt.patch ..."
    git apply --ignore-whitespace "${SCRIPT_DIR}/esp32s3_pcnt.patch" || {
        echo "⚠️ 自动 patch 失败，正在进行直接注入..."
        echo "#define MICROPY_HW_ESP32S3_EXTENDED_IO (1)" >> "${MPY_DIR}/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigboard.h"
        echo "#define MICROPY_PY_MACHINE_ENCODER (1)" >> "${MPY_DIR}/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigboard.h"
        echo "#define MICROPY_PY_MACHINE_COUNTER (1)" >> "${MPY_DIR}/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigboard.h"
        echo "#define MICROPY_PY_MACHINE_PCNT (1)" >> "${MPY_DIR}/ports/esp32/boards/ESP32_GENERIC_S3/mpconfigboard.h"
    }
fi

# 5. 编译 mpy-cross 交叉编译器
echo ">> [5/6] 编译 mpy-cross ..."
make -C mpy-cross -j$(sysctl -n hw.ncpu || nproc)

# 6. 编译 ESP32-S3 目标固件
echo ">> [6/6] 编译 ESP32_GENERIC_S3 固件 (BOARD=ESP32_GENERIC_S3) ..."
cd "${MPY_DIR}/ports/esp32"
make BOARD=ESP32_GENERIC_S3 -j$(sysctl -n hw.ncpu || nproc)

BUILD_OUT="${MPY_DIR}/ports/esp32/build-ESP32_GENERIC_S3"
FINAL_BIN="${SCRIPT_DIR}/firmware_esp32s3_pcnt.bin"

if [ -f "${BUILD_OUT}/firmware.bin" ]; then
    cp -f "${BUILD_OUT}/firmware.bin" "${FINAL_BIN}"
    echo "=========================================================="
    echo "🎉 编译成功！"
    echo "固件输出路径: ${FINAL_BIN}"
    echo "文件大小: $(du -h "${FINAL_BIN}" | cut -f1)"
    echo "烧录指令 (起始偏移 0x0):"
    echo "esptool.py --chip esp32s3 -p <PORT> -b 921600 write_flash 0x0 ${FINAL_BIN}"
    echo "=========================================================="
else
    echo "❌ 编译未生成 firmware.bin，请检查上方日志输出！"
    exit 1
fi
