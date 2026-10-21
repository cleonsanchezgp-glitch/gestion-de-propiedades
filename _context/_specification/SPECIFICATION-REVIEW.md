# Revisión de la especificación

Fecha: 2026-10-11. Autor: Consultor. Estado: revisión parcial; alcance de actualizaciones confirmado, diseño pendiente.

## Alcance de la revisión

Revisión del encargo, los borradores VSD/BRD/FRD/NFRD y consistencia básica de la exportación DOC.txt. No constituye auditoría de conformidad de Notarius, aprobación de requisitos ni prueba del software futuro. Se aplica el perfil predeterminado classic + markdown.

La revisión del 2026-10-11 añade únicamente el alcance de actualizaciones aceptado y su cadena de requisitos. Se examinaron la guía Windows, la preparación de paquetes y las funciones de validación del paquete como punto de partida; no se repitió la comprobación de DOC.txt ni se ejecutó una actualización en el equipo del cliente.

## Cobertura del encargo

| Necesidad | Requisitos | Estado |
| --- | --- | --- |
| Backend como autoridad de lógica y datos | REQ-001; FR-001; NFR-006 | Expresa en el encargo |
| Preservar datos del origen | REQ-002; FR-002, FR-003 | Propuesta de continuidad; requiere reglas para discrepancias |
| Seguimiento mensual de pagos | REQ-003; FR-004 a FR-006 | Fuente funcional en el HTML; importes parciales pendientes |
| Uso en móvil y ordenador | REQ-004; FR-008; NFR-001, NFR-002 | Expresa en el encargo; navegadores y dimensiones de prueba propuestos |
| Estética inmobiliaria de Zaragoza | REQ-005; FR-009 | Expresa en el encargo; aprobación visual posterior |
| Autenticación Keycloak | REQ-006; FR-007; NFR-004, NFR-005 | Interpretación de «keyclock»; configuración y roles pendientes |
| Ibercaja y n8n | REQ-007; FR-010, FR-011 | Futura; fuera de aceptación de primera fase |
| Añadir funciones sin reinstalar toda la plataforma del cliente | OBJ-005; REQ-008; FR-012 a FR-016; NFR-007 a NFR-010 | Alcance confirmado el 2026-10-11; criterios incorporados, diseño e implementación pendientes |

## Hallazgos sobre el origen

Comprobación de la exportación, sin reproducir datos personales:

- 8 propiedades, 8 inquilinos, 41 pagos y 4 incidencias.
- Ningún inquilino referencia una propiedad inexistente; ninguna incidencia con referencia de propiedad apunta a una inexistente.
- 4 pagos referencian inquilinos que no aparecen en la colección actual: 1 coincide con un identificador del registro de inquilinos borrados y 3 no constan tampoco allí. Deben revisarse antes de definir su conservación histórica; no se eliminan ni se reasignan automáticamente.
- No se detectan pagos repetidos para la misma pareja inquilino/mes ni estados de pago fuera de pagado, parcial y pendiente.
- Hay 2 pagos parciales sin importe abonado. No puede reconstruirse un saldo fiable para esos registros.
- Hay 2 inquilinos con inicio y fin de contrato iguales. Es una situación a revisar, no un error corregible automáticamente con la información disponible.
- El HTML calcula el resumen cobrado sumando rentas actuales de inquilinos marcados como pagados. Este resumen no equivale a una conciliación bancaria ni fija la renta histórica.

## Decisiones confirmadas — 2026-10-09

1. Acceso exclusivo del usuario responsable del producto; identidad técnica pendiente de configurar.
2. Conservar propiedades, inquilinos, pagos, incidencias, documentos y recibos.
3. Registrar importes abonados y saldos; históricos sin importe permanecen desconocidos.

## Pendientes y resultado

Incorporadas estas decisiones a VSD, BRD y FRDs afectados, con AC-012 (600 debido, 250 abonado, saldo 350) y AC-013 (histórico desconocido). El resto de la especificación conserva su estado de borrador. No se declara el software implementado ni verificado.

Siguen pendientes reglas de pagos múltiples, sobrepagos, correcciones y renta histórica; conservación de pagos de inquilinos borrados y fechas contractuales; navegadores, adjuntos, recuperación, alojamiento y obligaciones de datos.

## Decisiones confirmadas — 2026-10-11

El usuario solicita continuar el plan para actualizar el programa del cliente sin reinstalar todo al añadir funciones y acepta incorporar el alcance propuesto: conservación de datos, usuario, configuración y túnel; paquetes habituales sin dependencias sin cambios; validación de versión y compatibilidad; copia previa y recuperación ante fallos, incluidas migraciones.

Se añade OBJ-005 en VSD, REQ-008 en BRD, FRD-005 con FR-012 a FR-016 y AC-014 a AC-023, y NFR-007 a NFR-010 con AC-107 a AC-110. La identidad, configuración y credenciales necesarias para el túnel se incluyen en la conservación y recuperación. Se mantienen los identificadores existentes y el estado de borrador del conjunto documental.

### Límites y pendientes del nuevo alcance

- El instalador actual solo admite reanudar instalaciones incompletas. No hay actualizador implementado ni evidencia de cumplimiento de los criterios nuevos.
- El paquete existente incluye todas las dependencias y su manifiesto no identifica una versión de aplicación ni las versiones de origen admitidas. Conditor debe definir cómo reconocer la instalación ya entregada, sin asumir una versión.
- Quedan pendientes formato y procedencia verificable del paquete, compatibilidad frontend–API–esquema, bloqueo de escrituras, copia coherente, activación, recuperación y detección de interrupciones.
- No se fijan fechas, tamaño máximo de paquete, duración máxima de mantenimiento ni actualizaciones automáticas. Los cambios de dependencias requieren alcance específico y no una reinstalación general implícita.
- ADD, Planning/Time, SQCA/TMP y TRACEABILITY-MATRIX todavía no incorporan este alcance. Su actualización corresponde a sus especialistas; los resultados previos no verifican los criterios nuevos.

Siguiente acción: Conditor incorporará REQ-008 al diseño de actualización y recuperación, con compatibilidad para la instalación Windows existente y el frontend publicado por separado. Después Rector podrá planificar trabajo respaldado por ese diseño y Quaestor definir pruebas; Vestigator refrescará la matriz cuando estén disponibles esas fuentes.

## Fuentes

- [VSD](../VSD.md), [BRD](BRD.md), [NFRD](NFRD.md) y FRDs en esta carpeta.
- [Exportación](../../DOC.txt) y [HTML de origen](../../promalza-pro.html).
