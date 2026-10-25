# Visión y alcance — Gestión de propiedades

## Title

| Field | Value |
| --- | --- |
| Document | Vision and Scope Document |
| Initiative | Portal de gestión de propiedades |
| Version | 0.3 |
| Status | Draft - for review |
| Author | Consultor |
| Reviewers | Responsable del producto — pendiente de identificar |
| Organization | Aelium |
| Repository Type | Software Product |
| Last Updated | 2026-10-11 |

## 1. Vision

Convertir la aplicación HTML existente en un portal web para gestionar propiedades, inquilinos, pagos e incidencias desde ordenador y móvil. Centralizar la lógica y la información en un backend y ofrecer una interfaz con temática inmobiliaria inspirada en Zaragoza, con acceso autenticado mediante Keycloak.

## 2. Problem Statement

El HTML actual contiene lógica de negocio, guarda información en localStorage y sincroniza el estado con JSONBin desde el navegador. El usuario solicita trasladar esa responsabilidad a un backend que entregue la información al frontend. DOC.txt contiene una exportación JSON del dominio existente, no documentación de requisitos.

## 3. Business Opportunity

Disponer de una gestión centralizada accesible desde ambos tipos de dispositivo y preparar una futura automatización del seguimiento de cobros. El beneficio económico y el volumen esperado de usuarios no están definidos.

## 4. Stakeholders

| Stakeholder | Role | Interest |
| --- | --- | --- |
| Aelium | Organización del proyecto | Desarrollo y mantenimiento del portal |
| Responsable del producto | Define alcance y valida resultados; identidad pendiente | Continuidad de la gestión existente |
| Personal de gestión | Usuario previsto; permisos por confirmar | Revisar y actualizar información desde móvil y ordenador |

Acceso exclusivo del responsable del producto, confirmado el 2026-10-09. No se incluye acceso de otros gestores ni de inquilinos.

## 5. Product Scope

Primera fase: backend responsable de datos, validaciones y cálculos; frontend para móvil y ordenador; autenticación con Keycloak; estética inmobiliaria de Zaragoza. Se toma el HTML como referencia de las funciones existentes: propiedades, inquilinos, pagos mensuales, incidencias, documentos, recibos y resumen de gestión. Su conservación completa fue confirmada el 2026-10-09. Se registrarán importes abonados y saldos; los importes históricos ausentes seguirán siendo desconocidos.

Mantenimiento de la entrega al cliente: incorporar nuevas funciones y correcciones mediante actualizaciones de la aplicación, sin reinstalar toda la plataforma. Deben conservarse los datos, la identidad del usuario y la configuración; comprobarse versión y compatibilidad antes de aplicar cambios; y existir una copia previa y recuperación ante fallos, incluidas migraciones de datos. Los cambios habituales se entregarán en paquetes que no incluyan dependencias sin cambios. Este alcance fue aceptado el 2026-10-11; el mecanismo técnico y su validación quedan pendientes. No se presupone actualización automática ni ausencia de interrupciones.

Fase posterior: identificación de pagos a partir de correos de Ibercaja mediante n8n. Se documenta como futura capacidad; no forma parte de la aceptación de la primera fase. No se incluyen órdenes bancarias ni transferencias.

Para una instalación Docker nueva en Windows con Docker Desktop, el responsable solicita el 2026-10-24 publicar versiones de la API en GitHub Container Registry y aplicarlas automáticamente sin intervención del cliente. PostgreSQL y Keycloak también se ejecutarán en contenedores con datos persistentes. Esta variante no migra ni modifica la instalación nativa Windows existente; el frontend conserva su publicación independiente. La comprobación periódica requiere que Docker Desktop esté disponible en la sesión Windows.

## 6. Objectives

Los objetivos y criterios siguientes son propuestas derivadas del encargo, pendientes de revisión del responsable del producto.

| ID | Objective | Success Metric | Target |
| --- | --- | --- | --- |
| OBJ-001 | Centralizar la gestión y conservar la información existente | Operaciones del alcance resueltas por backend y conciliación de importación | Datos del origen conservados o diferencias explicadas; sin acceso directo del navegador a JSONBin en el portal nuevo |
| OBJ-002 | Permitir gestión desde móvil y ordenador con identidad visual de Zaragoza | Flujos de consulta y actualización verificados en ambos formatos | Flujos acordados utilizables en ambos; revisión visual aceptada por responsable |
| OBJ-003 | Controlar el acceso al portal mediante Keycloak | Comprobaciones de acceso autenticado y rechazo sin sesión válida | Ninguna operación protegida permite acceso anónimo |
| OBJ-004 | Preparar una futura automatización de seguimiento de pagos | Reglas de conciliación definidas y verificadas antes de activar automatización | No modificar pagos automáticamente con coincidencias ambiguas; fase futura |
| OBJ-005 | Mantener y ampliar el programa del cliente sin reinstalar toda la plataforma | Actualización de una instalación existente y recuperación ante fallos verificadas | Nuevas funciones disponibles conservando datos, identidad y configuración; dependencias sin cambios conservadas; fallos sin éxito falso ni pérdida silenciosa de información |

## 7. Constraints

- Keycloak se interpreta como el producto denominado «keyclock» en el encargo. La interpretación queda pendiente de revisión.
- Los documentos organizativos se provisionan desde CRM por indicación del usuario y conservan estado de borrador.
- No existe MANAGEMENT-MODEL.yaml: se aplica classic + markdown como valor predeterminado; no se cambia el modelo.
- Lenguaje del backend, base de datos, alojamiento, dominio y despliegue están pendientes de decisión de arquitectura.
- Identidad técnica del único usuario autorizado, concurrencia, navegadores objetivo, requisitos legales aplicables, retención y disponibilidad están pendientes de confirmar; no se inventan compromisos.
- En pagos parciales, el origen registra estado pero no importe abonado. No permite deducir por sí solo el saldo pendiente.

## References

- Encargo del usuario y confirmación de Aelium y CRM en esta sesión, 2026-10-02.
- [Aplicación de origen](../promalza-pro.html).
- [Exportación JSON de origen](../DOC.txt). No se reproducen datos personales en esta especificación.
- [Política de pruebas](./_verification/Test-Policy.md) y [estrategia](./_verification/Test-Strategy.md).

## Confirmación de producto — 2026-10-09

El usuario confirma acceso exclusivamente para él; conservación de propiedades, inquilinos, pagos, incidencias, documentos y recibos; registro de importes abonados y saldos. Los importes históricos ausentes siguen siendo desconocidos. No se aprueban decisiones ajenas a estos puntos ni se acredita implementación.

## Confirmación de producto — 2026-10-11

El usuario solicita continuar el plan para añadir funciones sin reinstalar todo el programa del cliente y acepta incorporar el alcance de actualizaciones descrito en la sección 5 y sus criterios de aceptación. OBJ-005 expresa ese objetivo confirmado. Esta confirmación no aprueba en bloque los borradores anteriores ni acredita un actualizador implementado.
