@echo off
setlocal enabledelayedexpansion

title STM32 Proteus Auto-Loader

echo ===================================================
echo   STM32 Proteus Auto-Build ^& Simulation
echo ===================================================
echo.

:: -----------------------------------------------------
:: 1. DYNAMIC CONFIGURATION & TARGET RESOLUTION
:: -----------------------------------------------------
set "PROJECT_DIR=%~dp0"
set "BUILD_DIR=%PROJECT_DIR%build"

:: Ưu tiên 1: Tên target nhận từ đối số truyền vào (ví dụ: build.bat Lab2)
set "TARGET_NAME=%~1"

:: Ưu tiên 2: Tự động quét file thiết kế Proteus (*.pdsprj) trong thư mục dự án
if "%TARGET_NAME%"=="" (
    for %%F in ("%PROJECT_DIR%*.pdsprj") do (
        if exist "%%F" (
            set "TARGET_NAME=%%~nF"
            set "PDS_PROJECT=%%F"
        )
    )
)

:: Ưu tiên 3: Nếu không có file pdsprj, lấy theo tên thư mục cha
if "%TARGET_NAME%"=="" (
    for %%I in ("%PROJECT_DIR:~0,-1%") do set "TARGET_NAME=%%~nxI"
)

:: Thiết lập đường dẫn file
if not defined PDS_PROJECT (
    if exist "%PROJECT_DIR%%TARGET_NAME%.pdsprj" (
        set "PDS_PROJECT=%PROJECT_DIR%%TARGET_NAME%.pdsprj"
    )
)
set "HEX_FILE=%BUILD_DIR%\%TARGET_NAME%.hex"
set "HEX_ROOT=%PROJECT_DIR%%TARGET_NAME%.hex"

:: Thiết lập toolchain nếu có
set "TOOLCHAIN_ARG="
if exist "%PROJECT_DIR%cmake\gcc-arm-none-eabi.cmake" (
    set "TOOLCHAIN_ARG=-DCMAKE_TOOLCHAIN_FILE="%PROJECT_DIR%cmake\gcc-arm-none-eabi.cmake""
)

echo [INFO] Detected target: %TARGET_NAME%
echo.

:: -----------------------------------------------------
:: 2. LOCATE PROTEUS 8 EXECUTABLE
:: -----------------------------------------------------
set "PROTEUS_EXE="

:: Kiểm tra trong Registry hệ thống
for /f "tokens=2* skip=2" %%a in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PDS.EXE" /ve 2^>nul') do (
    if exist "%%b" set "PROTEUS_EXE=%%b"
)

:: Nếu Registry không có, kiểm tra các đường dẫn mặc định
if not defined PROTEUS_EXE (
    if exist "C:\Program Files (x86)\Labcenter Electronics\Proteus 8 Professional\BIN\PDS.EXE" (
        set "PROTEUS_EXE=C:\Program Files (x86)\Labcenter Electronics\Proteus 8 Professional\BIN\PDS.EXE"
    ) else if exist "C:\Program Files\Labcenter Electronics\Proteus 8 Professional\BIN\PDS.EXE" (
        set "PROTEUS_EXE=C:\Program Files\Labcenter Electronics\Proteus 8 Professional\BIN\PDS.EXE"
    )
)

:: -----------------------------------------------------
:: 3. BUILD FIRMWARE
:: -----------------------------------------------------
echo [1/3] Compiling firmware [%TARGET_NAME%]...
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: Configure CMake nếu chưa tạo Makefile hoặc build.ninja
if not exist "%BUILD_DIR%\Makefile" if not exist "%BUILD_DIR%\build.ninja" (
    cmake -B "%BUILD_DIR%" -G "MinGW Makefiles" %TOOLCHAIN_ARG%
    if errorlevel 1 goto BUILD_ERROR
)

cmake --build "%BUILD_DIR%"
if errorlevel 1 goto BUILD_ERROR

:: Trường hợp tên file HEX đầu ra khác với TARGET_NAME, tự động tìm file .hex trong build/
if not exist "%HEX_FILE%" (
    for /r "%BUILD_DIR%" %%F in (*.hex) do (
        set "HEX_FILE=%%F"
        set "HEX_ROOT=%PROJECT_DIR%%%~nxF"
    )
)

if not exist "%HEX_FILE%" goto BUILD_ERROR

:: Đồng bộ file HEX ra thư mục gốc
copy /y "%HEX_FILE%" "%HEX_ROOT%" >nul

:: Sao chép đường dẫn file HEX vào Clipboard
<nul set /p="%HEX_FILE%" | clip

echo.
echo [2/3] SUCCESS: Firmware compiled successfully!
echo       HEX file updated: "%HEX_FILE%"
echo.

:: -----------------------------------------------------
:: 4. RELOAD OR LAUNCH PROTEUS
:: -----------------------------------------------------
echo [3/3] Checking Proteus 8 status...

tasklist /FI "IMAGENAME eq PDS.exe" 2>NUL | find /I /N "PDS.exe">NUL
if "%ERRORLEVEL%"=="0" goto PROTEUS_RUNNING

:PROTEUS_NOT_RUNNING
if "%PROTEUS_EXE%"=="" (
    echo [ERROR] Proteus 8 is not running and PDS.EXE path was not found.
    goto END
)
if exist "%PDS_PROJECT%" (
    echo [INFO] Proteus is not running. Launching design file: "%PDS_PROJECT%"
    start "" "%PROTEUS_EXE%" "%PDS_PROJECT%"
) else (
    echo [INFO] Proteus is not running. Launching Proteus 8...
    start "" "%PROTEUS_EXE%"
)
goto SUCCESS_END

:PROTEUS_RUNNING
echo [INFO] Proteus 8 is ALREADY RUNNING!
echo [INFO] Triggering simulation reload...

:: Focus vào Proteus, gửi phím Shift+Space để dừng, sau đó gửi Space để nạp lại mã mới và chạy
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$wshell = New-Object -ComObject WScript.Shell;" ^
    "if ($wshell.AppActivate('Proteus')) {" ^
        "Start-Sleep -Milliseconds 200;" ^
        "$wshell.SendKeys('+ ');" ^
        "Start-Sleep -Milliseconds 300;" ^
        "$wshell.SendKeys(' ');" ^
    "}"

:SUCCESS_END
echo.
echo ===================================================
echo   CODE BUILD AND AUTO-RELOAD SUCCESSFUL!
echo ===================================================
echo   HEX Path copied to clipboard: %HEX_FILE%
echo ===================================================
echo.
goto END

:BUILD_ERROR
echo.
echo ===================================================
echo   [BUILD ERROR] COMPILATION FAILED!
echo ===================================================
echo   Please check the error output above.
echo   Fix the code errors and run this script again.
echo ===================================================
echo.

:END
pause