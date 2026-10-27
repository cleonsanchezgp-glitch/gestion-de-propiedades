@echo off
setlocal
set "ROOT=%~dp0"
set "ACTION=Install"

if /I "%~1"=="update" set "ACTION=Update"
if /I "%~1"=="recover" set "ACTION=Recover"
if not "%~1"=="" if /I not "%~1"=="update" if /I not "%~1"=="recover" (
    echo Uso: Instalar-Cliente.bat [update^|recover]
    exit /b 2
)

if not exist "%ROOT%compose.yaml" (
    echo Falta compose.yaml junto al instalador.
    exit /b 2
)
if not exist "%ROOT%Actualizar.ps1" (
    echo Falta Actualizar.ps1 junto al instalador.
    exit /b 2
)
if not exist "%ROOT%.env" (
    echo Falta .env. Copie .env.example a .env y complete la configuracion privada.
    exit /b 2
)
where docker >nul 2>&1
if errorlevel 1 (
    echo Docker no esta instalado o no aparece en PATH.
    exit /b 2
)
docker info --format "{{.ServerVersion}}" >nul 2>&1
if errorlevel 1 (
    echo Docker Desktop no esta iniciado o no esta disponible para esta cuenta de Windows.
    exit /b 2
)

echo Ejecutando %ACTION% desde "%ROOT%"...
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%Actualizar.ps1" -Action %ACTION%
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
    echo La operacion fallo. Revise el error y state\update.log.
    exit /b %RESULT%
)
echo Operacion completada.
exit /b 0
