# Portal local de propiedades

Para instalar esta web en Cloudflare y la API con PostgreSQL en un servidor local,
consulta [la guía de despliegue independiente](../deploy/README.md).

Frontend modular con Vite y formulario de acceso propio, validado por Keycloak a través del backend. La interfaz utiliza verde oscuro, tonos de piedra, tipografía Manrope/DM Sans y un dibujo del perfil del Pilar para la dirección visual de Zaragoza. Los pagos se muestran en tabla en ordenador y en filas adaptadas a móvil. No copia datos de DOC.txt ni usa JSONBin o localStorage como fuente de negocio.

## Preparación y acceso

Desde la raíz del repositorio:

```powershell
npm run test:infra:up
npm run test:infra:check
npm run local:prepare
npm run local:login-config
npm run backend:build
```

Después, en dos terminales:

```powershell
npm run backend:local
npm run frontend:dev
```

Abrir http://127.0.0.1:55173. Usuario de prueba: `gestor-local`. La contraseña se encuentra en `tests/.runtime/local-access.txt`, excluido de Git. Las cuentas y los datos son sintéticos. La cuenta `sin-acceso-local` sirve para verificar rechazo. La preparación utiliza únicamente la administración del Keycloak local y conserva las contraseñas generadas entre ejecuciones.

El frontend utiliza rutas del mismo origen y no necesita configuración de identidad ni secretos en su compilación. El backend local utiliza el sujeto de gestor guardado en settings, mientras las pruebas de API siguen usando la cuenta de servicio sintética. No se infiere una identidad de producción ni se incluye un secreto de cliente en el navegador.

## Operaciones disponibles

- Resumen mensual de importes conocidos y recuentos desconocidos.
- Listar, crear, editar y archivar propiedades, inquilinos, incidencias y documentos con archivos adjuntos.
- Registrar estado, importe debido del período y total abonado; el servidor calcula el saldo.
- Usuario y contraseña se introducen en el propio portal. El backend los valida con un cliente confidencial de Keycloak mediante Direct Access Grants y comprueba la identidad exclusiva. Tokens y renovación permanecen en backend; el navegador recibe una cookie HttpOnly, SameSite=Strict, Secure cuando el origen usa HTTPS. No se guardan contraseñas ni tokens en localStorage.
- Mensajes de error, conflictos de versión, carga y listas vacías. Los guardados solo se confirman tras respuesta satisfactoria del servidor.

Documentos permite subir, descargar y sustituir archivos de hasta 10 MB. Se guardan en PostgreSQL con los metadatos, en una única transacción; las descargas requieren sesión y los documentos archivados no se descargan. Los recibos adjuntos a pagos siguen pendientes. No hay importación automática del origen, conciliación bancaria, HTTPS de publicación ni reglas definitivas de pagos múltiples, sobrepagos o correcciones. Un importe en blanco conserva el existente; los datos históricos ausentes permanecen desconocidos. El estado se selecciona expresamente, sin deducirlo del saldo.

## Verificación

```powershell
npm run frontend:build
npm --prefix frontend run browser:install
npm run test:browser
```

Las pruebas arrancan y detienen sus propios servidores; exigen tener libres 58080 y 55173. Comprueban login desde el formulario de gestor sin salir del portal, credenciales incorrectas, cookie protegida, origen de escrituras, invalidación de sesión al salir, renovación de token, creación de inmueble/inquilino, pago 600/250/350, persistencia tras recarga, rechazo de guardado con conflicto y cierre de sesión a 1440 y 360 px, más rechazo de otro usuario autenticado. Generan capturas y evidencia en `tests/artifacts/frontend/`. No certifican una matriz completa de navegadores ni aceptación visual del responsable.

Para publicación se requiere configuración de identidad real y un proxy HTTPS para `/api`: el proxy de Vite solo sirve al desarrollo local. Los puertos actuales escuchan en loopback.

Referencias de implementación: [adaptador JavaScript de Keycloak](https://www.keycloak.org/securing-apps/javascript-adapter) y [proxy de desarrollo Vite](https://vite.dev/config/server-options).

## Sesión integrada

El backend local recibe `KEYCLOAK_LOGIN_CLIENT_ID`, `KEYCLOAK_LOGIN_CLIENT_SECRET` y `PORTAL_ORIGIN` desde el runner privado. El cliente `portal-local-login` es confidencial y admite el intercambio de credenciales solicitado por el usuario; el cliente público anterior mantiene Direct Access Grants deshabilitado. `local:login-config` configura ese cliente sin modificar contraseñas de usuarios. Las sesiones duran un máximo absoluto de treinta minutos desde el inicio de sesión y se guardan en memoria del backend; reiniciarlo exige iniciar sesión de nuevo. Logout elimina inmediatamente la sesión local y solicita el cierre a Keycloak. Los flujos de MFA, cambio de contraseña obligatorio y proveedores externos no están implementados en este formulario.

Referencia del intercambio: [Direct Access Grants de Keycloak](https://www.keycloak.org/securing-apps/oidc-layers).

El saldo inicial es el importe debido menos cero cuando aún no hay abonos. Los archivos se incorporan mediante la migración 0004_document_files.sql; la actualización del cliente debe incluirla y verificar su copia y restauración antes de aplicarse.
