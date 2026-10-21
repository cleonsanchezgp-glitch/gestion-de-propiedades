# Arranque, versión y mantenimiento — WP-007

Implementación de los modos del ejecutable, guardia de escrituras, lanzador y primitivas de control. No es todavía un actualizador cliente terminado: no conecta la copia/recuperación de WP-008 ni ejecuta el flujo integrado de WP-009. Los helpers no deben instalarse o activarse en un equipo cliente con una simple copia de archivos; la adopción necesita origen admitido, corte de escritores y copia recuperable.

## Compilación identificable

`backend/build.rs` incorpora `AELIUM_RELEASE_ID`, `AELIUM_BUILD_ID` y `AELIUM_API_CONTRACT`. Una compilación `release` exige los dos primeros y admite identificadores ASCII de 1–80 caracteres, empezando por letra/número. Usar IDs nuevos por entrega/compilación y conservar los archivos exactos asociados. En desarrollo se generan IDs `dev-*`, sin inferir la versión desde Cargo; no acreditan una entrega cliente aceptada.

```powershell
$env:AELIUM_RELEASE_ID='propiedades-r1'
$env:AELIUM_BUILD_ID='propiedades-r1-build1'
$env:AELIUM_API_CONTRACT='propiedades-v3'
cargo build --locked --release --target x86_64-pc-windows-msvc --manifest-path backend/Cargo.toml
```

El constructor inicial también acepta `-ReleaseId`/`-BuildId` y restaura las variables previas tras compilar. Su manifiesto format=1 conserva estos metadatos. Los instaladores antiguos guardados no se reescriben. El constructor de actualización contrasta el historial del manifiesto con el que declara el ejecutable.

## Modos de ejecutable

| Comando | Efecto |
| --- | --- |
| `--release-info` | JSON con producto, release/build, contrato, migraciones/checksums SQLx y si todas son transaccionales. No carga autenticación, conecta la base ni migra |
| `--serve --no-migrate --install-root <raíz>` | Arranque administrado: exige registro válido, fase que permita iniciar y coincidencia de entrega; consulta el historial completo antes de abrir HTTP; no ejecuta migraciones |
| `--migrate-only --install-root <raíz>` | Solo en Applying para la candidata. Comprueba un prefijo compatible, aplica pendientes con SQLx, vuelve a verificar y termina sin abrir HTTP |
| `--migrate-only --bootstrap --install-root <raíz>` | Preparación explícita de instalación inicial incompleta; rechaza Complete=true y un protocolo de actualización ya introducido |
| `--serve --no-migrate --initial-layout --install-root <raíz>` | Arranque del instalador inicial, sin selector nuevo ni migraciones implícitas. Cuando se introduce mantenimiento bloquea negocio; solo admite de nuevo este layout tras Recovered verificado de su misma entrega y sin selector activo |
| `--dev --migrate` | Preparación y arranque explícitos para desarrollo, fuera de una raíz administrada. Los scripts de ensayo existentes pasan ahora estos argumentos |

El arranque sin argumentos tampoco migra: requiere raíz operativa o un modo explícito válido y, sin ella, termina con error. No se permite `--serve --migrate`. La consulta de esquema verifica todas las versiones, checksums y estados success; faltantes, extras, cambios o fallos impiden servir. No borra el historial ni modifica migraciones aplicadas. El modo administrativo habitual rechaza migraciones no transaccionales; cambios de roles/dependencias requieren su plan y revisión específicos.

SQLx `run` aplica pendientes además de validar; por eso se usa una consulta separada para el arranque. [SQLx 0.8.6: Migrator](https://docs.rs/sqlx/0.8.6/sqlx/migrate/struct.Migrator.html).

## Registro y exclusión

`maintenance/operation.json` tiene `format=1`, `operationId`, `phase`, `sourceReleaseId`, `targetReleaseId`, `backupReference`, `checksPassed`, `step` y array `services`. El registro no lleva credenciales. `Committed` y `Recovered` requieren checksPassed=true; es un indicador que deberá publicar el flujo de comprobación real, no evidencia por sí mismo.

`Control.ps1` ofrece `Open-UpdateControl`, `Set-UpdateOperation` y helpers de servicio. Abrir control conserva un descriptor exclusivo de `update.lock`; mantenerlo durante toda la operación y cerrarlo en finally. Otra operación incompleta no puede sustituirse. Las transiciones siguen el orden de fases, o entran en recuperación; no se permite saltar de Preflight a Committed ni cambiar identidades dentro de la operación.

La publicación JSON usa archivo nuevo, flush y sustitución en el mismo volumen. `write-gate.lock` coordina los procesos: las peticiones de escritura guardan un bloqueo nativo compartido hasta acabar el handler/transacción; el publicador toma un bloqueo exclusivo antes de sustituir estado. Si hay conflicto no publica una fase y devuelve fallo para reintento controlado. El flujo de WP-009 debe esperar el drenaje antes de seguir; no sustituye la comprobación de detención/conexiones para copiar datos.

La API relee el registro por petición. Registros ausentes, inválidos, con enlaces/reparse, fase desconocida, identidad incompatible o terminal no verificado no habilitan escrituras. Las ordinarias reciben 503 y `MAINTENANCE_IN_PROGRESS` antes de acceder al handler de escritura. Login/logout siguen disponibles para las comprobaciones de identidad. El arranque controlado se permite en Verifying/Committing, manteniendo la guardia, o en un terminal verificado.

## Lanzador y selector

`update/run-api.ps1` es la candidata a lanzador estable `scripts/run-api.ps1`, distinta del script del instalador inicial. Recibe `-InstallRoot` explícita o la raíz padre cuando está colocado en la carpeta estable de scripts. No deriva la raíz desde una entrega bajo releases.

`config/active-release.json` declara `format=1`, `releaseId`, `path=releases/<releaseId>` y `manifestSha256`. El lanzador verifica selector, ruta, manifiesto, archivos y fase antes de iniciar; rechaza reparse y destinos no admitidos. Lee metadatos del ejecutable sin secretos, los compara con contrato/historial, carga la configuración existente y llama a serve sin migración. No crea secretos, usuarios, realm, dependencias o servicios.

`-CheckOnly` verifica únicamente metadatos/archivos de arranque; no ejecuta el binario, consulta la base ni acredita readiness. La escritura/selección de una entrega y recuperación del selector se conectan en WP-008/009.

## Identidad y comprobaciones sintéticas

`GET /api/v1/system/version` conserva la autenticación existente y la restricción al sujeto propietario. Devuelve metadatos de compilación, fase, capacidad write y un `instanceId` nuevo por proceso; no publica configuración, copia o tokens. `/api/v1/me` comunica write=false durante mantenimiento.

`Set-DiagnosticGrant` requiere administrador y Verifying. Escribe `maintenance/diagnostic.json` con nonce aleatorio, operación, instanceId y un máximo de 16 fixtures; protege el directorio para SYSTEM/Administrators y lectura de LocalService. No imprime el nonce. Obtenerlo de forma privada para la herramienta de comprobación, nunca de una URL, bundle o informe público.

Las peticiones usan `X-Aelium-Operation`, `X-Aelium-Capability` y, para crear, `X-Aelium-Fixture`, además de autenticación normal. Se admiten POST de creación y GET/PATCH/DELETE sobre IDs exactos `maintenance-<operationId>-...` de las cuatro colecciones persistentes. No hay capacidad para pagos de inquilinos reales ni rutas arbitrarias. Referencias de fixtures deben apuntar a otros fixtures creados por esta comprobación; no a registros del cliente.

El proceso recuerda solo registros que ha creado satisfactoriamente; no permite adoptar ni sobrescribir un registro previo por aparecer en una lista. La limpieza elimina únicamente ese registro y sus auditorías sintéticas, respetando dependencias. Reiniciar el proceso invalida la capacidad anterior; detectar un registro inválido, salir de Verifying o rotar nonce también impide reusar la anterior. Si quedan fixtures tras interrupción, no se supone que desaparecieron: WP-008/009 deben recuperar o resolver el conjunto antes de Committing.

## Protección de servicios antigua

`Suspend-UpdateWriters` exige administrador, Quiescing, rutas de servicio bajo la raíz y cuenta LocalService. Inventaría estado, inicio, inicio retrasado y recuperación; persiste la intención antes de efectos. Deshabilita inicio y recuperación y detiene Tunnel → API → Keycloak; PostgreSQL no cambia. Comprueba opciones persistidas y ausencia de procesos escritores bajo la raíz. Devuelve `databaseConnectionsVerified=false`: antes de copiar falta contrastar conexiones/escritores en ambas bases.

`Restore-UpdateWriters` exige comprobaciones verificadas y fase Committing/Committed/Recovered. Restaura opciones y estado previo en orden Keycloak → API → Tunnel y comprueba opciones. No declara UpdateSucceeded. Las acciones de reinicio se admiten; recovery con comandos personalizados/reboot se rechaza y exige otro plan para no exponer datos ni inventar una recuperación. Ante error se conserva el registro y la protección aplicada; nunca reinstala servicios para remediarlo.

La implementación usa las APIs SCM para leer/escribir configuración, sin analizar texto localizado de `sc.exe` ni asumir que una modificación directa del registro actualiza el gestor. [Microsoft: QueryServiceConfig2](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-queryserviceconfig2w), [ChangeServiceConfig2](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-changeserviceconfig2w). La reversión administrativa del estado persistido queda a cargo del flujo de recuperación, no de un catch que reactive un conjunto sin verificar.

## Pruebas disponibles y pendientes

- `cargo test --manifest-path backend/Cargo.toml --locked --offline`: política de historial, fases, identidad, capacidad y CLI, más pruebas existentes.
- `npm run test:update-control`: journal, exclusión, transiciones y metadatos de lanzador. Compila el helper SCM, pero no modifica servicios.
- `npm run test:update-runtime`: exige Windows y ZIP/manifest original de PostgreSQL conservados. Prepara otro cluster bajo una carpeta nueva de artefactos, prueba API real y una identidad RSA sintética local y detiene sus procesos al terminar. No usa Keycloak/DB del cliente ni instala servicios. El ZIP con ejecutable real de este ensayo contiene declaraciones sintéticas de dependencias; no es una entrega productiva aceptada.
- `npm run test:update-package`: regresión de constructor/verificador y candidatos antiguos.

Los informes sanitizados por runId se guardan bajo `tests/artifacts/updates`. Los clusters, logs privados, grants y demás archivos de fixture no se exportan como evidencia pública. La firma del fixture comprueba el validador JWT y el sujeto exclusivo, no el Keycloak o portal real. Faltan cambios SCM y reinicio real en entorno representativo WP-010, revisión independiente, arranque completo del instalador con esta versión y la integración de conservación/recuperación. No se cierran familias del TMP ni MS-003.
