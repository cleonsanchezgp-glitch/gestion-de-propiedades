# Instalación nueva de PROMALZA en Windows

La entrega vigente es `Instalar-Promalza-Desde-Cero.exe`, acompañada de
`Guia-instalacion-PROMALZA-cliente.pdf`. Ambos están en
`deploy/artifacts/backend-fresh-installer-20261023-r4/PROMALZA/`.

El instalador crea PostgreSQL, Keycloak y la API en
`C:\ProgramData\Aelium\Propiedades`. Después se configura el túnel de Cloudflare
con `Configurar-Tunel.ps1`. El PDF explica los pasos y la comprobación final.

## Construir una nueva entrega

1. Crear el paquete completo con `Build-Package.ps1`, indicando `-ReleaseId` y
   `-BuildId`. El paquete incluye el ejecutable del backend y las dependencias
   declaradas en `dependencies.json`.
2. Ejecutar `Build-FreshBackendInstaller.ps1 -PackageDirectory RUTA_DEL_PAQUETE`.
   Requiere el compilador oficial de Inno Setup en `deploy/tools/inno/ISCC.exe`.
3. Entregar el EXE, su archivo `.sha256` y el PDF. Verificar la instalación y el
   acceso desde el portal según la guía.

Una instalación nueva incompleta se reanuda con `/RESUME=1`.
