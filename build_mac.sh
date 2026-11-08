#!/usr/bin/env bash
# ==============================================================================
# Mac (Apple Silicon M系列/Intel) lv_micropython + LVGL 8.3 固件编译脚本
# 适用芯片: ESP32-S3 (释放 GPIO19、GPIO20 为普通引脚)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/workspace"
REPO_DIR="${WORK_DIR}/lv_micropython"
DIST_DIR="${SCRIPT_DIR}/dist_windows"
BOARD_NAME="GENERIC_S3"

echo "=== [1/6] 检查与配置编译环境 ==="
if [ -z "$IDF_PATH" ]; then
    if [ -f "$HOME/esp/esp-idf-v4.4/export.sh" ]; then
        DEFAULT_IDF_PATH="$HOME/esp/esp-idf-v4.4"
    else
        DEFAULT_IDF_PATH="$HOME/esp/esp-idf"
    fi
    if [ -f "$DEFAULT_IDF_PATH/export.sh" ]; then
        echo "正在从 $DEFAULT_IDF_PATH 载入 ESP-IDF 环境..."
        . "$DEFAULT_IDF_PATH/export.sh"
    else
        echo "错误: 未找到 ESP-IDF 环境！"
        echo "请先安装 ESP-IDF v4.4.x (推荐 v4.4.6)，并执行: . \$IDF_PATH/export.sh"
        exit 1
    fi
fi

echo "ESP-IDF 路径: $IDF_PATH"
python3 --version
cmake --version

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "=== [2/6] 拉取 lv_micropython 源码 (release/v8 分支) ==="
if [ ! -d "$REPO_DIR" ]; then
    git clone -b release/v8 https://github.com/lvgl/lv_micropython.git
fi

cd "$REPO_DIR"

echo "=== [3/6] 同步必要子模块 ==="
git submodule update --init --recursive lib/lv_bindings
git submodule update --init --recursive lib/berkeley-db-1.xx

echo "=== [4/6] 应用补丁 (Apple Silicon 兼容 + 释放GPIO19/20 + S3驱动适配) ==="
if [ -f "${SCRIPT_DIR}/board_patch/lv_micropython.patch" ]; then
    git apply --whitespace=nowarn "${SCRIPT_DIR}/board_patch/lv_micropython.patch" || true
fi
if [ -f "${SCRIPT_DIR}/board_patch/lv_bindings.patch" ]; then
    cd lib/lv_bindings
    git apply --whitespace=nowarn "${SCRIPT_DIR}/board_patch/lv_bindings.patch" || true
    cd ../..
fi

# 确保板级配置就绪
TARGET_BOARD_DIR="ports/esp32/boards/${BOARD_NAME}"
cp -f "${SCRIPT_DIR}/board_patch/mpconfigboard.h" "${TARGET_BOARD_DIR}/mpconfigboard.h"
cp -f "${SCRIPT_DIR}/board_patch/sdkconfig.board" "${TARGET_BOARD_DIR}/sdkconfig.board"
cp -f "${SCRIPT_DIR}/board_patch/partitions-8MiB.csv" "ports/esp32/partitions-8MiB.csv"

# 编译 mpy-cross
make -C mpy-cross -j$(sysctl -n hw.ncpu)

echo "=== [5/6] 编译 ESP32-S3 固件 ==="
make -C ports/esp32 BOARD=${BOARD_NAME} submodules
make -C ports/esp32 BOARD=${BOARD_NAME} -j$(sysctl -n hw.ncpu)

echo "=== [6/6] 导出交付固件 ==="
BUILD_OUTPUT_DIR="ports/esp32/build-${BOARD_NAME}"
mkdir -p "$DIST_DIR"

if [ -f "${BUILD_OUTPUT_DIR}/firmware.bin" ]; then
    cp -f "${BUILD_OUTPUT_DIR}/firmware.bin" "${DIST_DIR}/firmware.bin"
    cp -f "${BUILD_OUTPUT_DIR}/firmware.bin" "${SCRIPT_DIR}/firmware.bin"
    echo "=========================================================="
    echo "编译完成！固件已生成并复制到交付目录:"
    echo "-> ${DIST_DIR}/firmware.bin"
    echo "=========================================================="
else
    echo "错误: 未生成 firmware.bin，请检查编译日志！"
    exit 1
fi
