@echo off
setlocal EnableExtensions
rem ==============================================================================
rem ESP32-S3 Firmware One-Click Flash Tool (Windows)
rem ==============================================================================
cd /d "%~dp0"
title ESP32-S3 Firmware One-Click Flash Tool

set "PYTHON_CMD="
set "CAND="
set "FLASH_RET=1"

rem ---- 1. python in PATH -------------------------------------------------------
where python >nul 2>&1
if errorlevel 1 goto try_py
set "CAND=python"
call :probe
if defined PYTHON_CMD goto have_python

:try_py
rem ---- 2. py launcher ---------------------------------------------------------
where py >nul 2>&1
if errorlevel 1 goto try_python3
set "CAND=py -3"
call :probe
if defined PYTHON_CMD goto have_python

:try_python3
rem ---- 3. python3 -------------------------------------------------------------
where python3 >nul 2>&1
if errorlevel 1 goto try_localappdata
set "CAND=python3"
call :probe
if defined PYTHON_CMD goto have_python

:try_localappdata
rem ---- 4. %LOCALAPPDATA%\Programs\Python\Python3* -----------------------------
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do call :probe_file "%%D\python.exe"
if defined PYTHON_CMD goto have_python

:try_cpython
rem ---- 5. C:\Python3* ---------------------------------------------------------
for /d %%D in ("C:\Python3*") do call :probe_file "%%D\python.exe"
if defined PYTHON_CMD goto have_python

rem ---- Python not found -------------------------------------------------------
goto no_python

:probe
%CAND% -c "import sys" >nul 2>&1
if errorlevel 1 goto :eof
set "PYTHON_CMD=%CAND%"
goto :eof

:probe_file
if not exist "%~1" goto :eof
set "CAND="%~1""
call :probe
goto :eof

:have_python
echo [OK] Using Python: %PYTHON_CMD%
echo.
%PYTHON_CMD% "%~dp0flash_auto.py"
set "FLASH_RET=%errorlevel%"
echo.
if "%FLASH_RET%"=="0" goto flash_ok
echo [NOTE] Flasher finished with code %FLASH_RET%.
goto flash_end

:flash_ok
echo [SUCCESS] Flashing completed!

:flash_end
echo.
pause
exit /b %FLASH_RET%

:no_python
echo ==============================================================================
echo [ERROR] Python 3 was not detected on your computer!
echo ==============================================================================
echo.
echo Please install Python 3 from the official site:
echo   https://www.python.org/downloads/
echo.
echo IMPORTANT: check "Add python.exe to PATH" during installation.
echo.
echo ------------------------------------------------------------------------------
echo [Alternative] You can also flash the firmware with Thonny or Mixly:
echo   Firmware file: firmware_N8R8.bin
echo   Flash address: 0x0000
echo ------------------------------------------------------------------------------
echo.
pause
exit /b 1
