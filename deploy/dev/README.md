# Entorno Docker de desarrollo

`node deploy/dev/manage.mjs up` prepara y arranca en Docker Desktop el frontend compilado desde el código local, la API, Keycloak y dos bases PostgreSQL. Se crea el proyecto `propiedades-dev`; sus datos viven en volúmenes propios y no utilizan los de `propiedades-demo`, las pruebas ni una instalación de cliente.

En el primer arranque se generan contraseñas, un realm `propiedades-dev`, el cliente `portal-login` y el usuario `dev-owner`. La configuración privada queda en `.runtime/`, ignorada por Git. El comando comprueba las migraciones, el portal servido por Nginx, el proxy `/api`, el inicio de sesión y `/api/v1/me` antes de terminar. Tras editar Rust o el frontend, ejecuta de nuevo `node deploy/dev/manage.mjs up` para reconstruir las imágenes. `node deploy/dev/manage.mjs down` detiene el proyecto y conserva volúmenes; `node deploy/dev/manage.mjs status` muestra los servicios. También existen los scripts `npm.cmd run docker:dev:*`.

| Servicio | Dirección local |
| --- | --- |
| Portal frontend | `http://127.0.0.1:55173` |
| API | `http://127.0.0.1:58201` |
| Keycloak | `http://127.0.0.1:58200` |
| PostgreSQL de la aplicación | `127.0.0.1:58202` |

Las credenciales locales están en `.runtime/access.txt`. Abre `http://127.0.0.1:55173` en el navegador; no hace falta arrancar Vite aparte. Nginx sirve la compilación de Vite y envía `/api` a la API en la red Docker, igual que el portal utiliza rutas del mismo origen en Cloudflare. Si Windows reserva alguno de los puertos, cambia `frontendPort`, `keycloakPort`, `apiPort` y `postgresPort` en `.runtime/settings.json` antes de arrancar; el script vuelve a generar el archivo de entorno. Si Keycloak ya tiene el realm importado, cambiar su puerto cambia también el issuer de los tokens y exige recrear solo el entorno de desarrollo tras guardar los datos que necesites.

Este entorno usa HTTP únicamente en loopback y permite una conexión interna de la API a Keycloak dentro de la red Docker. El frontend es un quinto contenedor **solo para pruebas locales**: la entrega prevista al cliente mantiene cuatro contenedores (API, Keycloak y dos PostgreSQL), que corresponden a tres imágenes distintas porque ambas bases usan la misma imagen. El frontend definitivo se publica en Cloudflare. No uses las contraseñas, realm, volúmenes ni imágenes `:dev` como entrega de cliente. La entrega usa [el Compose y el flujo GHCR separados](../container/README.md). Este contenedor prueba la compilación y el proxy locales; no reproduce Cloudflare Worker, Access ni el túnel HTTPS.
