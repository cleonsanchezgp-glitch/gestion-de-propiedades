# Instalador del servidor para Windows 10 Home x64

Entrega nativa: no requiere Docker, Rust, Node, WSL ni iniciar sesión en Windows
para arrancar los servicios instalados. Requiere permisos de administrador,
Windows 10 de 64 bits actualizado (22H2 recomendado) y un procesador Intel/AMD.
Se recomienda disponer de 8 GB de RAM y al menos 5 GB libres más el espacio de datos
y copias. No sirve para Windows de 32 bits ni ARM. Compruebe las actualizaciones de
seguridad disponibles para el Windows 10 del cliente antes de ponerlo en servicio.

## Preparar la entrega (solo en el ordenador de desarrollo)

Para actualizaciones habituales de aplicación, consultar las [herramientas de paquetes versionados](update/README.md). El constructor separado no incluye dependencias sin cambios. El protocolo de actualización del cliente aún está en desarrollo; esta guía mantiene el procedimiento de instalación inicial.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File deploy/windows/Build-Package.ps1 -ReleaseId propiedades-r1 -BuildId propiedades-r1-build1
```

Genera `deploy/artifacts/backend-windows-x64-FECHA.zip` y su SHA256. Incluye la API
compilada y dependencias descargadas de Microsoft, PostgreSQL/EDB, Keycloak,
Eclipse Adoptium, WinSW y Cloudflare. Versiones y hashes están en `manifest.json`.
Los hashes comprueban integridad; el instalador propio no tiene firma de editor.
No incluye bases de datos, contraseñas ni configuración de este ordenador.
Los archivos de licencia de las distribuciones se conservan dentro de sus ZIP.

## Instalación en el ordenador del cliente

1. Copiar el ZIP y el SHA256 al ordenador del cliente; comprobar el hash con
   `Get-FileHash -Algorithm SHA256 RUTA_DEL_ZIP`. Extraerlo en una carpeta local.
2. Botón derecho en `Instalar.cmd` → **Ejecutar como administrador**. Puede ser
   necesario desbloquear el ZIP descargado desde Propiedades antes de extraerlo.
3. Introducir el origen HTTPS definitivo del portal (sin barra final), el usuario
   del propietario y su contraseña, con al menos 12 caracteres. No necesita el
   dominio Keycloak: la identidad queda privada en el ordenador del cliente.
4. Esperar la comprobación de PostgreSQL, Keycloak, API y login. El directorio
   por defecto es `C:\ProgramData\Aelium\Propiedades`.
5. Si Microsoft solicita reiniciar, hacerlo. Comprobar de nuevo el estado de los
   servicios. Si falla la instalación, conservar datos y logs privados; para
   reanudar una instalación incompleta ejecutar el `Instalar.ps1` original con
   `-Resume`. Una instalación terminada no admite reinstalación encima.

Ejemplo de reanudación desde PowerShell como administrador, en la carpeta extraída:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Instalar.ps1 -Resume
```

## Conectar el portal de Cloudflare

La web se despliega por separado con `frontend/wrangler.jsonc`. Configurar
`API_ORIGIN` con el dominio público API y los secretos del token Service Auth
del Worker, como explica la guía `deploy/README.md` del repositorio.

En Cloudflare crear un túnel persistente y una aplicación publicada API que
apunte a `http://127.0.0.1:58090`. Proteger todo ese dominio con Access Service
Auth. No publicar PostgreSQL ni Keycloak; no abrir puertos del router.

En PowerShell **como administrador**, ejecutar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Configurar-Tunel.ps1'
```

El token del túnel se pide oculto y se guarda en un archivo con permisos
restringidos, no en los argumentos del proceso. El túnel queda como servicio
`AeliumTunnel`. El token de servicio Access del Worker es distinto del token
del túnel y se guarda en Cloudflare, no en el frontend compilado.

El instalador configura los servicios `AeliumPostgres`, `AeliumKeycloak` y
`AeliumAPI` con inicio automático y recuperación tras fallo. PostgreSQL escucha
en `127.0.0.1:55434`, Keycloak en `127.0.0.1:58082` y la API en `127.0.0.1:58090`.
Los servicios usan LocalService. Las credenciales y datos tienen ACL restringidas
a administradores, sistema, cuenta instaladora y cuenta de servicio según uso.
No hay reglas de firewall nuevas ni exposición a la LAN.

## Uso y mantenimiento

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Administrar.ps1' -Accion Estado
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Copia-Seguridad.ps1'
```

Las operaciones de mantenimiento requieren PowerShell como administrador. La
copia incluye los dos archivos `pg_dump` y la configuración necesaria para
preservar usuario, identificador y secretos. Contiene información sensible:
conservarla cifrada fuera del ordenador, comprobar restauración y establecer
una tarea periódica de copias. La copia no es una migración automática ni restaura
sobre datos existentes. No copiar carpetas PostgreSQL mientras está funcionando.

La cuenta administrativa local de Keycloak se guarda en
`config\RECUPERACION.txt` (solo administradores/sistema). La contraseña que se
introduce para el portal no se conserva en la configuración tras validar el
login; Keycloak conserva su hash en la base de datos. No guardar logs en carpetas
públicas. Los servicios solo se detienen mediante Administrar.ps1 o Servicios de
Windows; no eliminar el directorio ni usar programas de limpieza sobre sus datos.

Antes de entregar, comprobar desde el portal: login, crear propiedad/inquilino,
registrar un pago, recargar y salir. Reiniciar el ordenador del cliente y comprobar
el acceso antes de iniciar sesión en Windows. Verificar también una restauración
de copia en una instalación separada. Desactivar la suspensión del servidor.

## Alcance de validación

`Instalar.ps1 -SmokeTest -InstallRoot RUTA_NUEVA` permite ensayar PostgreSQL,
Keycloak, migraciones y login con procesos aislados y puertos alternativos, sin
registrar servicios ni instalar el runtime de Microsoft. Es una herramienta
de desarrollo; utiliza un usuario y contraseña aleatorios de prueba, inicia
procesos propios y los detiene al finalizar. Mantiene el directorio para inspección.
No sustituye la validación de servicios y reinicio en Windows 10 Home del cliente.

Fuentes: [PostgreSQL Windows](https://www.postgresql.org/download/windows/),
[Keycloak](https://www.keycloak.org/server/supported-configurations),
[WinSW](https://github.com/winsw/winsw),
[Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/get-started/).
