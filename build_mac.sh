#!/usr/bin/env bash
# ==============================================================================
# Mac (Apple Silicon M系列/Intel) lv_micropython + LVGL 8.3 固件编译脚本
# 适用芯片: ESP32-S3 (释放 GPIO19、GPIO20 为普通引脚，支持 N8R8 / N8R2 双硬件)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/workspace"
REPO_DIR="${WORK_DIR}/lv_micropython"
DIST_WIN="${SCRIPT_DIR}/dist_windows"
DIST_MAC="${SCRIPT_DIR}/dist_mac"

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

# 同步公共代码与板级目标
cp -f "${SCRIPT_DIR}/board_patch/partitions-8MiB.csv" "ports/esp32/partitions-8MiB.csv"
cp -f "${SCRIPT_DIR}/board_patch/machine_encoder.c" "ports/esp32/machine_encoder.c"
cp -f "${SCRIPT_DIR}/board_patch/machine_encoder.h" "ports/esp32/machine_encoder.h"

cp -rf "${SCRIPT_DIR}/board_patch/GENERIC_S3_N8R8" "ports/esp32/boards/"
cp -rf "${SCRIPT_DIR}/board_patch/GENERIC_S3_N8R2" "ports/esp32/boards/"

# 编译 mpy-cross
make -C mpy-cross -j$(sysctl -n hw.ncpu)

# 目标判断 (支持传参编译单一目标，默认全量编译双目标)
TARGET="$1"
BOARDS_TO_BUILD=()

if [ "$TARGET" == "n8r8" ] || [ "$TARGET" == "N8R8" ]; then
    BOARDS_TO_BUILD=("GENERIC_S3_N8R8")
elif [ "$TARGET" == "n8r2" ] || [ "$TARGET" == "N8R2" ]; then
    BOARDS_TO_BUILD=("GENERIC_S3_N8R2")
else
    BOARDS_TO_BUILD=("GENERIC_S3_N8R8" "GENERIC_S3_N8R2")
fi

echo "=== [5/6] 编译 ESP32-S3 目标固件: ${BOARDS_TO_BUILD[*]} ==="
mkdir -p "$DIST_WIN" "$DIST_MAC"

for BOARD in "${BOARDS_TO_BUILD[@]}"; do
    echo ">>> 开始编译板型: ${BOARD} ..."
    make -C ports/esp32 BOARD="${BOARD}" submodules
    make -C ports/esp32 BOARD="${BOARD}" -j$(sysctl -n hw.ncpu)
    
    BUILD_DIR="ports/esp32/build-${BOARD}"
    BIN_NAME="firmware_N8R8.bin"
    [ "$BOARD" == "GENERIC_S3_N8R2" ] && BIN_NAME="firmware_N8R2.bin"

    if [ -f "${BUILD_DIR}/firmware.bin" ]; then
        cp -f "${BUILD_DIR}/firmware.bin" "${SCRIPT_DIR}/${BIN_NAME}"
        cp -f "${BUILD_DIR}/firmware.bin" "${DIST_WIN}/${BIN_NAME}"
        cp -f "${BUILD_DIR}/firmware.bin" "${DIST_MAC}/${BIN_NAME}"
        echo "[√] 成功生成: ${BIN_NAME}"
    else
        echo "错误: 板型 ${BOARD} 未生成固件！"
        exit 1
    fi
done

# 默认主固件指向 N8R8
if [ -f "${SCRIPT_DIR}/firmware_N8R8.bin" ]; then
    cp -f "${SCRIPT_DIR}/firmware_N8R8.bin" "${SCRIPT_DIR}/firmware.bin"
    cp -f "${SCRIPT_DIR}/firmware_N8R8.bin" "${DIST_WIN}/firmware.bin"
    cp -f "${SCRIPT_DIR}/firmware_N8R8.bin" "${DIST_MAC}/firmware.bin"
fi

echo "=== [6/6] 导出交付固件完成 ==="
echo "=========================================================="
echo "固件已同步至根目录、dist_windows 与 dist_mac:"
echo "1. firmware_N8R8.bin (8MB Octal/OPI PSRAM)"
echo "2. firmware_N8R2.bin (2MB Quad/QSPI PSRAM)"
echo "=========================================================="
