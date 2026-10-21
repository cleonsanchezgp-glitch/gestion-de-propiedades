# Requisitos de calidad

## Title

| Field | Value |
| --- | --- |
| Document | Non-Functional Requirements Document |
| Initiative | Portal de gestión de propiedades |
| Version | 0.2 |
| Status | Draft - for review |
| Author | Consultor |
| Reviewers | Responsable del producto — pendiente |
| Organization | Aelium |
| Last Updated | 2026-10-11 |

## 1. Overview

Requisitos de calidad derivados del alcance y de la política y estrategia provisionadas. Controles y umbrales propuestos requieren revisión. No se presentan como acuerdos ya aprobados.

NFR-007 a NFR-010 concretan el alcance de actualizaciones aceptado el 2026-10-11 en REQ-008. Se clasifican en las características de calidad de ISO/IEC 25010:2023 según la referencia de Qualitas; no constituyen una declaración de conformidad con la norma ni evidencia de implementación.

## 2. Performance Efficiency

Pendiente de definir: volumen de registros, usuarios concurrentes, tamaño de adjuntos y tiempos máximos de respuesta. No hay umbral autorizado.

## 3. Compatibility

| ID | Requirement | Target / Threshold | Traces to (REQ-xxx) | Verifies (AC-xxx) |
| --- | --- | --- | --- | --- |
| NFR-001 | Permitir los mismos flujos acordados en navegadores de móvil y ordenador | Matriz de navegadores/versiones pendiente; sin pérdida de funciones por formato | REQ-004 | AC-101 |
| NFR-010 | Comprobar compatibilidad de aplicación, esquema y frontend antes de activar una actualización y evitar operar con combinaciones no admitidas | Rechazo previo si la compatibilidad requerida es desconocida o no está admitida; intercambio frontend–API verificado tras el cambio | REQ-008 | AC-110 |

## 4. Interaction Capability

| ID | Requirement | Target / Threshold | Traces to (REQ-xxx) | Verifies (AC-xxx) |
| --- | --- | --- | --- | --- |
| NFR-002 | Presentar navegación, formularios y pagos legibles y operables en ambos formatos | Verificación propuesta a 360 y 1440 px; sin controles inaccesibles ni solapados | REQ-004 | AC-102 |

Accesibilidad formal y dispositivos finales pendientes de confirmar.

## 5. Reliability

| ID | Requirement | Target / Threshold | Traces to (REQ-xxx) | Verifies (AC-xxx) |
| --- | --- | --- | --- | --- |
| NFR-003 | No confirmar guardados fallidos y conservar la integridad de la importación | Ningún éxito falso ni descarte silencioso en los escenarios acordados | REQ-001, REQ-002 | AC-103 |
| NFR-007 | Preservar datos de negocio, adjuntos, identidad autorizada, configuración y credenciales necesarias durante una actualización | Identificadores, relaciones, importes y adjuntos del conjunto de prueba conservados; mismo usuario y configuración de conexión operativos | REQ-008 | AC-107 |
| NFR-009 | Permitir recuperar un estado operativo coherente tras fallo o interrupción de una actualización, incluida una migración de esquema | Aplicación, datos y configuración compatibles con el punto de recuperación; sin escrituras de negocio durante el cambio hasta verificar la actualización o la recuperación; fallo visible si no se recupera | REQ-008 | AC-109 |

Disponibilidad general, periodicidad de copias y concurrencia pendientes de arquitectura y revisión del producto. La copia previa y la recuperación de actualizaciones quedan acotadas por FR-014, FR-016 y NFR-009; no se fija una duración máxima de interrupción ni se promete servicio sin cortes.

## 6. Security

| ID | Requirement | Target / Threshold | Traces to (REQ-xxx) | Verifies (AC-xxx) |
| --- | --- | --- | --- | --- |
| NFR-004 | El backend debe rechazar solicitudes protegidas sin autenticación válida | Rechazo para credenciales ausentes, inválidas y expiradas | REQ-006 | AC-104 |
| NFR-005 | El portal publicado debe cifrar las comunicaciones de autenticación y datos mediante HTTPS; no debe publicar claves maestras del almacén en el frontend | Sin peticiones de datos o credenciales por HTTP ni claves maestras entregadas al navegador | REQ-006, REQ-001 | AC-105 |

Keycloak gestiona autenticación; no sustituye al cifrado del transporte. Roles, aislamiento, auditoría, protección de adjuntos y obligaciones legales pendientes de definir explícitamente.

## 7. Maintainability

| ID | Requirement | Target / Threshold | Traces to (REQ-xxx) | Verifies (AC-xxx) |
| --- | --- | --- | --- | --- |
| NFR-006 | Mantener reglas de validación y cálculo en backend y documentar su interfaz | El frontend no es la autoridad de las reglas ni accede directamente a JSONBin | REQ-001 | AC-106 |
| NFR-008 | Permitir sustituir los componentes de aplicación afectados por una entrega habitual sin reinstalar las dependencias que no cambian | Paquete habitual sin distribuciones de dependencias sin cambios; versiones y configuración de esas dependencias permanecen iguales tras actualizar | REQ-008 | AC-108 |

## 8. Flexibility

No se han establecido umbrales de escalabilidad ni portabilidad. La futura integración de n8n requiere un contrato posterior; no se presupone arquitectura concreta.

## 9. Safety

No se ha identificado una función de seguridad física en el alcance. Los riesgos de atribución incorrecta de pagos se recogen en BRD y en la especificación futura; aplicabilidad adicional pendiente de revisión.

## 10. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-101 | Una matriz de navegadores acordada | Se ejecutan consulta y actualización en cada navegador | Los resultados persistidos son equivalentes | NFR-001 |
| AC-102 | Pantallas de 360 y 1440 px como propuesta de prueba | Se abre navegación y formulario de pago | Los controles se ven y pueden accionarse sin solapamientos | NFR-002 |
| AC-103 | Un fallo de persistencia y un JSON de prueba con relación inválida | Se intenta guardar e importar | El fallo se muestra sin éxito falso y la discrepancia se informa | NFR-003 |
| AC-104 | Solicitudes sin credenciales, con credenciales inválidas o expiradas | Se accede a un recurso protegido | Todas se rechazan sin devolver datos protegidos | NFR-004 |
| AC-105 | Un portal preparado para publicación | Se inspeccionan peticiones y recursos del navegador | Las comunicaciones protegidas usan HTTPS y no se entrega una clave maestra del almacén | NFR-005 |
| AC-106 | Un frontend con validación local omitida y un dato inválido según contrato acordado | Se solicita el cambio al backend | El backend lo rechaza y el frontend no puede imponer su persistencia | NFR-006 |
| AC-107 | Una instalación de prueba con propiedades, inquilinos, pagos con importes conocidos y desconocidos, incidencias, documentos y recibos, más su identidad y configuración registradas como referencia | Se aplica una actualización compatible y se consulta desde el portal | Se conservan identificadores, relaciones, importes y contenido de adjuntos; los desconocidos siguen siendo desconocidos y el mismo usuario accede con la configuración existente | NFR-007 |
| AC-108 | Una entrega que solo cambia la aplicación y una instalación con dependencias compatibles | Se inspecciona el paquete y se actualiza | El paquete no incluye distribuciones de dependencias sin cambios y estas mantienen versión y configuración, sin ejecutar su reinstalación | NFR-008 |
| AC-109 | Una copia previa coherente y fallos inyectados tanto antes como después de una migración y durante la recuperación | Se intenta actualizar y se ejecuta o reanuda la recuperación | Se restablece aplicación, datos y configuración compatibles con la copia y se verifica su acceso; mientras no se verifique un estado coherente se rechazan escrituras de negocio y se informa del fallo sin declarar éxito | NFR-009 |
| AC-110 | Un paquete con compatibilidad declarada, un esquema de prueba y un frontend compatible o incompatible según esa declaración | Se evalúa cada combinación y se aplica la admitida | La combinación incompatible o desconocida se rechaza antes de modificar la instalación y la admitida supera consultas y una operación de escritura desde el frontend antes de declararse operativa | NFR-010 |

## References

- [BRD](BRD.md).
- [Política](../_verification/Test-Policy.md) y [estrategia](../_verification/Test-Strategy.md) de Aelium, tomadas de CRM.
- Estructura de calidad del template Qualitas NFRD.
- [Actualizaciones del cliente](FRDs/frd-actualizaciones-cliente.md) y confirmación del alcance en [VSD](../VSD.md), 2026-10-11.
