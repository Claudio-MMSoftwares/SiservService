@echo off
setlocal
sc query SiservService
if errorlevel 1 echo O servico SiservService nao esta instalado.
pause
exit /b 0
