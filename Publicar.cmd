@echo off
setlocal
cd /d "%~dp0"
py -3 tools\publish_pack.py
if errorlevel 1 (
  echo.
  echo No se pudo generar el paquete.
) else (
  echo.
  echo Archivos listos en la carpeta dist.
)
pause
