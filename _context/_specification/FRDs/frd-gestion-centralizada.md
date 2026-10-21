# Gestión centralizada

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Gestión centralizada de propiedades |
| ID | FRD-001 |
| Version | 0.2 |
| Status | Draft - for review |
| Author | Consultor |
| Last Updated | 2026-10-09 |

## 1. Overview

Trasladar la gestión observada en el HTML a un backend. El usuario confirmó conservar propiedades, inquilinos, pagos, incidencias, documentos y recibos el 2026-10-09.

## 2. Actors

| Actor | Description |
| --- | --- |
| Personal de gestión | Consulta y actualiza la información |
| Backend | Valida, persiste y prepara resultados |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-001 | El backend debe resolver consultas y altas, modificaciones y bajas del alcance acordado de propiedades, inquilinos, incidencias y documentos; el frontend presenta los resultados | Primera fase | REQ-001 |
| FR-002 | La importación del JSON debe conservar identificadores y relaciones; debe reportar incompatibilidades sin descartar información silenciosamente | Primera fase | REQ-002 |
| FR-003 | Los recibos y el registro de borrados existentes deben contemplarse en la conciliación, evitando reintroducir registros marcados como borrados | Primera fase | REQ-002 |

## 4. Workflow

1. El usuario solicita una consulta o cambio.
2. El backend comprueba el acceso y valida la operación.
3. Persiste el cambio o informa del rechazo.
4. El frontend muestra el resultado confirmado por el backend.

La importación se verifica por separado, comparando registros y relaciones con el origen antes de aceptar sus resultados.

## 5. Inputs

| Input | Source |
| --- | --- |
| Consultas y modificaciones | Frontend |
| Exportación JSON | DOC.txt |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Información y confirmación de cambios | Frontend |
| Discrepancias de importación | Responsable de revisión |

## 7. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-001 | Una sesión válida y un registro aceptado por el backend | Se actualiza el registro y se consulta desde otro dispositivo | Ambos dispositivos reciben el valor persistido por el backend | FR-001 |
| AC-002 | Un JSON de prueba con relaciones válidas y otra referencia inexistente | Se importa | Se conservan los identificadores válidos y se informa de la referencia inválida; no se declara importación completa | FR-002 |
| AC-003 | Un origen de prueba con recibo y un registro marcado como borrado | Se realiza la conciliación | El recibo queda contabilizado y el registro borrado no aparece como activo | FR-003 |

## 8. Error Handling

Si falla el backend, el frontend informa del fallo y no confirma un guardado. Las reglas exactas de validación, borrado, conflicto concurrente y límites de adjuntos se concretarán antes de implementar cada operación.

## 9. Interface Requirements

| ID | Interface | Description | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| INT-001 | Frontend–backend | Consultas y cambios mediante una interfaz del backend; contrato, protocolo y rutas pendientes de arquitectura | REQ-001 |
| INT-002 | Importación JSON | Colecciones propiedades, inquilinos, pagos, incidencias, documentos; recibos, deleted y _ts observados en el origen | REQ-002 |

## References

- [BRD](../BRD.md).
- [HTML](../../../promalza-pro.html) y [exportación](../../../DOC.txt).

## Confirmación de producto — 2026-10-09

El usuario confirma acceso exclusivamente para él; conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos; registro de importes abonados y saldos. Los importes históricos ausentes siguen siendo desconocidos. No se aprueban decisiones ajenas a estos puntos ni se acredita implementación.
