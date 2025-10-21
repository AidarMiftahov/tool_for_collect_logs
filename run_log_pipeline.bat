@echo off
setlocal

:: === Настройки ===
set "SCRIPTS_DIR=%~dp0"
set "COLLECT_SCRIPT=%SCRIPTS_DIR%collect_logs.ps1"
set "IMPORT_SCRIPT=%SCRIPTS_DIR%Import-LogsToDB.ps1"
set "WEB_APP=%SCRIPTS_DIR%app.py"

:: === Проверка файлов ===
for %%f in ("%COLLECT_SCRIPT%" "%IMPORT_SCRIPT%" "%WEB_APP%") do (
    if not exist "%%~f" (
        echo ERROR: Required file not found: %%~f
        pause
        exit /b 1
    )
)

:: === Шаг 1: Сбор логов ===
echo.
echo === Step 1: Collecting logs ===
powershell.exe -ExecutionPolicy Bypass -File "%COLLECT_SCRIPT%"
if errorlevel 1 (
    echo ERROR: collect_logs.ps1 failed.
    pause
    exit /b 1
)

:: === Шаг 2: Импорт в SQLite ===
echo.
echo === Step 2: Importing logs to database ===
powershell.exe -ExecutionPolicy Bypass -File "%IMPORT_SCRIPT%"
if errorlevel 1 (
    echo ERROR: Import-LogsToDB.ps1 failed.
    pause
    exit /b 1
)

:: === Шаг 3: Запуск веб-приложения ===
echo.
echo === Step 3: Starting web application (app.py) ===
echo Opening browser in 3 seconds...
timeout /t 3 /nobreak >nul

:: Запускаем Python в новом окне (чтобы не блокировать текущее)
start "" python "%WEB_APP%"

:: Опционально: открыть браузер
start "" "http://127.0.0.1:5000"

echo Web app started. Check the new console window for logs.
echo Press any key to close this launcher (web app will keep running).
pause >nul