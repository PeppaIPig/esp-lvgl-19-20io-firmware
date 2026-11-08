@echo off
chcp 65001 >nul
title ESP32-S3 LVGL8.3 固件一键烧录工具

:: ==============================================================================
:: 【重要配置】请在下方填入你的开发板串口号 (在 Windows 设备管理器 -> 端口(COM和LPT) 中查看)
:: 例如：COM3、COM4、COM10 等
SET COM_PORT=COM3
:: ==============================================================================

cls
echo ==============================================================================
echo                 ESP32-S3 LVGL8.3 固件一键烧录程序
echo          (已关闭USB-JTAG控制台，GPIO19与GPIO20已释放为普通IO)
echo ==============================================================================
echo.
echo 当前配置的目标端口: %COM_PORT%
echo 待烧录固件文件: firmware.bin
echo.
echo [注意提醒]:
echo 1. 请务必连接【第二个独立USB口】(通常为 CH340 / CP2102 芯片对应的串口)！
echo 2. 原来绑定GPIO19/20的USB口已关闭虚拟串口功能，无法用于烧录和REPL调试。
echo 3. 如需修改端口，请右键用记事本打开本脚本，修改第 8 行的 SET COM_PORT=%COM_PORT%
echo.
set /p USER_INPUT=按回车键直接使用 %COM_PORT% 烧录，或输入新的COM号(如 COM4)后回车: 
if not "%USER_INPUT%"=="" set COM_PORT=%USER_INPUT%

echo.
echo 正在准备连接设备 %COM_PORT% ...
echo ------------------------------------------------------------------------------

:: 检查固件是否存在
if not exist "firmware.bin" (
    echo 【错误】当前目录下未找到固件文件 firmware.bin！
    echo 请确认 firmware.bin 与本脚本位于同一文件夹下。
    goto FLASH_FAIL
)

:: 探测烧录工具 (优先使用免安装 esptool.exe，其次探测系统 python/esptool)
SET ESPTOOL_BIN=
if exist "esptool.exe" (
    SET ESPTOOL_BIN=esptool.exe
) else (
    where esptool.exe >nul 2>nul
    if %errorlevel% equ 0 (
        SET ESPTOOL_BIN=esptool.exe
    ) else (
        where python >nul 2>nul
        if %errorlevel% equ 0 (
            SET ESPTOOL_BIN=python -m esptool
        )
    )
)

if "%ESPTOOL_BIN%"=="" (
    echo 【错误】未检测到烧录工具 esptool.exe！
    echo 解决方法：
    echo 请直接将官方免安装版的 esptool.exe 放入当前文件夹下，
    echo 或在电脑中安装 Python 并执行: pip install esptool
    goto FLASH_FAIL
)

echo 烧录工具就绪: %ESPTOOL_BIN%
echo 正在全片擦除旧数据 (耗时约3秒，防止旧文件系统残留)...
%ESPTOOL_BIN% --chip esp32s3 --port %COM_PORT% --baud 460800 erase_flash
if %errorlevel% neq 0 (
    echo 【警告】全片擦除失败，尝试直接写入固件...
)

echo.
echo 正在向 ESP32-S3 (%COM_PORT%) 写入全新固件...
echo.

%ESPTOOL_BIN% --chip esp32s3 --port %COM_PORT% --baud 460800 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size 8MB 0x0 firmware.bin

if %errorlevel% equ 0 (
    echo.
    echo ==============================================================================
    echo [√ 烧录成功！] 固件已顺利写入 ESP32-S3！
    echo 开发板已自动复位重启。
    echo 您现在可以在 Thonny IDE 中选择 %COM_PORT% 开始 MicroPython 编程。
    echo ==============================================================================
    goto FLASH_END
) else (
    echo.
    echo ==============================================================================
    echo [X 烧录失败！] 未能成功连接或写入开发板。
    echo 排查建议：
    echo 1. 确认数据线是否插入到了【带有CH340/CP2102芯片的串口USB口】。
    echo 2. 在设备管理器中核对端口号是否正确，是否被 Thonny 或串口助手占用。
    echo 3. 手动进入下载模式：按住板上的 [BOOT] 键不放，点按一下 [RST/RESET] 键，
    echo    松开 [BOOT] 键后，重新双击本脚本烧录。
    echo ==============================================================================
    goto FLASH_FAIL
)

:FLASH_FAIL
echo.
pause
exit /b 1

:FLASH_END
echo.
pause
exit /b 0
