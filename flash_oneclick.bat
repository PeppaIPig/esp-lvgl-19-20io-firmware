@echo off
chcp 65001 >nul
title ESP32-S3 LVGL8.3 智能识别固件一键烧录系统

cd /d "%~dp0"

:: 优先调用 Python 智能全自动脚本 (自动寻口 + 硬件识别 + 自动烧录 + 自动校验)
where python >nul 2>nul
if %errorlevel% equ 0 (
    if exist "flash_auto.py" (
        python flash_auto.py
        if %errorlevel% equ 0 goto FLASH_END
    )
)

:: ==============================================================================
:: 【备用纯批处理模式】当未安装 Python 时通过 esptool.exe 自动探测硬件并烧录
:: ==============================================================================
SET COM_PORT=COM3

cls
echo ==============================================================================
echo                 ESP32-S3 LVGL8.3 固件一键烧录程序
echo          (已关闭USB-JTAG控制台，GPIO19与GPIO20已释放为普通IO)
echo ==============================================================================
echo.
echo 当前配置的目标端口: %COM_PORT%
echo [注意提醒]: 请连接【第二个独立UART接口】(带 CH340 / CP2102 芯片的 Type-C 口)！
echo.
set /p USER_INPUT=按回车直接使用 %COM_PORT%，或输入新的COM号(如 COM4)后回车: 
if not "%USER_INPUT%"=="" set COM_PORT=%USER_INPUT%

echo.
echo 正在准备连接设备 %COM_PORT% ...
echo ------------------------------------------------------------------------------

:: 探测烧录工具
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
    echo 【错误】未检测到烧录工具 esptool.exe 或 Python！
    goto FLASH_FAIL
)

echo 烧录工具就绪: %ESPTOOL_BIN%
echo 正在自动探测开发板硬件与 PSRAM 型号...

:: 读取硬件特征并自动匹配固件
SET TEMP_INFO=%TEMP%\esp_hw_info_%RANDOM%.txt
%ESPTOOL_BIN% --chip esp32s3 --port %COM_PORT% chip_id > "%TEMP_INFO%" 2>&1

SET TARGET_BIN=
findstr /i "Embedded.PSRAM.8MB" "%TEMP_INFO%" >nul
if %errorlevel% equ 0 (
    SET TARGET_BIN=firmware_N8R8.bin
    echo [★ 自动识别硬件]: ESP32-S3 N8R8 (8MB Octal/OPI 八线 PSRAM)
    echo [★ 自动匹配固件]: firmware_N8R8.bin (满血 8.2MB 运存)
    del "%TEMP_INFO%" >nul 2>nul
    goto FLASH_START
)

findstr /i "Embedded.PSRAM.16MB" "%TEMP_INFO%" >nul
if %errorlevel% equ 0 (
    SET TARGET_BIN=firmware_N8R16.bin
    echo [★ 自动识别硬件]: ESP32-S3 N8R16 (16MB Octal/OPI 八线 PSRAM)
    echo [★ 自动匹配固件]: firmware_N8R16.bin (满血 16MB 运存)
    del "%TEMP_INFO%" >nul 2>nul
    goto FLASH_START
)

findstr /i "Embedded.PSRAM.2MB" "%TEMP_INFO%" >nul
if %errorlevel% equ 0 (
    SET TARGET_BIN=firmware_N8R2.bin
    echo [★ 自动识别硬件]: ESP32-S3 N8R2 (2MB Quad/QSPI 四线 PSRAM，老版)
    echo [★ 自动匹配固件]: firmware_N8R2.bin (满血 2.0MB 运存)
    del "%TEMP_INFO%" >nul 2>nul
    goto FLASH_START
)

del "%TEMP_INFO%" >nul 2>nul

:: 如果未检测到片上 eFuse，降级显示手动菜单
echo [!] 未在 eFuse 中检测到明确型号，请手动选择：
echo   [1] ESP32-S3 N8R8  (8MB PSRAM)  -> firmware_N8R8.bin
echo   [2] ESP32-S3 N8R16 (16MB PSRAM) -> firmware_N8R16.bin
echo   [3] ESP32-S3 N8R2  (2MB PSRAM)  -> firmware_N8R2.bin
set /p HW_CHOICE=请输入选项 [1、2 或 3，默认 1]: 
SET TARGET_BIN=firmware_N8R8.bin
if "%HW_CHOICE%"=="2" SET TARGET_BIN=firmware_N8R16.bin
if "%HW_CHOICE%"=="3" SET TARGET_BIN=firmware_N8R2.bin

:FLASH_START
if not exist "%TARGET_BIN%" (
    if exist "firmware.bin" (
        SET TARGET_BIN=firmware.bin
    ) else (
        echo 【错误】未找到待烧录固件 %TARGET_BIN%！
        goto FLASH_FAIL
    )
)

echo.
echo 正在全片擦除旧数据 (耗时约3秒)...
%ESPTOOL_BIN% --chip esp32s3 --port %COM_PORT% --baud 460800 erase_flash
if %errorlevel% neq 0 echo 【警告】全片擦除返回提示，继续写入...

echo.
echo 正在向 ESP32-S3 写入全新固件 (%TARGET_BIN%)...
%ESPTOOL_BIN% --chip esp32s3 --port %COM_PORT% --baud 460800 --before default_reset --after hard_reset write_flash -z --flash_mode dio --flash_freq 80m --flash_size 8MB 0x0 %TARGET_BIN%

if %errorlevel% equ 0 (
    echo.
    echo ==============================================================================
    echo [√ 烧录成功！] 固件 (%TARGET_BIN%) 已顺利写入 ESP32-S3！
    echo 开发板已自动复位重启。您现在可以在 Thonny IDE 中连接 %COM_PORT% 开始编程。
    echo ==============================================================================
    goto FLASH_END
) else (
    echo.
    echo ==============================================================================
    echo [X 烧录失败！] 未能成功连接或写入开发板。
    echo 排查建议：按住板上 [BOOT] 键不放，点按一下 [RST] 键松开，然后重新运行本脚本。
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
