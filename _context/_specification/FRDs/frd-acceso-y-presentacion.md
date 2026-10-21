# Acceso y presentación del portal

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Acceso y presentación |
| ID | FRD-003 |
| Version | 0.3 |
| Status | Draft - for review |
| Author | Consultor |
| Last Updated | 2026-10-09 |

## 1. Overview

Portal con autenticación Keycloak, utilizable en móvil y ordenador y con identidad inmobiliaria inspirada en Zaragoza. Autenticación y cifrado del transporte se documentan como controles separados.

## 2. Actors

| Actor | Description |
| --- | --- |
| Usuario | Accede y utiliza el portal |
| Keycloak | Gestiona la autenticación requerida |
| Backend | Comprueba el acceso a datos y operaciones |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-007 | El portal debe ofrecer un formulario propio de usuario y contraseña, validarlos mediante Keycloak a través del backend y cerrar la sesión; el backend autoriza exclusivamente al responsable del producto | Primera fase | REQ-006 |
| FR-008 | El frontend debe permitir los flujos acordados de consulta y actualización en móvil y ordenador | Primera fase | REQ-004 |
| FR-009 | El frontend debe presentar una temática inmobiliaria inspirada en Zaragoza, revisada por el responsable del producto | Primera fase | REQ-005 |

## 4. Workflow

1. El usuario introduce usuario y contraseña en el formulario del portal; el backend los verifica con Keycloak y crea una sesión autorizada.
2. El portal solicita información al backend mediante la cookie de sesión; los tokens de Keycloak permanecen en servidor.
3. El frontend adapta la presentación al dispositivo.
4. El usuario cierra sesión; el portal deja de mostrar datos protegidos y las nuevas peticiones sin credenciales válidas se rechazan.

## 5. Inputs

| Input | Source |
| --- | --- |
| Resultado de autenticación | Keycloak |
| Información de gestión | Backend |
| Dimensiones de pantalla | Dispositivo |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Sesión y errores de acceso | Usuario |
| Interfaz adaptada | Móvil y ordenador |

## 7. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-007 | El responsable autorizado, otro usuario autenticado y una solicitud sin sesión válida | Ambos solicitan un recurso protegido | Solo el responsable obtiene el recurso; el otro usuario autenticado y la solicitud sin sesión se rechazan sin datos protegidos | FR-007 |
| AC-008 | Una sesión válida en móvil y ordenador | Se consulta un inmueble y se actualiza el estado de un pago | Ambas presentaciones permiten completar el flujo y muestran la confirmación del backend | FR-008 |
| AC-009 | Una propuesta visual del portal | El responsable revisa los elementos inmobiliarios y las referencias a Zaragoza | Se registra aceptación o ajustes; no se declara aceptada sin revisión | FR-009 |

## 8. Error Handling

Si el acceso falla o expira, comunicarlo sin mostrar información protegida. El acceso es exclusivo del responsable del producto. La configuración de clientes Keycloak, identidad autorizada, sesiones y despliegue sigue pendiente de arquitectura. Una sesión válida de otro usuario no concede acceso.

## References

- [BRD](../BRD.md), REQ-004, REQ-005 y REQ-006.

## Confirmación de producto — 2026-10-09

El usuario confirma acceso exclusivamente para él; conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos; registro de importes abonados y saldos. Los importes históricos ausentes siguen siendo desconocidos. No se aprueban decisiones ajenas a estos puntos ni se acredita implementación.

## Confirmación de acceso integrado

El usuario solicita expresamente introducir las credenciales desde el propio portal y verificarlas con Keycloak. Esta decisión sustituye el flujo anterior con redirección; no autoriza conservar contraseñas en el frontend ni altera el acceso exclusivo.
