# Backend de PROMALZA en Windows

Guía para el cliente y su responsable técnico. El backend guarda los datos en el ordenador servidor; el frontend se publica por separado en Cloudflare. Mantener el servidor encendido, con Internet y sin suspensión.

## 1. Elegir el procedimiento

| Situación | Qué utilizar |
| --- | --- |
| Equipo nuevo, sin PROMALZA | Instalador completo de Windows, con `Instalar.cmd`, `Instalar.ps1`, dependencias y payload. |
| Equipo que ya tiene PROMALZA y datos | Paquete de actualización compatible, catálogo y observaciones revisados, más herramientas de mantenimiento. |
| ZIP `promalza-candidate-20261021-r1` | Material para revisión. Contiene el ejecutable, pero no el instalador completo ni el paquete de actualización admitido para el cliente. |

No ejecutar el EXE de la candidata para instalar ni copiarlo encima del servidor existente. El responsable debe entregar el paquete apropiado antes de los pasos 3 o 4.

## 2. Preparar la entrega

El responsable confirma: ruta de instalación, dominio HTTPS del portal y dominio de la API, cuenta del propietario y resultado del ensayo de actualización/restauración sobre una copia aislada. En una actualización, debe haber revisado el inventario del cliente y los archivos de compatibilidad y almacenamiento.

Extraer el ZIP en una carpeta local, por ejemplo `C:\Entregas\Promalza`. Obtener el SHA256 de referencia del responsable por un canal autenticado y comprobarlo antes de extraer:

```powershell
Get-FileHash -LiteralPath 'C:\Entregas\paquete.zip' -Algorithm SHA256
```

El valor debe coincidir exactamente con la referencia. Conservar la entrega anterior y una copia recuperable fuera del equipo. Las copias contienen datos privados.

## 3. Instalación inicial — solo equipo nuevo

Requiere Windows x64 compatible y permisos de administrador. El instalador nativo no necesita Docker, Node ni Rust en el cliente. La validación del Windows concreto y sus servicios debe completarse antes de dar la instalación por aceptada.

1. Usar el instalador completo preparado por el responsable; no la carpeta `backend` de la candidata.
2. En la carpeta extraída, pulsar con el botón derecho sobre `Instalar.cmd` y elegir **Ejecutar como administrador**.
3. Introducir el origen HTTPS definitivo del portal, sin barra final, y el usuario y contraseña del propietario. La contraseña debe tener al menos 12 caracteres.
4. Esperar a que terminen las comprobaciones de PostgreSQL, Keycloak, API y login. La ruta habitual es `C:\ProgramData\Aelium\Propiedades`.
5. Si se solicita reiniciar Windows, hacerlo y comprobar los servicios después.

Si la instalación queda incompleta, conservar los archivos y comunicar el fallo al responsable. La reanudación con el instalador original, desde PowerShell como administrador y en su carpeta, es:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Instalar.ps1 -Resume
```

No usar este procedimiento encima de una instalación terminada.

## 4. Actualización — equipo con datos existentes

Este paso solo se ejecuta cuando el responsable haya entregado el ZIP de aplicación compatible y validado el ensayo. El JSON de inventario inicial no sustituye los tres archivos revisados de este ejemplo.

1. Acordar una ventana de mantenimiento y cerrar el portal en todos los dispositivos.
2. Extraer el ZIP de mantenimiento en `C:\Entregas\Promalza\mantenimiento`.
3. Colocar los archivos entregados en `C:\Entregas\Promalza` y abrir **Windows PowerShell como administrador**.
4. Ir a la carpeta de mantenimiento y sustituir las rutas y el hash por los valores de la entrega:

```powershell
Set-Location 'C:\Entregas\Promalza\mantenimiento'
$parameters = @{
  InstallationRoot = 'C:\ProgramData\Aelium\Propiedades'
  Archive = 'C:\Entregas\Promalza\aplicacion.zip'
  ExpectedSha256 = 'SUSTITUIR_POR_SHA256_VERIFICADO'
  CatalogPath = 'C:\Entregas\Promalza\catalogo-revisado.json'
  ObservationPath = 'C:\Entregas\Promalza\entorno-revisado.json'
  InventoryPath = 'C:\Entregas\Promalza\almacenamiento-revisado.json'
}
& .\Actualizar.ps1 -Action Preflight @parameters
```

Continuar únicamente si el resultado indica `PreflightVerified`. Si la política de ejecución impide iniciar el script, solicitar al responsable que lo ejecute conforme a la política del equipo; no cambiar la política global.

```powershell
& .\Actualizar.ps1 -Action Apply @parameters
```

Se solicita la cuenta existente del propietario. La herramienta prepara y comprueba la copia, aplica la actualización y verifica el resultado. No apagar el ordenador durante el proceso. El portal compatible debe estar disponible para la verificación; coordinar su publicación con la guía de frontend.

| Resultado | Acción |
| --- | --- |
| `UpdateSucceeded` | Continuar con las comprobaciones del paso 6. |
| `AlreadyApplied` | Esa entrega exacta ya está aplicada; comprobar igualmente el funcionamiento. |
| `VerificationPending` | No declarar éxito. El responsable corrige acceso/conectividad y ejecuta `Finalize`. |
| `UpdateFailedRecovered` | Se ha recuperado el origen; la nueva versión no está instalada con éxito. Avisar al responsable. |
| Rechazo o recuperación pendiente | Detener el procedimiento y comunicar el resultado. No reinstalar ni borrar copias. |

Los comandos de continuación, reservados al responsable tras revisar el estado, son:

```powershell
& .\Actualizar.ps1 -Action Finalize -InstallationRoot $parameters.InstallationRoot
# Solo cuando proceda recuperar una operación interrumpida:
& .\Actualizar.ps1 -Action Recover -InstallationRoot $parameters.InstallationRoot
```

Una operación ya completada no permite recuperar una copia antigua descartando cambios posteriores.

## 5. Conectar el servidor con Cloudflare

El responsable crea un túnel persistente y publica el dominio API hacia `http://127.0.0.1:58090`. Protege todo ese dominio con Cloudflare Access y una política **Service Auth**; su token se configura en el Worker siguiendo la guía de frontend. PostgreSQL y Keycloak permanecen privados. No abrir puertos del router.

En el servidor, desde PowerShell como administrador:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Configurar-Tunel.ps1'
```

Introducir el token del túnel cuando se solicite. Es distinto del token Service Auth del Worker. Si el túnel existente funciona, conservarlo salvo indicación del responsable.

## 6. Comprobar y aceptar

Desde PowerShell como administrador, comprobar el estado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Administrar.ps1' -Accion Estado
```

Comprobar API, PostgreSQL y Keycloak; también Tunnel cuando esté configurado. Abrir el portal definitivo e iniciar sesión. Revisar edificios, viviendas, inquilinos, importes y documentos existentes; guardar un cambio de prueba acordado, recargar y comprobar su persistencia; cerrar sesión. Reiniciar el servidor y confirmar el acceso desde otro dispositivo antes de iniciar sesión en Windows.

Configurar copias periódicas y verificar una restauración en un entorno separado. La copia manual se solicita con:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\Aelium\Propiedades\scripts\Copia-Seguridad.ps1'
```

Ante un fallo, enviar al responsable el estado y mensaje mostrado, sin contraseñas, tokens, archivos de configuración ni copias de bases por canales públicos.
