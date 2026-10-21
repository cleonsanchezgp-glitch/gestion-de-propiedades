# Actualizador de backend con ventana Windows

El cliente abre un único EXE, acepta la elevación de Windows, confirma la carpeta e introduce la cuenta del portal. No necesita Node, Rust ni Docker. Usa Windows PowerShell 5.1 y .NET Framework 4.x de Windows x64.

El ejecutable contiene las herramientas y, en una entrega revisada, el ZIP de aplicación y los tres documentos de compatibilidad. No reinstala PostgreSQL, Keycloak, Java, WinSW ni el túnel. La copia, comprobación de restauración, migración, conservación y recuperación siguen a cargo del actualizador existente. La barra es indeterminada: no presenta porcentajes ficticios. No permite cerrar la ventana mientras ejecuta una operación. No modifica el frontend.

## Preparar el EXE para una instalación concreta

El responsable necesita una carpeta revisada con estos cuatro archivos:

- `application.zip`: paquete format=2 generado con `Build-UpdatePackage.ps1`.
- `catalog.json`: catálogo con los orígenes admitidos revisados.
- `observation.json`: observación del cliente, incluida su ruta de instalación.
- `inventory.json`: inventario de almacenamiento revisado, incluidos adjuntos.

Desde la raíz del repositorio:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/windows/Build-DesktopUpdater.ps1 -DeliveryRoot C:\Entregas\cliente-revisado -ExpectedArchiveSha256 HASH_VERIFICADO
```

El resultado es `Actualizar-Promalza.exe` y su SHA256 bajo `deploy/artifacts/desktop-updater/build-FECHA`. Distribuir únicamente el EXE final y las instrucciones; no enviar la carpeta de construcción ni las copias privadas. El EXE no tiene firma Authenticode de editor: distribuir su hash por un canal autenticado; si se firma, recalcular el hash externo después de firmar.

La construcción comprueba integridad y presencia de revisión, pero la validación definitiva del origen y estado vivo se vuelve a hacer en el equipo antes de cambiar servicios o datos. Construir el EXE no acredita aceptación del cliente. Ensayarlo con servicios y credenciales reales sobre una copia aislada y comprobar recuperación y reinicio antes de distribuirlo para producción.

## Cuando todavía falta el inventario del cliente

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File deploy/windows/Build-DesktopUpdater.ps1 -CandidatePath RUTA\propiedades-backend.exe
```

Genera `Preparar-Actualizacion-Promalza.exe`. Su única acción es obtener el inventario existente y guardarlo donde el cliente elija. No actualiza ni presenta un resultado de actualización correcta. El backend candidato queda incluido como material de preparación, pero no se ejecuta para sustituir una instalación desconocida.

El cliente devuelve el JSON al responsable, que completa la revisión de compatibilidad y almacenamiento, construye `application.zip` y genera la edición final. No fabricar un catálogo revisado a partir de los archivos del cliente sin revisión técnica.

## Uso por el cliente

1. Abrir el EXE y aceptar la solicitud de administrador de Windows.
2. En la edición de preparación, elegir **Obtener inventario**, guardar el JSON y enviarlo al responsable. No enviar bases, contraseñas ni configuraciones.
3. En la edición final revisada, comprobar la carpeta y elegir **Actualizar backend**. Introducir el usuario y contraseña existentes del portal; se usan en memoria y no se pasan por la línea de comandos ni se guardan en un archivo nuevo.
4. Esperar sin apagar el equipo. La ventana distingue éxito, repetición, verificación pendiente y fallo recuperado. Solo un resultado explícito de éxito acredita la nueva versión.
5. Si queda pendiente, revisar el portal con el responsable y usar **Reintentar verificación**. **Recuperar** es para una operación interrumpida/fallida, no para descartar cambios posteriores a una actualización completada.

La extracción queda en una carpeta aleatoria privada bajo `%ProgramData%\PromalzaUpdate`, accesible a administradores y SYSTEM. Se conserva para soporte; no limpiar mientras haya mantenimiento pendiente. Las bases y copias siguen en los directorios que controla el actualizador. El hash embebido detecta corrupción del recurso, pero no sustituye la autenticación del EXE recibido.
