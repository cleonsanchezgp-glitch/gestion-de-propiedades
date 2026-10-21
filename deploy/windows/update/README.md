# Paquetes de actualización de aplicación

Herramientas de WP-006: contrato format=2, constructor de ZIP, validación de paquete sin extracción y reconocimiento de huellas sobre evidencia revisada. Usan Windows PowerShell 5.1 y .NET de Windows; no descargan ni instalan dependencias. `Build-Package.ps1` sigue siendo el instalador completo inicial.

La entrada Actualizar.ps1 integra copia, restauración aislada, selección, verificación y recuperación. Su uso y sus límites actuales se describen en [USO.md](USO.md). La validación de servicios Windows, reinicios y copia del cliente sigue pendiente; no se declara una entrega cliente aceptada. Los modos de arranque y control se describen en [STARTUP.md](STARTUP.md). `PackageVerified` y `SourceFingerprintMatched` nunca significan `UpdateSucceeded`.

## Preparar un paquete

Crear una carpeta de contenido que solo contenga los archivos declarados y un JSON de definición fuera de ella. La definición tiene los campos de [manifest.schema.json](manifest.schema.json), salvo `size` y `sha256` en `files`: el constructor los calcula. El verificador PowerShell aplica además las restricciones cruzadas que se describen abajo. Los fixtures y su definición se generan con `npm run test:update-package`; son archivos sintéticos, no ejecutables distribuibles.

El constructor ordinario ejecuta `--release-info` sobre la candidata compilada de confianza y exige que identidad, contrato e historial embebido coincidan con la definición. Rechaza migraciones no transaccionales. `-SyntheticFixture` permite comprobar archivos ficticios únicamente bajo `tests/artifacts/updates`, con identidades `fixture-*`; no se usa para distribuir una aplicación. Los IDs de compilación de desarrollo tampoco representan una entrega productiva aceptada.

```powershell
& .\deploy\windows\Build-UpdatePackage.ps1 `
  -ContentRoot C:\entregas\contenido `
  -DefinitionPath C:\entregas\definicion.json `
  -OutputArchive C:\entregas\distribucion\aplicacion-r1.zip
```

La carpeta de distribución debe existir. Se crean el ZIP, una referencia SHA256 externa y `release-ledger.json`, protegido contra constructores concurrentes por apertura exclusiva. No se sobrescribe un ZIP ni se reutiliza un `releaseId` o `buildId` registrado en esa carpeta. Mantener un único almacén de distribución y su registro; el registro no es un catálogo mundial ni detecta identificadores usados en otra carpeta. Para volver a enviar una entrega, conservar y enviar exactamente su ZIP original. Una construcción interrumpida puede dejar archivos sin registrar: se inspeccionan, no se publican automáticamente ni se borran como parte del constructor.

La referencia SHA256 debe obtenerse de un canal de entrega autenticado distinto del contenido del ZIP. Un `.sha256` recibido junto a un ZIP por un canal no verificado no acredita procedencia. Ejecutar el verificador desde las herramientas de mantenimiento de confianza, nunca desde un ZIP pendiente de verificar.

```powershell
& .\deploy\windows\Test-UpdatePackage.ps1 `
  -ArchivePath C:\entregas\distribucion\aplicacion-r1.zip `
  -ExpectedSha256 <sha256-obtenido-del-canal-autenticado>
```

Se comprueba el hash y se lee el ZIP desde el mismo descriptor, bloqueando cambios concurrentes. No se extraen archivos ni se ejecuta contenido. Hay límites de tamaño, lectura descomprimida acotada y rechazo de enlaces/reparse, rutas absolutas, escapadas, ADS, alias de mayúsculas, nombres reservados, archivos ausentes o extra y claves JSON repetidas. Solo se admiten cuatro nombres de payload: `bin/propiedades-backend.exe`, `scripts/run-api.ps1`, `scripts/application.ps1` y `docs/LEEME.md`. El ejecutable es obligatorio. `target=stable` solo se admite para `scripts/run-api.ps1`; los demás van en una entrega. No hay hooks ni archivos de datos, configuración, instalador o distribuciones de dependencias.

## Contrato de compatibilidad

- `format=2`, `kind=application-update`, `product=aelium-propiedades`, `platform=windows-x64`.
- `releaseId` y `buildId` identifican la candidata; `acceptedSources` contiene `sourceId` y referencia `evidence` de revisión para cada origen admitido. Los identificadores son de 1–80 caracteres ASCII, sin separadores de ruta.
- `files` declara ruta, destino, tamaño exacto y SHA256. El ZIP contiene exactamente esos archivos y `manifest.json`. Límites: 512 MiB por archivo, 1 GiB de contenido total y 1 MiB de manifiesto.
- `dependencies` exige evidencia de las seis dependencias existentes: `postgresql`, `keycloak`, `java`, `winsw`, `cloudflared` y `vc-runtime`. Cada entrada tiene versión y archivos instalados con hashes. El hash del ZIP de un proveedor no sustituye al de un archivo instalado. No se permite un cambio de dependencias en este flujo.
- `schemaBefore`, `migrations` y `schemaAfter` contienen versiones SQLx como cadenas decimales y checksums SHA384 de 96 caracteres hexadecimales. El historial final debe ser exactamente el previo más las migraciones nuevas; no se admiten versiones repetidas. WP-007 debe contrastar estas declaraciones con las migraciones embebidas y la base real.
- `apiContract` y `supportedFrontends` identifican el contrato y frontends probados, con referencia de evidencia. Declarar una referencia no ejecuta ni demuestra una prueba.
- `recovery` enumera todos los orígenes admitidos, el esquema previo, seis comprobaciones obligatorias y la conservación de aplicación, esquema, datos, identidad, configuración, adjuntos y servicios. No ejecuta esa recuperación.

## Catálogo de instalación antigua

`New-LegacySourceCandidate.ps1` verifica un ZIP completo original contra su referencia externa y todos sus archivos contra el manifiesto original. Traduce el ejecutable y los scripts a sus rutas instaladas. El lector admite separadores antiguos de .NET Framework; format=2 exige `/`.

```powershell
& .\deploy\windows\New-LegacySourceCandidate.ps1 `
  -OriginalArchive C:\entregas\instalador-original.zip `
  -ExpectedSha256 <sha256-original> `
  -OutputCatalog C:\entregas\catalogo-candidato.json
```

El resultado siempre es `reviewed=false`: dependencias instaladas, historial, frontend/contrato, servicios y revisión quedan sin afirmar. El catálogo incluido en [catalogs/legacy-20261010-185325.json](catalogs/legacy-20261010-185325.json) procede del ZIP local conservado de esa fecha, cotejado con su sidecar local. Esto documenta consistencia local, sin comprobar de nuevo un canal autenticado ni el equipo cliente. Su identificador `legacy-<hash>` es el ID del candidato del catálogo; no escribe la identidad instalada `legacy:<huella>` prevista para la adopción. Los instaladores originales nuevos que ya declaran `releaseId` conservan ese ID en el candidato; siguen necesitando revisión e identificación de lo efectivamente instalado.

Para admitir un origen hace falta completar y revisar las evidencias reales. El catálogo tiene `format=1` y `sources`; cada origen contiene `sourceId`, `reviewed`, `reviewer`, `evidence`, `originalArchiveSha256`, `files`, `dependencies`, `schema`, `frontend`, `apiContract` y `services`. Inventariar al menos binario, `run-api.ps1`, `Common.ps1` y `run-keycloak.ps1`, y conservar todos los scripts efectivos. Los servicios mínimos son API, PostgreSQL y Keycloak; incluir Tunnel si existe. Cada servicio declara `id`, `executable` relativo `services/<id>.exe` y `account=LocalService`. Un esquema de servicios diferente se rechaza para este flujo.

La observación tiene `format=1`, `installationRoot` absoluta, `completeInventory=true`, `dependencies`, `schema` con `success=true` por migración, `frontend`, `apiContract`, `services` y referencia `evidence`. Catálogo y observación deben proceder de revisión controlada, no del propio payload. No incluir contraseñas, tokens ni datos personales. El orden y las propiedades de las declaraciones comparadas deben coincidir: ante discrepancia se rechaza de forma conservadora.

```powershell
& .\deploy\windows\Test-UpdatePackage.ps1 `
  -ArchivePath C:\entregas\distribucion\aplicacion-r1.zip `
  -ExpectedSha256 <sha256-autenticado> `
  -InstallationRoot C:\ProgramData\Aelium\Propiedades `
  -CatalogPath C:\mantenimiento\catalogo-revisado.json `
  -ObservationPath C:\mantenimiento\observacion-revisada.json
```

El reconocimiento lee `Complete` y formato de settings y vuelve a calcular hashes de archivos de aplicación y dependencias de esa raíz; un catálogo sin revisión, origen desconocido, instalación parcial o combinación incompatible se rechaza. No modifica esa raíz y no imprime settings. La observación externa aún no se actualiza consultando servicios, base de datos ni portal: el resultado informa `livePreflightComplete=false`. WP-007/009 deben completar comprobaciones actuales de coherencia de configuración, servicios, historial y frontend antes de cualquier mantenimiento. Tampoco se detecta todavía `AlreadyApplied` sobre el futuro selector de entrega.

## Verificación disponible

`npm run test:update-package` construye un ZIP con archivos sintéticos, ejecuta positivos y negativos en PowerShell nativo, comprueba que el reconocimiento no cambia archivos y genera un informe por ejecución en `tests/artifacts/updates/<runId>/report.json`. Comprueba también una unión NTFS y un ZIP original sintético con separadores antiguos. No necesita administrar servicios ni descargar componentes.

Los informes son evidencia parcial de TEST-023, TEST-024 y TEST-035, con entorno, identidades y resultado por variante. No cierran las familias del TMP, WP-006 ni MS-003: faltan el ejecutable identificable, catálogo cliente revisado, estado vivo e integración con actualización/recuperación. Las copias privadas y secretos nunca deben incorporarse a estos informes.
