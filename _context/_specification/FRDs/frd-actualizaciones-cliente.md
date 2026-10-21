# Actualizaciones del programa del cliente

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Actualizaciones sin reinstalar toda la plataforma |
| ID | FRD-005 |
| Version | 0.1 |
| Status | Draft - for review; scope confirmed 2026-10-11 |
| Author | Consultor |
| Last Updated | 2026-10-11 |

## 1. Overview

Entregar nuevas funciones y correcciones sobre la instalación existente del cliente, conservando datos, identidad y configuración. El usuario aceptó este alcance el 2026-10-11. Los requisitos siguientes concretan REQ-008 y no acreditan un actualizador implementado.

La entrega observada es un servidor Windows x64 con PostgreSQL, Keycloak, API y túnel; el frontend se despliega por separado. El instalador existente no permite reinstalar encima de una instalación terminada y su opción Resume solo reanuda instalaciones incompletas. Esta capacidad requiere un flujo de actualización propio; no se considera resuelta por cambiar esa restricción del instalador.

Una actualización habitual no cambia las dependencias instaladas y debe evitar redistribuirlas. Las entregas que requieran actualizar PostgreSQL, Keycloak, Java, WinSW, el runtime o el túnel deben identificar ese alcance y contar con una ruta de mantenimiento específica; su migración no queda diseñada en este FRD. El orden de publicación frontend–backend deberá respetar la compatibilidad declarada. No se presupone actualización automática, un proveedor de distribución ni servicio sin interrupciones.

## 2. Actors

| Actor | Description |
| --- | --- |
| Responsable de mantenimiento | Aplica el paquete en el equipo del cliente con los permisos requeridos y consulta el resultado |
| Responsable del producto | Verifica que conserva acceso y datos y que están disponibles las funciones de la nueva versión |
| Mecanismo de actualización | Valida compatibilidad, protege el estado previo, aplica cambios, comprueba el resultado y permite recuperación |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-012 | Antes de modificar la instalación, el mecanismo debe comprobar integridad del paquete, producto y plataforma, versión instalada y destino, compatibilidad con dependencias, esquema y frontend y prerrequisitos; si falta evidencia necesaria o no se admite la combinación, debe rechazar el paquete con una causa visible | Mantenimiento de la entrega | REQ-008 |
| FR-013 | Debe aplicar los cambios de aplicación y las migraciones declaradas sobre una instalación terminada, conservando componentes y configuración no afectados, sin ejecutar una instalación inicial; repetir una entrega ya aplicada no debe repetir migraciones ni reinicializar datos | Mantenimiento de la entrega | REQ-008 |
| FR-014 | Antes de reemplazar componentes o ejecutar migraciones, debe crear y comprobar una copia coherente de los datos de negocio, adjuntos, datos de identidad y configuración necesaria para recuperar la versión anterior, junto con su versión y componentes; si la copia falla, debe abortar sin aplicar cambios | Mantenimiento de la entrega | REQ-008 |
| FR-015 | Debe comprobar tras el cambio la versión activa, el acceso del usuario existente y los flujos acordados de lectura y escritura frontend–API; solo debe declarar éxito cuando se verifiquen, e informar de versión anterior y destino, resultado y ubicación de la copia sin revelar credenciales | Mantenimiento de la entrega | REQ-008 |
| FR-016 | Ante fallo o interrupción debe identificar la operación incompleta y permitir recuperar aplicación, datos y configuración compatibles con la copia previa; debe impedir escrituras de negocio durante actualización y recuperación hasta comprobar un estado coherente, e informar del fallo si la recuperación no concluye | Mantenimiento de la entrega | REQ-008 |

## 4. Workflow

1. El responsable dispone de un paquete de actualización y de una instalación existente identificable.
2. El mecanismo comprueba el paquete, la versión instalada, los permisos y la compatibilidad necesaria antes de modificar la instalación.
3. Protege el período de mantenimiento contra escrituras de negocio y prepara la copia coherente y los componentes necesarios para recuperar el estado anterior.
4. Solo tras comprobar la copia, aplica los cambios de aplicación y las migraciones declaradas; conserva las dependencias y la configuración no afectadas.
5. Comprueba la versión y los flujos del portal, incluido el acceso del usuario existente. La comprobación de escritura usa un registro de prueba identificable y no modifica pagos reales del cliente.
6. Si las comprobaciones pasan, habilita la operación normal y registra éxito. Si fallan, registra el estado y permite recuperar la versión anterior con datos y configuración compatibles.
7. Una ejecución posterior detecta una operación interrumpida antes de aceptar otra actualización. No declara la instalación operativa hasta verificar el estado recuperado o actualizado.

El mecanismo concreto de bloqueo de escrituras, copia, sustitución, comprobación y recuperación pertenece al diseño posterior. Las comprobaciones y su limpieza deben dejar los datos de negocio intactos. No se garantiza recuperar una migración de esquema mediante el mero reemplazo del ejecutable.

## 5. Inputs

| Input | Source |
| --- | --- |
| Paquete de actualización con versión destino, componentes, integridad y compatibilidad declaradas | Preparación de entrega; formato pendiente de Conditor |
| Versión y estado de la instalación, dependencias, esquema y configuración | Instalación del cliente; mecanismo de identificación pendiente |
| Compatibilidad frontend–API y orden admitido de publicación | Declaración de entrega; contrato técnico pendiente |
| Datos y configuración necesarios para copia y recuperación | Instalación existente; manejo con los permisos de mantenimiento |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Nueva versión comprobada, o rechazo sin modificación de la instalación | Instalación del cliente |
| Copia previa coherente y referencias a los componentes de recuperación | Almacenamiento de mantenimiento con acceso restringido |
| Resultado de actualización o recuperación con versiones y causa de fallo, sin secretos | Responsable de mantenimiento |
| Estado incompleto reconocible tras una interrupción | Siguiente ejecución de mantenimiento |

## 7. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-014 | Una instalación existente y paquetes alterados, de otro producto o plataforma, o con versión de origen o compatibilidad no admitidas o desconocidas | Se solicita cada actualización | Cada paquete se rechaza con causa visible antes de detener servicios o modificar aplicación, datos o configuración | FR-012 |
| AC-015 | Una instalación terminada con datos sintéticos y un paquete compatible que incorpora una función de aplicación | Se aplica el paquete | La nueva función queda disponible sobre esa instalación sin ejecutar el instalador inicial ni reinstalar las dependencias sin cambios | FR-013 |
| AC-016 | Una versión ya aplicada con sus migraciones registradas | Se presenta otra vez el mismo paquete | Se informa de que ya está aplicado, sin repetir migraciones, reinicializar datos ni alterar la configuración | FR-013 |
| AC-017 | Una instalación con datos de negocio, adjuntos, identidad y configuración, y componentes de aplicación identificados | Se prepara una actualización | Antes del primer reemplazo o migración existe una copia comprobada y una referencia a los componentes y versión recuperables; el conjunto puede restaurarse en un entorno de prueba aislado | FR-014 |
| AC-018 | Una instalación operativa y un fallo de copia por falta de espacio o permisos | Se intenta actualizar | Se informa del fallo, no se sustituyen componentes ni se ejecutan migraciones y se restablece la operación anterior si se había entrado en mantenimiento | FR-014 |
| AC-019 | Una actualización compatible con comprobaciones de versión, login, lectura y escritura completadas | Finaliza el cambio | Se registra éxito con las versiones anterior y activa, comprobaciones y ubicación de copia, sin credenciales ni tokens en el resultado | FR-015 |
| AC-020 | Una nueva versión cuya comprobación de acceso o de operación desde el frontend falla | Finaliza el cambio | Se muestra fallo sin declarar éxito ni habilitar operación normal sobre la versión no verificada, con información para iniciar recuperación | FR-015 |
| AC-021 | Una copia coherente de prueba y un fallo inyectado después de una migración que cambia el esquema | Se solicita recuperación | Se restablece la versión anterior junto con esquema, datos, identidad y configuración compatibles; login y consultas reproducen la referencia previa antes de habilitar escrituras | FR-016 |
| AC-022 | Una actualización interrumpida durante sustitución o migración, o una recuperación interrumpida | Se ejecuta de nuevo el mantenimiento | La operación incompleta se reconoce y se permite recuperar un estado coherente antes de aceptar otra actualización o habilitar escrituras de negocio | FR-016 |
| AC-023 | Una actualización o recuperación todavía no verificada y una petición de escritura de negocio | Se intenta modificar un registro | La petición se rechaza de forma visible y el registro queda intacto; solo las comprobaciones controladas de mantenimiento pueden escribir datos de prueba | FR-016 |

## 8. Error Handling

Un rechazo previo no debe alterar la instalación. Un fallo de copia no debe dar paso a sustituciones ni migraciones. Un fallo posterior al cambio debe dejar visible qué operación está incompleta, conservar la copia y permitir recuperar un conjunto compatible de aplicación, datos y configuración.

La ausencia de una versión de origen identificable no se resuelve asumiendo compatibilidad: el diseño deberá definir cómo reconocer y admitir la instalación entregada actualmente. Restaurar datos requiere proteger el período de mantenimiento de escrituras; no se descartarán silenciosamente cambios posteriores a la copia. Un fallo de recuperación no se presenta como éxito ni habilita escrituras sobre un estado inconsistente. Las copias y logs no deben exponerse públicamente ni incorporar secretos al informe de resultado.

## References

- [BRD, REQ-008](../BRD.md), [VSD, OBJ-005](../../VSD.md) y [NFRD, NFR-007 a NFR-010](../NFRD.md).
- [Entrega Windows existente](../../../deploy/windows/README.md) y [preparación de paquetes](../../../deploy/windows/Build-Package.ps1), examinadas como evidencia del punto de partida, no como implementación de estos requisitos.
- Solicitud del usuario y aceptación del alcance en esta sesión, 2026-10-11.
