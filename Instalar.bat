@echo off
setlocal
chcp 65001 >nul
title Instalador de Neo Modpack

set "INSTALLER_URL=https://raw.githubusercontent.com/tecteccruz-dot/NeoModPack/main/tools/install.ps1"
set "INSTALLER_SCRIPT=%TEMP%\NeoModPack-install.ps1"

where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo ERROR: Este instalador necesita Windows PowerShell.
  echo Descargalo desde: https://learn.microsoft.com/powershell/
  start "" "https://learn.microsoft.com/powershell/"
  pause
  exit /b 1
)

if exist "%~dp0tools\install.ps1" (
  set "INSTALLER_SCRIPT=%~dp0tools\install.ps1"
) else (
  echo Descargando el instalador actualizado...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%INSTALLER_URL%' -OutFile '%INSTALLER_SCRIPT%'"
  if errorlevel 1 (
    echo.
    echo ERROR: No se pudo descargar el instalador.
    echo Revisa tu conexion e intentalo de nuevo.
    pause
    exit /b 1
  )
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%INSTALLER_SCRIPT%" -Gui
set "RESULT=%ERRORLEVEL%"
exit /b %RESULT%
