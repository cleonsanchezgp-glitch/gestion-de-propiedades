# Plan de gestión de pruebas

## Title

| Field | Value |
| --- | --- |
| Document | Test Management Plan |
| Initiative | Portal de gestión de propiedades |
| Version | 0.5 |
| Status | Draft - for review; partial local evidence; families open |
| Author | Quaestor |
| Reviewers | Responsable del producto y revisor independiente — pendientes |
| Organization | Aelium |
| Last Updated | 2026-10-16 |

## 1. Introduction

### 1.1 Purpose

Preparar las pruebas del portal centralizado siguiendo la política y estrategia de Aelium designadas desde CRM. Este plan no constituye aprobación de requisitos pendientes ni evidencia del software. Se aplica classic + markdown; sin declaración de ejecución, los resultados deberán provenir de una herramienta externa que se elija y vincularse aquí.

## 2. Test Objectives

| Objective | Description |
| --- | --- |
| Centralización e integridad | Verificar que cambios y consultas se resuelven en backend sin éxito falso ni descarte silencioso |
| Acceso | Verificar acceso exclusivo del responsable, rechazo de otros usuarios autenticados y de sesiones inválidas en todas las rutas protegidas |
| Dos formatos | Completar consultas y cambios en móvil y ordenador |
| Continuidad | Contrastar datos y funciones acordadas con el origen sin asumir que todo comportamiento actual es correcto |
| Actualización del cliente | Incorporar funciones sin reinstalar toda la plataforma, conservando datos, identidad y configuración, y rechazando versiones incompatibles |
| Recuperación de actualización | Recuperar un conjunto coherente tras fallo o interrupción, sin escrituras sobre estado incompleto ni descarte de cambios posteriores a una actualización ya terminada |

La revisión del 2026-10-09 incorporó las tres decisiones confirmadas de producto y ADR-009/ADR-010. La del 2026-10-11 añade REQ-008 y ADR-012 a ADR-016, con TEST-023 a TEST-038. La profundidad se deriva de las 19 subcaracterísticas High de [SQCA](SQCA.md). La estrategia local de Aelium clasifica autenticación, datos personales y registros financieros como Critical, con todos los niveles aplicables y revisión independiente. No se ha realizado esa revisión. La estrategia sigue siendo la copia en borrador designada desde CRM; no se afirma aprobación organizativa ni comprobación nueva de vigencia de su fuente.

## 3. Test Scope

### In Scope

- FR-001 a FR-009 y NFR-001 a NFR-006, con casos condicionados cuando falte una regla de aceptación.
- Autenticación, datos de gestión, persistencia, errores y uso en ambos formatos.
- Importación propuesta: identificadores, relaciones, borrados y datos no reconstruibles.
- Revisión visual de temática inmobiliaria y referencias a Zaragoza.
- FR-012 a FR-016 y NFR-007 a NFR-010: paquete de aplicación, adopción de instalación antigua, compatibilidad, copia coherente, control de escrituras, actualización, repetición y recuperación. Cada familia nueva incluye variantes Critical donde afecta identidad, persistencia o migración; los aspectos de diagnóstico y recursos Medium reciben variantes enfocadas.

### Out of Scope

- FR-010 y FR-011: Ibercaja/n8n diferidos a fase futura.
- Transferencias bancarias y decisiones financieras automáticas no solicitadas.
- Certificación normativa y compromisos de rendimiento, disponibilidad o accesibilidad aún no definidos.
- Cambios de versión de dependencias, pruebas sobre datos reales o el servidor del cliente, creación de infraestructura comercial y publicación remota no autorizadas. La distribución automática de la API para la nueva variante Docker se cubre en TEST-039 a TEST-041, en un entorno aislado antes de entregarla al cliente.

## 4. Test Strategy

| Level | Description |
| --- | --- |
| Unit Testing | Estados, reglas de validación, cálculos y conservación de valores desconocidos; reglas exactas pendientes donde se señala |
| Integration Testing | API con persistencia y Keycloak; comprobación de acceso y rechazos; importación sintética |
| System Testing | Consistencia entre pantallas, errores ante fallos y consulta desde segundo dispositivo |
| End-to-End Testing | Acceso, consulta, cambio, confirmación y cierre de sesión desde móvil y ordenador |
| Acceptance | Revisión de resultados contra criterios acordados, incluidos alcance visual y discrepancias de importación |

Orden: acceso e integridad de datos, cambios y resúmenes financieros, uso en ambos formatos, revisión visual. Los casos Critical requieren variantes unitarias, de integración, de sistema y aceptación aplicables; la tabla siguiente identifica familias de casos, no sustituye su desarrollo ejecutable.

Entrada: implementación disponible, contratos y reglas relevantes definidos, entorno listo y datos controlados. Salida: criterios del nivel satisfechos y ningún incidente Critical o High de integración abierto. No se declara completada la fase con incidentes Critical abiertos; decisiones de riesgo residual deben quedar registradas, siguiendo Test Strategy.

Para actualizaciones: primero verificador de paquete/origen y casos de rechazo sin cambios; después arranque sin migración y guardia de escrituras; luego copia/restauración aisladas; por último actualización integrada, compatibilidad de portal y fallos por fase. Las variantes unitarias comprueban decisiones de formato/estado; integración verifica API, SQLx, identidad y archivos; sistema Windows verifica servicios y reinicio; E2E usa portal, proxy y datos sintéticos; aceptación compara los criterios y revisa evidencia. La disponibilidad de un entorno o una prueba unitaria no acredita los demás niveles.

Entrada específica: contratos de WP-006 disponibles para pruebas estáticas; candidatos identificables y primitivas implementadas para integración; MS-004/entorno WP-010 comprobado antes de ensayos Windows con servicios o reinicio; configuración autorizada de portal de prueba para E2E. Si falta un prerrequisito se registra Not Run en el plan y, cuando haya intento de ejecución, BLOCKED con causa en el registro externo, sin degradar el caso a una prueba local que se declare equivalente.

## 5. Test Environment

| Environment | Description |
| --- | --- |
| Local | PostgreSQL y Keycloak aislados mediante tests/compose.yaml; backend y frontend locales con implementación parcial y datos sintéticos |
| Validación | Configuración representativa para identidad, HTTPS y persistencia; aún sin provisionar |
| Navegadores | Matriz de navegadores/versiones pendiente; anchuras propuestas de 360 y 1440 px no equivalen a matriz de compatibilidad confirmada |
| Windows aislado | Entorno WP-010 con versión/build registrados, representativo del Windows x64 objetivo del instalador y con baseline sintética recuperable; disponibilidad pendiente, sin utilizar instalación personal ni servidor cliente |
| Portal de prueba | Frontend/Worker, Access y túnel configurados para la identidad y datos sintéticos del ensayo; disponibilidad pendiente y publicación sujeta a autorización específica |

El usuario autorizó implementar infraestructura de pruebas el 2026-10-03 y usar el entorno local el 2026-10-09. Se gestiona en INI-002 / PRJ-002 / WP-001, separada de la entrega del portal. Existen Compose, realm, fixtures, runner de API y pruebas de navegador con dos identidades humanas sintéticas. Hay ejecución parcial de aplicación enlazada abajo, sin configuración de producción ni CI remoto. Los estados Not Run de la tabla representan familias cuyo cierre completo no se ha evaluado; no sustituyen los resultados de los artefactos externos.

La preparación Windows, baseline, capacidades de interrupción y recogida de artefactos están planificadas en [WP-010](../_planning/WP-010.md), bajo la iniciativa independiente INI-002. Quaestor describe el entorno y los casos; no lo provisiona ni registra servicios. Docker/Compose no demuestra el comportamiento de los servicios nativos o del arranque del equipo. Una ejecución en otra edición/build Windows debe declarar su límite de representatividad antes de usarse para aceptación.

## 6. Test Data

Datos sintéticos para propiedades, inquilinos, rentas, estados y adjuntos. Preparar dos identidades sintéticas: responsable permitido y otro usuario autenticado del mismo emisor; importes debidos 600.00, abonados 250.00, saldo 350.00, decimales 0.30 y 0.10, y cantidades históricas null. Preparar casos con referencias inválidas, inquilino borrado, recibo existente, contrato con fechas iguales y pago parcial sin importe. No copiar datos personales de DOC.txt a fixtures, capturas o registros de CI. La revisión local del origen no es evidencia de una migración futura.

Para actualizaciones se requiere una instalación completa sintética de origen con huella reconocida, candidata compatible y candidatas negativas; dependencias inventariadas; historial SQLx con checksums; dos versiones de frontend identificadas; y variantes con migración declarada y fallo inducido. La referencia anterior incluye los seis módulos, IDs/relaciones, importes y null, contenido de adjuntos, sujeto/emisor, configuración de origen/puertos/servicios/túnel y ACL. Comparar contenido de negocio normalizado, no exigir igualdad binaria entre dumps de esquemas distintos.

Los secretos y tokens de prueba se crean para el ensayo; las copias pueden contenerlos bajo ACL privadas, pero informes, capturas y bundles públicos no. Usar identificadores de fixture propios de cada operación y comprobar su limpieza. Antes de cada variante destructiva restaurar la baseline de ensayo; no encadenar variantes sobre un estado desconocido. El caso posterior a Committed crea expresamente una escritura sintética nueva para comprobar que no se pierde al solicitar una reversión automática inadmisible.

## 7. Automation Strategy

Seleccionar herramientas después del stack: framework unitario, integración/API, navegador y captura de evidencias. Automatizar regresión de autenticación y registros financieros como exige Aelium. La revisión estética permanece humana. CI, repositorio remoto y ejecutor no están configurados.

Cada ejecución deberá identificar versión del software, entorno, caso, fecha, resultado y artefacto. El enlace de evidencia estará vacío mientras no exista ejecución. No asignar PASS por disponibilidad de documentos ni por coherencia de identificadores.

### Contrato de evidencia para actualizaciones

Ubicación prevista de informes sanitizados: `tests/artifacts/updates/<runId>/`; es una ruta de salida futura, no un enlace a evidencia existente. Cada registro debe identificar TEST y variante, criterio, nivel, releaseId/buildId y hashes anterior/candidato, contrato de frontend, esquema/checksums, versión/build de Windows, raíz de ensayo, tiempos, punto de fallo, resultado esperado/real, estado final y artefactos. Se enlazarán resultados externos inmutables o conservados por runId; no se sobrescribe una ejecución anterior.

La evidencia debe distinguir instalación disponible, código probado, actualización correcta, fallo recuperado y recuperación pendiente. Para rechazo previo se registra comparación antes/después y ausencia de efectos sobre servicios/datos/configuración; para conservación se registran comparaciones sintéticas; para interrupciones, fase y estado observado después de reanudar; para E2E, identidad y parejas de versiones y ruta efectivamente utilizadas. No publicar dumps, configuración privada, tokens, cookies o contraseñas en esa carpeta de informes. Sus copias privadas permanecen en el almacén restringido del ensayo y se referencian solo por identificador/hash seguro.

Una familia solo obtiene PASS cuando todas sus variantes y niveles exigidos tienen evidencia suficiente, sin incidente bloqueante. Las filas del TMP conservan Not Run hasta evaluar esa cobertura; una variante PASS no promueve automáticamente la familia ni el requisito. CI y proveedor de ejecución siguen sin configurar; este contrato no inventa una autoridad GitHub Actions.

## 8. Defect Management

Registrar incidente con pasos, resultado esperado/real, impacto, severidad, entorno y evidencia sin datos personales innecesarios. Seguir abierto → investigado → corregido → retestado → cerrado. Herramienta y responsables pendientes. Los cambios Critical necesitan revisión independiente según la política; no se considera cumplida por una autorrevisión automatizada.

## 9. Metrics and Reporting

| Metric | Description |
| --- | --- |
| Cobertura prevista | FR/NFR en primera fase con familia de pruebas definida; distinguir casos condicionados |
| Cobertura ejecutada | Evidencia local parcial por variante y nivel, enlazada en sección 10; ninguna familia del actualizador aceptada |
| Resultados | Not Run, PASS, FAIL y BLOCKED por ejecución; Planned indica preparación, no ejecución |
| Incidentes | Critical/High abiertos y retestados |
| Discrepancias | Datos no conciliados y decisiones pendientes de importación |
| Actualizaciones | Criterios nuevos con variantes/niveles planificados, ejecutados y pendientes, distinguiendo rechazo, éxito, fallo recuperado y recuperación fallida |
| Recuperación | Fases de interrupción ensayadas y comparaciones de conservación verificadas; tiempos medidos sin un objetivo máximo inventado |

## 10. Traceability

Cada descripción incluye la acción y el resultado verificable. Evidence «—» significa ausencia de evidencia, no aprobación. Las familias conservan Not Run mientras no se cierre su cobertura completa; este estado de familia no niega las variantes locales ejecutadas. Los enlaces marcados parciales solo acreditan el alcance descrito en la conciliación del 2026-10-16. Las nuevas familias TEST-023 a TEST-038 cubren el alcance de actualizaciones; sus criterios son los existentes en FRD/NFRD, no requisitos creados por el plan de pruebas.

| Requirement (FR-xxx / NFR-xxx) | Test (TEST-xxx) | Evidence | Status |
| --- | --- | --- | --- |
| FR-001 | TEST-001: modificar un registro válido, consultar desde otro dispositivo y verificar el valor persistido; variantes unitarias, integración y E2E; AC-001 | — | Not Run |
| FR-002 | TEST-002: importar JSON sintético con referencias válidas e inválidas; conservar IDs y reportar incompatibilidades sin éxito completo; AC-002 | — | Not Run |
| FR-003 | TEST-003: importar un recibo y un registro borrado; conservar la asociación y evitar reactivar el borrado; AC-003 | — | Not Run |
| FR-004 | TEST-004: consultar un mes sin registro, guardar parcial y volver a consultar; pendiente primero y parcial después; rechazar estado inválido; AC-004 | — | Not Run |
| FR-005 | TEST-005: consultar mes con estados variados, importes conocidos e históricos desconocidos; sumar solo abonados conocidos e identificar por separado los registros desconocidos sin tratarlos como cero; AC-005 | — | Not Run |
| FR-006 | TEST-006: adjuntar un recibo sintético y recuperarlo para el mismo inquilino/mes desde otro dispositivo autorizado; AC-006 | — | Not Run |
| FR-007 | TEST-007: autenticar al responsable y otro usuario del mismo emisor; solicitar recurso con ambos y repetir sin sesión, con sesión inválida y expirada; solo el responsable obtiene datos; AC-007 | — | Not Run |
| FR-007 | TEST-008: cerrar sesión y solicitar de nuevo un recurso sin credenciales válidas; no obtener datos protegidos; modo de sesión pendiente | — | Not Run |
| FR-008 | TEST-009: consultar inmueble y cambiar estado de pago en móvil y ordenador; completar flujo y ver confirmación del backend; AC-008 | — | Not Run |
| FR-009 | TEST-010: revisión por responsable de producto de temática inmobiliaria y Zaragoza; registrar aceptación o ajustes; AC-009 | — | Not Run |
| NFR-001 | TEST-011: repetir consulta y actualización en matriz de navegadores acordada; obtener los mismos datos persistidos; matriz pendiente; AC-101 | — | Not Run |
| NFR-002 | TEST-012: abrir navegación y formulario a 360 y 1440 px propuestos; comprobar controles visibles y accionables, sin solapamientos; AC-102 | — | Not Run |
| NFR-003 | TEST-013: inducir fallo de persistencia; comprobar mensaje de error y ausencia de confirmación de éxito; AC-103 | — | Not Run |
| NFR-003 | TEST-014: importar referencia inexistente; comprobar reporte de discrepancia y ausencia de descarte silencioso; AC-103 | — | Not Run |
| NFR-004 | TEST-015: enviar solicitudes sin credenciales, inválidas y expiradas a cada ruta protegida; todas se rechazan sin datos; AC-104 | — | Not Run |
| NFR-005 | TEST-016: inspeccionar peticiones y recursos de un despliegue de validación; datos y credenciales viajan por HTTPS y ninguna clave maestra se entrega al navegador; AC-105 | — | Not Run |
| NFR-006 | TEST-017: omitir validación de frontend y enviar dato inválido según contrato; backend rechaza el cambio y no persiste; contrato pendiente; AC-106 | — | Not Run |
| FR-007 | TEST-018: con token válido de otro usuario del mismo emisor, recorrer todas las rutas de negocio existentes, incluidas /me, lecturas, escrituras y descargas de documentos y recibos; esperar 403 sin datos y sin cambios en persistencia; como control, el responsable accede a los recursos válidos; AC-007, ADR-009 | — | Not Run |
| FR-007 | TEST-019: retirar configuración de identidad permitida, reiniciar entorno y solicitar recursos con token válido; verificar denegación sin datos ni escrituras; restaurar configuración sintética y comprobar coincidencia de emisor/sujeto, sin autorizar por correo o nombre; ADR-009 | — | Not Run |
| FR-004 | TEST-020: guardar pago sintético con debido 600.00 y abonado 250.00; volver a consultar por API y desde otro dispositivo de la misma identidad; esperar abonado 250.00 y saldo 350.00; variantes unitarias, integración y E2E; AC-012, ADR-010 | — | Not Run |
| FR-005 | TEST-021: consultar histórico sin abonado y variante sin debido; esperar saldo null y motivo de desconocimiento; en resumen mezclar registros conocidos y desconocidos, comprobar suma de conocidos y recuentos de desconocidos; no inferir importe por estado pagado/parcial ni renta actual; AC-013, ADR-010 | — | Not Run |
| FR-004 | TEST-022: calcular debido 0.30 menos abonado 0.10 en backend; esperar cadena decimal 0.20; repetir PUT idéntico con la versión vigente y comprobar que sustituye el total sin incrementarlo; comprobar que balance no puede imponerse desde cliente; contrato de API, ADR-010 | — | Not Run |
| FR-012 | TEST-023: sobre referencia sintética inventariada, presentar paquetes con hash distinto de la referencia de entrega, archivo alterado/faltante, producto/plataforma/formato incorrectos, campos obligatorios ausentes, destinos duplicados, ruta fuera de raíz o punto de reanálisis; cada variante se rechaza con causa antes de detener servicios o modificar aplicación, esquema, datos o configuración; comparar estado antes/después; AC-014, ADR-013; WP-006 | [package — parcial](../../tests/artifacts/updates/package-20261011T160436528Z-3e3cab02/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-012 | TEST-024: reconocer una instalación completa mediante catálogo verificado; repetir con ejecutable/script cambiado, instalación parcial, dependencia o historial SQLx incompatible y frontend desconocido; admitir solo el origen demostrado y rechazar los demás sin efectos ni asignación de versión por Cargo/fecha; AC-014, AC-110, ADR-013; WP-006 | [package — parcial](../../tests/artifacts/updates/package-20261011T160436528Z-3e3cab02/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-013 | TEST-025: aplicar candidata compatible que incorpora una función identificable a baseline completa, con variantes de primera adopción antigua y actualización posterior; comprobar función, versión, arranque y conservación, sin invocar instalador inicial, reinicializar bases/realm ni reinstalar dependencias; AC-015, ADR-012; WP-006, WP-007, WP-009 | [runtime — parcial](../../tests/artifacts/updates/runtime-2026-10-11T16-09-26-428Z-8c746f07/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-013 | TEST-026: tras actualización verificada, presentar otra vez el mismo releaseId y hash; esperar AlreadyApplied, historial de migraciones y datos/configuración intactos; variante con mismo ID y contenido distinto debe rechazarse; AC-016, ADR-012/013; WP-006, WP-009 | [package — parcial](../../tests/artifacts/updates/package-20261011T160436528Z-3e3cab02/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-014 | TEST-027: cortar escritores sobre baseline con ambas bases, configuración/ACL, roles, componentes y adjuntos inventariados; crear copia y restaurarla en entorno aislado antes de primer reemplazo/migración; comprobar datos/relaciones, identidad y componentes previos recuperables y acceso restringido de la copia; AC-017, ADR-015; WP-008 | [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json) | Not Run |
| FR-014 | TEST-028: inducir por separado falta de espacio, permiso de copia denegado, dump fallido y archivo con índice legible cuya restauración falla; abortar antes de reemplazo/migración, no declarar copia válida y recuperar estado operativo/servicios previos si entró en mantenimiento; comparar datos y configuración; AC-018, ADR-015; WP-008 | [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json) | Not Run |
| FR-015 | TEST-029: completar actualización compatible y comprobar versión, login con el mismo sujeto, lectura y escritura de fixture, limpieza y ruta real portal/Worker/túnel de prueba; solo entonces registrar UpdateSucceeded con versiones/comprobaciones y referencia de copia, sin secretos; verificar nuevos datos desde frontend; AC-019, ADR-016; WP-009 | [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-015 | TEST-030: inducir por separado fallo de versión, login, lectura, escritura, limpieza y ruta de portal requerida no disponible; /health/live=200 no debe producir éxito; comprobar fallo o VerificationPending según diseño, sin UpdateSucceeded ni operación normal sobre candidata no verificada; conservar copia e información de recuperación; AC-020, ADR-016; WP-009 | [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-016 | TEST-031: inyectar fallo tras migración que modifica el esquema y ejecutar recuperación; comparar aplicación/scripts, historial, datos, identidad, configuración/ACL y adjuntos con referencia previa; login y consultas deben funcionar antes de reabrir escrituras; mantener bases fallidas y distinguir UpdateFailedRecovered de UpdateSucceeded; AC-021, ADR-015; WP-008, WP-009 | [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-016 | TEST-032: interrumpir proceso y reiniciar equipo en los puntos de la tabla de interrupciones, usando baseline nueva por variante; reanudar mantenimiento y comprobar operación incompleta reconocida, recuperación coherente y rechazo de otra actualización mientras exista estado intermedio; registro ausente/inválido tras introducir el protocolo no habilita negocio; AC-022, ADR-014/015; WP-007 a WP-009 | [control — parcial](../../tests/artifacts/updates/control-20261011T160440988Z-3b401d33/report.json); [runtime — parcial](../../tests/artifacts/updates/runtime-2026-10-11T16-09-26-428Z-8c746f07/report.json); [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-016 | TEST-033: durante fases no verificadas enviar escrituras ordinarias por cada ruta de negocio y repetir con capacidad ausente, errónea, de otra operación o destinada a registro real; no debe persistir ninguna; capacidad válida exige además identidad autorizada y solo permite fixtures acotados durante Verifying; invalidar al interrumpir/terminar y probar rechazo; comprobar backend, no solo UI; AC-023, ADR-014/016; WP-007, WP-009 | [runtime — parcial](../../tests/artifacts/updates/runtime-2026-10-11T16-09-26-428Z-8c746f07/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| NFR-007 | TEST-034: comparar los seis módulos sintéticos antes y después de actualización y de recuperación: IDs, relaciones, importes, null históricos y contenido de adjuntos; comprobar mismo sujeto/usuario y configuración de origen, puertos, servicios y túnel, con comparación privada de secretos sin imprimirlos; sin fixtures residuales ni cambios en registros originales; AC-107, ADR-015; WP-008, WP-009 | [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| NFR-008 | TEST-035: inspeccionar ZIP habitual y registrar antes/después versiones y configuración de dependencias; aplicar entrega que solo cambia aplicación, comprobar ausencia de distribuciones sin cambios y de llamadas a instaladores/reconfiguración de dependencias o creación de realm; pueden detenerse/iniciarse servicios, pero no reinstalarse; AC-108, ADR-012; WP-006 | [package — parcial](../../tests/artifacts/updates/package-20261011T160436528Z-3e3cab02/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| NFR-009 | TEST-036: recorrer fallos antes/después de migración y durante recuperación, incluida copia dañada, fallo de restauración e intercambio parcial de bases; no permitir escrituras con conjunto incoherente ni declarar éxito; recuperar conjunto previo comprobado o informar RecoveryRequired; tras Committed crear dato sintético nuevo y solicitar reversión automática antigua: no debe restaurar la copia ni descartar ese dato; AC-109, ADR-014/015; WP-007 a WP-009 | [backup — parcial](../../tests/artifacts/updates/backup-2026-10-11T16-17-28-716Z-d8b36d54/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| NFR-010 | TEST-037: probar las parejas declaradas frontend anterior/backend anterior, anterior/nuevo y nuevo/nuevo, más la pareja o recuperación de frontend necesaria para volver al backend anterior; una combinación no admitida/desconocida se rechaza antes del cambio; la admitida permite consulta/escritura de fixture desde frontend; incluir pestaña antigua y capacidades nuevas deshabilitadas en backend recuperado; AC-110, ADR-013/016; WP-006, WP-009 | [package — parcial](../../tests/artifacts/updates/package-20261011T160436528Z-3e3cab02/report.json); [browser — parcial](../../tests/artifacts/updates/browser-2026-10-11T16-04-06-825Z-4e6fdaf6/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |
| FR-015 | TEST-038: con secretos sintéticos identificables inspeccionar informes, salida administrativa, logs y assets públicos de una ejecución correcta, otra recuperada y otra pendiente; verificar versiones, fase, causa y referencia de copia sin contraseñas/cookies/tokens/datos de cliente; en frontend inducir 503 de mantenimiento con formulario sin guardar: entrada conservada y sin reintento automático; comprobar guía y diferencia entre actualización y recuperación; AC-019, AC-020, ADR-016 y contrato de API; WP-009 | [browser — parcial](../../tests/artifacts/updates/browser-2026-10-11T16-04-06-825Z-4e6fdaf6/report.json); [flow — parcial](../../tests/artifacts/updates/flow-2026-10-11T16-17-18-593Z-e7738363/report.json) | Not Run |

| FR-017 | TEST-039: publicar una etiqueta de prueba vX.Y.Z desde un repositorio aislado; comprobar prueba previa, metadatos de versión, imagen GHCR inmutable y avance de stable solo tras build satisfactorio; AC-024 | — | Not Run |
| FR-018 | TEST-040: instalar Compose en Windows/Docker Desktop con datos e identidad sintéticos, reiniciar Docker y verificar persistencia de ambas bases, API y Keycloak; AC-025 | — | Not Run |
| FR-019 | TEST-041: ejecutar la tarea con imagen repetida y nueva compatible; comprobar actualización idempotente y versión activa sin intervención del cliente; AC-026 | — | Not Run |
| FR-020 | TEST-042: inducir migración fallida e interrupción tras copia; comprobar restauración de ambas bases e imagen anterior y bloqueo ante estado pendiente; AC-027 y AC-028 | — | Not Run |

### Variantes de interrupción — TEST-032 y TEST-036

Cada fila requiere una ejecución independiente con corte de proceso; las fases que afectan arranque/selección/restauración requieren también reinicio real del entorno aislado. Una simulación de archivos no sustituye esas variantes Windows.

| Punto | Acción posterior y resultado exigido |
| --- | --- |
| Quiescing, antes y después de detener escritores | Comprobar qué acciones se completaron, mantener protección persistente y volver a obtener copia si pudo haber escrituras; no recuperar desde un punto anterior a escrituras permitidas |
| BackingUp, entre dumps o antes de comprobar restauración | Detectar copia incompleta y no usarla; sin sustitución/migración; recuperar servicios previos tras comprobar estado |
| Applying, antes/después de migración y antes/después de selector o cambio de lanzador | Detectar intención/efecto completado, comprobar esquema y aplicación y recuperar conjunto compatible; no servir candidata por un selector incompleto |
| Verifying y Committing, antes de terminar comprobaciones o restaurar opciones de servicio | No habilitar escrituras ni éxito al reiniciar; completar comprobación o recuperar; invalidar capacidades efímeras anteriores |
| Recovering, durante restauración y entre intercambios de bases | No arrancar sobre pareja de bases mezclada; reconocer recursos de la operación y completar/revertir de forma repetible, conservando las fallidas |
| Recuperación de primera adopción antigua | Mantener túnel detenido hasta verificar localmente identidad/datos y compatibilidad; no reactivar el lanzador antiguo prematuramente |

### Profundidad y correspondencia con trabajo

Todas las familias de actualización parten de riesgo Critical por la información y credenciales afectadas; sus variantes técnicas reciben la profundidad pertinente. TEST-023/024/026 añaden unitarias de formato/decisión e integración sin cambios; TEST-027/028 añaden integración de copia/restauración; TEST-025/029/031/032/033/034/036 requieren sistema Windows y variantes de aceptación; TEST-037 incorpora contratos y E2E; TEST-038 enfoca diagnóstico/confidencialidad e interacción. TEST-035 combina inspección de paquete, integración y sistema. Ninguna agrupación excluye regresión de autenticación, importes y valores desconocidos donde hay impacto.

| Trabajo | Familias previstas para su alcance | Condición de cierre |
| --- | --- | --- |
| WP-006 | TEST-023, TEST-024, TEST-026, TEST-035; integración de TEST-025/037 en WP-009 | Herramientas y origen reconocible comprobados; no implica una actualización integrada ya aceptada |
| WP-007 | TEST-025, TEST-032, TEST-033, TEST-036; metadatos usados en TEST-029/030 | Arranque/migración y bloqueo de escrituras comprobados, con evidencia Windows para servicios/reinicio |
| WP-008 | TEST-027, TEST-028, TEST-031, TEST-034, TEST-036 | Copia restaurable y recuperación conjunta probadas antes de activar sustitución/migración |
| WP-009 | TEST-025/026, TEST-029 a TEST-034, TEST-036 a TEST-038 | Cobertura integrada y revisión independiente suficiente antes de proponer MS-003 |
| WP-010 | Entorno y recogida de evidencia que soportan las familias anteriores | MS-004 confirma preparación de entorno, no PASS del actualizador |

### Condiciones de cierre pendientes

- Acceso exclusivo y descarga protegida definidos en FR-007 y ADR-009; cobertura añadida en TEST-018 y TEST-019. Identidad técnica concreta pendiente de configurar. Auditoría de operaciones sigue pendiente de requisitos y diseño; no se declara cubierta por comprobar acceso.
- Restauración de actualizaciones: prioridad alta y alcance definido por FR-014/016 y NFR-009, con TEST-027/028/031/032/034/036 abiertas y evidencia local parcial enlazada. Periodicidad general de copias y tiempo máximo de recuperación siguen pendientes; importación y listado de dump no verifican restauración.
- Cambios concurrentes y renta histórica: reglas pendientes; añadir escenarios después de confirmarlas.
- Pruebas de carga: sin umbral acordado; una medición exploratoria no demostrará cumplimiento de un objetivo inexistente.
- Actualizaciones: candidatos, primitivas y orquestación tienen implementación y evidencia local parcial. Faltan WP-010, configuración real de portal de ensayo, admisión del origen mediante evidencia revisada, variantes/niveles pendientes y revisor independiente. La revisión humana exigida no se sustituye por comprobación automatizada de documentos ni por esta planificación.
- Cierre de MS-003: familias/variantes requeridas con evidencia suficiente, incidentes bloqueantes resueltos/retestados y revisión/aceptación registradas. Una recuperación correcta de un fallo no acredita por sí sola una actualización correcta.

### Ejecución parcial disponible — 2026-10-09

La ejecución de implementación produjo nueve comprobaciones locales de API en [artefacto de integración](../../tests/artifacts/api-2026-10-09T10-49-36.455Z.json). Hay además escenarios de navegador a [1440 px](../../tests/artifacts/frontend/browser-1440.json) y [360 px](../../tests/artifacts/frontend/browser-360.json), junto con una prueba de rechazo de la segunda identidad en `frontend/tests/portal.spec.js`. Relación de cobertura parcial: TEST-001/009 (crear, actualizar y consultar), TEST-007/018 (login sintético y segunda identidad), TEST-008 (logout sin comprobación de revocación de tokens ya emitidos), TEST-012 (ausencia de desbordamiento y controles en los dos anchos), TEST-020 (600/250/350). Los escenarios comprueban también el mensaje de conflicto de guardado en frontend.

Estos resultados no cierran familias completas: matriz de navegadores, identidad real, HTTPS, recuperación, importación y adjuntos siguen pendientes. La prueba de saldo decimal y desconocidos tiene evidencia parcial en API y unitarias; no se declara aceptación de producto ni se asigna PASS global a un requisito. Los enlaces de artefactos de navegador apuntan a la última ejecución local y no son registros inmutables de CI.

### Conciliación de evidencia del actualizador — 2026-10-16

Revisión documental de ejecuciones conservadas del 2026-10-11; Quaestor no ha ejecutado pruebas nuevas. El [resumen local](../../tests/artifacts/updates/local-summary.json) registra 128 comprobaciones satisfactorias: 11 Rust, 52 paquetes, 15 control, 18 runtime, 15 copia/recuperación, 4 navegador y 13 flujo. Registra aparte tres comprobaciones ACL y compilación frontend correcta. El resultado es PASS de alcance local parcial y clientAccepted=false, no aceptación de producto. El recuento no equivale a 128 criterios distintos ni a cobertura completa.

Los informes enlazados son archivos locales conservados por runId, no evidencia de CI ni ejecución remota; no se afirma inmutabilidad técnica. El resumen de Rust/ACL/build sin registro de variante detallado es auxiliar y no justifica por sí solo una familia. Los informes no etiquetan exhaustivamente TEST/AC/nivel por variante: la siguiente correspondencia es una evaluación documental de cobertura parcial, que debe conservarse junto a una futura ejecución con el contrato de evidencia completo.

API/PostgreSQL son reales en los ensayos de integración; identidad y proxy/portal son simulados. El navegador usa respuestas API sintéticas. Control comprueba metadatos y estructuras nativas, sin ejecutar cambios SCM. No se acredita Windows 10 Home del cliente, servicios bajo sus cuentas, reinicio del sistema, Keycloak real ni ruta remota. Las 16 familias siguen abiertas/Not Run en la tabla de cierre; no se asigna PASS global a ninguna.

| Familia | Alcance local observado en los enlaces de la fila principal | Cobertura pendiente para cierre |
| --- | --- | --- |
| TEST-023 | Paquetes alterados, formato/plataforma, rutas y payload rechazados; hash externo rechazado antes de detener API | Rechazo sin efectos sobre servicios/datos/configuración en baseline Windows representativa |
| TEST-024 | Huella sintética revisada, origen sin revisar rechazado y preflight local integrado | Admisión del origen real, inventario y contrato frontend revisados |
| TEST-025 | Candidata compilada y actualización integrada con migración, copia y selección sintéticas | Primera adopción y actualización posterior completas con servicios Windows e identidad real |
| TEST-026 | AlreadyApplied con mismo hash y rechazo de reutilización de identidad de paquete | Cobertura completa de historial/configuración y servicios en instalación representativa |
| TEST-027 | Dos bases e inventario de archivos/ACL; restauración aislada comprueba filas, relaciones, secuencias y roles | Corte de escritores SCM, identidad real, inventario completo y ACL bajo cuentas objetivo |
| TEST-028 | Rechazo de copia no verificada, dump corrupto y configuración alterada: evidencia relacionada de protección | No demuestra las cuatro variantes exigidas: falta de espacio, permiso denegado, dump fallido e índice legible con restauración fallida; probar aborto y restauración de servicios sin cambios |
| TEST-029 | Flujo registra actualización y CRUD satisfactorios con identidad/proxy simulados | Login real, ruta HTTPS Worker/Access/túnel y comprobación desde frontend real |
| TEST-030 | Portal simulado no disponible produce VerificationPending y mantiene bloqueo de escrituras | Fallos independientes de versión, login, lectura, escritura y limpieza; ruta real requerida |
| TEST-031 | Fallo posterior al cambio recupera bases, selector y referencia sintética; conserva bases fallidas | Servicios, Keycloak y portal reales, ACL objetivo y cobertura tras migración con transformaciones admitidas |
| TEST-032 | Registro y guardia, reinicio API, intercambio parcial de bases y reanudación local | Cortes por cada punto de la tabla y reinicio real Windows; incluye primera adopción y restauración parcial |
| TEST-033 | Escrituras ordinarias rechazadas, capacidades acotadas e identidad distinta denegada; revocación tras reinicio API | Cobertura representativa de todas las fases/rutas con servicios e identidad reales |
| TEST-034 | Importes, null, relaciones, identidad sintética, configuración y adjunto externo conservados | Seis módulos completos y configuración de servicios/túnel en instalación representativa; cambios reales de Keycloak |
| TEST-035 | Paquete rechaza distribuciones de dependencias; actualización sintética usa dependencias existentes | Comparación completa antes/después y ausencia de reinstalación/reconfiguración con servicios reales |
| TEST-036 | Copia corrupta, intercambio interrumpido y recuperación comprobados; operación Committed rechaza volver a copia antigua | Matriz completa de fallos/reinicios; reanudación revisada de restauración parcial y dato posterior a Committed explícitamente comprobado |
| TEST-037 | Rechazo de frontend no admitido; navegador con backend sin metadatos/contrato desconocido; proxy local | Todas las parejas identificadas frontend–API, pestaña antigua, recuperación y capacidades en backend anterior con integración real |
| TEST-038 | Navegador conserva formulario ante mantenimiento; resultado de flujo distingue éxito, pendiente y recuperación | Inspección con secretos sintéticos de informes/logs/assets en los tres resultados y revisión de guía; no asumir confidencialidad por lectura del informe |

Orden de trabajo restante, derivado del riesgo High de integridad/recuperación y del nivel Critical de la estrategia:

1. Confirmar WP-010/MS-004 y baseline aislada recuperable antes de servicios/reinicios; identificar build Windows, cuentas y recursos. Preparar origen revisado e inventario representativo, sin usar datos del cliente en los ensayos.
2. Completar rechazos previos y fallos de copia sin cambios (TEST-023/024/028), después matriz de cortes/restauración y bloqueo (TEST-027/031/032/033/036). Cada variante requiere referencia antes/después y estado final, no solo vida del servicio.
3. Revisar con Conditor la política de conservación que hoy rechaza cambios en filas existentes, incluidos los producidos por Keycloak y migraciones que transforman datos o añaden columnas. Antes de admitirlos, definir comparaciones justificadas y ensayar esos cambios y su recuperación; mantener los rechazos conservadores mientras falte política aprobada. Una restauración parcial interrumpida requiere reanudación revisada y no se sobrescribe automáticamente.
4. Completar identidad, portal real, parejas frontend–API, conservación de seis módulos y confidencialidad (TEST-025/029/030/034/035/037/038). Registrar rechazos/pendientes reales por variante cuando exista intento bloqueado; esta revisión no inventa resultados BLOCKED de ejecución.
5. Reunir revisión independiente Critical, cobertura/niveles suficientes y resolución/retest de incidentes antes de proponer aceptación de familias y MS-003. El resumen local no permite afirmar ausencia de incidentes Critical/High ni aceptar riesgo residual.

Las prioridades SQCA se mantienen: resultados locales satisfactorios no reducen el impacto de perder datos o identidad. La planificación conciliada en PRJ-003 y WP-006 a WP-009 permanece In Progress. La matriz consolidada sigue desactualizada y corresponde a Vestigator refrescarla; esta revisión no la modifica.

## References

- [SQCA](SQCA.md), [Test Policy](Test-Policy.md), [Test Strategy](Test-Strategy.md).
- [VSD](../VSD.md), [BRD](../_specification/BRD.md), [NFRD](../_specification/NFRD.md).
- [ADD](../_design/ADD.md).
- [FRD de actualizaciones](../_specification/FRDs/frd-actualizaciones-cliente.md), [diseño](../_design/UPDATE-DESIGN.md), [contrato](../_design/API-CONTRACT.md) y [proyecto de actualizaciones](../_planning/PRJ-003.md).
- [WP-006](../_planning/WP-006.md), [WP-007](../_planning/WP-007.md), [WP-008](../_planning/WP-008.md), [WP-009](../_planning/WP-009.md) y [entorno Windows WP-010](../_planning/WP-010.md).
- [Infraestructura de pruebas](../../tests/README.md) y [WP-001](../_planning/WP-001.md).
- [Matriz consolidada](../TRACEABILITY-MATRIX.md): queda desactualizada tras este cambio de cobertura y debe refrescarse mediante Vestigator; Quaestor no la modifica.
