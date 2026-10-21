# Automatización futura de pagos

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Conciliación mediante correos de Ibercaja y n8n |
| ID | FRD-004 |
| Version | 0.1 |
| Status | Draft - deferred; for review |
| Author | Consultor |
| Last Updated | 2026-10-02 |

## 1. Overview

Capacidad futura solicitada por el usuario. Este documento delimita la intención y las cuestiones pendientes; no define un contrato implementable ni autoriza conexión a correo o banca.

## 2. Actors

| Actor | Description |
| --- | --- |
| Personal de gestión | Revisa asociaciones propuestas |
| n8n | Automatización prevista |
| Backend | Aplicación futura de reglas de pago |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-010 | La fase futura debe obtener de avisos de Ibercaja candidatos de asociación a pagos mediante n8n y reglas acordadas | Futura; pendiente de refinamiento | REQ-007 |
| FR-011 | Antes de activar cambios automáticos, deben definirse el tratamiento de duplicados y la revisión de candidatos ambiguos | Futura; propuesta para revisión | REQ-007 |

## 4. Workflow

Flujo propuesto: aviso → extracción → asociación candidata → revisión o aplicación según reglas confirmadas. Debe refinarse con muestras anonimizadas de los avisos reales.

## 5. Inputs

| Input | Source |
| --- | --- |
| Avisos; formato y acceso pendientes | Correos de Ibercaja |
| Inquilinos y pagos | Backend |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Propuestas de asociación y resultados | Gestión y backend |

## 7. Acceptance Criteria

Criterios propuestos para la fase futura, no criterios de aceptación de la primera fase.

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-010 | Un aviso de prueba y una regla de asociación confirmada | n8n procesa el aviso | Se produce la asociación esperada por esa regla | FR-010 |
| AC-011 | Un aviso repetido y otro con varios candidatos | Se procesa el conjunto | No se duplica el efecto y el caso ambiguo queda para revisión sin cambiar automáticamente el pago | FR-011 |

## 8. Error Handling

Pendientes: formato de avisos, legitimidad y acceso al buzón, autenticación de integración, identificador de evento, duplicados, pagos parciales y múltiples, devoluciones, atrasos, cuentas y trazabilidad. No se infiere un pago pendiente únicamente por ausencia de correo.

## References

- [BRD](../BRD.md), REQ-007.
