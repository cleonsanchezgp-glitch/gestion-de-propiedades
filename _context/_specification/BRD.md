# Requisitos de negocio — Gestión de propiedades

## Title

| Field | Value |
| --- | --- |
| Document | Business Requirements Document |
| Initiative | Portal de gestión de propiedades |
| Version | 0.3 |
| Status | Draft - for review |
| Author | Consultor |
| Reviewers | Responsable del producto — pendiente |
| Organization | Aelium |
| Last Updated | 2026-10-11 |

## 1. Introduction

### 1.1 Purpose

Especificar el resultado de negocio del portal solicitado a partir del encargo y las funciones observadas en el HTML. La conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos está confirmada por el usuario el 2026-10-09.

### 1.2 Scope

Primera fase: gestión centralizada, acceso con Keycloak e interfaz para ordenador y móvil. REQ-007 pertenece exclusivamente a una fase futura.

REQ-008 incorpora el mantenimiento de la entrega al cliente mediante actualizaciones que conservan la instalación existente, con alcance aceptado el 2026-10-11. Su diseño e implementación siguen pendientes.

### 1.3 Definitions

| Term | Definition |
| --- | --- |
| Pago mensual | Registro asociado a un inquilino y mes, con estado pagado, parcial o pendiente |
| Recibo | Adjunto asociado al inquilino y mes en la aplicación actual |
| Conciliación | Asociación de un aviso bancario a un pago; reglas aún no definidas |
| Actualización habitual | Entrega de funciones o correcciones de la aplicación que no requiere cambiar las dependencias instaladas |
| Recuperación de actualización | Restablecimiento de una versión operativa y de datos y configuración compatibles tras un fallo; no equivale necesariamente a sustituir solo el ejecutable |

## 2. Business Objectives

| Objective | Description |
| --- | --- |
| OBJ-001 | Centralizar gestión y preservar datos |
| OBJ-002 | Utilizar el portal desde móvil y ordenador con identidad de Zaragoza |
| OBJ-003 | Controlar acceso mediante Keycloak |
| OBJ-004 | Preparar automatización futura de pagos |
| OBJ-005 | Mantener y ampliar el programa del cliente sin reinstalar toda la plataforma |

## 3. Stakeholders

| Stakeholder | Role | Interest |
| --- | --- | --- |
| Aelium | Organización | Mantenimiento del producto |
| Responsable del producto | Revisión de requisitos | Validar alcance y reglas |
| Personal de gestión | Usuario previsto | Gestionar propiedades y cobros |

## 4. Business Requirements

| ID | Requirement | Priority | Traces to (OBJ-xxx) |
| --- | --- | --- | --- |
| REQ-001 | La gestión debe disponer de una fuente central de datos cuya lógica, validaciones y cálculos se ejecuten en el backend | Primera fase | OBJ-001 |
| REQ-002 | Debe conservarse la información del origen, sus identificadores y relaciones, con discrepancias visibles antes de aceptar la importación | Primera fase; propuesta de continuidad | OBJ-001 |
| REQ-003 | Debe poder gestionarse el estado mensual de cobro de cada inquilino, registrar importes abonados y consultar saldos y resumen correspondiente | Primera fase; función existente | OBJ-001 |
| REQ-004 | El portal debe permitir consultar y actualizar información desde móvil y ordenador | Primera fase | OBJ-002 |
| REQ-005 | La interfaz debe tener temática inmobiliaria inspirada en Zaragoza | Primera fase | OBJ-002 |
| REQ-006 | El portal debe controlar el acceso mediante autenticación con Keycloak y autorizar exclusivamente al responsable del producto | Primera fase | OBJ-003 |
| REQ-007 | Una fase posterior debe identificar pagos mediante correos de Ibercaja y n8n, con reglas de asociación revisadas antes de su activación | Futura; detalles pendientes | OBJ-004 |
| REQ-008 | Deben poder entregarse nuevas funciones y correcciones al programa del cliente sin reinstalar toda la plataforma, conservando datos, identidad y configuración; las actualizaciones deben comprobar versión y compatibilidad, disponer de copia previa y recuperación ante fallos y evitar incluir dependencias sin cambios en las entregas habituales | Mantenimiento de la entrega; alcance confirmado el 2026-10-11 | OBJ-005 |

| REQ-009 | Una instalación Docker nueva en Windows debe ejecutar API, Keycloak y PostgreSQL en contenedores; al publicarse una nueva versión de API en GHCR, el servidor del cliente debe detectarla y aplicarla sin intervención del cliente, conservando datos, identidad y configuración y mostrando fallos de actualización | Nueva variante Docker; alcance confirmado el 2026-10-24 | OBJ-005 |

## 5. Business Constraints

| ID | Constraint | Rationale |
| --- | --- | --- |
| CON-001 | Conservar el origen como referencia durante la transición | El HTML y la exportación son las fuentes existentes |
| CON-002 | Separar la aceptación de la primera fase de la automatización bancaria futura | Encargo explícito del usuario |
| CON-003 | No asumir importe cobrado para pagos parciales | El registro de pago actual no contiene ese importe |

## 6. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Importación incompleta o relaciones inválidas | Pérdida o atribución errónea de datos | Conciliación del origen y reporte de errores |
| Sesión inválida aceptada por backend | Acceso indebido | Validación del acceso en backend; pruebas negativas |
| Interpretar parcial como una cantidad conocida | Resumen financiero incorrecto | Mantener desconocidos los importes históricos ausentes; calcular saldos solo con importes debidos y abonados conocidos |
| Aviso bancario duplicado o ambiguo | Cambio incorrecto del estado de cobro | Definir deduplicación y revisión de ambigüedades en fase futura |
| Actualización que sobrescribe datos, configuración o identidad | Pérdida de información o acceso del cliente | Copia previa coherente, conservación de configuración y verificación antes de declarar éxito |
| Versión de aplicación incompatible con esquema de datos o frontend | Servicio inutilizable o resultados incorrectos | Comprobar compatibilidad antes de modificar la instalación y definir recuperación de aplicación y datos conjuntamente |
| Interrupción durante una actualización o su recuperación | Instalación parcial declarada operativa | Estado de operación visible, detección de operación incompleta y recuperación sin habilitar escrituras sobre un estado inconsistente |

## 7. Success Criteria

Verificar OBJ-001 a OBJ-003 con criterios de aceptación de FRD y NFRD. OBJ-004 queda diferido. Estos documentos son borradores; su existencia no constituye aprobación ni evidencia de implementación.

OBJ-005 se verificará mediante FR-012 a FR-016 y NFR-007 a NFR-010: actualización de una instalación con datos sintéticos, rechazo de paquetes incompatibles, conservación de dependencias y recuperación tras fallo e interrupción. Véase [actualizaciones del cliente](FRDs/frd-actualizaciones-cliente.md). No hay resultados de ejecución para estos criterios todavía.

## References

- [VSD](../VSD.md).
- [HTML de origen](../../promalza-pro.html) y [JSON de origen](../../DOC.txt).

## Confirmación de producto — 2026-10-09

El usuario confirma acceso exclusivamente para él; conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos; registro de importes abonados y saldos. Los importes históricos ausentes siguen siendo desconocidos. No se aprueban decisiones ajenas a estos puntos ni se acredita implementación.

## Confirmación de producto — 2026-10-11

REQ-008 desarrolla el alcance de actualizaciones aceptado por el usuario en esta sesión. Se autoriza incorporar requisitos y criterios verificables; el protocolo de paquetes, el mecanismo de recuperación y los cambios de arquitectura se concretarán posteriormente. No se declara aprobada ni implementada toda la especificación.
