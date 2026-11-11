@echo off
setlocal
net start SiservService
if errorlevel 1 (
  echo O servico nao esta instalado ou nao pode ser iniciado.
  pause
  exit /b 1
)
echo SiservService iniciado.
exit /b 0
