# Seguimiento de pagos

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Seguimiento mensual de pagos |
| ID | FRD-002 |
| Version | 0.2 |
| Status | Draft - for review |
| Author | Consultor |
| Last Updated | 2026-10-09 |

## 1. Overview

Conservar el seguimiento mensual existente, haciendo que el backend gestione estados y resúmenes. El HTML muestra seis meses y asocia pagos a inquilino y mes. No almacena el importe abonado en cada pago.

## 2. Actors

| Actor | Description |
| --- | --- |
| Personal de gestión | Consulta y registra estado y notas |
| Backend | Persiste pagos y calcula resúmenes |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-004 | El backend debe gestionar estados pagado, parcial y pendiente por inquilino y mes, registrar el importe abonado y entregar el saldo como importe debido del período menos importe abonado cuando ambos sean conocidos; en ausencia de registro debe mostrar pendiente, conservando fecha y nota disponibles | Primera fase | REQ-003 |
| FR-005 | El backend debe entregar el resumen mensual de importes abonados y saldos conocidos, distinguir los pagos históricos con importes desconocidos y no tratarlos como cero ni inferirlos del estado | Primera fase | REQ-003 |
| FR-006 | Debe poder asociarse y consultarse un recibo para un inquilino y mes, preservando las asociaciones importadas | Primera fase; función existente | REQ-003 |

## 4. Workflow

1. El usuario selecciona un mes.
2. El backend entrega pagos y resumen.
3. El usuario registra el importe abonado, modifica el estado o una nota, o adjunta un recibo.
4. El backend confirma la operación y entrega los resultados actualizados.

## 5. Inputs

| Input | Source |
| --- | --- |
| Inquilino, mes, estado, importe abonado, importe debido del período, fecha, nota | Registro de pago y formulario |
| Renta y situación activa | Registro de inquilino |
| Recibo | Adjunto del usuario o importación |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Estados y resumen mensual | Frontend |
| Recibo asociado | Usuario autorizado |

## 7. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-004 | Un inquilino sin registro de pago para un mes | Se consulta y después se guarda estado parcial | Primero se muestra pendiente y una nueva consulta devuelve parcial; si falta un importe necesario, el saldo se muestra desconocido | FR-004 |
| AC-005 | Pagos pagados, parciales y pendientes en un mes | Se consulta el resumen | Se distinguen los tres estados, se suman los importes abonados conocidos y se identifican por separado los históricos sin importe | FR-005 |
| AC-012 | Un pago con importe debido 600 y abonado 250 | Se guarda y vuelve a consultar | El backend devuelve importe abonado 250 y saldo 350 | FR-004 |
| AC-013 | Un pago histórico sin importe abonado | Se consulta el pago y el resumen | Importe abonado y saldo permanecen desconocidos; no se sustituyen por cero ni por la renta actual | FR-005 |
| AC-006 | Un recibo asociado a un inquilino y mes | Se consulta ese pago desde otro dispositivo autorizado | Se puede recuperar el recibo de esa asociación | FR-006 |

## 8. Error Handling

Rechazar estados no admitidos y referencias inexistentes. No confirmar un cambio si falla la persistencia. Importes abonados y saldos confirmados el 2026-10-09. Siguen pendientes pagos múltiples, sobrepagos, período histórico, renta histórica, correcciones y cierre de mes. El saldo requiere un importe debido del período conocido; no se reconstruye a partir de la renta actual sin una regla confirmada. El resumen del origen suma la renta actual de los inquilinos marcados pagados; no prueba por sí solo ingresos bancarios reales.

## References

- [BRD](../BRD.md), REQ-003.
- HTML de origen: renderPagos, getPago y togglePago.

## Confirmación de producto — 2026-10-09

El usuario confirma acceso exclusivamente para él; conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos; registro de importes abonados y saldos. Los importes históricos ausentes siguen siendo desconocidos. No se aprueban decisiones ajenas a estos puntos ni se acredita implementación.
