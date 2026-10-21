## Title

| Field | Value |
| --- | --- |
| Document | Roadmap |
| Roadmap ID | RDM-001 |
| Version | 0.5 |
| Status | Draft - dates pending |
| Author | Rector |
| Reviewers | Responsable individual; identidad pendiente |
| Organization | Aelium |
| Last Updated | 2026-10-16 |

## 1. Purpose

Orden de estados objetivo sin inventar fechas. Un responsable individual gestiona la entrega; disponibilidad y esfuerzo no confirmados. La infraestructura se gestiona como iniciativa independiente. Este documento no compromete plazos y no contiene Tasks.

Se añade el horizonte de mantenimiento del cliente y un estado de disponibilidad de infraestructura Windows. Su orden expresa condiciones de entrega, no calendario ni ampliación del equipo. La fecha de modificación de estos documentos no es una fecha de inicio de implementación.

## 2. Horizons

| Horizon | Period | Theme |
| --- | --- | --- |
| HOR-001 | Pendiente de capacidad | Primera fase del portal |
| HOR-002 | Inicio de infraestructura 2026-10-03; cierre pendiente | Verificación reproducible |
| HOR-003 | Pendiente de disponibilidad y esfuerzo real; sin período comprometido | Actualizaciones de la instalación del cliente |

## 3. Milestones

| ID | Milestone | Horizon | Target Date | Status |
| --- | --- | --- | --- | --- |
| MS-001 | Portal validado con criterios acordados | HOR-001 | Sin fecha comprometida | Planned |
| MS-002 | Infraestructura reproducible con evidencia de comprobación | HOR-002 | Sin fecha comprometida | In progress |
| MS-003 | Actualización y recuperación del programa del cliente verificadas, conservando datos, identidad y configuración | HOR-003 | Sin fecha comprometida | Planned |
| MS-004 | Entorno Windows aislado disponible con instalación sintética reproducible y capacidad de recuperar y recoger evidencia tras reinicios | HOR-002 | Sin fecha comprometida | Planned |

## 4. Milestone Conditions

MS-004 proporciona disponibilidad de entorno para comprobar MS-003; no es una prueba de que el actualizador funcione. Los criterios y la evidencia de MS-003 se registran en PRJ-003 y sus Work Packages, con verificación formal pendiente de Quaestor. MS-001 y MS-002 conservan su alcance y estado anteriores; la nueva planificación no los declara alcanzados. No se fija un orden temporal total entre la entrega inicial del portal y las actualizaciones: las rutas utilizadas deben tener una base comprobada, pero los pendientes de negocio no relacionados no bloquean preparar el mecanismo.

### Revisión de avance — 2026-10-16

PRJ-003 y WP-006 a WP-009 están In Progress, con implementación y pruebas locales parciales registradas en sus documentos. MS-003 conserva Planned porque la validación integral y aceptación siguen pendientes. MS-004 conserva Planned: no se ha acreditado el entorno Windows con servicios/reinicios requerido por WP-010. No se añaden fechas sin capacidad confirmada ni se interpreta la evidencia local como cumplimiento de los hitos.

### Registro anterior de disponibilidad de entorno — 2026-10-16

El usuario confirma que no dispone todavía de entorno aislado. WP-010 y TSK-035 registran el bloqueo de recurso; MS-004 sigue Planned, sin fecha. La validación Windows de sistema necesaria para MS-003 depende de resolverlo. El avance local ya registrado no acredita el entorno ni elimina esta dependencia.

### VM disponible según declaración — 2026-10-16

El usuario informa de una VM Windows 10 en VirtualBox. Se supera el bloqueo por ausencia declarada de recurso y WP-010/TSK-035 quedan In Progress; siguen pendientes identificación, aislamiento, permisos y recuperación comprobada. MS-004 y MS-003 conservan Planned, sin fecha comprometida.

## References

- [Portal](../_planning/PRJ-001.md), [infraestructura](../_planning/PRJ-002.md).
- [Actualizaciones del cliente](../_planning/PRJ-003.md).
