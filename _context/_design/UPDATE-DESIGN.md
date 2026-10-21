# Diseño de actualización y recuperación del cliente Windows

| Field | Value |
| --- | --- |
| Document | Client Update Design |
| Version | 0.2 |
| Status | Draft - for review; partial local implementation |
| Author | Conditor |
| Organization | Aelium |
| Last Updated | 2026-10-16 |
| Architecture decisions | ADR-012 a ADR-016 en ADD.md |
| Requirement | REQ-008, alcance confirmado el 2026-10-11 |

## 1. Alcance y punto de partida

Diseño para añadir funciones y correcciones sin reinstalar toda la plataforma del cliente. Los contratos descritos tienen implementación local parcial. La revisión del 2026-10-16 contrasta código e informes conservados del 2026-10-11; no acredita ejecución sobre el cliente, servicios Windows reales ni despliegues remotos.

Punto de partida examinado al diseñar el flujo el 2026-10-11 (no representa por sí solo el estado vigente del código):

| Archivo | Comportamiento observado | Consecuencia para el diseño |
| --- | --- | --- |
| deploy/windows/Build-Package.ps1 | Empaqueta API, scripts y todas las dependencias; manifest.json tiene format=1, plataforma, fecha y hashes | Crear un flujo de paquete de aplicación distinto, conservando el instalador inicial |
| deploy/windows/client/Instalar.ps1 | settings.json registra Complete e identidad; bloquea reinstalación terminada; usa servicios con inicio automático y recuperación | Actualizar sobre instalación completa sin invocar instalación inicial ni regenerar secretos |
| deploy/windows/client/run-api.ps1 | Carga config/api.json y ejecuta bin/propiedades-backend.exe | Introducir selección de entrega y comprobación persistente de mantenimiento |
| backend/src/main.rs | Ejecuta sqlx::migrate!().run antes de abrir HTTP | Separar el modo de migración del arranque Windows operativo |
| deploy/windows/client/Copia-Seguridad.ps1 | Dos dumps, pg_restore --list y copia de settings.json | Ampliar cobertura y comprobar restauración; faltan las demás configuraciones, componentes y adjuntos fuera de PostgreSQL |
| deploy/windows/client/Configurar-Tunel.ps1 | Conserva token en config/tunnel-token.txt y wrapper/XML en services | Preservar token, binario, cuenta y configuración; no volver a configurar el túnel |
| frontend/cloudflare/worker.js | Proxy de mismo origen que conserva cabeceras de petición, sustituye credenciales Access y evita caché de API | Comprobar la ruta real del portal sin incluir secretos Access en cliente ni paquete |

No se deduce la versión instalada del valor 0.1.0 de Cargo.toml, de la fecha del ZIP ni de que un servicio responda. No se ha inspeccionado el equipo del cliente. classic + markdown sigue siendo el modelo predeterminado; no hay declaración MANAGEMENT-MODEL.yaml.

## 2. Entregas y reconocimiento del origen — ADR-012 y ADR-013

### 2.1. Paquete habitual

Un ZIP de aplicación con manifest.json, API compilada, scripts de aplicación afectados y documentación. No contiene bases de datos, secretos, configuración del cliente ni distribuciones de PostgreSQL, Keycloak, Java, WinSW, runtime o cloudflared sin cambios. El empaquetado completo actual conserva su función de instalación inicial.

El contrato implementado usa format=2, kind=application-update, product=aelium-propiedades y platform=windows-x64. El contrato debe rechazar formatos o campos obligatorios desconocidos o ausentes; format=1 no se interpreta como paquete de actualización.

| Campo del manifiesto | Significado y validación |
| --- | --- |
| releaseId, buildId | Identificadores únicos de entrega y compilación; no reutilizables para archivos distintos |
| acceptedSources | Entregas o huellas de instalación antigua admitidas y evidencia de compatibilidad probada |
| files | Lista completa de archivos, tamaños, SHA256 y destino permitido de aplicación; se rechazan duplicados, archivos extra ejecutables, rutas absolutas, rutas que escapen y puntos de reanálisis |
| dependencies | Versiones o huellas de dependencias que deben estar ya instaladas; ninguna sustitución implícita |
| schemaBefore, schemaAfter, migrations | Historial esperado de migraciones y checksums compatibles con SQLx; coincide con las migraciones embebidas en el ejecutable |
| apiContract, supportedFrontends | Contrato y entregas de frontend admitidas durante actualización y recuperación, incluidos clientes anteriores |
| recovery | Entrega previa y esquema recuperables, comprobaciones requeridas y conservación de sus componentes |

Antes de ejecutar scripts del paquete se verifica el hash del ZIP contra una referencia obtenida del canal de entrega autenticado, distinta del contenido del mismo ZIP, y después todos los archivos contra el manifiesto. Un hash incluido en un paquete no prueba por sí solo la procedencia. No existe firma de editor en la entrega actual; no se promete una firma inexistente ni se distribuye una clave privada. El primer verificador debe proceder de la entrega de mantenimiento autenticada, no de contenido todavía sin comprobar.

La extracción se inspecciona y se hace en un directorio nuevo de preparación con ACL restringidas. No se sobrescriben archivos activos ni se ejecutan hooks arbitrarios del manifiesto. Destinos de aplicación admitidos: la nueva entrega bajo releases/<releaseId> y, en la primera transición, los scripts estables explícitamente inventariados. Configuración, datos y dependencias no son destinos del payload.

### 2.2. Instalación antigua

Antes de detener servicios se leen sin modificar: Complete, formato y coherencia de configuración; hashes del ejecutable y scripts de arranque; rutas, cuenta y dependencias de servicios; versiones de dependencias; historial SQLx y compatibilidad del frontend. Secretos y datos personales no se incorporan al informe.

Un catálogo de origen revisado debe vincular esos hashes con una entrega original conservada y con las versiones y contratos comprobados. El manifiesto de un ZIP original sirve de evidencia para sus archivos; no se usa el hash del archivo comprimido de una dependencia como si fuese el hash de su ejecutable extraído. El catálogo debe incluir la evidencia adecuada para la instalación efectiva.

Si no hay coincidencia íntegra o no se puede acreditar compatibilidad, se rechaza antes del mantenimiento. Se conserva un informe de lo desconocido para preparar un catálogo verificable; no se asigna una versión ficticia ni se transforma una instalación parcial en completa.

Tras reconocer el origen y comprobar la copia previa, se registra una identidad legacy:<huella> y se introduce el selector de entregas. Los componentes anteriores se conservan con hashes, incluyendo scripts de arranque. Si esta primera transición se revierte, se recupera también el arranque antiguo; nunca se invoca Instalar.ps1 ni New-Realm.

### 2.3. Archivos estables y entregas

Raíz: la ya instalada, por defecto C:\ProgramData\Aelium\Propiedades. El verificador confirma la ruta absoluta y su correspondencia con los servicios antes de mover o restaurar contenido.

| Ruta propuesta bajo la raíz | Función |
| --- | --- |
| releases/<releaseId>/ | Ejecutable y scripts de aplicación de una entrega comprobada e inmutable |
| config/active-release.json | Identidad, ruta relativa y hash de la entrega seleccionada; sin secretos |
| maintenance/operation.json | Operación, fases, versiones, copia, cambios de servicios y resultados; sin secretos |
| maintenance/update.lock | Exclusión mediante apertura exclusiva; una operación incompleta persiste aunque se libere el bloqueo al terminar el proceso |
| backups/<operationId>/ | Copia coherente, componentes previos, inventario y metadatos de restauración, con ACL administrativas |
| scripts/run-api.ps1 | Lanzador estable; valida selector, rutas y estado antes de ejecutar la API |

No cambian nombres de servicios, cuentas, puertos, origen del portal, sujeto autorizado, credenciales ni rutas de dependencias. Los datos y adjuntos no residen en releases. No se eliminan automáticamente entregas anteriores ni copias; la política de retención queda pendiente. Repetir un releaseId ya aplicado exige el mismo hash y devuelve AlreadyApplied sin migrar ni reconfigurar.

El lanzador estable determina la raíz real y la transmite explícitamente a los scripts de la entrega. Un script bajo releases no puede deducir la raíz de instalación haciendo simplemente Split-Path de su propia carpeta; conserva las referencias a config, data y servicios de la instalación existente.

## 3. Fases, arranque y migraciones — ADR-014

Solo una operación de mantenimiento por raíz. Los registros y el selector se escriben mediante sustitución comprobada de archivo en el mismo volumen, sin dejar JSON parcialmente escrito. Se registra la intención antes de cada efecto y su comprobación después; la selección de aplicación y la migración no se describen como una única transacción atómica.

| Fase persistente | Efecto permitido y salida |
| --- | --- |
| Preflight | Validar origen, paquete, permisos, espacio para preparación, copia y recuperación, historial y compatibilidad. Ningún cambio en servicios o instalación; fallos rechazan el paquete |
| Quiescing | Registrar estado, inicio y recuperación de servicios; impedir arranque automático y detener túnel, API y Keycloak en ese orden, comprobando procesos y conexiones. PostgreSQL sigue operativo |
| BackingUp | Con escritores detenidos, capturar y comprobar el conjunto previo. Si falla sin cambios de aplicación/esquema, recuperar el estado de servicios anterior y verificarlo |
| Applying | Registrar intención; introducir el lanzador si corresponde; migrar explícitamente y seleccionar la candidata, manteniendo servicios protegidos y sin escrituras de negocio |
| Verifying | Arrancar Keycloak y candidata de forma controlada y con guardia de mantenimiento. Probar versión, identidad, lectura y escritura sintética; comprobar el portal publicado cuando esté conectado |
| Committing | Registrar comprobaciones y selección durables, restaurar las opciones de servicio inventariadas y comprobar el arranque. Mantener guardia de escrituras hasta finalizar estos pasos |
| Committed | Estado operativo verificado; quitar restricciones temporales y credenciales de comprobación. Es el único resultado UpdateSucceeded |
| Recovering | Detener escritores, restablecer conjunto anterior, comprobarlo y restaurar servicios; se puede repetir desde una fase interrumpida |
| Recovered | Estado anterior verificado. Resultado UpdateFailedRecovered, nunca UpdateSucceeded |
| RecoveryRequired | Recuperación pendiente o fallida; no permitir escrituras de negocio ni otra actualización |

Un reinicio o registro inválido en cualquier fase intermedia mantiene bloqueada la operación normal. El lanzador actualizado y el backend comprueban ese estado antes de atender escrituras; un lock liberado o /health/live=200 no lo sustituye. No se limita la protección a un botón deshabilitado en frontend.

Durante la transición antigua, cuyo lanzador no tiene esta guardia, se deshabilita persistentemente el arranque automático de los servicios escritores y se comprueba su detención antes de iniciar copia o sustitución. Se inventarían también sus opciones de recuperación y el túnel. No se altera PostgreSQL ni se reinstalan servicios. Si se interrumpe antes del corte efectivo y no hubo cambios, se vuelve a comprobar y obtener una copia nueva; no se restaura una copia potencialmente anterior a escrituras aún permitidas. El arranque antiguo no se reactiva antes de verificar una recuperación completa.

La implementación incorpora modos de ejecutable separados:

- --release-info: identidad de compilación, contrato y migraciones embebidas, sin conectar ni migrar bases.
- --migrate-only: ejecución local administrativa de las migraciones declaradas para esta operación, validando historial y finalizando con código de resultado.
- --serve --no-migrate: arranque Windows que solo comprueba el historial esperado; si faltan migraciones o hay checksums incompatibles, no sirve tráfico de negocio.

Estos modos están implementados y cuentan con pruebas locales de API/PostgreSQL. El desarrollo conserva una preparación explícita de su base; esto no acredita servicios Windows ni reinicios reales. Se conservan migraciones aplicadas sin reescribirlas; no se borra la tabla de historial para forzar reejecución. El historial con fallo o diferencia no se da por compatible. Las migraciones no transaccionales, cambios de roles o cambios de dependencias requieren un plan específico y se rechazan en el flujo habitual.

SQLx documenta que run ejecuta migraciones pendientes y valida las aplicadas; por ello no se usa como una mera consulta durante preflight ni durante arranque operativo. [SQLx 0.8.6, Migrator](https://docs.rs/sqlx/0.8.6/sqlx/migrate/struct.Migrator.html).

La protección persistente del arranque se deriva de que Windows arranca los servicios automáticos y permite cambiar su configuración de inicio. Guardar/restaurar esa configuración es parte del protocolo, no evidencia de que ya se haga. [Microsoft: arranque automático](https://learn.microsoft.com/en-us/windows/win32/services/automatically-starting-services), [configuración de servicios](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-changeserviceconfigw).

## 4. Copia y recuperación coherentes — ADR-015

La copia se inicia solo tras comprobar el corte de escritores. API y Keycloak permanecen detenidos mientras se toman los dos dumps y los archivos, de modo que no se interpreta un dump individual como un snapshot simultáneo de todo el sistema. PostgreSQL permanece en funcionamiento; no se copia su directorio de datos en caliente.

Contenido: dumps completos de propiedades y keycloak, inventario de roles y privilegios necesarios, toda la configuración persistente y sus ACL, XML/configuración de servicios, tokens de túnel existentes, componentes de aplicación anterior con hashes y adjuntos en sus ubicaciones inventariadas. Los adjuntos almacenados dentro de PostgreSQL viajan en el dump; si existe almacenamiento externo, se copia también. No se da por cubierto un almacén externo desconocido. El paquete de actualización nunca lleva estos secretos.

El manifiesto privado de copia identifica operación, origen, esquema, archivos/hashes, ubicación de adjuntos, permisos y comprobaciones. Se verifica código de salida, integridad y restauración aislada de los dumps, roles necesarios y relaciones antes del primer cambio irreversible. pg_restore --list solo inspecciona el índice; no sustituye el ensayo de restauración. El espacio para ese ensayo se considera en preflight. Las bases aisladas no se conectan al portal y se limpian únicamente tras verificar sus nombres, pertenencia a la operación y ausencia de uso externo.

pg_dump cubre una base; los objetos globales requieren consideración separada. Se conserva evidencia privada de roles mediante pg_dumpall --globals-only para comprobar restauración en el entorno aislado; el flujo habitual no cambia roles ni restaura indiscriminadamente objetos globales sobre el cluster activo. [PostgreSQL 16: pg_dump](https://www.postgresql.org/docs/16/app-pgdump.html), [pg_dumpall](https://www.postgresql.org/docs/16/app-pg-dumpall.html).

Recuperación después de un cambio de esquema:

1. Registrar Recovering y confirmar escritores detenidos y servicios protegidos. Verificar de nuevo hashes y pertenencia de la copia a la operación.
2. Restaurar los dumps en bases nuevas de recuperación del mismo cluster y comprobarlos, sin sobrescribir ni mezclar datos en las bases afectadas. Conservar propietarios, ACL y roles requeridos; abortar ante un error.
3. Con API y Keycloak detenidos, intercambiar los nombres de las bases de forma controlada, manteniendo las bases fallidas bajo nombres de cuarentena propios de la operación. Registrar cada intercambio; si hay interrupción entre ambos, completar o revertir según las identidades inventariadas, sin arrancar escritores sobre una pareja mezclada.
4. Restaurar archivos/configuración/adjuntos afectados y permisos, seleccionar los componentes previos y verificar el historial de esquema. En la transición inicial recuperar también los scripts antiguos.
5. Verificar Keycloak, identidad existente, lectura y relaciones y ausencia de fixtures. Confirmar compatibilidad con el frontend activo antes de restaurar servicios y habilitar escrituras.
6. Registrar Recovered o RecoveryRequired. Mantener copia y bases fallidas para inspección; no eliminar datos automáticamente.

En una recuperación a la aplicación antigua sin guardia propia, la comprobación de identidad y datos se realiza localmente con el túnel todavía detenido. La compatibilidad del frontend se contrasta con la evidencia de contrato y los metadatos disponibles. El túnel se habilita el último, una vez verificado el conjunto recuperado; no se abre tráfico público para probar una versión antigua aún sin verificar.

pg_restore se ejecutará con salida de error obligatoria; --single-transaction es una opción para la restauración de cada dump en su base aislada, no una transacción que cubra ambas bases, archivos y servicios. [PostgreSQL 16: pg_restore](https://www.postgresql.org/docs/16/app-pgrestore.html).

Si no hubo cambios de esquema ni de datos fuera de comprobaciones sintéticas, recuperar archivos/selector puede ser suficiente, pero exige evidencia de esquema intacto y limpieza comprobada. Nunca se supone que sustituir el ejecutable revierte una migración.

Tras Committed pueden existir escrituras nuevas: esta copia deja de ser una reversión automática admisible. Una recuperación posterior requiere otro plan que preserve esas escrituras. Las sesiones en memoria se pierden al reiniciar la API; se exige nuevo login, conservando usuario, contraseña e identidad, conforme a ADR-011.

## 5. Frontend, comprobaciones y activación — ADR-016

### 5.1. Publicación compatible

Se identifican tres estados de contrato que la entrega debe haber probado: frontend anterior con backend anterior; frontend anterior con backend nuevo; frontend nuevo con backend nuevo. Para recuperar backend anterior después de publicar frontend nuevo, también se exige compatibilidad probada de esa pareja o una recuperación coordinada del frontend. No se asume que todas las pestañas descargan inmediatamente la nueva versión.

Las actualizaciones habituales de /api/v1 preservan el contrato necesario del frontend anterior. El backend nuevo se aplica primero; después se puede publicar el frontend. La nueva interfaz debe conservar el funcionamiento base con el backend recuperable y habilitar funciones nuevas solo cuando la API declare capacidad compatible. Cambios que no permitan esta transición quedan fuera del flujo habitual y requieren plan específico; no se resuelven reinstalando la plataforma.

Se propone release.json público del frontend, sin secretos, con su identidad y contrato; GET /api/v1/system/version protegido informa de releaseId, apiContract, capacidades y estado operativo. La instalación antigua sin estos metadatos se reconoce por el catálogo y evidencia de despliegue/contrato, no por una petición de vida. Los metadatos no sustituyen pruebas del contrato ni identificación del Worker.

No se modifica la configuración Access, el token del túnel, el origen ni los secretos del Worker al actualizar la aplicación. Una reversión Cloudflare es un paso remoto independiente; se conserva su versión y configuración como evidencia. No se garantiza que esté disponible sin comprobar las condiciones de la cuenta y los bindings. [Cloudflare: rollbacks](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/).

### 5.2. Comprobaciones sin modificar registros reales

Antes de admitir una entrega, se conservan resultados de contrato y navegador con los frontends admitidos y datos sintéticos. En la instalación, se verifican versión y esquema, acceso del usuario existente, lectura y una escritura de prueba a través de la API, más la ruta HTTPS del portal/Worker/túnel cuando esté publicada. Una API local correcta no acredita una ruta remota correcta. Si el portal requerido no es comprobable, queda VerificationPending y no UpdateSucceeded.

La contraseña del usuario existente se solicita de forma oculta para la comprobación y se mantiene solo en memoria; no se regenera ni se guarda. Las comprobaciones requieren el mismo sujeto autorizado, validación de origen y sesión que las rutas normales. No se añade un usuario con acceso a datos ni se desactiva autenticación.

Durante Verifying, una capacidad aleatoria por operación, conservada en archivo con acceso mínimo y transmitida solo en las peticiones de comprobación, permite operaciones sobre una lista cerrada de identificadores sintéticos. Requiere además autenticación del propietario y estado/operación coincidentes; no basta venir de loopback, pues el túnel también llega desde loopback. No se incluye en bundles, URLs o logs, no desactiva controles de acceso y no permite escribir registros existentes. Las peticiones de negocio ordinarias reciben 503 con código MAINTENANCE_IN_PROGRESS antes de persistir.

La herramienta prueba creación, consulta y modificación únicamente de fixtures propios de la operación y elimina sus residuos comprobando los identificadores exactos. Un fallo de limpieza bloquea Committing. El token se invalida al terminar o interrumpirse la operación. Cuando se reanuda se genera una capacidad nueva; no se reabre tráfico ordinario sobre una operación sin verificar.

El informe de resultado contiene operación, versiones/huellas, hashes de entrega, fase, comprobaciones, causa de fallo y ubicación de copia. No contiene contraseñas, cookies, tokens, datos de inquilinos ni dumps. UpdateFailedRecovered distingue recuperación satisfactoria de actualización satisfactoria.

## 6. Trazabilidad y límites

| Decisión | Requisitos y criterios cubiertos por el diseño | Alcance que debe cubrirse para aceptación integral |
| --- | --- | --- |
| ADR-012 | FR-013, NFR-008; AC-015, AC-016, AC-108 | Paquete pequeño, repetición sin efecto, conservación de dependencias |
| ADR-013 | FR-012, NFR-010; AC-014, AC-110 | Catálogo antiguo, paquetes alterados e incompatibles, coincidencia de contrato |
| ADR-014 | FR-016, NFR-009; AC-022, AC-023, AC-109 | Cortes de proceso/reinicio en cada fase y bloqueo real de escrituras |
| ADR-015 | FR-014, FR-016, NFR-007, NFR-009; AC-017, AC-018, AC-021, AC-107, AC-109 | Restauración aislada y conservación integral, fallos de copia y esquema |
| ADR-016 | FR-012, FR-015, NFR-010; AC-014, AC-019, AC-020, AC-110 | Combinaciones frontend–API, identidad, ruta publicada y ausencia de éxito falso |

Existe ejecución local parcial de estos escenarios. El [resumen del 2026-10-11](../../tests/artifacts/updates/local-summary.json) registra 128 comprobaciones: 11 Rust, 52 de paquetes, 15 de control, 18 de runtime, 15 de copia/recuperación, 4 de navegador y 13 de flujo integrado. Registra además tres comprobaciones ACL y compilación frontend correcta. Se han leído los informes conservados, sin repetir su ejecución en esta revisión.

La orquestación usa API y PostgreSQL reales, con identidad y portal simulados, sin SCM ni reinicio Windows. El informe declara clientAccepted=false. WP-006 a WP-009 asignan trabajo y TEST-023 a TEST-038 definen cobertura; sus estados y evidencias deben conciliarse por Rector y Quaestor antes de proponer cierre. La matriz debe refrescarse por Vestigator. No se asigna PASS a familias ni requisitos desde el diseño.

Límites y condiciones pendientes:

- Windows aislado con administrador y baseline recuperable; servicios, arranque y reinicios por fase. No se usa el servidor del cliente para sustituir este entorno.
- Catálogo del origen real revisado, copia representativa e inventario completo de almacenamiento; el catálogo legacy conservado sigue sin admitir al cliente.
- Keycloak real y ruta portal/Worker/Access/túnel; el éxito del proxy simulado no acredita la ruta remota ni todas las parejas de frontend–API.
- La conservación actual rechaza cambios en filas existentes, incluidos los que puede producir Keycloak al iniciar sesión. Migraciones que transformen datos o añadan columnas a tablas existentes necesitan una política revisada y pruebas adicionales; no están admitidas por el éxito de los ensayos actuales.
- Una restauración parcial interrumpida se conserva y exige reanudación revisada; no se sobrescribe automáticamente. La repetibilidad comprobada de intercambios de bases no acredita cualquier interrupción durante la restauración.
- Revisión independiente requerida por riesgo Critical y aceptación pendientes. No se declaran cerrados MS-003, MS-004 ni los paquetes asociados.

No se fijan plazos ni esfuerzo. Actualizaciones de dependencias requieren un plan separado; retención, firma de editor, duración máxima de mantenimiento y automatización de distribución permanecen pendientes.

## References

- [ADD](ADD.md), [BRD](../_specification/BRD.md), [FRD de actualizaciones](../_specification/FRDs/frd-actualizaciones-cliente.md) y [NFRD](../_specification/NFRD.md).
- [Guía vigente de uso y límites](../../deploy/windows/update/USO.md), [herramienta integrada](../../deploy/windows/update/Updater.ps1), [copia y recuperación](../../deploy/windows/update/Backup.ps1) y [control](../../deploy/windows/update/Control.ps1).
- [Contrato de API](API-CONTRACT.md), [guía Windows](../../deploy/windows/README.md), [copia existente](../../deploy/windows/client/Copia-Seguridad.ps1), [arranque existente](../../deploy/windows/client/run-api.ps1) y [arranque backend](../../backend/src/main.rs).
- Fuentes oficiales enlazadas en las secciones correspondientes, consultadas el 2026-10-11. Apoyan restricciones de herramientas; la coordinación propuesta del sistema es una decisión de este diseño, no una garantía de sus proveedores.
