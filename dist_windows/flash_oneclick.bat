@echo off
rem ==============================================================================
rem ESP32-S3 Firmware One-Click Flash Tool (Windows)
rem ==============================================================================
cd /d "%~dp0"
title ESP32-S3 Firmware One-Click Flash Tool

set PYTHON_CMD=

rem 1. Check if python is in PATH
where python >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=python&& goto FOUND_PYTHON

rem 2. Check if py launcher is available
where py >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=py -3&& goto FOUND_PYTHON

rem 3. Check python3
where python3 >nul 2>&1
if %errorlevel% equ 0 set PYTHON_CMD=python3&& goto FOUND_PYTHON

rem 4. Check user local app data python installations
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do (
    if exist "%%D\python.exe" set PYTHON_CMD="%%D\python.exe"&& goto FOUND_PYTHON
)

rem 5. Check C:\Python3* installations
for /d %%D in ("C:\Python3*") do (
    if exist "%%D\python.exe" set PYTHON_CMD="%%D\python.exe"&& goto FOUND_PYTHON
)

rem If not found, show error and exit
echo ==============================================================================
echo [ERROR] Python 3 was not detected on your computer!
echo ==============================================================================
echo.
echo Please install Python 3 from official site:
echo   https://www.python.org/downloads/
echo.
echo IMPORTANT: Make sure to check "Add Python to PATH" during installation.
echo.
echo ------------------------------------------------------------------------------
echo [Alternative]: You can also flash the firmware directly using Thonny or Mixly:
echo   Firmware file: firmware_N8R8.bin, Offset: 0x0
echo ==============================================================================
echo.
pause
exit /b 1

:FOUND_PYTHON
echo [OK] Using Python: %PYTHON_CMD%
echo.

%PYTHON_CMD% flash_auto.py
set FLASH_RET=%errorlevel%

echo.
if %FLASH_RET% equ 0 (
    echo [SUCCESS] Flashing completed!
) else (
    echo [NOTE] Flasher finished with code %FLASH_RET%.
)
echo.
pause
exit /b %FLASH_RET%
