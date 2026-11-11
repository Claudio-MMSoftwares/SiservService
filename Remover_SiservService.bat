@echo off
setlocal
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Este arquivo precisa ser executado como Administrador.
  pause
  exit /b 1
)

net stop SiservService >nul 2>&1
sc.exe delete SiservService
schtasks /Delete /TN SiservService /F >nul 2>&1
echo Servico removido.
pause
exit /b 0
