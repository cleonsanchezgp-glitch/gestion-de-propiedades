# Análisis de características de calidad

## Title

| Field | Value |
| --- | --- |
| Document | Software Quality Characteristics Analysis (SQCA) |
| Initiative | Portal de gestión de propiedades |
| Version | 0.4 |
| Status | Draft - for review; provisional risk assessment |
| Author | Quaestor |
| Reviewers | Responsable del producto y revisor independiente — pendientes |
| Organization | Aelium |
| Last Updated | 2026-10-16 |

## 1. Purpose

Determinar la profundidad de las pruebas a partir del encargo, la exportación y los requisitos documentados. Se examinan las 40 subcaracterísticas del template Qualitas, sin inferir obligaciones legales no confirmadas. La especificación y las fuentes organizativas continúan en borrador. Las prioridades son una valoración técnica provisional; los casos condicionados a decisiones de producto se indican en TMP.

La revisión del 2026-10-11 incorpora REQ-008, FR-012 a FR-016 y NFR-007 a NFR-010, con diseño ADR-012 a ADR-016 y planificación PRJ-003/WP-006 a WP-010. El alcance de actualizaciones está confirmado; no se declara implementado. Se conserva la estrategia local de Aelium designada desde CRM, en borrador y sin comprobación nueva de fuente canónica o aprobación. El análisis distingue prioridades de subcaracterísticas de la clasificación Critical de la estrategia para cambios en autenticación y datos financieros.

## 2. Priority Scale

| Priority | Meaning |
| --- | --- |
| High | Fallo que compromete el propósito central, datos de gestión o acceso protegido; cobertura específica y profunda |
| Medium | Riesgo concreto y acotado; cobertura representativa |
| Low | Exposición limitada; comprobación puntual |
| N/A | Sin aplicación identificada en el alcance actual, con motivo explícito |
| TBD | Sin información suficiente para asignar prioridad justificada |

## 3. Characteristic Assessment

### 3.1 Functional Suitability

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Functional completeness | High | La sustitución del HTML y las actualizaciones pueden dejar fuera funciones de gestión; REQ-001, seis funciones confirmadas y REQ-008 | Inventario, regresión y aceptación de actualización |
| Functional correctness | High | REQ-003 exige importes y saldos correctos; REQ-008 exige conservarlos tras actualizar y recuperar, manteniendo históricos desconocidos | Unitarias, integración, comparación de datos y recuperación |
| Functional appropriateness | Medium | El encargo requiere revisar datos desde ambos dispositivos; REQ-004 | Escenarios de uso representativos |

### 3.2 Performance Efficiency

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Time behaviour | TBD | Sin objetivos de latencia ni patrón de uso acordado | Medición exploratoria; aceptación pendiente |
| Resource utilization | Medium | El diseño de REQ-008 requiere espacio para paquete, copia y ensayo de restauración; no hay presupuesto general de CPU/memoria ni límites de adjuntos confirmados | Comprobar prerrequisitos y falta de espacio, sin inventar umbrales de rendimiento |
| Capacity | TBD | No se conoce concurrencia ni volumen futuro | Carga tras definir capacidad |

### 3.3 Compatibility

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Co-existence | Medium | REQ-008 conserva dependencias, servicios y configuración existentes; no se conoce el inventario de otras aplicaciones del equipo cliente | Comparación del inventario afectado y aislamiento del ensayo; no afirmar compatibilidad con aplicaciones desconocidas |
| Interoperability | High | REQ-001/006 conectan frontend, backend e identidad; NFR-010 exige combinaciones compatibles durante actualización y recuperación | Contratos por versión, frontend antiguo/nuevo e integración de identidad |

### 3.4 Interaction Capability

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Appropriateness recognisability | Medium | La interfaz debe expresar gestión inmobiliaria y Zaragoza; REQ-005 | Revisión visual de aceptación |
| Learnability | TBD | No se ha definido experiencia de los usuarios ni objetivo de aprendizaje | Evaluación posterior con usuarios |
| Operability | High | Uso desde móvil y ordenador es condición expresa; REQ-004 | Flujos completos en ambos formatos |
| User error protection | High | REQ-003 afecta registros financieros; FR-015/016 impiden éxito falso y escrituras durante un estado de mantenimiento no verificado | Entradas inválidas, rechazo de escritura, conservación de formulario y resultados de mantenimiento |
| User engagement | Medium | Existe dirección estética expresa; REQ-005 | Revisión visual representativa |
| Inclusivity | TBD | No hay necesidades de accesibilidad ni objetivo formal confirmado | Evaluación y definición del objetivo |
| User assistance | Medium | FR-001/NFR-003 requieren fallos visibles; FR-015 exige causa y ubicación de copia para orientar el mantenimiento | Errores visibles, recuperación de formulario y revisión de guía de actualización |
| Self-descriptiveness | Medium | REQ-003 distingue estados de pago; FR-015 y el diseño distinguen actualización correcta, recuperación y comprobación pendiente | Etiquetas de negocio y resultados de mantenimiento inequívocos |

### 3.5 Reliability

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Faultlessness | High | REQ-001 centraliza la persistencia; REQ-008 no permite reinicializar datos ni repetir migraciones al actualizar | Persistencia, repetición sin efectos e integración de actualización |
| Availability | TBD | Portal web solicitado sin acuerdo de disponibilidad | Definición de objetivo y medición posterior |
| Fault tolerance | High | REQ-001/003 prohíben guardados falsos; FR-015/016 requieren detectar interrupciones y no habilitar escrituras o éxito sin comprobación | Fallos de persistencia/red, interrupciones de proceso y reinicio por fase |
| Recoverability | High | REQ-008, FR-014/016 y NFR-009 exigen recuperar aplicación, esquema, datos, identidad y configuración coherentes tras fallo | Copia y restauración aisladas, fallo tras migración e interrupción de recuperación; política general de copias aún pendiente |

### 3.6 Security

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Confidentiality | High | REQ-006 protege datos personales y rentas; las copias de REQ-008 contienen configuración y credenciales, mientras FR-015 exige informes sin secretos | Acceso negativo, adjuntos, ACL de copia y ausencia de secretos en informes/bundles |
| Integrity | High | REQ-001/006 protegen datos; FR-012 exige rechazar paquetes alterados y FR-016 bloquear escrituras sobre estado incompleto | Validación de paquetes/rutas, acceso exclusivo y preservación de datos durante mantenimiento |
| Non-repudiation | TBD | No se ha solicitado firma ni prueba jurídica de operaciones | Aclaración de necesidad antes de diseñar pruebas |
| Accountability | High | La política de Aelium exige responsabilidad sobre cambios de datos financieros; diseño de registro pendiente | Verificación de identidad de operaciones cuando se defina auditoría |
| Authenticity | High | REQ-006 usa Keycloak; NFR-007 conserva la misma identidad y FR-015 exige comprobar su acceso tras actualizar o recuperar | Sesiones e identidad anterior/posterior; rechazo de otro usuario y capacidades de diagnóstico inválidas |
| Resistance | High | REQ-006 expone acceso protegido; el diagnóstico de ADR-016 no debe permitir usar una capacidad de mantenimiento sobre datos reales | Negativos de autenticación, capacidad de diagnóstico, rutas de paquete y revisión de seguridad |

### 3.7 Maintainability

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Modularity | High | REQ-001 centraliza lógica; NFR-008 y ADR-012 separan aplicación actualizable de dependencias y configuración persistentes | Inspección de responsabilidades, paquete selectivo y comparación de componentes no afectados |
| Reusability | TBD | No hay reutilización entre productos o módulos solicitada | No se fija cobertura dedicada |
| Analysability | Medium | REQ-002 requiere explicar discrepancias; FR-015/016 requieren identificar versión, fase y causa de fallo sin secretos | Reportes de discrepancias y resultados de actualización/recuperación |
| Modifiability | High | REQ-008 confirma añadir funciones sin reinstalar toda la plataforma ni alterar datos; NFR-008 exige conservar dependencias sin cambios | Actualización de aplicación, regresión, repetición sin efectos y conservación de configuración |
| Testability | High | La estrategia exige evidencia sobre autenticación y registros financieros; REQ-008 requiere fallos y restauración reproducibles con entorno independiente WP-010 | Casos por fase, baseline sintética, artefactos externos e identificación exacta de versiones |

### 3.8 Flexibility

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Adaptability | High | Móvil y ordenador son formatos expresamente requeridos; REQ-004 | Compatibilidad y adaptación visual |
| Scalability | TBD | Sin volumen ni previsión de crecimiento confirmados | Objetivo pendiente |
| Installability | High | REQ-008 y ADR-012/013 requieren actualizar una instalación Windows terminada, reconocer origen y rechazar incompatibilidades sin reinstalación general | Adopción antigua, actualización, rechazo previo, repetición e interrupción |
| Replaceability | High | REQ-008, FR-014/016 y NFR-007/009 requieren sustituir o recuperar aplicación conservando datos, identidad y configuración compatibles | Comparación anterior/posterior y recuperación conjunta de aplicación y esquema |

### 3.9 Safety

| Subcharacteristic | Priority | Rationale | Derived test types |
| --- | --- | --- | --- |
| Operational constraint | N/A | No se ha identificado control físico o función de seguridad de personas en el alcance | Reevaluar si cambia el alcance |
| Risk identification | N/A | No se han identificado peligros físicos; riesgos financieros se tratan en correctness e integrity | Reevaluar si cambia el alcance |
| Fail safe | N/A | Sin estado seguro físico identificado en este portal | Fallos de datos cubiertos en reliability |
| Hazard warning | N/A | No hay advertencias de peligro físico solicitadas | Errores operativos cubiertos en interaction |
| Safe integration | N/A | No existe integración con un sistema de seguridad física | Ibercaja/n8n requiere evaluación futura separada |

## 4. Summary — High Priority Only

| Characteristic | Subcharacteristic | Rationale | Derived test types |
| --- | --- | --- | --- |
| Functional Suitability | Functional completeness | Continuidad de gestión al sustituir el HTML y actualizar la aplicación | Inventario, regresión y aceptación de actualización |
| Functional Suitability | Functional correctness | Conservar importes, saldos e históricos desconocidos tras actualización/recuperación | Unitarias, integración y comparación de datos |
| Compatibility | Interoperability | Combinaciones frontend–backend–identidad compatibles por versión | Contratos, integración y recuperación |
| Interaction Capability | Operability | Uso exigido desde ambos formatos | Sistema y E2E en móvil y ordenador |
| Interaction Capability | User error protection | Evitar escrituras y éxito falso durante mantenimiento de datos financieros | Negativos, conservación de formulario y resultados |
| Reliability | Faultlessness | Persistencia y actualización sin reinicialización ni migraciones repetidas | Integración y repetición sin efectos |
| Reliability | Fault tolerance | Evitar éxito falso y reapertura prematura tras interrupciones | Fallos por fase y reinicio |
| Reliability | Recoverability | Recuperar aplicación, esquema, datos, identidad y configuración coherentes | Copia, restauración aislada y recuperación interrumpida |
| Security | Confidentiality | Datos personales y secretos de configuración/copias | Acceso negativo, ACL y ausencia de secretos en informes |
| Security | Integrity | Rechazar paquetes alterados y escrituras sobre estado incompleto | Validación, rutas de paquete y guardia backend |
| Security | Accountability | Política de pruebas para cambios financieros | Auditoría condicionada a diseño |
| Security | Authenticity | Conservar identidad y acceso existentes tras cambio | Sesiones, comparación de sujeto y capacidades de diagnóstico |
| Security | Resistance | Exposición del portal y diagnóstico que no debe autorizar datos reales | Negativos y revisión de seguridad |
| Maintainability | Modularity | Separar aplicación de dependencias/configuración persistentes | Responsabilidades y sustitución selectiva |
| Maintainability | Modifiability | Añadir funciones sin reinstalar ni alterar datos | Actualización, regresión y repetición |
| Maintainability | Testability | Reproducir fallos y resultados con versiones identificadas | Automatización, baseline y artefactos externos |
| Flexibility | Adaptability | Uso desde móvil y ordenador | Compatibilidad y adaptación |
| Flexibility | Installability | Actualizar instalación Windows completa con origen reconocido | Adopción antigua, rechazo previo y recuperación |
| Flexibility | Replaceability | Recuperar una versión compatible conservando información | Comparación integral y recuperación de aplicación/esquema |

### Revisión de riesgo del actualizador — 2026-10-16

Se conserva la valoración de las 40 subcaracterísticas y las 19 High. El diseño y planificación conciliados y el [resumen local](../../tests/artifacts/updates/local-summary.json) acreditan avance parcial, no aceptación ni reducción de impacto. Persisten riesgo de recuperación/conservación, autenticidad e interoperabilidad: faltan servicios/reinicios Windows, Keycloak y portal reales, origen revisado y revisión independiente. La conservación actual rechaza cambios de filas existentes; transformaciones de datos y cambios de identidad necesitan política revisada y pruebas específicas, sin relajar integridad para obtener un resultado satisfactorio.

Se ha consultado la estrategia designada desde CRM y la copia local; ambas conservan Draft - for review y exigen revisión independiente para riesgo Critical. No se establece una fuente canónica nueva ni aprobación organizativa. TMP registra la correspondencia parcial y el orden de variantes pendientes; no se ejecutan pruebas desde este análisis.

## References

- [VSD](../VSD.md), [BRD](../_specification/BRD.md), [NFRD](../_specification/NFRD.md).
- [Revisión del origen](../_specification/SPECIFICATION-REVIEW.md).
- [Test Policy](Test-Policy.md), [Test Strategy](Test-Strategy.md), [TMP](TMP.md).
- Template SQCA de la instalación Qualitas: inventario de características y subcaracterísticas.
- [FRD de actualizaciones](../_specification/FRDs/frd-actualizaciones-cliente.md), [diseño](../_design/UPDATE-DESIGN.md) y [proyecto de actualización](../_planning/PRJ-003.md), revisados el 2026-10-11.
