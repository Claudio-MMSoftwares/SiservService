@echo off
setlocal
set "APP_DIR=%~dp0"
set "SERVICE_EXE=%APP_DIR%SiservServiceHost.exe"

net session >nul 2>&1
if not "%errorlevel%"=="0" (
  echo Este arquivo precisa ser executado como Administrador.
  pause
  exit /b 1
)

if not exist "%SERVICE_EXE%" (
  echo Host do servico nao encontrado: %SERVICE_EXE%
  echo Compile o projeto SiservServiceHost antes de instalar.
  pause
  exit /b 2
)
if not exist "%APP_DIR%SiservService.dll" (
  echo DLL nao encontrada: %APP_DIR%SiservService.dll
  pause
  exit /b 3
)

net stop SiservService >nul 2>&1
schtasks /Delete /TN SiservService /F >nul 2>&1
sc.exe delete SiservService >nul 2>&1
sc.exe create SiservService binPath= "%SERVICE_EXE%" DisplayName= "Siserv Service" start= auto obj= LocalSystem
if errorlevel 1 (
  echo Falha ao instalar o servico SiservService.
  pause
  exit /b 4
)

echo Servico instalado com sucesso.
echo Iniciando SiservService...
net start SiservService
echo.
echo Use Parar_SiservService.bat, Iniciar_SiservService.bat ou Remover_SiservService.bat.
pause
exit /b 0
