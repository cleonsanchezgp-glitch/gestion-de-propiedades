# Actualizar sin reinstalar dependencias

Para la VM aislada sin portal, usar el [ensayo local explícito](ENSAYO-LOCAL.md).
Ese modo devuelve estados LocalRehearsal y no acredita portal ni producción;
la ejecución ordinaria sigue requiriendo el portal HTTPS real.

Estado: implementación y pruebas locales en desarrollo. No autorizada todavía para la instalación del cliente. Falta un Windows de pruebas con administrador, una copia del cliente, admisión del origen real y revisión independiente. Las pruebas actuales usan PostgreSQL y API reales con identidad y portal simulados; no acreditan SCM, reinicios de Windows ni acceso remoto real.

## Preparación de una entrega

El responsable prepara la candidata con identidad de versión, migraciones transaccionales y contrato compatible; construye su ZIP con Build-UpdatePackage.ps1. Revisa el catálogo del origen, la observación del entorno y el inventario de almacenamiento. El catálogo legacy conservado tiene reviewed=false: no cambiarlo para eludir la revisión. No utilizar fixtures como paquetes del cliente.

La herramienta usa las dependencias ya instaladas. El ZIP de mantenimiento y el ZIP de aplicación son entregas distintas. Distribuir sus SHA-256 por un canal de confianza externo; un hash situado junto al ZIP solo acredita consistencia.

## Operación en el Windows de pruebas

Extraer el ZIP de mantenimiento en una carpeta del operador. Abrir Windows PowerShell como administrador. Sustituir los valores de este ejemplo por archivos revisados:

```powershell
$parameters = @{
  InstallationRoot = 'C:\ProgramData\Aelium\Propiedades'
  Archive = 'C:\Entregas\aplicacion.zip'
  ExpectedSha256 = '<SHA256 verificado por canal externo>'
  CatalogPath = 'C:\Entregas\catalogo-revisado.json'
  ObservationPath = 'C:\Entregas\entorno-revisado.json'
  InventoryPath = 'C:\Entregas\almacenamiento-revisado.json'
}
.\Actualizar.ps1 -Action Preflight @parameters
.\Actualizar.ps1 -Action Apply @parameters
```

Preflight comprueba compatibilidad y espacio sin aplicar cambios. Apply pide la cuenta existente del propietario: la contraseña no se guarda. Suspende escritores, copia ambas bases y archivos inventariados, comprueba una restauración aislada, aplica migraciones, selecciona la candidata y verifica acceso y operaciones. No ejecutar Instalar.ps1 para añadir funcionalidades.

Si devuelve VerificationPending, los cambios ordinarios siguen bloqueados. Corregir conectividad o acceso y ejecutar:

```powershell
.\Actualizar.ps1 -Action Finalize -InstallationRoot $parameters.InstallationRoot
```

Para una operación interrumpida o RecoveryRequired, revisar los metadatos privados y ejecutar Recover con la misma raíz. Conserva bases en cuarentena y copias; no eliminarlas manualmente. No permite recuperar una operación ya completada y descartar escrituras posteriores. Si Recover vuelve a fallar, mantener los escritores detenidos y revisar la causa con el responsable. Una restauración interrumpida antes de registrar su validación conserva la base parcial y requiere una reanudación revisada; no la sobrescribe automáticamente.

```powershell
.\Actualizar.ps1 -Action Recover -InstallationRoot $parameters.InstallationRoot
```

Códigos: 0 = PreflightVerified, AlreadyApplied o UpdateSucceeded (leer status); 2 = VerificationPending; 3 = actualización fallida con origen recuperado; 4 = rechazo o recuperación pendiente. Solo UpdateSucceeded declara la nueva versión operativa.

## Límites actuales

El comprobador de conservación rechaza cambios en filas existentes, incluidos cambios de identidad que pueda producir un Keycloak real al iniciar sesión. Las migraciones que transforman datos o añaden columnas a tablas existentes necesitan una política de conservación revisada y pruebas adicionales. No dar por aceptada una entrega solo porque su ZIP sea válido.

Nunca exportar carpetas privadas de mantenimiento o artefactos completos de pruebas: incluyen copias y configuración. Compartir únicamente reportes sanitizados.
