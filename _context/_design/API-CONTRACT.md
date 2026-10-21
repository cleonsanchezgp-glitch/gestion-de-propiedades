# Propuesta de contrato y migración

| Field | Value |
| --- | --- |
| Document | API Contract Proposal |
| Version | 0.5 |
| Status | Draft - for review; partially implemented |
| Author | Conditor |
| Organization | Aelium |
| Last Updated | 2026-10-20 |

Actualización: el usuario ha aceptado la base técnica el 2026-10-03 y ha autorizado implementar la infraestructura de pruebas. El contrato detallado, las reglas de negocio y los permisos mantienen su estado de propuesta; no están aprobados por aceptar el stack.

Cambio funcional solicitado el 2026-10-20: los edificios son registros independientes (`edificios`) creados antes que las viviendas. Cada propiedad referencia un edificio mediante `edificioId`, validado por la API. La migración agrupa los registros anteriores por su campo `recinto` y conserva las viviendas existentes. El contrato es `propiedades-v3`; las versiones anteriores no se declaran compatibles con esta relación obligatoria.

## 1. Alcance y decisiones

Desarrollo técnico de ADR-005 a ADR-008 del [ADD](ADD.md). Es una propuesta revisable para implementar REQ-001, REQ-004 y REQ-006. La importación y los módulos del origen se detallan de forma condicionada a confirmar REQ-002 y alcance funcional. El alcance de las seis funciones, el acceso exclusivo y los importes abonados y saldos fueron confirmados el 2026-10-09. No implica que se hayan habilitado endpoints.

Propuesta: Rust/Axum/SQLx, PostgreSQL y frontend HTML/CSS/JavaScript modular con Vite. Mantener un único backend organizado por módulos, sin microservicios adicionales. La persistencia y las reglas se encapsulan detrás de los handlers de API. Keycloak es externo al dominio inmobiliario.

## 2. Convenciones de API

- Prefijo `/api/v1`; respuestas JSON para datos y errores, salvo descargas de adjuntos.
- Identificadores opacos de texto. No exigir UUID a los datos importados: los identificadores del origen usan distintos formatos.
- Fechas contractuales normalizadas como `YYYY-MM-DD`, mes de pago como `YYYY-MM`. La importación debe detectar fechas ambiguas del origen sin reinterpretación silenciosa.
- Campos monetarios como cadena decimal y moneda EUR; el backend utiliza representación decimal exacta. No usar coma flotante para cálculos de dinero.
- Resultado desconocido como `null`, acompañado de motivo cuando sea relevante. No transformar importe parcial desconocido en cero.
- Validación y permisos en backend; filtros y cálculos del navegador no determinan acceso ni estado persistido.
- Paginación propuesta `limit` y `cursor`; límite máximo, orden estable y filtros finales pendientes de volumen y reglas.
- Errores sin datos personales ni detalles SQL: `{"error":{"code":"VALIDATION_ERROR","message":"Datos no válidos","requestId":"…"}}`. Campo adicional `fields` solo para errores de formulario seguros.
- HTTP: 400 para formato inválido, 401 para autenticación ausente o inválida, 403 para permiso insuficiente, 404 para recurso no disponible al usuario, 409 para conflicto de versión y 500 para error inesperado. La API no debe confirmar un cambio que no se ha persistido.

## 3. Rutas propuestas

Todas las rutas de negocio requieren autenticación válida y coincidencia con la única identidad autorizada según ADR-009; otro usuario autenticado recibe 403 sin datos protegidos. Crear usuarios, asignar roles y administrar Keycloak no se exponen implícitamente mediante esta API.

| Method | Path | Resultado previsto | Fuente |
| --- | --- | --- | --- |
| GET | `/health/live` | Comprobación mínima del proceso, sin datos de negocio | Operación técnica de ADR-005 |
| GET | `/api/v1/me` | Identidad y capacidades efectivas de la sesión | REQ-006 |
| GET | `/api/v1/dashboard?mes=YYYY-MM` | Resumen calculado por backend, con limitaciones financieras explícitas | REQ-001, REQ-003 |
| GET, POST | `/api/v1/propiedades` | Listar o crear propiedad | FR-001 |
| GET, PATCH, DELETE | `/api/v1/propiedades/{id}` | Consultar, cambiar o solicitar baja | FR-001; efecto sobre relaciones pendiente |
| GET, POST | `/api/v1/inquilinos` | Listar o crear inquilino | FR-001 |
| GET, PATCH, DELETE | `/api/v1/inquilinos/{id}` | Consultar, cambiar o solicitar baja | FR-001; conservación histórica pendiente |
| GET | `/api/v1/pagos?mes=YYYY-MM` | Estados del mes y datos necesarios para presentación | FR-004 |
| PUT | `/api/v1/inquilinos/{id}/pagos/{mes}` | Registrar importe debido, importe abonado y nota; calcular estado y saldo en backend | FR-004 |
| GET, POST | `/api/v1/incidencias` | Listar o crear incidencia | FR-001; alcance confirmado el 2026-10-09 |
| GET, PATCH, DELETE | `/api/v1/incidencias/{id}` | Consultar, cambiar o solicitar baja | FR-001; alcance confirmado el 2026-10-09 |
| GET, POST | `/api/v1/documentos` | Metadatos de documentos | FR-001; alcance confirmado el 2026-10-09 |
| GET, PATCH, DELETE | `/api/v1/documentos/{id}` | Consultar, cambiar o solicitar baja | FR-001; alcance confirmado el 2026-10-09 |
| GET, PUT | `/api/v1/inquilinos/{id}/pagos/{mes}/recibo` | Recuperar o adjuntar recibo asociado | FR-006; alcance confirmado el 2026-10-09 |

El estado no se selecciona manualmente: sin importe abonado o con cero queda `pendiente`; un abono mayor que cero e inferior al importe debido queda `parcial`; al cubrir o superar el importe debido queda `pagado`. El backend deriva y persiste el estado a partir de los importes en cada PUT, y también lo recalcula al consultar pagos existentes.

La importación se propone como herramienta local de administración con modo de validación, no como endpoint público de subida masiva. No se propone aún un endpoint n8n: requiere contrato y permisos de servicio posteriores.

## 4. Persistencia propuesta

| Entidad | Restricciones a concretar | Precaución respecto al origen |
| --- | --- | --- |
| Edificio | Clave primaria de texto y versión; nombre obligatorio, dirección y notas opcionales | Archivar solo cuando no tenga viviendas activas |
| Propiedad | Clave primaria de texto y versión; `edificioId` obligatorio y validado | Mantener ID importado; exigir edificio al editar registros antiguos sin asignación |
| Inquilino | Referencia de propiedad validada | Baja y relación histórica por confirmar |
| Pago | Inquilino y mes; unicidad propuesta de esa pareja | Importes nuevos registrados; los históricos ausentes permanecen null, incluida renta histórica desconocida |
| Incidencia | Relación con propiedad y estados admitidos | No exigir una referencia que el alcance permita omitir |
| Documento | Metadatos y asociaciones | No confundir metadatos con archivo adjunto |
| Recibo | Referencia a inquilino/mes y objeto almacenado | Inspeccionar formato real antes de migrar |
| Importación pendiente de conciliación | Registro original y motivo de discrepancia | Preservar referencias ausentes sin crear inquilinos ficticios |

Claves foráneas y transacciones se aplicarán al esquema aceptado. Los datos no conciliados se conservan separados y no cuentan automáticamente en resúmenes operativos. No se ha decidido una política de cascada ni se autorizan borrados irreversibles de datos históricos.

Propuesta de concurrencia: versión de registro y rechazo con 409 cuando cambió desde la lectura. Lectura previa, comprobación de versión y escritura deben realizarse de forma atómica. La interfaz permitirá recargar y revisar el conflicto; no sobrescribirá silenciosamente cambios de otro dispositivo.

## 4.1. Contrato de importes y saldos — ADR-010

Diseño derivado de REQ-003, FR-004 y FR-005. Los nombres siguientes son una propuesta de contrato; no acreditan endpoints implementados.

| Campo | Tipo JSON | Responsabilidad |
| --- | --- | --- |
| amountDue | Cadena decimal EUR o null | Importe debido de ese período, persistido sin recalcular automáticamente desde la renta actual |
| amountPaid | Cadena decimal EUR o null | Total abonado registrado para ese período; null histórico significa desconocido |
| balance | Cadena decimal EUR o null | Solo salida; calculado por backend como amountDue menos amountPaid si ambos son conocidos |
| amountUnknownReason | Cadena o null | Motivo de ausencia de importe histórico o debido; no contiene datos personales |

Ejemplo de lectura: `{"amountDue":"600.00","amountPaid":"250.00","balance":"350.00","amountUnknownReason":null}`. Histórico sin importes: `{"amountDue":null,"amountPaid":null,"balance":null,"amountUnknownReason":"historical_amounts_missing"}`.

Persistencia: columnas PostgreSQL NUMERIC para importes, anulables para históricos desconocidos; precisión y límites finales se fijarán con las reglas de dominio. Balance no se acepta como valor impuesto por el cliente. No usar float para almacenar o calcular importes. El resumen suma importes conocidos y devuelve recuentos separados de registros con abonado o saldo desconocido; nunca declara completo un total con cantidades desconocidas.

El PUT de pago representa sustitución explícita del total abonado, no incremento por cada petición; repetir el mismo payload no duplica el cobro. Requiere control de versión atómico para evitar sobrescrituras desde otro dispositivo. La actualización de importes y estado se confirma solo tras persistencia. El importe debido se conserva por período; su creación y corrección necesitan una regla de producto, sin asumir que la renta actual reconstruye la histórica.

Pagos múltiples, sobrepagos, correcciones y derivación automática de estado no tienen reglas confirmadas. No se incorpora un libro de movimientos ni se inventan reglas de cierre. Los escenarios afectados siguen bloqueados para implementación hasta su definición. La importación conserva como null las cantidades ausentes; un estado pagado tampoco acredita por sí solo un importe histórico.

## 5. Identidad y adjuntos

Proponer realm y cliente propios del proyecto al implementar, separados de CRM. Configuración mediante variables de entorno, con emisor, audiencia y claves de verificación conocidos. No copiar secretos, contraseñas de ejemplo ni excepciones de validación de CRM.

El backend valida credenciales y autoriza únicamente la pareja emisor/sujeto configurada para el responsable. No se acepta correo ni nombre como clave de autorización. Configuración ausente implica denegación. Esta comprobación incluye /api/v1/me, consultas, escrituras y adjuntos; /health/live devuelve únicamente estado técnico sin datos de negocio.

Propuesta de adjuntos: almacenamiento privado fuera del directorio público del frontend; metadatos en PostgreSQL; descarga mediante backend autorizado. Tamaños, tipos, análisis de contenido, retención y backup pendientes. El nombre del fichero no debe determinar una ruta de acceso arbitraria en el servidor.

## 6. Migración revisable

1. Conservar DOC.txt y HTML originales sin modificarlos; trabajar sobre copia identificada por hash.
2. Validar estructura, IDs, relaciones, fechas y tipos sin escribir datos operativos.
3. Generar reporte sin datos personales innecesarios. La revisión ya encuentra cuatro pagos con inquilino ausente, dos parciales sin importe y dos contratos con fechas iguales.
4. Separar discrepancias conservando los valores originales. No reasignar pagos, fabricar importes ni modificar fechas por inferencia.
5. Tras acordar las reglas, importar en una base de validación dentro de una transacción y comprobar cantidades y relaciones.
6. Comparar presentación y funciones acordadas con el origen. Probar backup y restauración una vez definida la política; tener una copia no demuestra restaurabilidad.
7. Antes del cambio operativo, acordar corte de escrituras del sistema antiguo, exportación final, conciliación y reversión. No mantener dos fuentes operativas editables sin resolver conflictos.

No se ha ejecutado ninguna de estas operaciones ni conectado a JSONBin.

## 7. Cuestiones pendientes

Identificador técnico del único usuario autorizado; renta histórica; pagos múltiples, sobrepagos y correcciones; conservación de pagos sin inquilino; reglas de baja y concurrencia; adjuntos; volumen; alojamiento y recuperación. La propuesta reduce las decisiones técnicas abiertas, sin convertir estos puntos de negocio en supuestos aprobados.

## 8. Implementación parcial y evidencia local — 2026-10-09

Implementados en backend: autorización exclusiva mediante `KEYCLOAK_ALLOWED_SUBJECT` dentro del emisor configurado; importes NUMERIC anulables mediante migración 0002; lectura y escritura de `amountDue`/`amountPaid`; saldo calculado y resumen de cantidades conocidas con recuentos desconocidos. Los campos de importe ausentes o null en PUT conservan cantidades existentes; una cadena decimal sustituye la cantidad. El campo `balance` enviado por cliente se rechaza. La configuración de sujeto ausente o vacía impide iniciar el backend.

[Evidencia de integración](../../tests/artifacts/api-2026-10-09T10-49-36.455Z.json): nueve comprobaciones locales aprobadas con datos e identidades de servicio sintéticos. También pasan cinco pruebas unitarias del backend. Esto no verifica PKCE/login del responsable en navegador, cierre de sesión, HTTPS, importación del origen, adjuntos ni aceptación de producto. La identidad real autorizada sigue pendiente de configurar. Las familias del TMP conservan Not Run hasta vincular y evaluar cobertura suficiente; una comprobación parcial no acredita la familia completa.

## 9. Acceso desde el formulario del portal — ADR-011

- POST `/api/v1/session/login`: JSON de username/password, origen autorizado obligatorio. Valida con cliente confidencial de Keycloak. 401 para credenciales incorrectas; 403 para cuenta no autorizada. Respuesta sin tokens ni contraseñas; cookie de sesión HttpOnly y SameSite Strict.
- POST `/api/v1/session/logout`: mismo origen autorizado; elimina la sesión local, solicita cierre a Keycloak y borra cookie.
- GET `/api/v1/me` y rutas protegidas admiten cookie de sesión. El backend renueva tokens y valida identidad; los Bearer existentes se conservan para pruebas/API.
- Escrituras con cookie requieren Origin igual a PORTAL_ORIGIN; una petición de otro origen se rechaza. Sesión máxima de ocho horas, en memoria. Secure cuando el portal usa HTTPS; HTTP solo en loopback de pruebas.
- El cliente anterior del navegador queda sustituido por sesión de backend. No se implementan todavía MFA, acciones obligatorias o recuperación de contraseña en este formulario.

## 10. Contrato de actualización y mantenimiento — propuesto, 2026-10-11

Extensión de REQ-008 y ADR-012 a ADR-016, detallada en [UPDATE-DESIGN.md](UPDATE-DESIGN.md). Esta sección no describe rutas ni controles ya implementados.

- GET `/api/v1/system/version`: requiere la misma identidad autorizada que las rutas de negocio; devuelve releaseId, apiContract, capacidades compatibles y estado operativo, sin secretos, rutas privadas, inventario de datos ni privilegios de instalación. Cache-Control: no-store. Se registra como ruta explícita antes de las rutas genéricas de colecciones.
- `/health/live` conserva su respuesta mínima: proceso vivo no significa esquema compatible, actualización completa ni permiso para escribir.
- Durante mantenimiento, las escrituras de negocio reciben HTTP 503 con `{"error":{"code":"MAINTENANCE_IN_PROGRESS","message":"Actualización en curso. Inténtalo cuando termine."}}`, sin persistencia ni éxito aparente. La guardia se comprueba en backend antes de modificar cualquier recurso, no solo en frontend.
- Comprobaciones de escritura durante Verifying: requieren identidad del propietario, origen válido, capacidad efímera de la operación y destino sintético permitido. No se crea una ruta remota para instalar, migrar o restaurar. La capacidad no autoriza registros del cliente y no se expone en JavaScript público ni logs.
- El frontend conserva formulario/entrada no guardada ante un rechazo de mantenimiento y no reintenta escrituras automáticamente; al terminar vuelve a comprobar sesión y compatibilidad antes de permitir otro guardado. Los conflictos existentes siguen requiriendo revisión.
- El arranque Windows normal verifica el historial SQLx esperado sin ejecutar migraciones. La migración se ejecuta en un modo local explícito, bajo la operación de mantenimiento, con retorno comprobado. El código actual aún migra al arrancar y debe adaptarse antes de afirmar cumplimiento.
- Las entregas habituales preservan el contrato del frontend anterior; la publicación y recuperación se comprueban con las combinaciones declaradas. Una pestaña antigua no se considera actualizada por haber publicado nuevos assets.

Resultados administrativos propuestos: AlreadyApplied, Rejected, VerificationPending, UpdateSucceeded, UpdateFailedRecovered y RecoveryRequired. Los informes distinguen fallo de actualización y recuperación correcta; no incluyen cookies, tokens ni datos de negocio. No son respuestas de una API de administración remota.

## References

- [ADD](ADD.md), [BRD](../_specification/BRD.md), [revisión de origen](../_specification/SPECIFICATION-REVIEW.md).
- [Diseño de actualización](UPDATE-DESIGN.md), 2026-10-11; implementación pendiente.
- Referencia local de stack: CRM/backend/Cargo.toml y CRM/frontend/package.json, leídos el 2026-10-03. Solo evidencia de tecnología utilizada, no autoridad de configuración.
- [Axum](https://docs.rs/axum/latest/axum/), [PostgreSQL constraints](https://www.postgresql.org/docs/current/ddl-constraints.html), [Vite](https://vite.dev/guide/) y [Keycloak JavaScript adapter](https://www.keycloak.org/securing-apps/javascript-adapter), consultados el 2026-10-03.
