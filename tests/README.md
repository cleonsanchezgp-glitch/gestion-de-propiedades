# Infraestructura local de pruebas

## Ensayo del actualizador sin portal — 2026-10-16

El procedimiento para la VM VirtualBox está en
[ENSAYO-LOCAL.md](../deploy/windows/update/ENSAYO-LOCAL.md). La preparación de
esa VM y el ensayo integrado del host tienen alcances distintos.

`npm run test:update-local-mode` comprueba restricciones y resultados del modo
local. `npm run test:update-flow` comprueba la orquestación con API/PostgreSQL
reales, identidad/proxy simulados y control de procesos del runner; incorpora
aplicación, repetición, rechazo de cambio de modo y recuperación local sin portal.
Estos resultados no acreditan el ensayo con servicios y Keycloak reales en la VM.

La candidata Windows se compila con identidades `rehearsal-*`; el constructor
`deploy/windows/Build-LocalRehearsalPackage.ps1 -CandidatePath <exe>` genera la
entrega de herramientas y candidata, sin distribuciones de dependencias. Dentro
de la VM, `Preparar-Ensayo-Local.ps1 -ConfirmIsolatedVM` prepara solo baseline y
preflight; Apply se ejecuta por separado después de revisar el resultado.

Las referencias `system-runtime/` de la dependencia vc-runtime designan las DLL
concretas de System32 admitidas por Package.ps1, leídas sin copiarlas ni alterarlas.
No son rutas de payload ni permiten acceso a archivos externos arbitrarios.

## Infraestructura Compose

Requisitos: Node.js 24 o posterior y Docker con `docker-compose` disponible. No requiere instalar paquetes npm. El proyecto Compose `aelium-propiedades-tests` y los puertos 55432/58081 están separados de CRM. Solo escucha en loopback.

En Windows, si PowerShell bloquea `npm.ps1`, utiliza `npm.cmd` en los comandos siguientes sin cambiar la política del sistema.

```powershell
npm test
npm run test:prepare
npm run test:infra:up
npm run test:infra:check
npm run test:infra:down
```

`prepare` genera secretos aleatorios en `tests/.runtime/`, excluido de Git, sin mostrarlos. No modifica los secretos existentes. La base de pruebas usa tmpfs: sus datos se pierden al bajar o recrear el contenedor y se reponen con fixtures sintéticos. No hay conexión a DOC.txt, JSONBin, correo, banca ni servicios de CRM.

Keycloak usa un realm propio y un cliente público con PKCE S256, sin Direct Access Grants. El cliente confidencial `infra-probe` comprueba tokens de servicio y representa la identidad sintética permitida en el runner de API; no prueba un login de usuario. El frontend de prueba se reserva en 55173, pero aún no existe.

`check` comprueba discovery, PKCE disponible, token del probe, rechazo de secreto incorrecto, fixtures SQL, claves foráneas y unicidad. Guarda resultados sin tokens ni secretos en `tests/artifacts/`. La prueba de fixtures con Node y estas comprobaciones verifican infraestructura, no los TEST del TMP ni la aplicación.

Este Compose usa Keycloak en modo de desarrollo para pruebas locales. No es configuración de producción ni prueba de HTTPS. Adjuntos, identidad real y login en navegador siguen pendientes. Las rutas existentes de API tienen cobertura sintética parcial descrita abajo.

Referencias: [Keycloak containers](https://www.keycloak.org/server/containers), [realm import](https://www.keycloak.org/server/importExport), [PostgreSQL psql](https://www.postgresql.org/docs/16/app-psql.html) y [Node test runner](https://nodejs.org/api/test.html).

## Backend e integración — 2026-10-09

El backend requiere `DATABASE_URL`, `KEYCLOAK_ISSUER`, `KEYCLOAK_AUDIENCE` y `KEYCLOAK_ALLOWED_SUBJECT`. Esta última variable identifica al único usuario autorizado por su sujeto estable dentro del emisor configurado. Si falta o está vacía, el backend no inicia. No se conceden permisos por roles, correo ni nombre. La identidad real deberá configurarse antes de usar el portal.

El runner local obtiene exclusivamente el sujeto de la cuenta sintética `infra-probe`; las otras cuentas se utilizan para comprobar rechazo. Esto verifica tokens de servicio de prueba, no el inicio de sesión del responsable en navegador.

Orden reproducible: `npm run test:infra:up`, `npm run test:infra:check`, `npm run backend:build` y `npm run test:api`. La comprobación de infraestructura espera a que Keycloak esté listo. Los resultados de API se guardan en `tests/artifacts/api-*.json`, sin tokens ni secretos. El runner detiene el backend al finalizar; los contenedores permanecen disponibles hasta ejecutar `npm run test:infra:down`.

La migración `0002_payment_amounts.sql` añade importes NUMERIC anulables sin reconstruir históricos. El PUT de pago acepta `amountDue` y `amountPaid` como cadenas decimales, conserva importes conocidos cuando esos campos faltan o son null, y sustituye el total abonado cuando se proporciona. El saldo es salida calculada; se rechaza si el cliente intenta imponerlo. Estado e importes se guardan juntos con control de versión. No se deriva automáticamente el estado del saldo. El resumen incluye totales conocidos y recuentos desconocidos; no acredita conciliación bancaria.

Verificación local: cinco pruebas unitarias del backend, dos de fixtures, seis de infraestructura y nueve de integración aprobadas. Esta cobertura es parcial respecto al TMP: no acredita frontend, PKCE en navegador, cierre de sesión, HTTPS, adjuntos ni aceptación del producto.
