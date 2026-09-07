@echo off
setlocal
chcp 65001 >nul
title Actualizador de Neo Modpack

set "UPDATER_URL=https://raw.githubusercontent.com/tecteccruz-dot/NeoModPack/main/tools/install.ps1"
set "UPDATER_SCRIPT=%TEMP%\NeoModPack-update.ps1"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Este actualizador necesita Windows PowerShell.
  echo Descargalo desde: https://learn.microsoft.com/powershell/
  start "" "https://learn.microsoft.com/powershell/"
  pause
  exit /b 1
)

if exist "%~dp0tools\install.ps1" (
  set "UPDATER_SCRIPT=%~dp0tools\install.ps1"
) else (
  echo Descargando el actualizador mas reciente...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%UPDATER_URL%' -OutFile '%UPDATER_SCRIPT%'"
  if errorlevel 1 (
    echo.
    echo ERROR: No se pudo descargar el actualizador.
    echo Revisa tu conexion e intentalo de nuevo.
    pause
    exit /b 1
  )
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UPDATER_SCRIPT%" -UpdateOnly
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo La actualizacion no se completo.
pause
exit /b %RESULT%
