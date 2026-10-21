# Preparación de la actualización del cliente

El paquete de inventario permite obtener la información de la instalación real
antes de construir el ZIP de aplicación compatible. No ejecuta la actualización.

1. Extraer el ZIP de inventario en una carpeta del equipo del cliente.
2. Abrir Windows PowerShell como administrador para poder consultar los servicios
   y leer la configuración instalada.
3. Ejecutar, indicando la ruta real de instalación:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Inventariar-Instalacion-Cliente.ps1 -InstallRoot 'C:\ProgramData\Aelium\Propiedades' -OutputPath "$env:USERPROFILE\Desktop\promalza-inventario-cliente.json"
```

El script consulta servicios, calcula hashes, consulta el historial de migraciones
y solicita `release.json` al portal configurado. Ejecuta `--release-info` del
backend instalado para identificarlo. No detiene servicios ni modifica la
aplicación, la configuración o las bases de datos. Crea únicamente el JSON de
salida. La consulta del portal necesita conexión a Internet.

Revisar el JSON antes de compartirlo: incluye rutas, versiones, hashes, servicios
y el dominio del portal; omite contraseñas y registros de los inquilinos.
Devolver ese JSON al responsable de la actualización. No enviar settings.json,
api.json, bases de datos ni carpetas de copias de seguridad.

El inventario es evidencia inicial: el responsable debe completar y revisar el
catálogo de origen, las dependencias, la observación y el inventario de
almacenamiento que exige el actualizador. Después construirá el ZIP de aplicación
y comprobará la actualización y recuperación en una copia aislada antes de
aplicarla al cliente. Un ZIP de candidata o de mantenimiento por sí solo no
constituye esa entrega instalable.
