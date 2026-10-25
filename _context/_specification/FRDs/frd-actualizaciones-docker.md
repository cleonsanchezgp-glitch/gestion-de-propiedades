# Actualizaciones automáticas de la instalación Docker nueva

## Document Control

| Field | Value |
| --- | --- |
| Requirement Name | Instalación Docker y actualización automática de API |
| ID | FRD-006 |
| Version | 0.1 |
| Status | Draft - scope confirmed 2026-10-24; validation pending |
| Author | Consultor |
| Last Updated | 2026-10-24 |

## 1. Overview

Esta variante se instala desde cero en Windows con Docker Desktop. No adopta automáticamente los datos de una instalación nativa previa. El frontend se publica por separado. Una versión nueva de aplicación se identifica por una imagen GHCR; las imágenes de PostgreSQL y Keycloak permanecen fijadas y requieren mantenimiento separado.

## 2. Actors

| Actor | Description |
| --- | --- |
| Publicador | Crea una versión etiquetada y publica su imagen mediante GitHub Actions |
| Servidor del cliente | Comprueba periódicamente el canal publicado y ejecuta la actualización cuando Docker Desktop está disponible |
| Responsable de mantenimiento | Configura una vez el servidor y atiende fallos o cambios de dependencias |

## 3. Functional Requirements

| ID | Description | Priority | Traces to (REQ-xxx) |
| --- | --- | --- | --- |
| FR-017 | Construir la API desde una etiqueta de versión y publicar una imagen identificable en GHCR | Mantenimiento | REQ-009 |
| FR-018 | Instalar API, Keycloak y bases PostgreSQL en contenedores con almacenamiento persistente y configuración privada | Mantenimiento | REQ-009 |
| FR-019 | Comprobar periódicamente la imagen publicada y omitir la entrega ya instalada; si hay una nueva versión compatible, descargarla y actualizar sin una acción del cliente | Mantenimiento | REQ-009 |
| FR-020 | Detener las escrituras, copiar ambas bases antes de migrar, comprobar la imagen y el historial de migraciones, iniciar la nueva API y recuperar imagen y bases anteriores si falla; una interrupción debe dejar un estado reconocible | Mantenimiento | REQ-009, REQ-008 |

## 4. Workflow

1. El publicador crea una etiqueta de versión; GitHub Actions comprueba el backend y publica la imagen versionada y el canal `stable`.
2. La tarea de Windows consulta el canal mientras Docker Desktop está disponible; compara la identidad de imagen con la versión instalada.
3. Para una imagen nueva comprueba producto, contrato de API e historial de migraciones; detiene API y Keycloak y copia sus dos bases.
4. Ejecuta las migraciones explícitas con la imagen nueva, arranca la API y comprueba respuesta de API y Keycloak.
5. Registra la versión aplicada, o restaura ambas bases y la imagen anterior; una recuperación incompleta bloquea otra actualización automática.

## 5. Inputs

| Input | Source |
| --- | --- |
| Imagen versionada y canal `stable` | GHCR |
| Credenciales, orígenes y ruta privada de copias | Configuración local de la instalación |
| Datos persistentes | Volúmenes de PostgreSQL y Keycloak |

## 6. Outputs

| Output | Destination |
| --- | --- |
| Imagen activa o estado pendiente de recuperación | Instalación y registro local |
| Copias de ambas bases y configuración | Carpeta privada de mantenimiento |

## 7. Acceptance Criteria

| ID | Given | When | Then | Verifies |
| --- | --- | --- | --- | --- |
| AC-024 | Etiqueta `vX.Y.Z` y pruebas satisfactorias | Se ejecuta Actions | GHCR contiene la imagen versionada y el canal `stable` apunta a ella | FR-017 |
| AC-025 | Instalación nueva con datos sintéticos | Se reinician contenedores | API, Keycloak y ambas bases arrancan conservando datos y la identidad | FR-018 |
| AC-026 | Tarea periódica y nueva imagen compatible | Se ejecuta la comprobación | La versión nueva queda activa sin intervención del cliente; repetirla no altera los datos | FR-019 |
| AC-027 | Fallo inyectado después de migrar | Se intenta actualizar | Se restaura la imagen anterior junto con ambas bases y no se declara éxito falso | FR-020 |
| AC-028 | Actualización interrumpida | Se ejecuta otra comprobación | Detecta el estado pendiente y no aplica otra imagen hasta recuperar | FR-020 |

## 8. Error Handling

Si Docker Desktop, GHCR, la copia o la verificación fallan, se registra el error. Un cambio de versión mayor de PostgreSQL/Keycloak, un contrato frontend incompatible o una migración no transaccional exige una ruta de mantenimiento específica. La comprobación HTTP de vida no sustituye una prueba completa de login y escritura desde el portal, pendiente de validación integrada.

## References

- [BRD, REQ-009](../BRD.md) y [VSD, OBJ-005](../../VSD.md).
- [Instalación Docker](../../../deploy/container/README.md).
